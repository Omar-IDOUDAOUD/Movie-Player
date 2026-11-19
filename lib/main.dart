import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:movie_player/pages/home/home_page.dart';
import 'package:movie_player/pages/player/player_page.dart';
import 'package:movie_player/link_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MoviePlayer());
}

/// Where Android sends the links shared into (or opened with) the app.
const sharedLinkChannel = MethodChannel('movie_player/shared_link');

class MoviePlayer extends StatefulWidget {
  const MoviePlayer({super.key});

  @override
  State<MoviePlayer> createState() => _MoviePlayerState();
}

class _MoviePlayerState extends State<MoviePlayer> {
  static const _themeModeKey = 'theme_mode';

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  ThemeMode _themeMode = ThemeMode.system;

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

  /// Opens a shared video right away.
  ///
  /// A shared web page is ignored for now: the browser tab will take
  /// it over in a later step.
  void _handleSharedLink(String raw) {
    final link = parseSharedLink(raw);
    if (link == null || !isDirectVideoLink(link)) return;

    void open() {
      if (!mounted) return;
      _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => PlayerPage(videoUri: link, videoTitle: ''),
        ),
      );
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
      home: HomePage(
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}
