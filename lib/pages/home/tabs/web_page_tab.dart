import 'package:flutter/material.dart';
import 'package:movie_player/pages/player/player_page.dart';
import 'package:movie_player/pages/home/tabs/tab_body.dart';
import 'package:movie_player/link_parser.dart';
import 'package:movie_player/web_page_scan.dart';

/// The "Web page" tab: scan a page for its videos.
///
/// One result plays directly, many results open a choice list, none
/// shows a message. A web page shared into the app is filled in and
/// scanned as soon as it arrives.
class WebPageTab extends StatefulWidget {
  const WebPageTab({
    super.key,
    this.findVideos,
    this.sharedPage,
  });

  /// Scans a web page for videos with both extraction mechanisms (html
  /// scraping and invisible WebView). Defaults to [findAllVideosOnPage];
  /// tests inject a stub so no network is used.
  final Future<List<Uri>> Function(Uri page)? findVideos;

  /// A web page shared into the app: its extractor starts as soon as the
  /// link arrives (a fresh token also makes a repeated share rescan).
  final ({String url, int token})? sharedPage;

  @override
  State<WebPageTab> createState() => _WebPageTabState();
}

class _WebPageTabState extends State<WebPageTab> {
  final TextEditingController _pageUrlController = TextEditingController();

  bool _pageInputError = false;

  /// True while a web page is being scanned for videos.
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    final shared = widget.sharedPage;
    if (shared != null) {
      // A link can be handed over before the first frame: scan once built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scanSharedPage(shared);
      });
    }
  }

  @override
  void didUpdateWidget(WebPageTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shared = widget.sharedPage;
    if (shared != null && shared.token != oldWidget.sharedPage?.token) {
      _scanSharedPage(shared);
    }
  }

  /// Fills the page field with a shared link and scans it at once.
  void _scanSharedPage(({String url, int token}) shared) {
    if (!mounted) return;
    _pageUrlController.text = shared.url;
    _scanWebPage();
  }

  @override
  void dispose() {
    _pageUrlController.dispose();
    super.dispose();
  }

  /// Scans the web page the user entered for playable video urls.
  Future<void> _scanWebPage() {
    // One scan at a time: a share arriving while scanning keeps the
    // running scan instead of racing it.
    if (_scanning) return Future.value();

    final page = parsePageUri(_pageUrlController.text);
    if (page == null) {
      setState(() => _pageInputError = true);
      return Future.value();
    }

    setState(() {
      _pageInputError = false;
      _scanning = true;
    });
    return _findVideos(page);
  }

  Future<void> _findVideos(Uri page) async {
    try {
      final scan = widget.findVideos ?? findAllVideosOnPage;
      final videos = await scan(page);
      if (!mounted) return;
      setState(() => _scanning = false);

      if (videos.isEmpty) {
        _showMessage('No video found on this page');
      } else if (videos.length == 1) {
        _openVideo(videos.first);
      } else {
        await _chooseVideo(videos);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _scanning = false);
      _showMessage('Could not read this web page');
    }
  }

  /// Lets the user pick one of the videos found on the page.
  Future<void> _chooseVideo(List<Uri> videos) async {
    final selected = await showDialog<Uri>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select a video'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final video in videos)
                TextButton(
                  onPressed: () => Navigator.pop(context, video),
                  child: Text(
                    video.toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    _openVideo(selected);
  }

  void _openVideo(Uri video) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerPage(videoUri: video, videoTitle: ''),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TabBody(
      children: [
        const Text('Play Video from a web page url'),
        const SizedBox(
          height: 5,
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _pageUrlController,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onChanged: (_) {
                  if (_pageInputError) {
                    setState(() => _pageInputError = false);
                  }
                },
                onSubmitted: (_) => _scanWebPage(),
                decoration: InputDecoration(
                  hintText: 'Web page url',
                  errorText: _pageInputError
                      ? 'Enter a valid web page url'
                      : null,
                  border: const OutlineInputBorder(),
                  focusedBorder: const OutlineInputBorder(),
                ),
              ),
            ),
            if (_scanning)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                onPressed: _scanWebPage,
                icon: const Icon(Icons.search),
                tooltip: 'Scan page for videos',
              ),
          ],
        ),
      ],
    );
  }
}
