import 'dart:convert';

import 'package:dir_picker/dir_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Storage key of the saved folder list.
const _savedFoldersKey = 'picked_folders';

const _videoExtensions = {
  'mp4', 'mkv', 'avi', 'mov',
  'webm', '3gp', 'm4v', 'ts',
};

/// The video files of a folder picked with `dir_picker`.
class PickedFolder {
  const PickedFolder({
    required this.name,
    required this.entries,
    this.token,
  });

  /// Persist token of the folder, `null` when keeping access failed.
  ///
  /// Save it (see [rememberFolder]) and pass it to [DirPicker.restore] on a
  /// later launch to open the folder again without asking the user.
  final String? token;

  /// Display name of the folder, derived from its location.
  final String name;

  /// The video files inside the folder.
  final List<FileSystemEntry> entries;
}

/// A folder picked in an earlier session, shown again on the landing page.
class SavedFolder {
  const SavedFolder({required this.token, required this.name});

  factory SavedFolder.fromJson(Map<String, dynamic> json) => SavedFolder(
        token: json['token'] as String,
        name: json['name'] as String,
      );

  /// The [DirPicker.persist] token of the folder.
  final String token;

  /// The button text: the folder's name.
  final String name;

  Map<String, dynamic> toJson() => {'token': token, 'name': name};
}

/// Picks a folder and lists its video files, or `null` when cancelled.
Future<PickedFolder?> selectVideosFolder() async {
  final location = await DirPicker.pick();

  if (location == null) {
    return null;
  }

  // Keep permission across app restarts so the folder can be saved and
  // opened again later. Persisting is best effort: a failure here must
  // not stop the folder from being listed.
  String? token;
  try {
    token = await DirPicker.persist(location);
  } catch (_) {
    // Ignored: the current session can still list the folder.
  }

  final entries = await DirPicker.listEntries(
    location,
    recursive: true,
  );

  return PickedFolder(
    token: token,
    name: folderNameFromUri(location.uri),
    entries: filterVideoEntries(entries),
  );
}

/// The video files among [entries], keeping the order of [entries].
List<FileSystemEntry> filterVideoEntries(Iterable<FileSystemEntry> entries) {
  return entries.where((entry) {
    if (entry.isDirectory || entry.uri == null) return false;

    final extension = entry.name.contains('.')
        ? entry.name.split('.').last.toLowerCase()
        : '';

    return _videoExtensions.contains(extension);
  }).toList();
}

/// The display name of the folder [uri] points to.
///
/// `content://…/tree/primary:DCIM/Camera` becomes `Camera` and
/// `file:///C:/Videos` becomes `Videos`.
String folderNameFromUri(Uri? uri) {
  if (uri == null) return 'Folder';

  final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
  final last = segments.isNotEmpty ? segments.last : '';
  if (last.isEmpty) return 'Folder';

  if (uri.scheme == 'file') {
    // A drive root such as `file:///C:` comes back as `C:`.
    if (last.length == 2 && last.endsWith(':')) return last.substring(0, 1);
    return last;
  }

  // Android document ids look like `primary:DCIM/Camera`: drop the volume
  // prefix and keep the last path part.
  var name = last;
  final colon = name.lastIndexOf(':');
  if (colon >= 0) name = name.substring(colon + 1);
  final slash = name.lastIndexOf('/');
  if (slash >= 0) name = name.substring(slash + 1);
  return name.isEmpty ? 'Folder' : name;
}

/// The folders saved in an earlier session, oldest first.
Future<List<SavedFolder>> loadSavedFolders() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_savedFoldersKey);
    if (raw == null || raw.isEmpty) return const [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(SavedFolder.fromJson)
        .toList();
  } catch (_) {
    // No saved folders (or unreadable storage): show none.
    return const [];
  }
}

/// Saves [folder] so it shows under "Picked folders" on the landing page.
///
/// Saving is best effort: a storage failure must never break the flow.
Future<void> rememberFolder(SavedFolder folder) async {
  final folders = [...await loadSavedFolders()]
    ..removeWhere((saved) => saved.token == folder.token)
    ..add(folder);
  await _saveFolders(folders);
}

/// Forgets the folder behind [token], for example when its access was lost.
Future<void> forgetFolder(String token) async {
  final folders = [...await loadSavedFolders()]
    ..removeWhere((saved) => saved.token == token);
  await _saveFolders(folders);
}

Future<void> _saveFolders(List<SavedFolder> folders) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _savedFoldersKey,
      jsonEncode(folders.map((folder) => folder.toJson()).toList()),
    );
  } catch (_) {
    // Saving is best effort, failures are not fatal.
  }
}
