// Recognising the links the user types, shares into the app, or opens
// the app with.

import 'package:movie_player/html_video_scraper.dart' show isVideoUrl;

/// Parses [raw] into a playable uri, or returns `null` when unsupported.
///
/// A missing scheme defaults to `https://`, so `example.com/video.mp4`
/// is accepted as well as a full `https://example.com/video.mp4`.
Uri? parseVideoUri(String raw) {
  var text = raw.trim();
  // Uri.parse percent-encodes invalid characters instead of failing, so
  // garbage like "not a url" must be rejected before parsing.
  if (text.isEmpty || RegExp(r'\s').hasMatch(text)) return null;
  if (!text.contains('://')) text = 'https://$text';

  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  // A percent sign in the host means the input was mangled while parsing.
  if (uri.host.contains('%')) return null;
  return uri;
}

/// Parses [raw] as the web page to scan. Only http(s) pages can be read.
Uri? parsePageUri(String raw) {
  var text = raw.trim();
  if (text.isEmpty || RegExp(r'\s').hasMatch(text)) return null;
  if (!text.contains('://')) text = 'https://$text';

  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.host.contains('%')) return null;
  return uri.scheme == 'http' || uri.scheme == 'https' ? uri : null;
}

/// The address the browser should open for [input]: the address itself
/// when the input looks like one, a Google search otherwise. Empty
/// input gives `null`, there is nothing to open.
///
/// A token with a dot or a port separator is an address
/// (`example.com/watch`, `localhost:8080`), a single word or anything
/// with a space is a search.
Uri? browserTargetUri(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  if (!text.contains(RegExp(r'\s')) &&
      (text.contains('.') || text.contains(':'))) {
    final page = parsePageUri(text);
    if (page != null) return page;
  }

  return Uri.parse(
    'https://www.google.com/search?q=${Uri.encodeQueryComponent(text)}',
  );
}

/// The url inside text shared from another app, or `null` when there is
/// none.
///
/// A share can be a bare url (`https://example.com/v.mp4`), a sentence
/// around one (`Watch https://example.com/v.mp4 !`) or a host without a
/// scheme (`example.com/v.mp4`), so the first url wins.
Uri? parseSharedLink(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  var target = RegExp(r'https?://\S+').firstMatch(text)?.group(0);
  target ??= text.contains('://') ? text.split(RegExp(r'\s')).first : null;
  target ??= text.contains(RegExp(r'\s')) ? null : 'https://$text';
  if (target == null) return null;

  // A link copied from running text can end with punctuation.
  target = target.replaceFirst(RegExp(r'[.,;:!?)\]]+$'), '');

  final uri = Uri.tryParse(target);
  if (uri == null) return null;
  // Local files come from file managers; web links need a real host.
  if (uri.scheme == 'content' || uri.scheme == 'file') return uri;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty || uri.host.contains('%')) return null;
  return uri;
}

/// Whether [link] is a video the player can open right away, as opposed to
/// a web page that must be scanned for videos first.
bool isDirectVideoLink(Uri link) {
  if (link.scheme == 'content' || link.scheme == 'file') return true;
  return isVideoUrl(link.toString());
}
