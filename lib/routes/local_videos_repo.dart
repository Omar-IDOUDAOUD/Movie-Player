import 'package:dir_picker/dir_picker.dart';

Future<List<FileSystemEntry>?> selectVideosFolder() async {
  final location = await DirPicker.pick();

  if (location == null) {
    return null;
  }

  // Keep permission across app restarts if needed. Persisting is best
  // effort: a failure here must not stop the folder from being listed.
  try {
    await DirPicker.persist(location);
  } catch (_) {
    // Ignored: the current session can still list the folder.
  }

  final entries = await DirPicker.listEntries(
    location,
    recursive: true,
  );

  const extensions = {
    'mp4', 'mkv', 'avi', 'mov',
    'webm', '3gp', 'm4v', 'ts',
  };

  return entries.where((entry) {
    if (entry.isDirectory || entry.uri == null) return false;

    final extension = entry.name.contains('.')
        ? entry.name.split('.').last.toLowerCase()
        : '';

    return extensions.contains(extension);
  }).toList();
}