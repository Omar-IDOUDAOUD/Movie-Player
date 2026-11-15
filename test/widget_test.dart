// Smoke tests for the movie player app.

import 'package:dir_picker/dir_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:movie_player/main.dart';
import 'package:movie_player/routes/player.dart';
import 'package:movie_player/routes/selected_folder_videos.dart';

void main() {
  /// A single playable entry of a picked folder.
  FileSystemEntry makeEntry(String name) => FileSystemEntry(
        name: name,
        relativePath: name,
        isDirectory: false,
        uri: Uri.parse('file:///videos/$name'),
        size: 1024 * 1024,
      );

  testWidgets('landing page shows the url input and the folder button',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MoviePlayer());

    expect(find.text('Movie Player'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
    expect(find.text('Select video from downloads'), findsOneWidget);
    expect(find.text('Select a Folder'), findsOneWidget);
  });

  testWidgets('empty url shows an error instead of opening the player',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MoviePlayer());

    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(find.text('Enter a valid video url'), findsOneWidget);
    expect(find.byType(PlayerPage), findsNothing);
  });

  testWidgets('malformed url shows an error instead of opening the player',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MoviePlayer());

    await tester.enterText(find.byType(TextField), 'not a url');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(find.text('Enter a valid video url'), findsOneWidget);
    expect(find.byType(PlayerPage), findsNothing);
  });

  testWidgets('the error clears while typing a new url',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MoviePlayer());

    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    expect(find.text('Enter a valid video url'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'https://example.com/a.mp4');
    await tester.pump();
    expect(find.text('Enter a valid video url'), findsNothing);
  });

  testWidgets('a valid url opens the player page', (WidgetTester tester) async {
    await tester.pumpWidget(const MoviePlayer());

    // A missing scheme is completed with https://
    await tester.enterText(find.byType(TextField), 'example.com/video.mp4');
    await tester.tap(find.byIcon(Icons.send));
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
}
