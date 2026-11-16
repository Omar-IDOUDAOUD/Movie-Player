import 'package:dir_picker/dir_picker.dart';
import 'package:flutter/material.dart';
import 'package:movie_player/routes/history.dart';
import 'package:movie_player/routes/local_videos_repo.dart';
import 'package:movie_player/routes/player.dart';
import 'package:movie_player/routes/selected_folder_videos.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({
    super.key,
    required this.onToggleTheme,
  });

  final VoidCallback onToggleTheme;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();

  bool _inputError = false;

  /// True while the folder picker is open, so the button can't be tapped
  /// twice (`DirPicker` rejects a second pick).
  bool _picking = false;

  /// True while a saved folder is being restored and listed.
  bool _restoring = false;

  /// The folders picked in earlier sessions, shown as buttons.
  List<SavedFolder> _savedFolders = const [];

  @override
  void initState() {
    super.initState();
    _loadSavedFolders();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  /// Shows the folders saved in earlier sessions under "Picked folders".
  Future<void> _loadSavedFolders() async {
    final folders = await loadSavedFolders();
    if (!mounted) return;
    setState(() => _savedFolders = folders);
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
        builder: (_) => PlayerPage(
          videoUri: uri,
          videoTitle: _titleController.text,
        ),
      ),
    );

    _titleController.clear();
    _urlController.clear();
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
        title: const Text('MPlayer'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: widget.onToggleTheme,
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
            ),
            tooltip: 'Toggle theme',
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryPage()),
            ),
            icon: const Icon(Icons.history),
            tooltip: 'Watch history',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Scrollable so the saved folder buttons never overflow the screen.
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(25.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Play Network Video'),
                    const SizedBox(
                      height: 5,
                    ),
                    TextField(
                      controller: _titleController,
                      keyboardType: TextInputType.name,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: 'Video Title (Optional)',
                        border: const OutlineInputBorder(),
                        focusedBorder: const OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(
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
                              errorText: _inputError
                                  ? 'Enter a valid video url'
                                  : null,
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
                    const SizedBox(
                      height: 15,
                    ),
                    const Text('Play videos from folder'),
                    FilledButton.icon(
                      label: const Text('Select a Folder'),
                      icon: const Icon(Icons.folder_open_rounded),
                      onPressed: _picking ? null : _pickFolder,
                    ),
                    if (_savedFolders.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Text('Picked folders'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final folder in _savedFolders)
                            OutlinedButton.icon(
                              onPressed: _restoring
                                  ? null
                                  : () => _openSavedFolder(folder),
                              icon: const Icon(Icons.folder_rounded),
                              label: Text(folder.name),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Picks a folder and opens the page listing its video files.
  Future<void> _pickFolder() async {
    setState(() => _picking = true);
    try {
      final folder = await selectVideosFolder();
      // The user cancelled the picker: stay on the landing page.
      if (folder == null || !mounted) return;

      await _savePickedFolder(folder);
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SelectedFolderVideosPage(
            entries: folder.entries,
            title: folder.name,
          ),
        ),
      );
    } on DirPickerException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_folderErrorMessage(error))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the folder picker')),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Remembers the picked folder so it shows under "Picked folders".
  ///
  /// Folders without a persist token can't be restored later and are not
  /// saved.
  Future<void> _savePickedFolder(PickedFolder folder) async {
    final token = folder.token;
    if (token == null) return;

    final saved = SavedFolder(token: token, name: folder.name);
    await rememberFolder(saved);
    if (!mounted) return;
    setState(() {
      _savedFolders = [
        ..._savedFolders.where((savedFolder) => savedFolder.token != token),
        saved,
      ];
    });
  }

  /// Restores a saved folder and opens the page listing its videos.
  Future<void> _openSavedFolder(SavedFolder folder) async {
    setState(() => _restoring = true);
    try {
      final location = await DirPicker.restore(folder.token);
      if (location == null) {
        // Access to the folder was lost: drop it from the list.
        await forgetFolder(folder.token);
        if (!mounted) return;
        setState(() {
          _savedFolders = [
            ..._savedFolders.where((saved) => saved.token != folder.token),
          ];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This folder is no longer accessible')),
        );
        return;
      }

      final entries = await DirPicker.listEntries(
        location,
        recursive: true,
      );
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SelectedFolderVideosPage(
            entries: filterVideoEntries(entries),
            title: folder.name,
          ),
        ),
      );
    } on DirPickerException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_folderErrorMessage(error))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this folder')),
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
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
