import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:movie_player/link_parser.dart';

/// The "Web page" tab: a small browser.
///
/// The user browses by hand and starts the video where the site puts
/// it, which beats guessing at pages that only run their player after
/// a click. The tab keeps several pages alive at once (a chip strip on
/// top), an address field that also searches Google, and the usual
/// navigation controls. Long-pressing a link offers to open it in a
/// new tab or to copy it.
///
/// The top bar (strip + address field) floats over the page: it shows
/// while the page sits at its top and snaps away as soon as the user
/// scrolls down, coming back on the way up. An input focused inside
/// the page also releases the address field.
class WebPageTab extends StatefulWidget {
  const WebPageTab({super.key});

  @override
  State<WebPageTab> createState() => _WebPageTabState();
}

/// One open browser page.
class _BrowserTab {
  _BrowserTab({required this.id, required this.url});

  /// Number of the tab, stable for its lifetime (chips key on it).
  final int id;

  /// The address the field shows and the page loads.
  String url;

  /// Page title for the chip, empty until the page reports one.
  String title = '';

  /// Load progress 0-100; starts at 100 so no bar shows up before
  /// anything is loading.
  int progress = 100;

  bool canGoBack = false;
  bool canGoForward = false;

  /// Last scroll position the page reported, in css pixels.
  int scrollY = 0;

  /// The position the top bar last snapped at; the bar toggles once
  /// the page has moved far enough away from it.
  int scrollAnchor = 0;

  /// Set once the platform web view for this tab exists.
  InAppWebViewController? controller;
}

class _WebPageTabState extends State<WebPageTab> {
  static const _homeUrl = 'https://www.google.com';

  /// Every page of the browser, oldest first; never empty (closing the
  /// last one starts a fresh one).
  final List<_BrowserTab> _tabs = [_BrowserTab(id: 0, url: _homeUrl)];

  var _activeId = 0;
  var _nextTabId = 1;

  final TextEditingController _addressController = TextEditingController();
  final FocusNode _addressFocus = FocusNode();

  _BrowserTab get _activeTab => _tabs.firstWhere(
        (tab) => tab.id == _activeId,
        orElse: () => _tabs.first,
      );

  /// A real web view only exists on mobile; everywhere else (widget
  /// tests, desktop runs) the chrome still builds and shows a notice.
  bool get _hasWebView => Platform.isAndroid || Platform.isIOS;

  /// Height of the floating top bar: the 44px strip plus the 56px
  /// address row. The spacer and the slide distance both use it, so
  /// the bar always exactly covers the room reserved for it.
  static const _topBarHeight = 44.0 + 56.0;

  /// How far the page must move before the bar snaps, in logical
  /// pixels. The web view reports raw device pixels, so this is scaled
  /// by the device pixel ratio — a bare "16" would be ~5dp on a 3x
  /// screen and make the bar flip on every scroll wobble.
  static const _snapThreshold = 56.0;

  /// Minimum time between two snaps: flipping again while the bar is
  /// still animating reads as a glitch.
  static const _snapCooldown = Duration(milliseconds: 300);

  static const _barAnimDuration = Duration(milliseconds: 180);

  /// When the bar last snapped, for [_snapCooldown].
  DateTime? _lastSnap;

  /// Whether the floating top bar currently covers the page.
  var _barShown = true;

  bool get _canSnap {
    final last = _lastSnap;
    return last == null || DateTime.now().difference(last) >= _snapCooldown;
  }

  /// Tells every frame of every page to report when an input inside it
  /// takes focus (iframes included), so the address field lets go.
  static final _pageFocusScript = UserScript(
    source: '''
document.addEventListener('focusin', function (event) {
  var target = event.target;
  if (!target) return;
  var tag = (target.tagName || '').toUpperCase();
  if (tag === 'INPUT' || tag === 'TEXTAREA' || target.isContentEditable) {
    var bridge = window.flutter_inappwebview;
    if (bridge && bridge.callHandler) bridge.callHandler('pageInputFocused');
  }
}, true);
''',
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    forMainFrameOnly: false,
  );

  /// Brings the top bar back and remembers where the page stands now,
  /// so the next scroll decides from the current position.
  void _showTopBar() {
    final tab = _activeTab;
    tab.scrollAnchor = tab.scrollY;
    if (_barShown) return;
    _lastSnap = DateTime.now();
    setState(() => _barShown = true);
  }

