import 'package:flutter/material.dart';
import 'package:movie_player/routes/downloads.dart';
import 'package:movie_player/routes/player.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final TextEditingController _urlControllr = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Movie Player'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                TextField(
                  controller: _urlControllr,
                ),
                const SizedBox(
                  width: 10,
                ),
                IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PlayerPage(vedioUrl: _urlControllr.text),
                      ),
                    );
                  },
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
            const SizedBox(
              height: 15,
            ),
            TextButton.icon(
              label: const Text("Discover Downloads Folder"),
              icon: const Icon(Icons.download),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DownloadsPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
