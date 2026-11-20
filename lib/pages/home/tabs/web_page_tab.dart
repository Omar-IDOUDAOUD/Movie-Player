import 'dart:collection';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:movie_player/ad_filter.dart';
import 'package:movie_player/link_parser.dart';
import 'package:movie_player/pages/player/player_page.dart';
import 'package:movie_player/video_requests.dart';

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
///
/// Ad blocking runs on two levels: the WebView's native content
/// blockers stop ad requests ([adContentBlockers]), and a document
/// start script hides what a blocked request leaves behind
/// ([adHideScript]). The shield in the strip switches both off and on
/// for every open page.
///
/// Every resource a page loads is watched ([isVideoRequest]): every
/// find is remembered on its tab, and the tab in front offers its
/// newest find on a card at the bottom of the viewport — switching
/// tabs away and back brings the offer up again, dismissing only
/// hides it. The button next to reload lists every video found on the
/// page. Playing one stops the media of every open page and hands the
/// address to the app's own player, remembered in history under the
/// page's title.
class WebPageTab extends StatefulWidget {
  const WebPageTab({super.key});

  @override
  State<WebPageTab> createState() => WebPageTabState();
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
  // int scrollY = 0;

  /// The position the top bar last snapped at; the bar toggles once
  /// the page has moved far enough away from it.
  // int scrollAnchor = 0;

  /// Set once the platform web view for this tab exists.
  InAppWebViewController? controller;

  /// Every video address found while this tab was open, oldest first
  /// and once per address — the list behind the count badge and the
  /// bottom sheet. It outlives the offer: dismissing the card does
  /// not take a video off it.
  final Set<String> videos = {};

  /// The video this tab currently offers on its card at the bottom
  /// of the viewport, or null: always the newest find, cleared when
  /// the card is played, dismissed or the page navigates. Stored per
  /// tab, so switching away and back brings an unplayed offer up
  /// again.
  String? offerUrl;
}

class WebPageTabState extends State<WebPageTab> {
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
  // static const _snapThreshold = 56.0;

  /// Minimum time between two snaps: flipping again while the bar is
  /// still animating reads as a glitch.
  // static const _snapCooldown = Duration(milliseconds: 300);

  // static const _barAnimDuration = Duration(milliseconds: 180);

  // /// When the bar last snapped, for [_snapCooldown].
  // DateTime? _lastSnap;

  // /// Whether the floating top bar currently covers the page.
  // var _barShown = true;

  /// Whether ad requests are blocked and ad leftovers hidden.
  var _adBlockOn = true;

  // bool get _canSnap {
  //   final last = _lastSnap;
  //   return last == null || DateTime.now().difference(last) >= _snapCooldown;
  // }

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

  /// Runs in every frame of every page: pauses its `video`/`audio`
  /// elements when the app broadcasts `__mplayer_pause` and passes
  /// the word to the frames it contains, so an embedded player stops
  /// too — the cascade walks the whole frame tree of a page.
  ///
  /// The same script widens the resource timing buffer: a busy page
  /// would drop resource reports after ~250 and with them the video
  /// request the offer card waits for.
  static final _pageMediaScript = UserScript(
    source: '''
window.addEventListener('message', function (event) {
  if (event.data !== '__mplayer_pause') return;
  var media = document.querySelectorAll('video, audio');
  for (var i = 0; i < media.length; i++) {
    try { media[i].pause(); } catch (e) {}
  }
  var frames = document.querySelectorAll('iframe');
  for (var j = 0; j < frames.length; j++) {
    try {
      frames[j].contentWindow.postMessage('__mplayer_pause', '*');
    } catch (e) {}
  }
}, false);
try {
  if (window.performance && performance.setResourceTimingBufferSize) {
    performance.setResourceTimingBufferSize(1000);
  }
} catch (e) {}
''',
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    forMainFrameOnly: false,
  );

  /// Brings the top bar back and remembers where the page stands now,
  /// so the next scroll decides from the current position.
  // void _showTopBar() {
  //   final tab = _activeTab;
  //   tab.scrollAnchor = tab.scrollY;
  //   if (_barShown) return;
  //   _lastSnap = DateTime.now();
  //   setState(() => _barShown = true);
  // }

