import 'package:flutter/material.dart';
import 'package:movie_player/pages/player/player_page.dart';
import 'package:movie_player/pages/home/tabs/tab_body.dart';
import 'package:movie_player/link_parser.dart';

/// The "Network" tab: play a video url directly.
class NetworkTab extends StatefulWidget {
  const NetworkTab({super.key});

  @override
  State<NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<NetworkTab> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();

  bool _inputError = false;

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _submit() {
    final uri = parseVideoUri(_urlController.text);
    if (uri == null) {
      setState(() => _inputError = true);
      return;
    }

    setState(() => _inputError = false);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerPage(
          videoUri: uri,
          videoTitle: _titleController.text,
        ),
      ),
    );

    _titleController.clear();
    _urlController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return TabBody(
      children: [
        const Text('Play Network Video'),
        const SizedBox(
          height: 5,
        ),
        TextField(
          controller: _titleController,
          keyboardType: TextInputType.name,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            hintText: 'Video Title (Optional)',
            border: OutlineInputBorder(),
            focusedBorder: OutlineInputBorder(),
          ),
        ),
        const SizedBox(
          height: 6,
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onChanged: (_) {
                  if (_inputError) {
                    setState(() => _inputError = false);
                  }
                },
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'Url',
                  errorText: _inputError ? 'Enter a valid video url' : null,
                  border: const OutlineInputBorder(),
                  focusedBorder: const OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              onPressed: _submit,
              icon: const Icon(Icons.play_arrow_rounded),
              tooltip: 'Play',
            ),
          ],
        ),
      ],
    );
  }
}
