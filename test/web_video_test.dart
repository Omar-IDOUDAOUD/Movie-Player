// Unit tests for the web page video scraper.

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_player/routes/web_video.dart';

void main() {
  final base = Uri.parse('https://example.com/episodes/one/');

  group('extractVideoUrls', () {
    test('finds absolute urls with a media extension', () {
      const html =
          '<p>https://cdn.example.com/master.m3u8?token=abc&amp;x=1</p>';
      final videos = extractVideoUrls(html, base);

      expect(
        videos.map((video) => video.toString()),
        ['https://cdn.example.com/master.m3u8?token=abc&x=1'],
      );
    });

    test('finds relative urls of video and source tags', () {
      const html =
          '<video controls><source src="clips/movie.mp4" type="video/mp4">'
          '</video>';
      final videos = extractVideoUrls(html, base);

      expect(
        videos.map((video) => video.toString()),
        ['https://example.com/episodes/one/clips/movie.mp4'],
      );
    });

    test('resolves urls against the base of the page', () {
      const html =
          '<base href="https://other.example.net/player/">'
          '<video src="film.m3u8"></video>';
      final videos = extractVideoUrls(html, base);

      expect(
        videos.map((video) => video.toString()),
        ['https://other.example.net/player/film.m3u8'],
      );
    });

    test('keeps one entry per url', () {
      const html =
          'https://cdn.example.com/a.mp4 '
          'https://cdn.example.com/a.mp4 '
          '<source src="https://cdn.example.com/a.mp4">';
      expect(extractVideoUrls(html, base), hasLength(1));
    });

    test('rejects urls whose extension is only part of a word', () {
      const html =
          'https://cdn.example.com/file.movie '
          'https://cdn.example.com/page.html';
      expect(extractVideoUrls(html, base), isEmpty);
    });

    test('ignores javascript and other non-http urls', () {
      const html =
          '<video src="javascript:alert(1)"></video>'
          '<source src="ftp://files.example.com/a.mp4">';
      expect(extractVideoUrls(html, base), isEmpty);
    });
  });

  group('extractIframeUrls', () {
    test('finds absolute and relative iframe urls', () {
      const html =
          '<iframe src="https://w.player.example/albaplayer/1"></iframe>'
          '<IFRAME src="/embed/next.html"></IFRAME>';
      final frames = extractIframeUrls(html, base);

      expect(
        frames.map((frame) => frame.toString()),
        [
          'https://w.player.example/albaplayer/1',
          'https://example.com/embed/next.html',
        ],
      );
    });

    test('skips youtube embeds that never expose a direct video', () {
      const html =
          '<iframe src="https://www.youtube.com/embed/abc"></iframe>'
          '<iframe src="https://youtu.be/embed/abc"></iframe>';
      expect(extractIframeUrls(html, base), isEmpty);
    });
  });

  group('unpackPackedScripts', () {
    test('decodes a packed eval(function(p,a,c,k,e,d){…}) block', () {
      const packed =
          "eval(function(p,a,c,k,e,d){e=function(c){return c.toString(36)};"
          "while(c--)if(k[c])p=p.replace(new RegExp('x'+e(c)+'x','g'),k[c]);"
          "return p}('2 1 0 2',36,3,"
          "'https://cdn.example.com/video.m3u8|jwplayer|setup'"
          ".split('|'),0,{}))";
      final unpacked = unpackPackedScripts(packed);

      // The dictionary swap turns the numeric tokens into real words.
      expect(
        unpacked,
        contains(
          'setup jwplayer https://cdn.example.com/video.m3u8 setup',
        ),
      );
      expect(extractVideoUrls(unpacked, base), hasLength(1));
    });

    test('leaves plain html untouched', () {
      const html = '<video src="a.mp4"></video>';
      expect(unpackPackedScripts(html), html);
    });
  });

  group('findVideosOnPage', () {
    final page = Uri.parse('https://example.com/episode/1');
    final frame = Uri.parse('https://w.player.example/embed/1');
    final video = Uri.parse('https://cdn.example.com/master.m3u8');

    test('follows player iframes until a video is found', () async {
      final fetched = <Uri>[];
      final videos = await findVideosOnPage(
        page,
        fetchPage: (uri, timeout) async {
          fetched.add(uri);
          if (uri == page) return '<iframe src="$frame"></iframe>';
          return 'jwplayer().setup({file:"$video"})';
        },
      );

      expect(fetched, [page, frame]);
      expect(videos, [video]);
    });

    test('collects videos of the start page too', () async {
      final videos = await findVideosOnPage(
        page,
        fetchPage: (uri, timeout) async =>
            '<video src="https://cdn.example.com/direct.mp4"></video>',
      );

      expect(videos, hasLength(1));
    });

    test('does not follow iframes deeper than maxDepth', () async {
      final deeper = Uri.parse('https://w.player.example/embed/2');
      final fetched = <Uri>[];
      await findVideosOnPage(
        page,
        maxDepth: 1,
        fetchPage: (uri, timeout) async {
          fetched.add(uri);
          if (uri == page) return '<iframe src="$frame"></iframe>';
          if (uri == frame) return '<iframe src="$deeper"></iframe>';
          return 'https://cdn.example.com/deep.mp4';
        },
      );

      expect(fetched, isNot(contains(deeper)));
    });

    test('rethrows when the page the user asked for cannot be read', () {
      expect(
        findVideosOnPage(
          page,
          fetchPage: (uri, timeout) async => throw Exception('offline'),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('keeps going when an iframe cannot be read', () async {
      final videos = await findVideosOnPage(
        page,
        fetchPage: (uri, timeout) async {
          if (uri == page) return '<iframe src="$frame"></iframe>';
          throw Exception('blocked');
        },
      );

      expect(videos, isEmpty);
    });
  });
}