  /// Flips the bar and restarts the snap cooldown. A snap that is
  /// still cooling down re-arms its anchor instead, so the same
  /// movement decides again one threshold later — nothing is lost and
  /// nothing flips twice in a row.
  void _snap({required bool shown, required _BrowserTab tab, required int y}) {
    if (!_canSnap) {
      tab.scrollAnchor = y;
      return;
    }
    _lastSnap = DateTime.now();
    tab.scrollAnchor = y;
    setState(() => _barShown = shown);
  }

  /// Snaps the top bar with the page: away on the way down, back on
  /// the way up (or at the very top). Only the visible tab drives it.
  void _handleScroll(_BrowserTab tab, int y) {
    if (!mounted || !_tabs.contains(tab)) return;
    tab.scrollY = y;
    if (tab.id != _activeId) return;
    // The address field keeps the bar pinned while it is focused.
    if (_addressFocus.hasFocus) return;

    // The bar moves in logical pixels, the web view reports raw ones.
    final threshold =
        (MediaQuery.devicePixelRatioOf(context) * _snapThreshold).round();

    if (y <= 0) {
      // At the very top the bar always shows; the next scroll down
      // still needs the full threshold to hide it again.
      tab.scrollAnchor = 0;
      if (!_barShown) {
        _lastSnap = DateTime.now();
        setState(() => _barShown = true);
      }
      return;
    }

    final anchor = tab.scrollAnchor;
    if (_barShown) {
      if (y - anchor >= threshold) {
        _snap(shown: false, tab: tab, y: y);
      } else if (y < anchor) {
        // Keep the anchor at the topmost point: a reversal back down
        // then hides the bar again after the threshold.
        tab.scrollAnchor = y;
      }
    } else {
      if (anchor - y >= threshold) {
        _snap(shown: true, tab: tab, y: y);
      } else if (y > anchor) {
        // Follow the deepest point: scrolling up from it reveals.
        tab.scrollAnchor = y;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _addressController.text = _activeTab.url;
  }

  @override
  void dispose() {
    _addressController.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- tabs

  void _newTab({String url = _homeUrl}) {
    final tab = _BrowserTab(id: _nextTabId++, url: url);
    setState(() {
      _tabs.add(tab);
      _activeId = tab.id;
    });
    _showTopBar();
    _syncAddress();
  }

  void _closeTab(_BrowserTab tab) {
    final index = _tabs.indexOf(tab);
    if (index < 0) return;

    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        _tabs.add(_BrowserTab(id: _nextTabId++, url: _homeUrl));
      }
      if (_activeId == tab.id) {
        // The page that takes the closed one's place becomes active.
        _activeId = _tabs[index < _tabs.length ? index : _tabs.length - 1].id;
      }
    });
    _syncAddress();
  }

  void _selectTab(int id) {
    if (id == _activeId) return;
    setState(() => _activeId = id);
    _showTopBar();
    _syncAddress();
  }

  /// Puts the active page's address into the field, unless the user is
  /// busy typing one.
  void _syncAddress() {
    if (_addressFocus.hasFocus) return;
    _addressController.text = _activeTab.url;
  }

  // ------------------------------------------------------------ address

