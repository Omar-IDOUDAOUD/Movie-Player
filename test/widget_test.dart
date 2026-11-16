// Smoke tests for the movie player app.

import 'dart:async';
import 'dart:convert';

import 'package:dir_picker/dir_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:movie_player/main.dart';
import 'package:movie_player/routes/history.dart';
import 'package:movie_player/routes/landing.dart';
import 'package:movie_player/routes/local_videos_repo.dart';
import 'package:movie_player/routes/player.dart';
import 'package:movie_player/routes/selected_folder_videos.dart';
import 'package:movie_player/routes/watch_history.dart';

void main() {
  /// A single playable entry of a picked folder.
  FileSystemEntry makeEntry(String name) => FileSystemEntry(
        name: name,
        relativePath: name,
        isDirectory: false,
        uri: Uri.parse('file:///videos/$name'),
        size: 1024 * 1024,
      );

  /// One watch history entry, with a duration of one minute.
  WatchHistoryEntry makeHistoryEntry(String uri, {int positionMs = 1000}) =>
      WatchHistoryEntry(
        uri: uri,
        title: uri.split('/').last,
        durationMs: 60000,
        positionMs: positionMs,
        watchedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

  // Keep the saved preferences of one test out of the next one.
  tearDown(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('landing page shows the url input and the folder button',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MoviePlayer());

    expect(find.text('MPlayer'), findsOneWidget);
    // Title, video url and web page url inputs.
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byTooltip('Watch history'), findsOneWidget);
    expect(find.text('Play videos from folder'), findsOneWidget);
    expect(find.text('Select a Folder'), findsOneWidget);
    expect(find.text('Play Video from a web page url'), findsOneWidget);
    expect(find.byTooltip('Scan page for videos'), findsOneWidget);
    // Nothing was saved yet, so the section stays hidden.
    expect(find.text('Picked folders'), findsNothing);
  });

  /// The landing page inputs in order: title, video url, web page url.
  Finder videoUrlField() => find.byType(TextField).at(1);
  Finder pageUrlField() => find.byType(TextField).at(2);

  testWidgets('empty url shows an error instead of opening the player',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MoviePlayer());

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();

    expect(find.text('Enter a valid video url'), findsOneWidget);
    expect(find.byType(PlayerPage), findsNothing);
  });

  testWidgets('malformed url shows an error instead of opening the player',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MoviePlayer());

    await tester.enterText(videoUrlField(), 'not a url');
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();

    expect(find.text('Enter a valid video url'), findsOneWidget);
    expect(find.byType(PlayerPage), findsNothing);
  });

  testWidgets('the error clears while typing a new url',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MoviePlayer());

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(find.text('Enter a valid video url'), findsOneWidget);

    await tester.enterText(videoUrlField(), 'https://example.com/a.mp4');
    await tester.pump();
    expect(find.text('Enter a valid video url'), findsNothing);
  });

  testWidgets('a valid url opens the player page', (WidgetTester tester) async {
    await tester.pumpWidget(const MoviePlayer());

    // A missing scheme is completed with https://
    await tester.enterText(videoUrlField(), 'example.com/video.mp4');
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    // Let the page transition finish.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.text('Enter a valid video url'), findsNothing);
  });

  testWidgets('folder page lists the entries it was given',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SelectedFolderVideosPage(
          entries: [makeEntry('first.mp4'), makeEntry('second.mkv')],
        ),
      ),
    );

    expect(find.byType(ListTile), findsNWidgets(2));
    expect(find.text('first.mp4'), findsOneWidget);
    expect(find.text('second.mkv'), findsOneWidget);
  });

  testWidgets('tapping an entry opens the player for it',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SelectedFolderVideosPage(entries: [makeEntry('movie.mp4')]),
      ),
    );

    await tester.tap(find.text('movie.mp4'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PlayerPage), findsOneWidget);
  });

  testWidgets('folder page shows an empty state when there are no videos',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SelectedFolderVideosPage(entries: []),
      ),
    );

    expect(find.byType(ListTile), findsNothing);
    expect(find.text('No videos found in this folder'), findsOneWidget);
  });

  test('folder name is derived from the picked location', () {
    expect(folderNameFromUri(Uri.parse('file:///C:/Users/Videos')), 'Videos');
    expect(folderNameFromUri(Uri.parse('file:///home/me/movies')), 'movies');
    expect(
      folderNameFromUri(Uri.parse(
        'content://com.example.provider/tree/primary%3ADCIM',
      )),
      'DCIM',
    );
    expect(
      folderNameFromUri(Uri.parse(
        'content://com.example.provider/tree/primary%3ADCIM%2FCamera',
      )),
      'Camera',
    );
    expect(folderNameFromUri(null), 'Folder');
  });

  test('saved folders are remembered without duplicates', () async {
    SharedPreferences.setMockInitialValues({});

    await rememberFolder(const SavedFolder(token: 'file:///a', name: 'A'));
    await rememberFolder(const SavedFolder(token: 'file:///b', name: 'B'));
    await rememberFolder(const SavedFolder(token: 'file:///a', name: 'A new'));

    final folders = await loadSavedFolders();
    expect(folders.map((folder) => folder.name), ['B', 'A new']);

    await forgetFolder('file:///b');
    expect(
      (await loadSavedFolders()).map((folder) => folder.name),
      ['A new'],
    );
  });

  test('watch history keeps one entry per video, newest first', () async {
    SharedPreferences.setMockInitialValues({});

    await WatchHistory.record(makeHistoryEntry('file:///v/one.mp4'));
    await WatchHistory.record(
      makeHistoryEntry('file:///v/two.mp4', positionMs: 2000),
    );
    await WatchHistory.record(
      makeHistoryEntry('file:///v/one.mp4', positionMs: 5000),
    );

    final history = await WatchHistory.load();
    expect(
      history.map((entry) => entry.uri),
      ['file:///v/one.mp4', 'file:///v/two.mp4'],
    );
    expect(history.first.positionMs, 5000);

    await WatchHistory.record(makeHistoryEntry('file:///v/one.mp4'));
    expect(await WatchHistory.load(), hasLength(2));
  });

  testWidgets('saved folders show as buttons under "Picked folders"',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'picked_folders': jsonEncode([
        {'token': 'content://gone/a', 'name': 'Videos'},
        {'token': 'content://gone/b', 'name': 'Movies'},
      ]),
    });

    await tester.pumpWidget(const MoviePlayer());
    await tester.pumpAndSettle();

    expect(find.text('Picked folders'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNWidgets(2));
    expect(find.widgetWithText(OutlinedButton, 'Videos'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Movies'), findsOneWidget);
  });

  testWidgets('a saved folder without access shows a message',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'picked_folders': jsonEncode([
        {'token': 'content://gone/folder', 'name': 'Gone'},
      ]),
    });

    await tester.pumpWidget(const MoviePlayer());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gone'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(SnackBar), findsOneWidget);

    // Let the snackbar dismiss itself so no timer is left pending.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('the history button opens the watch history page',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MoviePlayer());
    await tester.tap(find.byTooltip('Watch history'));
    await tester.pumpAndSettle();

    expect(find.byType(HistoryPage), findsOneWidget);
    expect(find.text('No watch history yet'), findsOneWidget);
  });

  testWidgets('history page shows thumbnail, duration and watch position',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'watch_history': jsonEncode([
        {
          'uri': 'file:///videos/movie.mp4',
          'title': 'movie.mp4',
          'durationMs': 3723000, // 1:02:03
          'positionMs': 2712000, // 0:45:12
          'watchedAt': 1700000000000,
        },
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HistoryPage()));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('movie.mp4'), findsOneWidget);
    expect(find.text('1:02:03 • last at 0:45:12'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // No thumbnail can be generated in a test: the tile falls back to an icon.
    expect(find.byIcon(Icons.video_file_outlined), findsOneWidget);
  });

  testWidgets('tapping a history entry opens the player for it',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'watch_history': jsonEncode([
        {
          'uri': 'file:///videos/movie.mp4',
          'title': 'movie.mp4',
          'durationMs': 3723000,
          'positionMs': 2712000,
          'watchedAt': 1700000000000,
        },
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HistoryPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('movie.mp4'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PlayerPage), findsOneWidget);
  });

  // ------------------------------------------------- play from a web page

  /// Pumps a landing page whose page scanner is [scan].
  Future<void> pumpLanding(
    WidgetTester tester,
    Future<List<Uri>> Function(Uri page) scan,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: LandingPage(onToggleTheme: () {}, findVideos: scan),
      ),
    );
  }

  testWidgets('an invalid web page url shows an error instead of scanning',
      (WidgetTester tester) async {
    var scanned = false;
    await pumpLanding(tester, (page) async {
      scanned = true;
      return const [];
    });

    await tester.tap(find.byTooltip('Scan page for videos'));
    await tester.pump();

    expect(find.text('Enter a valid web page url'), findsOneWidget);
    expect(scanned, isFalse);

    // The error clears while typing a valid page url.
    await tester.enterText(pageUrlField(), 'example.com/watch');
    await tester.pump();
    expect(find.text('Enter a valid web page url'), findsNothing);
  });

  testWidgets('the scan shows a spinner until the videos are found',
      (WidgetTester tester) async {
    final scan = Completer<List<Uri>>();
    await pumpLanding(tester, (page) => scan.future);

    await tester.enterText(
      pageUrlField(),
      'https://example.com/episode/1',
    );
    await tester.tap(find.byTooltip('Scan page for videos'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    scan.complete([Uri.parse('https://cdn.example.com/video.m3u8')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(PlayerPage), findsOneWidget);
  });

  testWidgets('a page with one video plays it directly',
      (WidgetTester tester) async {
    final video = Uri.parse('https://cdn.example.com/movie.mp4');
    await pumpLanding(tester, (page) async => [video]);

    await tester.enterText(pageUrlField(), 'example.com/episode/1');
    await tester.tap(find.byTooltip('Scan page for videos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a page with many videos lets the user select one',
      (WidgetTester tester) async {
    final first = Uri.parse('https://cdn.example.com/first.m3u8');
    final second = Uri.parse('https://cdn.example.com/second.mp4');
    await pumpLanding(tester, (page) async => [first, second]);

    await tester.enterText(pageUrlField(), 'example.com/episode/1');
    await tester.tap(find.byTooltip('Scan page for videos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(first.toString()), findsOneWidget);
    expect(find.text(second.toString()), findsOneWidget);
    expect(find.byType(PlayerPage), findsNothing);

    await tester.tap(find.text(second.toString()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(PlayerPage), findsOneWidget);
  });

  testWidgets('a page without videos shows a message', (WidgetTester tester) async {
    await pumpLanding(tester, (page) async => const []);

    await tester.enterText(pageUrlField(), 'example.com/episode/1');
    await tester.tap(find.byTooltip('Scan page for videos'));
    await tester.pump();
    // Let the snackbar finish entering so its dismiss timer starts.
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('No video found on this page'), findsOneWidget);

    // Let the snackbar dismiss itself so no timer is left pending.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a page that cannot be read shows a message',
      (WidgetTester tester) async {
    await pumpLanding(
      tester,
      (page) async => throw Exception('boom'),
    );

    await tester.enterText(pageUrlField(), 'example.com/episode/1');
    await tester.tap(find.byTooltip('Scan page for videos'));
    await tester.pump();

    expect(find.text('Could not read this web page'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