  /// Flips the bar and restarts the snap cooldown. A snap that is
  /// still cooling down re-arms its anchor instead, so the same
  /// movement decides again one threshold later — nothing is lost and
  /// nothing flips twice in a row.
  // void _snap({required bool shown, required _BrowserTab tab, required int y}) {
  //   if (!_canSnap) {
  //     tab.scrollAnchor = y;
  //     return;
  //   }
  //   _lastSnap = DateTime.now();
  //   tab.scrollAnchor = y;
  //   setState(() => _barShown = shown);
  // }

  /// Snaps the top bar with the page: away on the way down, back on
  /// the way up (or at the very top). Only the visible tab drives it.
  // void _handleScroll(_BrowserTab tab, int y) {
  //   if (!mounted || !_tabs.contains(tab)) return;
  //   tab.scrollY = y;
  //   if (tab.id != _activeId) return;
  //   // The address field keeps the bar pinned while it is focused.
  //   if (_addressFocus.hasFocus) return;

  //   // The bar moves in logical pixels, the web view reports raw ones.
  //   final threshold =
  //       (MediaQuery.devicePixelRatioOf(context) * _snapThreshold).round();

  //   if (y <= 0) {
  //     // At the very top the bar always shows; the next scroll down
  //     // still needs the full threshold to hide it again.
  //     tab.scrollAnchor = 0;
  //     if (!_barShown) {
  //       _lastSnap = DateTime.now();
  //       setState(() => _barShown = true);
  //     }
  //     return;
  //   }