  /// Opens what the user entered: an address as it is, anything else
  /// as a Google search.
  Future<void> _submitAddress() async {
    final target = browserTargetUri(_addressController.text);
    if (target == null) return;

    _addressFocus.unfocus();
    final tab = _activeTab;
    final address = target.toString();
    setState(() {
      tab.url = address;
      // Show the resolved address right away, like a browser does.
      _addressController.text = address;
      // Without a web view nothing will report progress back.
      if (tab.controller != null) tab.progress = 0;
    });
    _showTopBar();

    final controller = tab.controller;
    // Not created yet: it loads [tab.url] as soon as it is.
    if (controller == null) return;
    try {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(tab.url)));
    } catch (_) {
      if (mounted) setState(() => tab.progress = 100);
    }
  }

  /// Runs [action] on the active page's web view, if it has one yet.
  Future<void> _onController(
    Future<void> Function(InAppWebViewController controller) action,
  ) async {
    final controller = _activeTab.controller;
    if (controller == null) return;
    try {
      await action(controller);
    } catch (_) {
      // The web view can disappear mid-call; nothing to do about it.
    }
  }

  // ------------------------------------------------------- web view glue

  void _handleLoadStart(_BrowserTab tab, String? url) {
    if (!mounted || !_tabs.contains(tab)) return;
    setState(() {
      tab.progress = 0;
      if (url != null && url.isNotEmpty) tab.url = url;
    });
    if (tab.id == _activeId) {
      _showTopBar();
      _syncAddress();
    }
  }

  void _handleLoadStop(_BrowserTab tab, String? url) {
    if (!mounted || !_tabs.contains(tab)) return;
    setState(() {
      tab.progress = 100;
      if (url != null && url.isNotEmpty) tab.url = url;
    });
    if (tab.id == _activeId) _syncAddress();
    _refreshNavState(tab);
  }

  void _handleProgress(_BrowserTab tab, int progress) {
    if (!mounted || !_tabs.contains(tab) || tab.progress == progress) return;
    setState(() => tab.progress = progress);
  }

  void _handleTitle(_BrowserTab tab, String? title) {
    if (!mounted || !_tabs.contains(tab)) return;
    setState(() => tab.title = title ?? '');
  }

  void _handleHistory(_BrowserTab tab, String? url) {
    if (!mounted || !_tabs.contains(tab)) return;
    setState(() {
      if (url != null && url.isNotEmpty) tab.url = url;
    });
    if (tab.id == _activeId) _syncAddress();
    _refreshNavState(tab);
  }

  /// Reads after a navigation whether the page can step back/forward.
  Future<void> _refreshNavState(_BrowserTab tab) async {
    final controller = tab.controller;
    if (controller == null) return;
    try {
      final back = await controller.canGoBack();
      final forward = await controller.canGoForward();
      if (!mounted || !_tabs.contains(tab)) return;
      setState(() {
        tab.canGoBack = back;
        tab.canGoForward = forward;
      });
    } catch (_) {
      // The web view went away while it was being asked.
    }
  }

  /// `target="_blank"` and `window.open()`: keep the link inside the
  /// browser by opening it as a new tab of our own.
  Future<bool?> _onCreateWindow(
    InAppWebViewController controller,
    CreateWindowAction action,
  ) async {
    final url = action.request.url?.toString();
    if (url != null && url.isNotEmpty) _newTab(url: url);
    // We created the "window": no separate web view is needed.
    return true;
  }

  /// Blocks main-frame jumps to schemes nothing can open yet (`tel:`,
  /// `mailto:`, `intent:` ...) instead of letting them fail silently.
  Future<NavigationActionPolicy?> _overrideUrlLoading(
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    final url = action.request.url;
    if (action.isForMainFrame &&
        url != null &&
        url.scheme != 'http' &&
        url.scheme != 'https') {
      return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  }

  /// Long press on a link: offer opening it in a new tab or copying it.
  Future<void> _onLongPressHitTest(
    InAppWebViewController controller,
    InAppWebViewHitTestResult result,
  ) async {
    final type = result.type;
    final isLink = type == InAppWebViewHitTestResultType.SRC_ANCHOR_TYPE ||
        type == InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE;
    if (!isLink) return;

    final raw = result.extra;
    if (raw == null) return;
    var url = Uri.tryParse(raw);
    if (url == null) return;
    if (!url.hasScheme) {
      // A relative href: resolve it against the page it was hit on.
      final base = Uri.tryParse(_activeTab.url);
      if (base == null) return;
      url = base.resolveUri(url);
    }
    if (url.scheme != 'http' && url.scheme != 'https') return;
    if (!mounted) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.tab_rounded),
              title: const Text('Open in new tab'),
              onTap: () => Navigator.pop(context, 'new-tab'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy link'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'new-tab':
        _newTab(url: url.toString());
      case 'copy':
        await Clipboard.setData(ClipboardData(text: url.toString()));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link copied')),
        );
    }
  }

  Widget _buildWebView(_BrowserTab tab) {
    return InAppWebView(
      key: ValueKey(tab.id),
      initialSettings: InAppWebViewSettings(
        // Let pages open their own windows: they become our tabs.
        supportMultipleWindows: true,
        javaScriptCanOpenWindowsAutomatically: true,
        useShouldOverrideUrlLoading: true,
        // Players must be able to start without a gesture so their
        // video requests fire (the extractor relied on this too).
        mediaPlaybackRequiresUserGesture: false,
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([
        _pageFocusScript,
      ]),
      onWebViewCreated: (controller) {
        tab.controller = controller;
        // An input focused inside the page releases the omnibox.
        controller.addJavaScriptHandler(
          handlerName: 'pageInputFocused',
          callback: (args) {
            if (_addressFocus.hasFocus) _addressFocus.unfocus();
            return null;
          },
        );
        // Loading here instead of through an initial url means a tab
        // always opens the address it holds, even one entered before
        // the web view was created.
        controller.loadUrl(urlRequest: URLRequest(url: WebUri(tab.url)));
      },
      onLoadStart: (controller, url) => _handleLoadStart(tab, url?.toString()),
      onLoadStop: (controller, url) => _handleLoadStop(tab, url?.toString()),
      onProgressChanged: (controller, progress) =>
          _handleProgress(tab, progress),
      onTitleChanged: (controller, title) => _handleTitle(tab, title),
      onScrollChanged: (controller, x, y) => _handleScroll(tab, y),
      onUpdateVisitedHistory: (controller, url, isReload) =>
          _handleHistory(tab, url?.toString()),
      shouldOverrideUrlLoading: _overrideUrlLoading,
      onCreateWindow: _onCreateWindow,
      onLongPressHitTestResult: _onLongPressHitTest,
    );
  }

  // ---------------------------------------------------------------- build

  /// The open pages as chips: tap to switch, X to close.
  Widget _buildTabStrip() {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: [for (final tab in _tabs) _buildTabChip(tab)],
            ),
          ),
          IconButton(
            onPressed: _newTab,
            icon: const Icon(Icons.add_rounded),
            tooltip: 'New tab',
          ),
        ],
      ),
    );
  }

  Widget _buildTabChip(_BrowserTab tab) {
    final active = tab.id == _activeId;
    final scheme = Theme.of(context).colorScheme;
    final host = Uri.tryParse(tab.url)?.host.replaceFirst('www.', '');
    final label = tab.title.isNotEmpty ? tab.title : (host ?? 'New tab');

    return GestureDetector(
      key: ValueKey('browser-tab-${tab.id}'),
      onTap: () => _selectTab(tab.id),
      child: Container(
        width: 140,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          color:
              active ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: active ? scheme.onPrimaryContainer : null,
                ),
              ),
            ),
            IconButton(
              onPressed: () => _closeTab(tab),
              icon: const Icon(Icons.close, size: 16),
              tooltip: 'Close tab',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              iconSize: 16,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  /// Back, forward, the address field and reload/stop.
  ///
  /// Fixed at 56px so the bar's slide distance always matches the
  /// room reserved for it.
  Widget _buildAddressBar(_BrowserTab active) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: active.canGoBack
                  ? () => _onController((c) => c.goBack())
                  : null,
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: active.canGoForward
                  ? () => _onController((c) => c.goForward())
                  : null,
              icon: const Icon(Icons.arrow_forward_rounded),
              tooltip: 'Forward',
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: TextField(
                controller: _addressController,
                focusNode: _addressFocus,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submitAddress(),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search or enter url',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _addressController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _addressController.clear();
                            setState(() {});
                            _addressFocus.requestFocus();
                          },
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: 'Clear',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: () => _onController(
                (c) => active.progress < 100 ? c.stopLoading() : c.reload(),
              ),
              icon: Icon(
                active.progress < 100
                    ? Icons.close_rounded
                    : Icons.refresh_rounded,
              ),
              tooltip: active.progress < 100 ? 'Stop loading' : 'Reload',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeTab;

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Room for the top bar while it shows; it collapses as the
            // bar slides away, so no page content is ever covered.
            AnimatedContainer(
              duration: _barAnimDuration,
              curve: Curves.easeOut,
              height: _barShown ? _topBarHeight : 0,
            ),
            if (active.progress < 100)
              LinearProgressIndicator(
                value: active.progress / 100,
                minHeight: 2,
              ),
            Expanded(
              child: _hasWebView
                  ? IndexedStack(
                      index: _tabs.indexWhere((tab) => tab.id == _activeId),
                      children: [for (final tab in _tabs) _buildWebView(tab)],
                    )
                  : const _NoWebViewNotice(),
            ),
          ],
        ),
        // The bar itself floats on top and slides out of the way.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedSlide(
            offset: _barShown ? Offset.zero : const Offset(0, -1),
            duration: _barAnimDuration,
            curve: Curves.easeOut,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              elevation: 4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTabStrip(),
                  _buildAddressBar(active),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown where no web view can run (widget tests, desktop runs): the
/// browser chrome around it still builds and behaves normally.
class _NoWebViewNotice extends StatelessWidget {
  const _NoWebViewNotice();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'The browser runs inside the Android app',
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      ),
    );
  }
}
