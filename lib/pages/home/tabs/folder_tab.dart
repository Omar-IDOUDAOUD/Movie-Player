import 'package:dir_picker/dir_picker.dart';
import 'package:flutter/material.dart';
import 'package:movie_player/folder_repo.dart';
import 'package:movie_player/pages/folder_videos/folder_videos_page.dart';
import 'package:movie_player/pages/home/tabs/tab_body.dart';

/// The "Folder" tab: pick a folder and list the saved ones.
class FolderTab extends StatefulWidget {
  const FolderTab({super.key});

  @override
  State<FolderTab> createState() => _FolderTabState();
}

class _FolderTabState extends State<FolderTab> {
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

  /// Shows the folders saved in earlier sessions under "Picked folders".
  Future<void> _loadSavedFolders() async {
    final folders = await loadSavedFolders();
    if (!mounted) return;
    setState(() => _savedFolders = folders);
  }

  @override
  Widget build(BuildContext context) {
    return TabBody(
      children: [
        const Text('Play videos from folder'),
        const SizedBox(
          height: 5,
        ),
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
                  onPressed:
                      _restoring ? null : () => _openSavedFolder(folder),
                  icon: const Icon(Icons.folder_rounded),
                  label: Text(folder.name),
                ),
            ],
          ),
        ],
      ],
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
