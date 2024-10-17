// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, this.vedioFile, this.vedioUri});
  final File? vedioFile;
  final Uri? vedioUri;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final VideoPlayerController _controller;


  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _controller = widget.vedioFile != null
        ? VideoPlayerController.file(widget.vedioFile!)
        : VideoPlayerController.networkUrl(widget.vedioUri!);
  }

  @override
  dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _saveWatchPosition(
        _controller.dataSource, _controller.value.position.inMilliseconds);
    _controller.dispose();    
    super.dispose();
  }

  SharedPreferences? _prefs;
  Future<void> _saveWatchPosition(String dataSource, milliseconds) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setInt(dataSource, milliseconds);
    } catch (e) {}
  }

  // Future<Duration> _loadWatchPosition() async {
  //   _prefs ??= await SharedPreferences.getInstance();
  //   return Duration(milliseconds: _prefs!.getInt(_controller.dataSource) ?? 0);
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder(
        future: _controller.initialize().then((_) async {
          // final p = await _loadWatchPosition();
          // await _controller.seekTo(p);
        }),
        builder: (_, sn) {
          if (sn.connectionState == ConnectionState.waiting)
            return const Center(
              child: SizedBox.square(
                dimension: 35,
                child: CircularProgressIndicator(),
              ),
            );
          if (!_controller.value.hasError)
            return _VideoLayers(controller: _controller);
          else
            return Center(
              child: Text(
                _controller.value.errorDescription ?? "Unknown error!",
                style: const TextStyle(color: Colors.white),
              ),
            );
        },
      ),
    );
  }
}

class _VideoLayers extends StatefulWidget {
  const _VideoLayers({super.key, required this.controller});
  final VideoPlayerController controller;

  @override
  State<_VideoLayers> createState() => __VideoLayersState();
}

class __VideoLayersState extends State<_VideoLayers> {
  VideoPlayerController get _controller => widget.controller;

  bool _showOverlay = false;

  final ValueNotifier<double?> _timelineDragHandlerOffset = ValueNotifier(null);
  final GlobalKey _timeLineKey = GlobalKey();

  final _timeLineHorPadding = 15.0;
  final _timeLineVerPadding = 6.0;
  late final ValueNotifier<bool> _loading;

  @override
  void initState() {
    super.initState();

    _loading = ValueNotifier(_controller.value.isBuffering);
    _controller.addListener(() {
      _loading.value = _controller.value.isBuffering;
    });

    _controller.play();
  }

  void _showOverlay_() {
    setState(() {
      _showOverlay = true;
    });
  }

  void _hideOverlay() {
    setState(() {
      _showOverlay = false;
    });
  }

  void _pause() {
    _controller.pause();
  }

  void _play() {
    _controller.play();
    if (_showOverlay) _hideOverlay();
  }

  void _pausePlay() {
    if (_controller.value.isPlaying) {
      _showOverlay_();
      _pause();
    } else {
      _play();
    }
  }

  double _previousSpeed = 1;
  Future<void> _speed(double speed) async {
    _previousSpeed = _controller.value.playbackSpeed;
    await _controller.setPlaybackSpeed(speed);
    setState(() {});
  }

  Future<void> _skipMoment() async {
    await _controller
        .seekTo(_controller.value.position + const Duration(seconds: 5));
    setState(() {});
  }

  Future<void> _rollbackMoment() async {
    await _controller
        .seekTo(_controller.value.position - const Duration(seconds: 5));
    setState(() {});
  }

  Future<void> _setMoment(int dx, double timeLineWidth) async {
    final d = _controller.value.duration;
    final momentInMilliseconds =
        (dx * d.inMilliseconds / timeLineWidth).round();

    await _controller.seekTo(Duration(milliseconds: momentInMilliseconds));
    setState(() {});
  }

  late final _timeLineWidth =
      (_timeLineKey.currentContext!.findRenderObject() as RenderBox).size.width;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: widget.controller.value.aspectRatio,
            child: VideoPlayer(widget.controller),
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
                      onDoubleTap: _rollbackMoment,
                      onTap: _pausePlay,
                      child: const ColoredBox(color: Colors.transparent),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onDoubleTap: _skipMoment,
                      onTap: _pausePlay,
                      onLongPressStart: (_) {
                        _speed(2);
                      },
                      onLongPressUp: () {
                        _speed(_previousSpeed);
                      },
                      child: const ColoredBox(color: Colors.transparent),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: GestureDetector(
                child: const ColoredBox(color: Colors.transparent),
                onTapDown: (_) => _pause(),
                onTapUp: (_) => _play(),
              ),
            ),
          ],
        ),
        if (_showOverlay) ...[
          ValueListenableBuilder(
            valueListenable: _timelineDragHandlerOffset,
            builder: (context, dx, _) {
              return Positioned(
                bottom: _timeLineVerPadding + 2,
                left: _timeLineHorPadding,
                right: _timeLineHorPadding,
                height: 30,
                child: GestureDetector(
                  onPanUpdate: (dets) {
                    _timelineDragHandlerOffset.value =
                        max(0, min(dets.localPosition.dx, _timeLineWidth));
                  },
                  onPanDown: (dets) {
                    _timelineDragHandlerOffset.value = dets.localPosition.dx;
                  },
                  onPanEnd: (dets) {
                    _setMoment(_timelineDragHandlerOffset.value!.round(),
                        _timeLineWidth);
                    _timelineDragHandlerOffset.value = null;
                  },
                  onPanCancel: () {
                    _setMoment(_timelineDragHandlerOffset.value!.round(),
                        _timeLineWidth);
                    _timelineDragHandlerOffset.value = null;
                  },
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
                horizontal: _timeLineHorPadding, vertical: _timeLineVerPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  children: [
                    () {
                      final p = _controller.value.position;
                      final d = _controller.value.duration;

                      return Text(
                        "${p.inHours}:${p.inMinutes}:${p.inSeconds} / ${d.inHours}:${d.inMinutes}:${d.inSeconds}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          shadows: [
                            BoxShadow(
                              color: Colors.black,
                              offset: Offset.zero,
                              spreadRadius: 2,
                              blurRadius: 2,
                            )
                          ],
                        ),
                      );
                    }(),
                    const Spacer(),
                    IconButton(
                      onPressed: () {
                        final speeds = <double>[
                          .25,
                          0.5,
                          0.75,
                          1,
                          1.25,
                          1.5,
                          1.75,
                          2
                        ];
                        final s = _controller.value.playbackSpeed;

                        _speed(
                          speeds.elementAtOrNull(speeds.indexOf(s) + 1) ??
                              speeds.elementAt(0),
                        );
                      },
                      icon: Text(
                        () {
                          final s = _controller.value.playbackSpeed;
                          return "${s}x";
                        }(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    )
                  ],
                ),
                SizedBox(
                  height: 2,
                  child: Stack(
                    key: _timeLineKey,
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: Colors.white.withOpacity(.3),
                      ),
                      FractionallySizedBox(
                        widthFactor:
                            (_controller.value.position.inMilliseconds == 0
                                    ? 1
                                    : _controller
                                        .value.position.inMilliseconds) /
                                _controller.value.duration.inMilliseconds,
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
        ValueListenableBuilder(
            valueListenable: _loading,
            builder: (_, loading, __) {
              if (loading)
                return const Center(
                  child: SizedBox.square(
                    dimension: 35,
                    child: CircularProgressIndicator(),
                  ),
                );
              else
                return const SizedBox.shrink();
            })
      ],
    );
  }
}