  //   final anchor = tab.scrollAnchor;
  //   if (_barShown) {
  //     if (y - anchor >= threshold) {
  //       _snap(shown: false, tab: tab, y: y);
  //     } else if (y < anchor) {
  //       // Keep the anchor at the topmost point: a reversal back down
  //       // then hides the bar again after the threshold.
  //       tab.scrollAnchor = y;
  //     }
  //   } else {
  //     if (anchor - y >= threshold) {
  //       _snap(shown: true, tab: tab, y: y);
  //     } else if (y > anchor) {
  //       // Follow the deepest point: scrolling up from it reveals.
  //       tab.scrollAnchor = y;
  //     }
  //   }
  // }

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
    // _showTopBar();
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
    // The offer travels with its tab: what the viewport shows is
    // whatever the tab in front holds, so coming back to a page
    // brings its unplayed offer up again.
    setState(() => _activeId = id);
    // _showTopBar();
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
    // _showTopBar();

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
      // The page the offer was made for is going away. The found
      // videos stay: the list belongs to the tab, not the page.
      tab.offerUrl = null;
    });
    if (tab.id == _activeId) {
      // _showTopBar();
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

  // ------------------------------------------------------- video offer

  /// A resource the page finished loading: when it looks like a
  /// video, remember it for its tab and offer it at the bottom of
  /// the viewport.
  ///
  /// Every tab collects, so a page finishing in the background is
  /// not lost. An address already known — offered, played or
  /// dismissed — does not raise the card again: an HLS stream
  /// re-requests its manifest every few seconds. A new find always
  /// replaces the card that is up. An ad's video is never the page's
  /// video, so it is skipped while ad blocking is on.
  void _handleResource(_BrowserTab tab, LoadedResource resource) {
    log("RESOURCE : ${resource.toMap()}");
    if (!mounted || !_tabs.contains(tab)) return;

    final url = resource.url?.toString();

    if (url == null) return;
    if (!isVideoRequest(url, initiatorType: resource.initiatorType)) return;

    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (_adBlockOn && blocksAdUrl(uri)) return;

    setState(() {
      tab.videos
        ..removeWhere((element) => cleanUrl(element) == cleanUrl(url))
        ..add(url);
      tab.offerUrl = url;
    });
    log("EXTRACTED VIDEO : $url");
  }

  /// Plays [url] in the app's player after stopping the media of
  /// every open page — background tabs included, they can keep
  /// playing under the player. History remembers the video under
  /// the current page's title.
  Future<void> _playVideo(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final title = _activeTab.title;

    await _pauseAllPages();

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerPage(
          videoUri: uri,
          videoTitle: title.isNotEmpty ? title : null,
        ),
      ),
    );
  }

  /// Plays what the card offers and lets the card go.
  Future<void> _playOfferedVideo() async {
    final tab = _activeTab;
    final url = tab.offerUrl;
    if (url == null) return;
    setState(() => tab.offerUrl = null);
    await _playVideo(url);
  }

  /// Hides the card; the video stays on the tab's list.
  void _dismissOffer() {
    final tab = _activeTab;
    if (tab.offerUrl == null) return;
    setState(() => tab.offerUrl = null);
  }

  /// Plays a video picked from the list; its card, if that is what
  /// is up, has been used.
  Future<void> _playFromSheet(String url) async {
    final tab = _activeTab;
    if (tab.offerUrl == url) setState(() => tab.offerUrl = null);
    await _playVideo(url);
  }

  /// Every video found on the page behind the tab in front, one per
  /// line: tap to play it in the app's player.
  void _showFoundVideos() {
    final videos = _activeTab.videos;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Found videos',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
            ),
            if (videos.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No videos found on this page yet',
                  textAlign: TextAlign.center,
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: videos.length,
                  itemBuilder: (context, index) => ListTile(
                    leading: const Icon(Icons.play_circle_outline_rounded),
                    title: Text(
                      describeVideoUrl(videos.elementAt(videos.length - index-1)),
                      maxLines:2 ,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _playFromSheet(
                          videos.elementAt(videos.length - index-1));
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Asks every open page to stop its media. The message reaches
  /// each frame through [_pageMediaScript], which cascades it into
  /// the frames each page contains.
  Future<void> _pauseAllPages() async {
    for (final tab in List.of(_tabs)) {
      final controller = tab.controller;
      if (controller == null) continue;
      try {
        await controller.evaluateJavascript(
          source: "window.postMessage('__mplayer_pause', '*')",
        );
      } catch (_) {
        // A page that went away mid-pause has nothing left to stop.
      }
    }
  }

  /// Shows the offer for [url] and puts it on the tab's list the way
  /// a reported video request would. Widget tests run without a web
  /// view to report one, so they call this directly.
  @visibleForTesting
  void debugShowVideoOffer(String url) {
    final tab = _activeTab;
    setState(() {
      if (!tab.videos.contains(url)) tab.videos.add(url);
      tab.offerUrl = url;
    });
  }

  /// `target="_blank"` and `window.open()`: keep the link inside the
  /// browser by opening it as a new tab of our own — unless it is an
  /// ad popup, which is swallowed instead.
  Future<bool?> _onCreateWindow(
    InAppWebViewController controller,
    CreateWindowAction action,
  ) async {
    final url = action.request.url?.toString();
    if (url != null && url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null && _adBlockOn && blocksAdHost(uri)) return true;
      _newTab(url: url);
    }
    // We created the "window": no separate web view is needed.
    return true;
  }

  /// Blocks main-frame jumps to schemes nothing can open yet (`tel:`,
  /// `mailto:`, `intent:` ...) and ad redirects, instead of letting
  /// them fail silently or yanking the user off the page.
  Future<NavigationActionPolicy?> _overrideUrlLoading(
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    final url = action.request.url;
    if (url != null && action.isForMainFrame) {
      if (url.scheme != 'http' && url.scheme != 'https') {
        return NavigationActionPolicy.CANCEL;
      }
      if (_adBlockOn && blocksAdHost(url)) {
        return NavigationActionPolicy.CANCEL;
      }
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

  /// The web view's settings. The only piece that changes after
  /// creation is the ad-blocking rule set, so the toggle hands this
  /// same object back with a different [InAppWebViewSettings.contentBlockers]
  /// — everything else must stay identical or it would reset.
  InAppWebViewSettings _buildSettings() => InAppWebViewSettings(
        // Let pages open their own windows: they become our tabs.
        supportMultipleWindows: true,
        javaScriptCanOpenWindowsAutomatically: true,
        useShouldOverrideUrlLoading: true,
        // Players must be able to start without a gesture so their
        // video requests fire (the extractor relied on this too).
        mediaPlaybackRequiresUserGesture: false,
        // Report every resource the page loads, so videos can be
        // offered. Kept explicit: the ad toggle re-sends this whole
        // settings object and would drop anything left unset.
        useOnLoadResource: true,
        // Native rules stop ad hosts and ad paths on every request.
        // (A Dart shouldInterceptRequest would disable this path.)
        contentBlockers: _adBlockOn ? adContentBlockers() : const [],
      );

  /// Switches ad blocking: the open pages swap their native rules and
  /// their style script follows the flag.
  void _toggleAdBlock() {
    setState(() => _adBlockOn = !_adBlockOn);
    final on = _adBlockOn;
    for (final tab in List.of(_tabs)) {
      final controller = tab.controller;
      if (controller != null) _applyAdBlock(on, controller);
    }
  }

  Future<void> _applyAdBlock(
    bool on,
    InAppWebViewController controller,
  ) async {
    try {
      await controller.setSettings(settings: _buildSettings());
      await controller.evaluateJavascript(
        source: 'window.__mplayerAdBlock && window.__mplayerAdBlock($on)',
      );
    } catch (_) {
      // The page went away mid-toggle; a fresh one opens with the
      // current flag anyway.
    }
  }

  Widget _buildWebView(_BrowserTab tab) {
    return InAppWebView(
      key: ValueKey(tab.id),
      initialSettings: _buildSettings(),
      initialUserScripts: UnmodifiableListView<UserScript>([
        _pageFocusScript,
        _pageMediaScript,
        UserScript(
          source: adHideScript(_adBlockOn),
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: false,
        ),
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
      // onScrollChanged: (controller, x, y) => _handleScroll(tab, y),
      onUpdateVisitedHistory: (controller, url, isReload) =>
          _handleHistory(tab, url?.toString()),
      onLoadResource: (controller, resource) => _handleResource(tab, resource),
      // shouldInterceptRequest: (controller, request) async {
      //   // log("INTERC REQ : ${request.url}");
      //   return null;
      // },
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
            onPressed: _toggleAdBlock,
            icon: Icon(
              _adBlockOn ? Icons.shield : Icons.shield_outlined,
              size: 20,
            ),
            tooltip: 'Ad blocking',
            visualDensity: VisualDensity.compact,
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
                onTapOutside: (event) {
                  _addressFocus.unfocus();
                },
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
              onPressed: _showFoundVideos,
              icon: Badge(
                isLabelVisible: active.videos.isNotEmpty,
                label: Text('${active.videos.length}'),
                child: const Icon(Icons.video_library, size: 22),
              ),
              tooltip: 'Found videos',
              visualDensity: VisualDensity.compact,
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
              // duration: _barAnimDuration,
              duration: Duration(microseconds: 0),
              curve: Curves.easeOut,
              // height: _barShown ? _topBarHeight : 0,
              height: _topBarHeight,
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
            // offset: _barShown ? Offset.zero : const Offset(0, -1),
            // duration: _barAnimDuration,
            offset: Offset.zero,
            duration: Duration(microseconds: 0),
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
        // A video the page started loading: offered at the bottom of
        // the viewport until it is played, dismissed or the page
        // moves on. The offer belongs to its tab, so it is back when
        // the user returns.
        if (active.offerUrl != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _VideoOfferToast(
              key: const ValueKey('video-offer-toast'),
              url: active.offerUrl!,
              onPlay: _playOfferedVideo,
              onDismiss: _dismissOffer,
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

/// The offer card at the bottom of the page: the address on one line
/// — host and last path node, meeting in the middle with '...' — a
/// dismiss button, and the play button on the far right that hands
/// it to the app's own player. Tapping anywhere else on the card
/// plays it too.
class _VideoOfferToast extends StatelessWidget {
  const _VideoOfferToast({
    super.key,
    required this.url,
    required this.onPlay,
    required this.onDismiss,
  });

  /// The video address the page asked to load.
  final String url;

  final VoidCallback onPlay;

  /// Hides the card without dropping the video from the tab's list.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.only(
            left: 14,
            top: 10,
            bottom: 10,
            right: 4,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Play This Video?',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      describeVideoUrl(url),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded, size: 20),
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: onPlay,
                icon: Icon(
                  Icons.play_circle_fill_rounded,
                  color: scheme.primary,
                  size: 36,
                ),
                tooltip: 'Play',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
