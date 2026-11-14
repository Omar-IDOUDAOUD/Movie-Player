import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

/// Plays a video from a local [videoFile] or from a network [videoUri].
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, this.videoFile, this.videoUri})
      : assert(
          videoFile != null || videoUri != null,
          'Either videoFile or videoUri must be provided.',
        );

  final File? videoFile;
  final Uri? videoUri;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  late final VideoPlayerController _controller;

  /// Initialized once in [initState], building must not start it again.
  late final Future<void> _initialization;

  SharedPreferences? _prefs;
  bool _pausedByLifecycle = false;

  String get _storageKey =>
      widget.videoFile?.path ?? widget.videoUri.toString();

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _controller = widget.videoFile != null
        ? VideoPlayerController.file(widget.videoFile!)
        : VideoPlayerController.networkUrl(widget.videoUri!);
    WidgetsBinding.instance.addObserver(this);
    _initialization = _initialize();
  }

  Future<void> _initialize() async {
    await _controller.initialize();
    if (!mounted) return;
    await _resumeWatchPosition();
  }

  /// Pauses while the app is backgrounded and resumes when it comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_controller.value.isPlaying) {
        _pausedByLifecycle = true;
        _controller.pause();
      }
    } else if (state == AppLifecycleState.resumed && _pausedByLifecycle) {
      _pausedByLifecycle = false;
      _controller.play();
    }
  }

  /// Remembers where the user stopped watching, so playback can resume.
  ///
  /// Called from dispose(): the position is read synchronously, the rest is
  /// best effort and must never throw while the page is closing.
  Future<void> _saveWatchPosition() async {
    try {
      final positionMs = _controller.value.position.inMilliseconds;
      final durationMs = _controller.value.duration.inMilliseconds;
      if (durationMs <= 0 || positionMs < 5000) return;

      _prefs ??= await SharedPreferences.getInstance();
      if (durationMs - positionMs < 10000) {
        // Almost finished: forget the position so the next play starts over.
        await _prefs!.remove(_storageKey);
      } else {
        await _prefs!.setInt(_storageKey, positionMs);
      }
    } catch (_) {
      // Saving the position is best effort, failures are not fatal.
    }
  }

  /// Seeks back to the saved position of a previous session, if any.
  Future<void> _resumeWatchPosition() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final savedMs = _prefs!.getInt(_storageKey);
      if (savedMs == null || savedMs <= 0) return;

      final durationMs = _controller.value.duration.inMilliseconds;
      // Do not resume close to the end, restart from the beginning instead.
      if (durationMs <= 0 || savedMs >= durationMs - 10000) return;

      await _controller.seekTo(Duration(milliseconds: savedMs));
    } catch (_) {
      // Resuming is best effort, failures are not fatal.
    }
  }

  String _errorMessage(Object? error) {
    if (error is PlatformException) return error.message ?? error.code;
    return error?.toString() ?? 'Unknown error!';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _saveWatchPosition();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox.square(
                dimension: 35,
                child: CircularProgressIndicator(),
              ),
            );
          }

          if (snapshot.hasError || _controller.value.hasError) {
            return _PlaybackError(
              message: _controller.value.errorDescription ??
                  _errorMessage(snapshot.error),
            );
          }

          return _VideoLayers(controller: _controller);
        },
      ),
    );
  }
}

/// Full screen error message with a way back to the previous page.
class _PlaybackError extends StatelessWidget {
  const _PlaybackError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 40,
              color: Colors.white70,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoLayers extends StatefulWidget {
  const _VideoLayers({required this.controller});

  final VideoPlayerController controller;

  @override
  State<_VideoLayers> createState() => _VideoLayersState();
}

class _VideoLayersState extends State<_VideoLayers> {
  static const List<double> _speeds = [
    0.25,
    0.5,
    0.75,
    1,
    1.25,
    1.5,
    1.75,
    2,
  ];

  VideoPlayerController get _controller => widget.controller;

  bool _showOverlay = false;

  /// Speed to restore when a long press (2x) is released.
  double _speedBeforeHold = 1;

  final ValueNotifier<double?> _timelineDragHandlerOffset = ValueNotifier(null);
  final GlobalKey _timeLineKey = GlobalKey();

  final double _timeLineHorPadding = 15;
  final double _timeLineVerPadding = 6;
  late final ValueNotifier<bool> _loading;

  @override
  void initState() {
    super.initState();

    _loading = ValueNotifier(_controller.value.isBuffering);
    _controller.addListener(_onControllerUpdate);

    _controller.play();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _loading.dispose();
    _timelineDragHandlerOffset.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    _loading.value = _controller.value.isBuffering;
    if (!mounted) return;
    // Keep the visible controls (time line, progress) up to date and bring
    // them back once the video finished.
    if (_showOverlay || _controller.value.isCompleted) {
      setState(() {
        if (_controller.value.isCompleted) _showOverlay = true;
      });
    }
  }

  void _showControls() {
    setState(() => _showOverlay = true);
  }

  void _hideControls() {
    setState(() => _showOverlay = false);
  }

  Future<void> _pause() async {
    await _controller.pause();
  }

  Future<void> _play() async {
    await _controller.play();
    if (mounted && _showOverlay) _hideControls();
  }

  Future<void> _pausePlay() async {
    if (_controller.value.isPlaying) {
      _showControls();
      await _pause();
    } else {
      await _play();
    }
  }

