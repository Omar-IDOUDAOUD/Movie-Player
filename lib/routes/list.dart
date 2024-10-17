import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ListPage extends StatelessWidget {
  const ListPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // final VideoPlayerController controller = VideoPlayerController.file(File(path));
    return ListView.builder(
      itemBuilder: (context, index) => const ListTile(),
    );
  }
}
