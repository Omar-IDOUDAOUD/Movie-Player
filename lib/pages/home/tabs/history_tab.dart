import 'dart:io';
import 'dart:typed_data';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:movie_player/pages/player/player_page.dart';
import 'package:movie_player/watch_history.dart';

/// The "History" tab: the videos the user played, with the last watch
/// position of each.
///
/// Every entry shows a thumbnail, the title (file name or url), the
/// duration and how far the user got. Tapping one resumes it in the
/// [PlayerPage].
class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  static final _fcThumbnail = FcNativeVideoThumbnail();

  late Future<List<WatchHistoryEntry>> _history;

  /// One future per video, so a thumbnail is generated at most once.
  final Map<String, Future<Uint8List?>> _thumbnailCache = {};

  @override
  void initState() {
    super.initState();
    _history = WatchHistory.load();
  }

  /// Opens [entry] in the player and refreshes the list when coming back,
  /// so the newest watch position is shown.
  Future<void> _open(WatchHistoryEntry entry) async {
    final uri = Uri.tryParse(entry.uri);
    if (uri == null) return;

    final Widget player;
    if (uri.scheme == 'file') {
      player = PlayerPage(videoFile: File.fromUri(uri));
    } else {
      player = PlayerPage(videoUri: uri);
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => player),
    );
    if (!mounted) return;
    setState(() {
      _history = WatchHistory.load();
    });
  }

  /// Generates a thumbnail, or returns null when the platform can't.
  Future<Uint8List?> _loadThumbnail(WatchHistoryEntry entry) async {
    final uri = Uri.tryParse(entry.uri);
    if (uri == null) return null;

    final isFile = uri.scheme == 'file';
    try {
      return await _fcThumbnail.saveThumbnailToBytes(
        srcFile: isFile ? uri.toFilePath() : entry.uri,
        width: 168,
        height: 120,
        quality: 70,
        srcFileUri: !isFile &&
            uri.scheme != 'http' &&
            uri.scheme != 'https',
      );
    } catch (_) {
      // No thumbnail: the tile falls back to an icon.
      return null;
    }
  }

  Widget _thumbnail(WatchHistoryEntry entry) {
    final future = _thumbnailCache.putIfAbsent(
      entry.uri,
      () => _loadThumbnail(entry),
    );

    return SizedBox(
      width: 56,
      height: 40,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: FutureBuilder<Uint8List?>(
          future: future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data != null) {
              return Image.memory(data, fit: BoxFit.cover);
            }
            return ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.video_file_outlined, size: 20),
            );
          },
        ),
      ),
    );
  }

  /// `H:MM:SS`, the same format the player uses.
  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 48, color: Colors.black38),
          SizedBox(height: 12),
          Text('No watch history yet'),
        ],
      ),
    );
  }

  Widget _buildEntry(BuildContext context, WatchHistoryEntry entry) {
    final subtitle =
        '${_formatDuration(entry.duration)} • last at '
        '${_formatDuration(entry.position)}';

    return ListTile(
      leading: _thumbnail(entry),
      title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: entry.progress,
              minHeight: 3,
            ),
          ),
        ],
      ),
      onTap: () => _open(entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WatchHistoryEntry>>(
      future: _history,
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <WatchHistoryEntry>[];

        if (entries.isEmpty) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox.square(
                dimension: 35,
                child: CircularProgressIndicator(),
              ),
            );
          }
          return _buildEmpty();
        }

        return ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) => _buildEntry(
            context,
            entries[index],
          ),
        );
      },
    );
  }
}
