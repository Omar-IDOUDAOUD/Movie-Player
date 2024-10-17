// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:movie_player/routes/player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  Future<bool> _requestStoragePermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    return status.isGranted;
  }

  Future<List<FileSystemEntity>> _getAllDownloadFiles() async {
    if (await _requestStoragePermission()) {
      Directory downloadsDirectory = Directory('/storage/emulated/0/Download');
      List<FileSystemEntity> files = downloadsDirectory.listSync();
      final List<String> videoExtensions = [
        '.mp4',
        '.mkv',
        '.avi',
        '.mov',
        '.flv',
        '.wmv',
        '.webm',
        '.m4v'
      ];

      // Filter video files by their extensions
      List<FileSystemEntity> videoFiles = files.where((file) {
        String filePath = file.path
            .toLowerCase(); // Convert to lowercase to avoid case issues
        return videoExtensions.any((ext) => filePath.endsWith(ext));
      }).toList();
      return videoFiles;
    } else {
      throw "Storage permission denied";
    }
  }

  Widget _getVedioThumbnail(FileSystemEntity file) {
    final uint8list = VideoThumbnail.thumbnailData(
      video: file.path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 128,
      quality: 25,
    );
    return FutureBuilder(
      future: uint8list,
      builder: (context, snapshot) {
        return snapshot.hasData
            ? SizedBox.square(
                dimension: 40, child: Image.memory(snapshot.data!))
            : const Icon(Icons.video_file_outlined);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Download Folder"),
      ),
      body: FutureBuilder(
        future: _getAllDownloadFiles(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(
              child: SizedBox.square(
                dimension: 35,
                child: CircularProgressIndicator(),
              ),
            );
          if (snapshot.hasData) {
            return ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                FileSystemEntity file = snapshot.data![index];
                String fileName = file.path.split('/').last;

                return ListTile(
                  title: Text(fileName),
                  leading: _getVedioThumbnail(file),
                  onTap:(){
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlayerPage(vedioFile: file as File,),
                        ),
                      );
                  } ,
                );
              },
            );
          }

          return Center(
            child: Text(snapshot.error?.toString() ?? "Something went wrong!"),
          );
        },
      ),
    );
  }
}
