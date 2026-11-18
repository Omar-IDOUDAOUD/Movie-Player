import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:movie_player/html_video_scraper.dart';

import 'web_page_scan.dart';


/// Video extraction with an invisible WebView.
///
/// Where [findVideosOnPage] only downloads html and follows iframes, this
/// runs the page's own javascript in a headless Android WebView and watches
/// what the player does:
///
/// 1. `shouldInterceptRequest` sees every url the page requests, so the
///    `.m3u8`/`.mp4` a player fetches while starting is caught even when it
///    never appears in the html.
/// 2. `onLoadStop` reads the rendered html (after giving lazy players a
///    moment to start) and scans it with [extractVideoUrls].
///
/// The WebView never throws: a timeout or a missing plugin simply yields
/// whatever was collected until then.
Future<PageVideoScanResult> findVideosWithWebView(
  Uri page, {
  Duration loadTimeout = const Duration(seconds: 60),
  Duration playerSettle = const Duration(seconds: 3),
}) async {
  // A headless WebView only exists on mobile; elsewhere there is nothing
  // to intercept.
  if (!Platform.isAndroid && !Platform.isIOS) return const PageVideoScanResult(title: '', videos: []);

  final found = <String, Uri>{};
  var pageTitle = '';
  final loaded = Completer<void>();
  HeadlessInAppWebView? webview;

  /// Remembers [raw] when a player could open it.
  void collect(String raw) {
    log("FOUND : $raw");
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    if (uri.scheme != 'http' && uri.scheme != 'https') return;
    if (!isVideoUrl(raw)) return;
    found.putIfAbsent(uri.toString(), () => uri);
  }

  try {
    webview = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(page.toString())),
      initialSettings: InAppWebViewSettings(
        userAgent: _userAgent,
        // Without this Android WebView blocks players from starting, so the
        // media request never fires and nothing can be intercepted.
        mediaPlaybackRequiresUserGesture: false,
      ),
      // Layer 1: watch the network traffic of the page.
      shouldInterceptRequest: (controller, request) async {
        collect(request.url.toString());
        return null; // Let the browser keep loading normally.
      },
      // Layer 2: scan the rendered html once the page finished loading.
      onLoadStop: (controller, url) async {
        if (loaded.isCompleted) return;
        try {
          // Lazy-loaded players need a moment before they request the stream.
          await Future.delayed(playerSettle);
          if (loaded.isCompleted) return;
          try {
            pageTitle = (await controller.getTitle())?.trim() ?? '';
          } catch (_) {}
          final html = await controller.getHtml();
          if (html != null) {
            final base = Uri.tryParse(url?.toString() ?? '') ?? page;
            for (final video in extractVideoUrls(html, base)) {
              found.putIfAbsent(video.toString(), () => video);
            }
          }
        } catch (_) {
          // The page went away while it was being read.
        } finally {
          if (!loaded.isCompleted) loaded.complete();
        }
      },
      onReceivedError: (controller, request, error) {
        // The main page failed: stop waiting for onLoadStop.
        if (request.isForMainFrame ?? true) {
          if (!loaded.isCompleted) loaded.complete();
        }
      },
    );

    await webview.run();
    await loaded.future.timeout(loadTimeout);
  } catch (_) {
    // Timeout or missing plugin: keep what was collected so far.
  } finally {
    // A headless WebView holds a lot of RAM: always release it.
    try {
      await webview?.dispose();
    } catch (_) {}
  }

  return PageVideoScanResult(title: pageTitle, videos: found.values.toList());
}

const _userAgent =
    'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
