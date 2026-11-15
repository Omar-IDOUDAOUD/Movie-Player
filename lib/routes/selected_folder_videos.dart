import 'dart:io';
import 'dart:typed_data';

import 'package:dir_picker/dir_picker.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:movie_player/routes/player.dart';

/// Lists the video files of a folder picked with `dir_picker`.
///
/// [entries] holds the videos of that folder (see `selectVideosFolder()`).
/// Tapping a video opens it in the [PlayerPage].
class SelectedFolderVideosPage extends StatefulWidget {
  const SelectedFolderVideosPage({
    super.key,
    required this.entries,
    this.title = 'Folder Videos',
  });

  /// The video files of the picked folder.
  final List<FileSystemEntry> entries;

  /// Text shown in the app bar.
  final String title;

  @override
  State<SelectedFolderVideosPage> createState() =>
      _SelectedFolderVideosPageState();
}

class _SelectedFolderVideosPageState extends State<SelectedFolderVideosPage> {
  static final _fcThumbnail = FcNativeVideoThumbnail();

  /// One future per video, so a thumbnail is generated at most once even
  /// when the list scrolls it out of view and back.
  final Map<String, Future<Uint8List?>> _thumbnailCache = {};

  /// The playable entries, grouped by folder for a stable order.
  late List<FileSystemEntry> _videos = _prepare(widget.entries);

  static List<FileSystemEntry> _prepare(List<FileSystemEntry> entries) {
    final videos = entries
        .where((entry) => !entry.isDirectory && entry.uri != null)
        .toList();
    videos.sort(
      (a, b) => a.relativePath
          .toLowerCase()
          .compareTo(b.relativePath.toLowerCase()),
    );
    return videos;
  }

  @override
  void didUpdateWidget(covariant SelectedFolderVideosPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entries, widget.entries)) {
      _videos = _prepare(widget.entries);
      _thumbnailCache.clear();
    }
  }

  /// Opens [entry] in the player, from its path or its content uri.
  void _openVideo(FileSystemEntry entry) {
    final uri = entry.uri;
    if (uri == null) return;

    final Widget player;
    if (uri.scheme == 'file') {
      player = PlayerPage(videoFile: File.fromUri(uri));
    } else {
      // content:// uris from Android's storage access framework are read
      // through the media content resolver, so they are passed as a uri.
      player = PlayerPage(videoUri: uri);
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => player),
    );
  }

  /// Generates a thumbnail, or returns null when the platform can't.
  Future<Uint8List?> _loadThumbnail(Uri uri) async {
    final isFilePath = uri.scheme == 'file';
    try {
      return await _fcThumbnail.saveThumbnailToBytes(
        srcFile: isFilePath ? uri.toFilePath() : uri.toString(),
        width: 168,
        height: 120,
        quality: 70,
        srcFileUri: !isFilePath,
      );
    } catch (_) {
      // No thumbnail: the tile falls back to an icon.
      return null;
    }
  }

  Widget _thumbnail(FileSystemEntry entry) {
    final uri = entry.uri;
    if (uri == null) return const Icon(Icons.video_file_outlined);

    final future = _thumbnailCache.putIfAbsent(
      uri.toString(),
      () => _loadThumbnail(uri),
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

  static String? _formatBytes(int? bytes) {
    if (bytes == null) return null;
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    if (value < 1024) return '$bytes B';

    var unit = -1;
    do {
      value /= 1024;
      unit++;
    } while (value >= 1024 && unit < units.length - 1);
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
  }

  Widget _buildList() {
    return ListView.builder(
      itemCount: _videos.length,
      itemBuilder: (context, index) {
        final entry = _videos[index];
        final inSubfolder = entry.relativePath != entry.name;
        final size = _formatBytes(entry.size);
        final subtitle = [
          if (inSubfolder) entry.relativePath,
          if (size != null) size,
        ].join('  •  ');

        return ListTile(
          title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: subtitle.isEmpty
              ? null
              : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          leading: _thumbnail(entry),
          onTap: () => _openVideo(entry),
        );
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.video_library_outlined, size: 48, color: Colors.black38),
          SizedBox(height: 12),
          Text('No videos found in this folder'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _videos.isEmpty ? _buildEmpty() : _buildList(),
    );
  }
}
