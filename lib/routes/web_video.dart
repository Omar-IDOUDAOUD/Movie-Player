import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Finds playable video urls inside a web page.
///
/// Many pages don't link the video directly: it lives inside one or more
/// nested `<iframe>` players, sometimes defined in obfuscated ("packed")
/// javascript such as the classic `eval(function(p,a,c,k,e,d){…})` packer.
///
/// [findVideosOnPage] loads the page, follows the player iframes up to
/// [maxDepth] levels deep, unpacks packed scripts and collects every media
/// url it finds. One result can be played directly, many results are shown
/// to the user for a choice.

/// What makes a url worth offering as a video.
const _mediaExtensions = [
  '.m3u8', '.mp4', '.mkv', '.webm', '.mov', '.m4v', '.avi', '.3gp', '.mpd',
];

/// Hosts whose embeds only play inside their own player, so following them
/// wastes requests — no direct media url ever comes out of them.
const _unplayableHosts = [
  'youtube.com',
  'youtu.be',
  'youtube-nocookie.com',
];

const _userAgent =
    'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

/// Loads [page] and returns every video url of it and its player iframes.
///
/// The first page failing throws, so the user learns the page couldn't be
/// read; a failing iframe is skipped. At most [maxPages] pages are fetched.
Future<List<Uri>> findVideosOnPage(
  Uri page, {
  int maxDepth = 3,
  int maxPages = 8,
  Duration timeout = const Duration(seconds: 15),
  Future<String> Function(Uri uri, Duration timeout)? fetchPage,
}) async {
  final fetch = fetchPage ?? _fetchPage;
  final videos = <String, Uri>{};
  final visited = <String>{};
  final queue = <({Uri uri, int depth})>[(uri: page, depth: 0)];
  var fetched = 0;

  while (queue.isNotEmpty && fetched < maxPages) {
    final next = queue.removeAt(0);
    if (!visited.add(next.uri.toString())) continue;

    String html;
    try {
      html = await fetch(next.uri, timeout);
    } catch (_) {
      // The page the user asked for must not fail silently.
      if (next.depth == 0) rethrow;
      continue;
    }
    fetched++;

    for (final video in extractVideoUrls(html, next.uri)) {
      videos.putIfAbsent(video.toString(), () => video);
    }

    if (next.depth < maxDepth) {
      for (final frame in extractIframeUrls(html, next.uri)) {
        queue.add((uri: frame, depth: next.depth + 1));
      }
    }
  }

  return videos.values.toList();
}

/// The media urls of [html], resolved against [base].
List<Uri> extractVideoUrls(String html, Uri base) {
  final text = _prepare(html);
  final pageBase = documentBaseOf(text, base);
  final result = <String, Uri>{};

  // Absolute urls that contain a media extension.
  for (final match in _absoluteUrl.allMatches(text)) {
    final url = _trimUrl(match.group(0)!);
    if (_looksLikeVideo(url)) _add(result, url, pageBase);
  }

  // The src of <video> and <source> tags, also relative ones.
  for (final match in _mediaTag.allMatches(text)) {
    _add(result, match.group(1)!, pageBase);
  }

  return result.values.toList();
}

/// The iframe urls of [html], resolved against [base], without the embeds
/// that can never play as a direct video.
List<Uri> extractIframeUrls(String html, Uri base) {
  final text = _prepare(html);
  final pageBase = documentBaseOf(text, base);
  final result = <String, Uri>{};

  for (final match in _iframeTag.allMatches(text)) {
    final uri = _resolve(match.group(1)!, pageBase);
    if (uri == null || _isUnplayable(uri)) continue;
    result.putIfAbsent(uri.toString(), () => uri);
  }

  return result.values.toList();
}

/// [source] with every packed `eval(function(p,a,c,k,e,d){…})` block
/// replaced by the javascript it decodes to.
///
/// The unpacking mirrors the packer's own decoder: every whole-word token
/// that is the base-[radix] spelling of a dictionary position is swapped
/// for that dictionary entry, from the end of the dictionary to the start.
String unpackPackedScripts(String source) {
  return source.replaceAllMapped(_packer, (match) {
    final packed = _unescapeJs(match.group(1)!);
    final radix = int.parse(match.group(2)!);
    final count = int.parse(match.group(3)!);
    final dictionary = _unescapeJs(match.group(4)!).split('|');

    var result = packed;
    var index = count;
    while (index-- > 0) {
      if (index >= dictionary.length || dictionary[index].isEmpty) continue;
      final token = index.toRadixString(radix);
      result = result.replaceAll(
        RegExp('\\b${RegExp.escape(token)}\\b'),
        dictionary[index],
      );
    }
    return result;
  });
}

