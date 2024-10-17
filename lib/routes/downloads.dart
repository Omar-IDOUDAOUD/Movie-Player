// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

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
      return files;
    } else {
      throw "Storage permission denied";
    }
  }

  @override
  Widget build(BuildContext context) {
    // final VideoPlayerController controller = VideoPlayerController.file(File(path));
    return FutureBuilder(
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
              ListTile(
                title: Text(fileName),
                leading: const Icon(Icons.file_present),
              );
            },
          );
        }

        return Center(
          child: Text(snapshot.error?.toString() ?? "Something went wrong!"),
        );
      },
    );
  }
}
