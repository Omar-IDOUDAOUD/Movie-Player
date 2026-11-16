import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:movie_player/routes/landing.dart';
import 'package:movie_player/routes/player.dart';
import 'package:movie_player/routes/web_video_extractor_1.dart' show isVideoUrl;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MoviePlayer());
}

/// Where Android sends the links shared into (or opened with) the app.
const sharedLinkChannel = MethodChannel('movie_player/shared_link');

/// The url inside text shared from another app, or `null` when there is
/// none.
///
/// A share can be a bare url (`https://example.com/v.mp4`), a sentence
/// around one (`Watch https://example.com/v.mp4 !`) or a host without a
/// scheme (`example.com/v.mp4`), so the first url wins.
Uri? parseSharedLink(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  var target = RegExp(r'https?://\S+').firstMatch(text)?.group(0);
  target ??= text.contains('://') ? text.split(RegExp(r'\s')).first : null;
  target ??= text.contains(RegExp(r'\s')) ? null : 'https://$text';
  if (target == null) return null;

  // A link copied from running text can end with punctuation.
  target = target.replaceFirst(RegExp(r'[.,;:!?)\]]+$'), '');

  final uri = Uri.tryParse(target);
  if (uri == null) return null;
  // Local files come from file managers; web links need a real host.
  if (uri.scheme == 'content' || uri.scheme == 'file') return uri;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty || uri.host.contains('%')) return null;
  return uri;
}

/// Whether [link] is a video the player can open right away, as opposed to
/// a web page that must be scanned for videos first.
bool isDirectVideoLink(Uri link) {
  if (link.scheme == 'content' || link.scheme == 'file') return true;
  return isVideoUrl(link.toString());
}

class MoviePlayer extends StatefulWidget {
  const MoviePlayer({super.key, this.findVideos});

  /// Passed to the landing page; tests inject a stub so no network is used.
  final Future<List<Uri>> Function(Uri page)? findVideos;

  @override
  State<MoviePlayer> createState() => _MoviePlayerState();
}

class _MoviePlayerState extends State<MoviePlayer> {
  static const _themeModeKey = 'theme_mode';

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  ThemeMode _themeMode = ThemeMode.system;

  /// A web page shared into the app, passed to the landing page so its
  /// extractor starts as soon as the page arrives.
  ({String url, int token})? _sharedPage;
  var _sharedToken = 0;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
    _receiveSharedLinks();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themeModeKey);
    if (!mounted) return;

    setState(() {
      switch (saved) {
        case 'light':
          _themeMode = ThemeMode.light;
          break;
        case 'dark':
          _themeMode = ThemeMode.dark;
          break;
        default:
          _themeMode = ThemeMode.system;
      }
    });
  }

  Future<void> _toggleTheme() async {
    final nextMode = switch (_themeMode) {
      ThemeMode.system => ThemeMode.dark,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.light,
    };

    setState(() => _themeMode = nextMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, nextMode.name);
  }

  /// Listens for the links Android sends over [sharedLinkChannel]: the one
  /// that opened the app, and every later share while it is running.
  Future<void> _receiveSharedLinks() async {
    sharedLinkChannel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedLink') {
        _handleSharedLink((call.arguments as String?) ?? '');
      }
    });

    try {
      final initial =
          await sharedLinkChannel.invokeMethod<String>('getInitialLink');
      if (initial != null) _handleSharedLink(initial);
    } catch (_) {
      // Not running on Android (tests, desktop): no shared links arrive.
    }
  }

  /// Opens a shared video right away, or hands a shared web page to the
  /// landing page extractor.
  void _handleSharedLink(String raw) {
    final link = parseSharedLink(raw);
    if (link == null) return;

    void open() {
      if (!mounted) return;
      if (isDirectVideoLink(link)) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => PlayerPage(videoUri: link, videoTitle: ''),
          ),
        );
        return;
      }

      // A web page: show the landing page and scan it there.
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      setState(() {
        _sharedToken++;
        _sharedPage = (url: link.toString(), token: _sharedToken);
      });
    }

    if (_navigatorKey.currentState != null) {
      open();
    } else {
      // The app is still starting: the first frame creates the routes.
      WidgetsBinding.instance.addPostFrameCallback((_) => open());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MPlayer',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: LandingPage(
        onToggleTheme: _toggleTheme,
        sharedPage: _sharedPage,
        findVideos: widget.findVideos,
      ),
    );
  }
}
