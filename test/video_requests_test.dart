// Tests for recognising a page's video requests.

import 'package:flutter_test/flutter_test.dart';

import 'package:movie_player/video_requests.dart';

void main() {
  test('media extensions make a video request', () {
    expect(isVideoRequest('https://cdn.example.com/movie.mp4'), isTrue);
    expect(
      isVideoRequest('https://cdn.example.com/live/index.m3u8?token=abc'),
      isTrue,
    );
    expect(isVideoRequest('https://cdn.example.com/clip.webm'), isTrue);
    expect(isVideoRequest('https://cdn.example.com/movie.mp4#t=1'), isTrue);
    expect(isVideoRequest('https://example.com/watch/123'), isFalse);
    // A word that merely contains an extension is not one.
    expect(isVideoRequest('https://example.com/a.movie/show'), isFalse);
  });

  test('stream segments are not offered', () {
    // An HLS or DASH stream loads hundreds of these; each would
    // otherwise raise its own offer.
    expect(isVideoRequest('https://cdn.example.com/seg-0001.ts'), isFalse);
    expect(isVideoRequest('https://cdn.example.com/chunk-1.m4s'), isFalse);
  });

  test('media elements without an extension count', () {
    const signed = 'https://cdn.example.com/v/abc123?expires=1&sig=2';
    expect(isVideoRequest(signed, initiatorType: 'video'), isTrue);
    expect(isVideoRequest(signed, initiatorType: 'audio'), isTrue);
    // The same address fetched as an image is just an image.
    expect(isVideoRequest(signed, initiatorType: 'img'), isFalse);
    expect(isVideoRequest(signed), isFalse);
  });

  test('only web addresses are offered', () {
    expect(isVideoRequest('blob:https://example.com/1234'), isFalse);
    expect(isVideoRequest('data:video/mp4;base64,AAAA'), isFalse);
    expect(isVideoRequest('file:///videos/movie.mp4'), isFalse);
    expect(
      isVideoRequest('file:///videos/movie.mp4', initiatorType: 'video'),
      isFalse,
    );
  });
}
