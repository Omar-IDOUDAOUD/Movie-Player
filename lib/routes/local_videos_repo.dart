import 'package:dir_picker/dir_picker.dart';

Future<List<FileSystemEntry>?> selectVideosFolder() async {
  final location = await DirPicker.pick();

  if (location == null) {
    return null;
  }

  // Keep permission across app restarts if needed.
  final token = await DirPicker.persist(location);

  // Save token in SharedPreferences if you want to restore it later.

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