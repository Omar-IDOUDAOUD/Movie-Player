import 'package:flutter/material.dart';
import 'package:movie_player/pages/home/tabs/folder_tab.dart';
import 'package:movie_player/pages/home/tabs/history_tab.dart';
import 'package:movie_player/pages/home/tabs/network_tab.dart';
import 'package:movie_player/pages/home/tabs/web_page_tab.dart';
import 'package:movie_player/web_page_scan.dart';

/// The landing page: a bottom navigation bar over the four tab views —
/// pick a folder, play a network video, extract videos from a web page
/// and the watch history.
///
/// All tabs stay built ([IndexedStack]) so a tab keeps its state (typed
/// urls, a running scan) while another one is showing.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.onToggleTheme,
    this.findVideos,
    this.sharedPage,
  });

  final VoidCallback onToggleTheme;

  /// Scans a web page for videos with both extraction mechanisms (html
  /// scraping and invisible WebView). Defaults to the combined scan of
  /// both extractors; tests inject a stub so no network is used.
  final Future<PageVideoScanResult> Function(Uri page)? findVideos;

  /// A web page shared into the app: the web page tab opens and its
  /// extractor starts as soon as the link arrives (a fresh token also
  /// makes a repeated share rescan).
  final ({String url, int token})? sharedPage;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Index of the web page tab inside the [NavigationBar] destinations.
  static const _webTab = 2;

  /// Which tab is showing.
  var _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.sharedPage != null) {
      // A link can be handed over before the first frame: show the web
      // page tab once built so the scan and its results are visible.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _tabIndex = _webTab);
      });
    }
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shared = widget.sharedPage;
    if (shared != null && shared.token != oldWidget.sharedPage?.token) {
      setState(() => _tabIndex = _webTab);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MPlayer'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: widget.onToggleTheme,
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
            ),
            tooltip: 'Toggle theme',
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          const FolderTab(),
          const NetworkTab(),
          WebPageTab(
            findVideos: widget.findVideos,
            sharedPage: widget.sharedPage,
          ),
          const HistoryTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) {
          // A hidden tab must not keep the keyboard for its inputs.
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() => _tabIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_open_outlined),
            selectedIcon: Icon(Icons.folder_open),
            label: 'Folder',
          ),
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle_fill),
            label: 'Network',
          ),
          NavigationDestination(
            icon: Icon(Icons.language),
            label: 'Web page',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }
}
