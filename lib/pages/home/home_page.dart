import 'package:flutter/material.dart';
import 'package:movie_player/pages/home/tabs/folder_tab.dart';
import 'package:movie_player/pages/home/tabs/history_tab.dart';
import 'package:movie_player/pages/home/tabs/network_tab.dart';
import 'package:movie_player/pages/home/tabs/web_page_tab.dart';

/// The landing page: a bottom navigation bar over the four tab views —
/// pick a folder, play a network video, browse the web and the watch
/// history.
///
/// The "MPlayer" app bar belongs to the first tab only; the other tabs
/// take the full height (the web page tab turns it into a floating
/// browser bar instead).
///
/// All tabs stay built ([IndexedStack]) so a tab keeps its state (typed
/// urls, open browser pages) while another one is showing.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onToggleTheme});

  final VoidCallback onToggleTheme;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Which tab is showing.
  var _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The app bar belongs to the folder tab only; the other tabs
      // make the full height their own.
      appBar: _tabIndex == 0
          ? AppBar(
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
            )
          : null,
      // Without an app bar the body keeps the status bar padding, so
      // it must consume it here (a no-op behind the app bar).
      body: SafeArea(
        top: true,
        bottom: false,
        child: IndexedStack(
          index: _tabIndex,
          children: const [
            FolderTab(),
            NetworkTab(),
            WebPageTab(),
            HistoryTab(),
          ],
        ),
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
