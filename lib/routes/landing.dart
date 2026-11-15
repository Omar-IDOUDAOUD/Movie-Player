import 'package:dir_picker/dir_picker.dart';
import 'package:flutter/material.dart';
import 'package:movie_player/routes/selected_folder_videos.dart';
import 'package:movie_player/routes/local_videos_repo.dart';
import 'package:movie_player/routes/player.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final TextEditingController _urlController = TextEditingController();

  bool _inputError = false;

  /// True while the folder picker is open, so the button can't be tapped
  /// twice (`DirPicker` rejects a second pick).
  bool _picking = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _submit() {
    final uri = _parseVideoUri(_urlController.text);
    if (uri == null) {
      setState(() => _inputError = true);
      return;
    }

    setState(() => _inputError = false);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerPage(videoUri: uri),
      ),
    );
  }

  /// Parses [raw] into a playable uri, or returns `null` when unsupported.
  ///
  /// A missing scheme defaults to `https://`, so `example.com/video.mp4`
  /// is accepted as well as a full `https://example.com/video.mp4`.
  Uri? _parseVideoUri(String raw) {
    var text = raw.trim();
    // Uri.parse percent-encodes invalid characters instead of failing, so
    // garbage like "not a url" must be rejected before parsing.
    if (text.isEmpty || RegExp(r'\s').hasMatch(text)) return null;
    if (!text.contains('://')) text = 'https://$text';

    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    // A percent sign in the host means the input was mangled while parsing.
    if (uri.host.contains('%')) return null;
    return uri;
  }

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
            const Text('Video url'),
                  const SizedBox(
              height: 5,
            ),
            Row(
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
                // const SizedBox(
                //   width: 10,
                // ),
                IconButton(
                  onPressed: _submit,
                  icon: const Icon(Icons.play_arrow_rounded),
                  tooltip: 'Play',
                ),
              ],
            ),
            const SizedBox(
              height: 15,
            ),
            const Text('Play videos from folder'),
            FilledButton.icon(
              label: const Text('Select a Folder'),
              icon: const Icon(Icons.folder_open_rounded),
              onPressed: _picking ? null : _pickFolder,
            ),
          ],
        ),
      ),
    );
  }

  /// Picks a folder and opens the page listing its video files.
  Future<void> _pickFolder() async {
    setState(() => _picking = true);
    try {
      final entries = await selectVideosFolder();
      // The user cancelled the picker: stay on the landing page.
      if (entries == null || !mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SelectedFolderVideosPage(entries: entries),
        ),
      );
    } on DirPickerException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_folderErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  String _folderErrorMessage(DirPickerException error) {
    switch (error.code) {
      case DirPickerException.alreadyActive:
        return 'A folder picker is already open';
      case DirPickerException.listError:
        return 'The selected folder could not be read';
      default:
        return error.message ?? 'Could not open the folder picker';
    }
  }
}
