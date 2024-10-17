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

  bool _inputError = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Movie Player'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Vedio url"),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlControllr,
                    decoration: InputDecoration(
                      hintText: 'Url',
                      errorText: _inputError ? "Unsupported format" : null,
                      border: const OutlineInputBorder(),
                      focusedBorder: const  OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(
                  width: 10,
                ),
                IconButton(
                  onPressed: () {
                    try { 
                      final uri = Uri.parse(_urlControllr.text);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlayerPage(vedioUri: uri),
                        ),
                      );
                    } catch (e) {
                      setState(() {
                        _inputError = true;
                      });
                    }
                  },
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
            const SizedBox(
              height: 15,
            ),
            Text("Select vedio from downloads"),
            FilledButton.icon(
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
