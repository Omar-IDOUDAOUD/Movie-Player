import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One entry of the played-videos history.
class WatchHistoryEntry {
  const WatchHistoryEntry({
    required this.uri,
    required this.title,
    required this.durationMs,
    required this.positionMs,
    required this.watchedAt,
  });

  factory WatchHistoryEntry.fromJson(Map<String, dynamic> json) =>
      WatchHistoryEntry(
        uri: json['uri'] as String,
        title: json['title'] as String,
        durationMs: (json['durationMs'] as num).toInt(),
        positionMs: (json['positionMs'] as num).toInt(),
        watchedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['watchedAt'] as num).toInt(),
        ),
      );

  /// The video as a uri string: `file://`, `content://` or `https://`.
  final String uri;

  /// File name of a local video, or the url of a network video.
  final String title;

  final int durationMs;
  final int positionMs;
  final DateTime watchedAt;

  Duration get duration => Duration(milliseconds: durationMs);
  Duration get position => Duration(milliseconds: positionMs);

  /// How far the user got, between 0 and 1.
  double get progress {
    if (durationMs <= 0) return 0;
    final value = positionMs / durationMs;
    return value.clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'uri': uri,
        'title': title,
        'durationMs': durationMs,
        'positionMs': positionMs,
        'watchedAt': watchedAt.millisecondsSinceEpoch,
      };
}

/// Reads and writes the played-videos history in shared preferences.
class WatchHistory {
  WatchHistory._();

  static const _storageKey = 'watch_history';

  /// Newest entries first, at most this many.
  static const _maxEntries = 100;

  /// All watched videos, most recent first.
  ///
  /// Returns an empty list when nothing was saved yet or the storage
  /// cannot be read.
  static Future<List<WatchHistoryEntry>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return const [];

      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(WatchHistoryEntry.fromJson)
          .toList();
    } catch (_) {
      // No history (or unreadable storage): show none.
      return const [];
    }
  }

  /// Remembers [entry] as the most recent watch of its video.
  ///
  /// One entry per video: an older entry for the same uri is replaced.
  /// Recording is best effort, failures are not fatal.
  static Future<void> record(WatchHistoryEntry entry) async {
    try {
      final entries = [...await load()]
        ..removeWhere((saved) => saved.uri == entry.uri)
        ..insert(0, entry);
      if (entries.length > _maxEntries) {
        entries.removeRange(_maxEntries, entries.length);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(entries.map((saved) => saved.toJson()).toList()),
      );
    } catch (_) {
      // History is best effort, failures are not fatal.
    }
  }
}
