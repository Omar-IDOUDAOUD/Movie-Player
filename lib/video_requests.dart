import 'dart:developer';

import 'package:movie_player/html_video_scraper.dart' show isVideoUrl;

/// Whether the resource at [url] is worth offering as a video.
///
/// The browser's web view reports every resource a page loads
/// ([LoadedResource]); two things make one worth offering to play:
///
///  * its address ends in a media extension (`.m3u8`, `.mp4`, ...), or
///  * the page started it as a media element ([initiatorType] is
///    `video` or `audio`), which catches signed CDN addresses without
///    a recognisable extension.
///
/// Segment addresses (`.ts`, `.m4s`) are deliberately not extensions:
/// an HLS or DASH stream loads hundreds of them and each would raise
/// its own offer.
///
/// [initiatorType] is the Resource Timing initiator of the request
/// (`video`, `audio`, `img`, ...) when the page reported one. Only
/// plain web addresses count: `blob:`, `data:` and local files are
/// nothing the app's player could open from a page.
bool isVideoRequest(String url, {String? initiatorType}) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;

  if (isVideoUrl(url)) return true;
  return initiatorType == 'video' || initiatorType == 'audio';
}

/// The part of [url] worth showing on the offer card and in the list
/// of found videos: host and last path node, without the scheme,
/// query or fragment.
///
/// A path of two or more nodes keeps its ends and meets in the
/// middle — `cdn.example.com/.../the-thing.mp4`. The host says where
/// the video comes from, the last node what it is; the middle rarely
/// says anything a long signed address does not already bury.
String describeVideoUrl(String url) {

  url = cleanUrl(url);

  const maxStartLength = 32;
  const maxEndLength = 32;
  const maxLength = maxStartLength + maxEndLength;

  if (url.length <= maxLength) return url;

  return '${url.substring(0, maxStartLength)}...'
      '${url.substring(url.length - maxEndLength)}';
}

String cleanUrl(String url) {
  final uri = Uri.tryParse(url);
  log(uri?.toString()??"null", name: "URRls");
  if (uri == null) return url;

  return Uri(scheme: uri.scheme, host: uri.host, port: uri.port, path: uri.path).toString();
}