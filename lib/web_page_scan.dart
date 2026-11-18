import 'package:movie_player/html_video_scraper.dart';
import 'package:movie_player/webview_video_finder.dart' as webview;

/// Videos and the title found on a scanned web page.
class PageVideoScanResult {
  const PageVideoScanResult({required this.title, required this.videos});

  final String title;
  final List<Uri> videos;
}

/// Runs both extraction mechanisms on [page] and merges their results.
///
/// The html scraper downloads and follows the player iframes, the webview
/// finder runs the page in an invisible WebView and intercepts its
/// requests; a video found by either is offered to the user. The page
/// itself failing still throws, so the user learns it could not be read.
Future<PageVideoScanResult> findAllVideosOnPage(Uri page) async {
  final fromWebView = webview.findVideosWithWebView(page);
  final fromHtml = await findVideosOnPage(page);
  final fromRequests = await fromWebView;

  final all = <String, Uri>{};
  for (final video in [...fromHtml, ...fromRequests.videos]) {
    all.putIfAbsent(video.toString(), () => video);
  }
  return PageVideoScanResult(
    title: fromRequests.title,
    videos: all.values.toList(),
  );
}
