// import 'dart:developer';
// import 'dart:io';
// import 'dart:typed_data';

// import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
// import 'package:flutter/material.dart';
// import 'package:movie_player/routes/player.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:permission_handler/permission_handler.dart';
// // import 'package:video_thumbnail/video_thumbnail.dart';

// class DownloadsPage extends StatefulWidget {
//   const DownloadsPage({super.key});

//   @override
//   State<DownloadsPage> createState() => _DownloadsPageState();
// }

// /// Thrown when the user did not grant access to the media files.
// class _PermissionDeniedException implements Exception {
//   const _PermissionDeniedException();

//   @override
//   String toString() => 'Storage permission denied';
// }

// class _DownloadsPageState extends State<DownloadsPage> {
//   static final _fcThumbnail = FcNativeVideoThumbnail();

//   static const List<String> _videoExtensions = [
//     '.mp4',
//     '.mkv',
//     '.avi',
//     '.mov',
//     '.flv',
//     '.wmv',
//     '.webm',
//     '.m4v',
//   ];

//   /// Kept in a field so the folder is only listed (and the permission only
//   /// requested) once, instead of on every rebuild of the page.
//   late Future<List<File>> _filesFuture;
//   final Map<String, Future<Uint8List?>> _thumbnailCache = {};

//   @override
//   void initState() {
//     super.initState();
//     // _filesFuture = _loadVideos();
//   }

//   // Future<void> _refresh() async {
//     // final future = _loadVideos();
//   //   setState(() {
//   //     _filesFuture = future;
//   //   });
//   //   try {
//   //     await future;
//   //   } catch (_) {
//   //     // The error is rendered by the FutureBuilder.
//   //   }
//   // }

//   // Future<void> _ensureStoragePermission() async {
//   //   // Desktop platforms have no runtime storage permission to ask for.
//   //   if (!Platform.isAndroid) return;

//   //   var status = await Permission.storage.status;
//   //   if (!status.isGranted) {
//   //     status = await Permission.storage.request();
//   //   }
//   //   if (status.isGranted) return;

//   //   // Android 13+ ignores READ_EXTERNAL_STORAGE, videos use READ_MEDIA_VIDEO.
//   //   status = await Permission.videos.status;
//   //   if (!status.isGranted) {
//   //     status = await Permission.videos.request();
//   //   }
//   //   if (!status.isGranted) {
//   //     throw const _PermissionDeniedException();
//   //   }
//   // }

//   // Future<Directory> _downloadsDirectory() async {
//   //   try {
//   //     final directory = await getDownloadsDirectory();
//   //     if (directory != null) return directory;
//   //   } on UnsupportedError {
//   //     // Reported as "unsupported" below (e.g. iOS has no Downloads folder).
//   //   }
//   //   throw UnsupportedError('Downloads folder is not available');
//   // }

//   // Future<List<File>> _loadVideos() async {
//   //   await _ensureStoragePermission();
//   //   final directory = await _downloadsDirectory();

//   //   final videos = <File>[];
//   //   final found = directory.listSync();

//   //   log(found.length.toString());
//   //   for (final entity in found) {
//   //     // Skip sub folders and links, only plain files can be played.
//   //     if (entity is! File) continue;
//   //     final path = entity.path.toLowerCase();
//   //     if (_videoExtensions.any(path.endsWith)) {
//   //       videos.add(entity);
//   //     }
//   //   }
//   //   // Newest downloads first.
//   //   videos.sort((a, b) => _lastModified(b).compareTo(_lastModified(a)));
//   //   return videos;
//   // }

//   int _lastModified(File file) {
//     try {
//       return file.lastModifiedSync().millisecondsSinceEpoch;
//     } catch (_) {
//       return 0;
//     }
//   }

//   Widget _videoThumbnail(File file) {
//     final future = _fcThumbnail.saveThumbnailToBytes(
//       srcFile: file.path,
//       width: 300,
//       height: 300,
//       quality: 90,
//       // file.path,
//       // () => VideoThumbnail.thumbnailData(
//       //   video: file.path,
//       //   imageFormat: ImageFormat.JPEG,
//       //   maxWidth: 128,
//       //   quality: 25,
//       // ),
//     );
//     return FutureBuilder<Uint8List?>(
//       future: future,
//       builder: (context, snapshot) {
//         final data = snapshot.data;
//         if (data != null) {
//           return SizedBox.square(
//             dimension: 40,
//             child: Image.memory(data),
//           );
//         }
//         return const Icon(Icons.video_file_outlined);
//       },
//     );
//   }

