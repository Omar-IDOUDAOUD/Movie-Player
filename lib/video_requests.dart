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