// ---------------------------------------------------------------- extraction

/// Unpacks the packed scripts, then fixes the escaping that hides urls.
String _prepare(String html) {
  final text = unpackPackedScripts(html);
  return text
      .replaceAll(r'\/', '/') // JSON-escaped slashes.
      .replaceAll(r'\u002F', '/')
      .replaceAll(r'\u002f', '/')
      .replaceAll(r'\u0026', '&')
      .replaceAll('&amp;', '&')
      .replaceAll('&#038;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#34;', '"');
}

final _absoluteUrl = RegExp(
  r'''https?://[^\s"'<>()\[\]{}\\`]+''',
  caseSensitive: false,
);

final _mediaTag = RegExp(
  r'''<(?:video|source)\b[^>]*?\bsrc\s*=\s*["']([^"']+)["']''',
  caseSensitive: false,
);

final _iframeTag = RegExp(
  r'''<iframe\b[^>]*?\bsrc\s*=\s*["']([^"']+)["']''',
  caseSensitive: false,
);

final _baseHref = RegExp(
  r'''<base\b[^>]*?\bhref\s*=\s*["']([^"']+)["']''',
  caseSensitive: false,
);

final _packer = RegExp(
  r'''eval\s*\(\s*function\s*\(\s*p\s*,\s*a\s*,\s*c\s*,\s*k\s*,\s*e\s*,\s*d\s*\)\s*\{.*?\}\s*\(\s*'((?:[^'\\]|\\.)*)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'((?:[^'\\]|\\.)*)'\s*\.\s*split\s*\(\s*'\|'\s*\)''',
  dotAll: true,
);

/// Whether [url] points at something a video player can open.
bool _looksLikeVideo(String url) {
  final lower = url.toLowerCase();
  for (final extension in _mediaExtensions) {
    final at = lower.indexOf(extension);
    if (at == -1) continue;
    final after = at + extension.length;
    // `file.mp4` counts, `file.movie` doesn't.
    if (after == lower.length) return true;
    final next = lower[after];
    if (next == '?' || next == '#' || next == '&') return true;
  }
  return false;
}

bool _isUnplayable(Uri uri) {
  final host = uri.host.toLowerCase();
  return _unplayableHosts.any(
    (unplayable) => host == unplayable || host.endsWith('.$unplayable'),
  );
}

void _add(Map<String, Uri> into, String raw, Uri base) {
  final uri = _resolve(raw, base);
  if (uri != null) into.putIfAbsent(uri.toString(), () => uri);
}

/// [raw] as an absolute http(s) uri, or `null` when it can't be played.
Uri? _resolve(String raw, Uri base) {
  final value = raw.trim();
  if (value.isEmpty || value.contains(RegExp(r'\s'))) return null;

  final Uri uri;
  try {
    final parsed = Uri.tryParse(value);
    if (parsed == null) return null;
    uri = parsed.hasScheme ? parsed : base.resolve(value);
  } on FormatException {
    return null;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

/// The base for relative urls of [preparedHtml]: the `<base href>` of the
/// page when it has one, or [page] itself.
Uri documentBaseOf(String preparedHtml, Uri page) {
  final match = _baseHref.firstMatch(preparedHtml);
  if (match == null) return page;
  return _resolve(match.group(1)!, page) ?? page;
}

/// Trims punctuation that can stick to a url found in running text.
String _trimUrl(String url) {
  var end = url.length;
  while (end > 0 && const ['.', ',', ';', ':'].contains(url[end - 1])) {
    end--;
  }
  return url.substring(0, end);
}

String _unescapeJs(String value) =>
    value.replaceAll(r"\'", "'").replaceAll(r'\"', '"');

// --------------------------------------------------------------------- fetch

/// The html of [uri] as text, or a throw when it can't be read.
Future<String> _fetchPage(Uri uri, Duration timeout) async {
  final client = HttpClient()..connectionTimeout = timeout;
  client.userAgent = _userAgent;
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    request.followRedirects = true;
    request.maxRedirects = 5;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    );

    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'The page answered with HTTP ${response.statusCode}',
        uri: uri,
      );
    }

    final bytes = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      bytes.addAll(chunk);
      // Player pages are small; stop reading after a generous limit.
      if (bytes.length > 8 * 1024 * 1024) break;
    }
    return utf8.decode(bytes, allowMalformed: true);
  } finally {
    client.close(force: true);
  }
}