  Future<void> _cycleSpeed() async {
    final current = _controller.value.playbackSpeed;
    final index = _speeds.indexWhere((s) => (s - current).abs() < 0.001);

    final double next;
    if (index == -1) {
      // Not one of the predefined speeds (e.g. a custom speed): pick the
      // next higher one, wrapping around to the slowest.
      next = _speeds.firstWhere((s) => s > current, orElse: () => _speeds.first);
    } else {
      next = _speeds[(index + 1) % _speeds.length];
    }

    await _controller.setPlaybackSpeed(next);
    if (mounted) setState(() {});
  }

  Future<void> _startSpeedHold() async {
    _speedBeforeHold = _controller.value.playbackSpeed;
    await _controller.setPlaybackSpeed(2);
    if (mounted) setState(() {});
  }

  Future<void> _endSpeedHold() async {
    await _controller.setPlaybackSpeed(_speedBeforeHold);
    if (mounted) setState(() {});
  }

  Future<void> _seekBy(Duration delta) async {
    final durationMs = _controller.value.duration.inMilliseconds;
    var targetMs =
        _controller.value.position.inMilliseconds + delta.inMilliseconds;
    if (durationMs > 0 && targetMs > durationMs) targetMs = durationMs;
    if (targetMs < 0) targetMs = 0;

    await _controller.seekTo(Duration(milliseconds: targetMs));
    if (mounted) setState(() {});
  }

  /// Width of the time line, `0` while it is not laid out yet.
  double get _timeLineWidth {
    final box = _timeLineKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) return box.size.width;
    return 0;
  }

  Future<void> _seekToMoment(double dx) async {
    final width = _timeLineWidth;
    final durationMs = _controller.value.duration.inMilliseconds;
    if (width <= 0 || durationMs <= 0) return;

    var momentMs = (dx * durationMs / width).round();
    if (momentMs < 0) momentMs = 0;
    if (momentMs > durationMs) momentMs = durationMs;

    await _controller.seekTo(Duration(milliseconds: momentMs));
    if (mounted) setState(() {});
  }

  void _endTimelineDrag() {
    final dx = _timelineDragHandlerOffset.value;
    _timelineDragHandlerOffset.value = null;
    if (dx != null) _seekToMoment(dx);
  }

  /// Progress of the playback between 0 and 1, safe for unknown durations.
  double get _progress {
    final durationMs = _controller.value.duration.inMilliseconds;
    if (durationMs <= 0) return 0;

    var positionMs = _controller.value.position.inMilliseconds;
    if (positionMs < 0) positionMs = 0;
    if (positionMs > durationMs) positionMs = durationMs;
    return positionMs / durationMs;
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  String get _speedLabel {
    final speed = _controller.value.playbackSpeed;
    final rounded = speed.roundToDouble();
    return '${speed == rounded ? rounded.toInt() : speed}x';
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        Navigator.maybePop(context);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space:
        _pausePlay();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _seekBy(const Duration(seconds: 5));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _seekBy(const Duration(seconds: -5));
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onDoubleTap: () =>
                            _seekBy(const Duration(seconds: -5)),
                        onTap: _pausePlay,
                        child: const ColoredBox(color: Colors.transparent),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onDoubleTap: () =>
                            _seekBy(const Duration(seconds: 5)),
                        onTap: _pausePlay,
                        onLongPressStart: (_) => _startSpeedHold(),
                        onLongPressUp: _endSpeedHold,
                        onLongPressCancel: _endSpeedHold,
                        child: const ColoredBox(color: Colors.transparent),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: GestureDetector(
                  onTapDown: (_) => _pause(),
                  onTapUp: (_) => _play(),
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
            ],
          ),
          if (_showOverlay) ...[
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Close player',
              ),
            ),
            ValueListenableBuilder<double?>(
              valueListenable: _timelineDragHandlerOffset,
              builder: (context, dx, _) {
                return Positioned(
                  bottom: _timeLineVerPadding + 2,
                  left: _timeLineHorPadding,
                  right: _timeLineHorPadding,
                  height: 30,
                  child: GestureDetector(
                    onPanDown: (dets) {
                      _timelineDragHandlerOffset.value = dets.localPosition.dx;
                    },
                    onPanUpdate: (dets) {
                      _timelineDragHandlerOffset.value = max(
                        0,
                        min(dets.localPosition.dx, _timeLineWidth),
                      );
                    },
                    onPanEnd: (_) => _endTimelineDrag(),
                    onPanCancel: _endTimelineDrag,
                    child: ColoredBox(
                      color: Colors.transparent,
                      child: dx == null
                          ? const SizedBox.shrink()
                          : Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: dx,
                                height: 30,
                                child: const ColoredBox(color: Colors.white),
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _timeLineHorPadding,
                vertical: _timeLineVerPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Text(
                        '${_formatDuration(_controller.value.position)} / '
                        '${_formatDuration(_controller.value.duration)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          shadows: [
                            BoxShadow(
                              color: Colors.black,
                              offset: Offset.zero,
                              spreadRadius: 2,
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _cycleSpeed,
                        icon: Text(
                          _speedLabel,
                          style: const TextStyle(color: Colors.white),
                        ),
                        tooltip: 'Playback speed',
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 2,
                    child: Stack(
                      key: _timeLineKey,
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                        FractionallySizedBox(
                          widthFactor: _progress,
                          alignment: Alignment.centerLeft,
                          child: const ColoredBox(
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          ValueListenableBuilder<bool>(
            valueListenable: _loading,
            builder: (context, loading, _) {
              if (loading) {
                return const Center(
                  child: SizedBox.square(
                    dimension: 35,
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }
}