//   String? _fileSize(File file) {
//     try {
//       return _formatBytes(file.lengthSync());
//     } catch (_) {
//       return null;
//     }
//   }

//   String _formatBytes(int bytes) {
//     const units = ['KB', 'MB', 'GB', 'TB'];
//     var value = bytes.toDouble();
//     if (value < 1024) return '${bytes}B';

//     var unit = -1;
//     do {
//       value /= 1024;
//       unit++;
//     } while (value >= 1024 && unit < units.length - 1);
//     return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
//   }

//   String _fileName(File file) {
//     final segments = file.uri.pathSegments;
//     return segments.isEmpty ? file.path : segments.last;
//   }

//   String _errorMessage(Object error) {
//     if (error is _PermissionDeniedException) {
//       return 'Storage permission is required to list your videos.';
//     }
//     if (error is UnsupportedError) {
//       return 'The Downloads folder is not available on this platform.';
//     }
//     if (error is FileSystemException) {
//       return 'Could not read the Downloads folder: ${error.message}';
//     }
//     return 'Something went wrong!';
//   }

//   Widget _buildError(Object error) {
//     final permissionDenied = error is _PermissionDeniedException;
//     return Center(
//       child: Padding(
//         padding: const EdgeInsets.all(24),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Icon(
//               permissionDenied ? Icons.lock_outline : Icons.error_outline,
//               size: 40,
//               color: Colors.black45,
//             ),
//             const SizedBox(height: 12),
//             Text(
//               _errorMessage(error),
//               textAlign: TextAlign.center,
//             ),
//             const SizedBox(height: 16),
//             Row(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 FilledButton.icon(
//                   onPressed: _refresh,
//                   icon: const Icon(Icons.refresh),
//                   label: const Text('Try again'),
//                 ),
//                 if (permissionDenied) ...[
//                   const SizedBox(width: 8),
//                   TextButton.icon(
//                     onPressed: openAppSettings,
//                     icon: const Icon(Icons.settings),
//                     label: const Text('Open settings'),
//                   ),
//                 ],
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildEmpty() {
//     return RefreshIndicator(
//       onRefresh: _refresh,
//       child: ListView(
//         physics: const AlwaysScrollableScrollPhysics(),
//         children: [
//           const SizedBox(height: 120),
//           const Icon(
//             Icons.video_library_outlined,
//             size: 48,
//             color: Colors.black38,
//           ),
//           const SizedBox(height: 12),
//           const Text(
//             'No videos found in the Downloads folder',
//             textAlign: TextAlign.center,
//           ),
//           const SizedBox(height: 8),
//           Center(
//             child: TextButton.icon(
//               onPressed: _refresh,
//               icon: const Icon(Icons.refresh),
//               label: const Text('Refresh'),
//             ),
//           ),
        // ],
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Download Folder'),
//       ),
//       body: FutureBuilder<List<File>>(
//         future: _filesFuture,
//         builder: (context, snapshot) {
//           if (snapshot.connectionState == ConnectionState.waiting) {
//             return const Center(
//               child: SizedBox.square(
//                 dimension: 35,
//                 child: CircularProgressIndicator(),
//               ),
//             );
//           }

//           if (snapshot.hasError) {
//             return _buildError(snapshot.error!);
//           }

//           final files = snapshot.data ?? const <File>[];
//           if (files.isEmpty) return _buildEmpty();

//           return RefreshIndicator(
//             onRefresh: _refresh,
//             child: ListView.builder(
//               physics: const AlwaysScrollableScrollPhysics(),
//               itemCount: files.length,
//               itemBuilder: (context, index) {
//                 final file = files[index];
//                 final size = _fileSize(file);

//                 return ListTile(
//                   title: Text(_fileName(file)),
//                   subtitle: size == null ? null : Text(size),
//                   leading: _videoThumbnail(file),
//                   onTap: () {
//                     Navigator.push(
//                       context,
//                       MaterialPageRoute(
//                         builder: (_) => PlayerPage(videoFile: file),
//                       ),
//                     );
//                   },
//                 );
//               },
//             ),
//           );
//         },
//       ),
//     );
//   }
// }
