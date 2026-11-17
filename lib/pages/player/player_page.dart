import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:movie_player/watch_history.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

/// Plays a video from a local [videoFile] or from a network [videoUri].
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, this.videoFile, this.videoUri, this.videoTitle})
      : assert(
          videoFile != null || videoUri != null,
          'Either videoFile or videoUri must be provided.',
        );

  final File? videoFile;
  final Uri? videoUri;
  final String? videoTitle;

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
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
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
      // Remember the progress while it is still readable: the system can
      // kill the app in the background without disposing the page.
      _saveWatchPosition();
      _recordHistory();
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

  /// Name shown in the watch history: the file name or the url.
  String get _title {
    if (widget.videoTitle != null) return widget.videoTitle!;

    final file = widget.videoFile;
    if (file != null) {
      final path = file.path;
      final index = path.lastIndexOf(RegExp(r'[/\\]'));
      if (index >= 0 && index < path.length - 1) {
        return path.substring(index + 1);
      }
      return path;
    }
    return widget.videoUri.toString();
  }

  /// The video as a uri string, for the watch history.
  String get _historyUri => widget.videoFile != null
      ? Uri.file(widget.videoFile!.path).toString()
      : widget.videoUri.toString();

  /// Remembers this video in the watch history with the current position.
  ///
  /// Called while the position is still readable, best effort like
  /// [_saveWatchPosition]: it must never throw while the page is closing.
  Future<void> _recordHistory() async {
    try {
      final durationMs = _controller.value.duration.inMilliseconds;
      final positionMs = _controller.value.position.inMilliseconds;
      // Require a second of playback so a video that was only opened
      // without being watched doesn't fill the history.
      if (durationMs <= 0 || positionMs < 1000) return;

      await WatchHistory.record(
        WatchHistoryEntry(
          uri: _historyUri,
          title: _title,
          durationMs: durationMs,
          positionMs: positionMs,
          watchedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      // History is best effort, failures are not fatal.
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
    _recordHistory();
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
                child: CircularProgressIndicator(
                  color: Colors.grey,
                  strokeCap: StrokeCap.round,
                  strokeWidth: 5,
                ),
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
  late final ValueNotifier<bool> _playPause;

  /// Gesture mode: classic "movie mode" (tap zones) or "normal mode"
  /// (tap toggles the controls, a centered button plays/pauses).
  /// Chosen per video: every video starts in movie mode.
  bool _movieMode = true;

  /// Video zoom (1 = fitted) and pan offset, adjusted by pinch and drag.
  double _zoom = 1;
  Offset _pan = Offset.zero;

  /// Pointers currently down, used to track pinch-to-zoom and panning.
  final Map<int, Offset> _activePointers = {};

  /// Distance and zoom captured when a pinch started, its basis.
  double _pinchStartSpan = 0;
  double _pinchStartZoom = 1;

  /// Whether the current touch has panned a zoomed video, so a pan can
  /// undo the pause done by movie mode's hold-to-pause zone.
  bool _panMoved = false;

  /// True between movie mode's hold-to-pause down and its release.
  bool _holdPause = false;

  /// True while a long press (2x) hold is running, so the speed is only
  /// restored once even if up and cancel both fire.
  bool _holdingSpeed = false;

  @override
  void initState() {
    super.initState();

    _loading = ValueNotifier(_controller.value.isBuffering);
    _playPause = ValueNotifier(_controller.value.isPlaying);
    _controller.addListener(_onControllerUpdate);
    _controller.play();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _loading.dispose();
    _playPause.dispose();
    _timelineDragHandlerOffset.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    _loading.value = _controller.value.isBuffering;
    _playPause.value = _controller.value.isPlaying;
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
      next =
          _speeds.firstWhere((s) => s > current, orElse: () => _speeds.first);
    } else {
      next = _speeds[(index + 1) % _speeds.length];
    }

    await _controller.setPlaybackSpeed(next);
    if (mounted) setState(() {});
  }

  Future<void> _startSpeedHold() async {
    if (_holdingSpeed) return;
    _holdingSpeed = true;
    _speedBeforeHold = _controller.value.playbackSpeed;
    await _controller.setPlaybackSpeed(2);
    if (mounted) setState(() {});
  }

  /// Switches the player between portrait and landscape.
  void _toggleOrientation() {
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    SystemChrome.setPreferredOrientations(
      isPortrait
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [DeviceOrientation.portraitUp],
    );
  }

  Future<void> _endSpeedHold() async {
    if (!_holdingSpeed) return;
    _holdingSpeed = false;
    await _controller.setPlaybackSpeed(_speedBeforeHold);
    if (mounted) setState(() {});
  }

  /// Shows the controls when they are hidden and the other way round.
  void _toggleOverlay() {
    setState(() => _showOverlay = !_showOverlay);
  }

  /// Switches between movie mode and normal mode (per video only).
  void _switchMode() {
    setState(() => _movieMode = !_movieMode);
  }

  /// Two fingers are down: remember the distance and zoom to compare with.
  void _startPinch() {
    final points = _activePointers.values.take(2).toList();
    if (points.length < 2) return;
    _pinchStartSpan = (points[0] - points[1]).distance;
    _pinchStartZoom = _zoom;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointers.isEmpty) _panMoved = false;
    _activePointers[event.pointer] = event.position;
    if (_activePointers.length >= 2) _startPinch();
  }

  void _onPointerMove(PointerMoveEvent event) {
    final previous = _activePointers[event.pointer];
    if (previous == null) return;
    _activePointers[event.pointer] = event.position;

    if (_activePointers.length >= 2) {
      // Pinch: scale the video between 1x (fitted) and 4x.
      if (_pinchStartSpan <= 0) return;
      final points = _activePointers.values.take(2).toList();
      if (points.length < 2) return;
      final span = (points[0] - points[1]).distance;
      setState(() {
        _zoom = min(max(_pinchStartZoom * span / _pinchStartSpan, 1.0), 4.0);
        _pan = _clampPan(_pan);
      });
      return;
    }

    // One finger: move around a zoomed video. Skipped while the controls
    // are shown so the timeline drag keeps working untouched.
    if (_zoom > 1 && !_showOverlay) {
      _panMoved = true;
      setState(() => _pan = _clampPan(_pan + (event.position - previous)));
    }
  }

  void _onPointerEnd(PointerEvent event) {
    final resumeAfterPan = _holdPause && _panMoved;
    _activePointers.remove(event.pointer);
    if (_activePointers.length >= 2) {
      // Take the remaining fingers as the new pinch basis.
      _startPinch();
    } else {
      _pinchStartSpan = 0;
    }
    if (resumeAfterPan) {
      // Dragging cancels the hold-to-pause tap, so onTapUp never fires.
      // Resume instead of leaving the video stuck on pause.
      _holdPause = false;
      _play();
    }
  }

  /// Keeps [pan] within the area a zoomed video can still cover, based on
  /// the letterboxed size of the video on the current screen.
  Offset _clampPan(Offset pan) {
    final screen = MediaQuery.sizeOf(context);
    if (screen.height <= 0) return Offset.zero;

    final aspect = _controller.value.aspectRatio;
    final videoAspect = aspect > 0 ? aspect : screen.width / screen.height;
    final screenAspect = screen.width / screen.height;

    final double fitWidth, fitHeight;
    if (videoAspect >= screenAspect) {
      fitWidth = screen.width;
      fitHeight = screen.width / videoAspect;
    } else {
      fitHeight = screen.height;
      fitWidth = screen.height * videoAspect;
    }

    final overX = max(0.0, (fitWidth * _zoom - screen.width) / 2);
    final overY = max(0.0, (fitHeight * _zoom - screen.height) / 2);
    return Offset(
      min(max(pan.dx, -overX), overX),
      min(max(pan.dy, -overY), overY),
    );
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

  /// How far the controls are lifted above their movie mode place, so the
  /// timeline sits a little higher in normal mode.
  double get _controlsLift => _movieMode ? 0 : 40;

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
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Listener(
        // Raw pointer tracking for pinch-to-zoom and panning: raw events
        // never join the gesture arena, so every tap, double tap, long
        // press and timeline drag below behaves exactly as before.
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerEnd,
        onPointerCancel: _onPointerEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Transform.translate(
              // The clamp also resets the pan when the video is back at 1x.
              offset: _clampPan(_pan),
              child: Transform.scale(
                scale: _zoom,
                filterQuality: FilterQuality.medium,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                ),
              ),
            ),
            if (_movieMode)
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
                      onTapDown: (_) {
                        _holdPause = true;
                        _pause();
                      },
                      onTapUp: (_) {
                        _holdPause = false;
                        _play();
                      },
                      child: const ColoredBox(color: Colors.transparent),
                    ),
                  ),
                ],
              )
            else
              // Normal mode: the seek and speed gestures stretch over the
              // full screen height, a single tap anywhere toggles the
              // controls instead of playing/pausing.
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onDoubleTap: () => _seekBy(const Duration(seconds: -5)),
                      onTap: _toggleOverlay,
                      child: const ColoredBox(color: Colors.transparent),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onDoubleTap: () => _seekBy(const Duration(seconds: 5)),
                      onTap: _toggleOverlay,
                      onLongPressStart: (_) => _startSpeedHold(),
                      onLongPressUp: _endSpeedHold,
                      onLongPressCancel: _endSpeedHold,
                      child: const ColoredBox(color: Colors.transparent),
                    ),
                  ),
                ],
              ),
            Positioned(
              top: 16,
              right: 10,
              child: ValueListenableBuilder(
                  valueListenable: _playPause,
                  builder: (context, value, child) {
                    return AnimatedOpacity(
                      opacity: !value ? 1 : 0,
                      curve: Curves.linearToEaseOut,
                      duration: Duration(
                        milliseconds: 200,
                      ),
                      child: AnimatedScale(
                        scale: !value ? 1 : 0,
                        curve: Curves.linearToEaseOut,
                        duration: Duration(
                          milliseconds: 200,
                        ),
                        child: Icon(
                          Icons.pause_rounded,
                          color: Colors.white
                              .withValues(alpha: _showOverlay ? 1 : .2),
                        ),
                      ),
                    );
                  }),
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
                    bottom: _timeLineVerPadding + 5 + _controlsLift,
                    left: _timeLineHorPadding,
                    right: _timeLineHorPadding,
                    height: 30,
                    child: GestureDetector(
                      onPanDown: (dets) {
                        _timelineDragHandlerOffset.value =
                            dets.localPosition.dx;
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
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: AlignmentGeometry.bottomCenter,
                                        end: AlignmentGeometry.topCenter,
                                        colors: [
                                          Colors.white,
                                          Colors.white.withValues(alpha: 0),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  );
                },
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  _timeLineHorPadding,
                  _timeLineVerPadding,
                  _timeLineHorPadding,
                  _timeLineVerPadding + _controlsLift,
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
                          onPressed: _toggleOrientation,
                          icon: const Icon(
                            Icons.screen_rotation,
                            color: Colors.white,
                          ),
                          tooltip: isPortrait
                              ? 'Switch to landscape'
                              : 'Switch to portrait',
                        ),
                        IconButton(
                          onPressed: _switchMode,
                          icon: Icon(
                            _movieMode
                                ? Icons.movie_outlined
                                : Icons.touch_app_outlined,
                            color: Colors.white,
                          ),
                          tooltip: _movieMode
                              ? 'Switch to normal mode'
                              : 'Switch to movie mode',
                        ),
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
                      height: 5,
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
              if (!_movieMode)
                Center(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _playPause,
                    builder: (context, playing, child) {
                      return IconButton(
                        onPressed: _pausePlay,
                        iconSize: 72,
                        tooltip: playing ? 'Pause' : 'Play',
                        icon: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 8),
                          ],
                        ),
                      );
                    },
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
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeCap: StrokeCap.round,
                        strokeWidth: 5,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }
}
