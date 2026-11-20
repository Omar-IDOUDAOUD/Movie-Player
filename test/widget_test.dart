// Smoke tests for the movie player app.

import 'dart:convert';

import 'package:dir_picker/dir_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:movie_player/main.dart';
import 'package:movie_player/folder_repo.dart';
import 'package:movie_player/pages/player/player_page.dart';
import 'package:movie_player/pages/folder_videos/folder_videos_page.dart';
import 'package:movie_player/pages/home/tabs/web_page_tab.dart';
import 'package:movie_player/link_parser.dart';
import 'package:movie_player/watch_history.dart';

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

  testWidgets('landing page shows the tabs and the folder button',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MoviePlayer());

    expect(find.text('MPlayer'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Folder'), findsOneWidget);
    expect(find.text('Network'), findsOneWidget);
    expect(find.text('Web page'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.byTooltip('Toggle theme'), findsOneWidget);
    // The first tab is the folder one.
    expect(find.text('Play videos from folder'), findsOneWidget);
    expect(find.text('Select a Folder'), findsOneWidget);
    // All tabs stay built (IndexedStack): the network tab's two inputs
    // and the browser address field. Hidden tabs are offstage, so these
    // look past the offstage nodes.
    expect(find.byType(TextField, skipOffstage: false), findsNWidgets(3));
    expect(
      find.text('Play Network Video', skipOffstage: false),
      findsOneWidget,
    );
    // The web page tab is a browser: page strip and address controls.
    expect(find.byTooltip('New tab', skipOffstage: false), findsOneWidget);
    expect(find.byTooltip('Back', skipOffstage: false), findsOneWidget);
    // Nothing was saved yet, so the section stays hidden.
    expect(find.text('Picked folders'), findsNothing);
    // History lives in its own tab now, not in the app bar.
    expect(find.byTooltip('Watch history'), findsNothing);
  });

  /// Switches to the landing page tab with the [label] of its bottom bar.
  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
  }

  /// The landing page inputs in order: title, video url (Network tab),
  /// page url (Web page tab). Hidden tabs are offstage, so the indices
  /// are taken across all of them.
  Finder videoUrlField() => find.byType(TextField, skipOffstage: false).at(1);
  Finder pageUrlField() => find.byType(TextField, skipOffstage: false).at(2);

  testWidgets('empty url shows an error instead of opening the player',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MoviePlayer());
    await openTab(tester, 'Network');

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();

    expect(find.text('Enter a valid video url'), findsOneWidget);
    expect(find.byType(PlayerPage), findsNothing);
  });

  testWidgets('malformed url shows an error instead of opening the player',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MoviePlayer());
    await openTab(tester, 'Network');

    await tester.enterText(videoUrlField(), 'not a url');
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();

    expect(find.text('Enter a valid video url'), findsOneWidget);
    expect(find.byType(PlayerPage), findsNothing);
  });

  testWidgets('the error clears while typing a new url',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MoviePlayer());
    await openTab(tester, 'Network');

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(find.text('Enter a valid video url'), findsOneWidget);

    await tester.enterText(videoUrlField(), 'https://example.com/a.mp4');
    await tester.pump();
    expect(find.text('Enter a valid video url'), findsNothing);
  });

  testWidgets('a valid url opens the player page', (WidgetTester tester) async {
    await tester.pumpWidget(const MoviePlayer());
    await openTab(tester, 'Network');

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

  testWidgets('the history tab shows the watch history',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MoviePlayer());
    await openTab(tester, 'History');
    await tester.pumpAndSettle();

    expect(find.text('No watch history yet'), findsOneWidget);
  });

  testWidgets('history tab shows thumbnail, duration and watch position',
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

    await tester.pumpWidget(const MoviePlayer());
    await openTab(tester, 'History');
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

    await tester.pumpWidget(const MoviePlayer());
    await openTab(tester, 'History');
    await tester.pumpAndSettle();

    await tester.tap(find.text('movie.mp4'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PlayerPage), findsOneWidget);
  });

  // --------------------------------------------------------------- browser

  /// Pumps the app on the browser tab of the landing page.
  Future<void> openBrowser(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MoviePlayer());
    await tester.pumpAndSettle();
    await openTab(tester, 'Web page');
    await tester.pumpAndSettle();
  }

  testWidgets('the web page tab is a browser', (WidgetTester tester) async {
    await openBrowser(tester);

    // A strip of open pages, an address field and the nav buttons.
    expect(find.byKey(const ValueKey('browser-tab-0')), findsOneWidget);
    expect(find.byTooltip('New tab'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Forward'), findsOneWidget);
    expect(find.byTooltip('Reload'), findsOneWidget);
    expect(pageUrlField(), findsOneWidget);
    // No web view can run in widget tests: the chrome says so.
    expect(
      find.text('The browser runs inside the Android app'),
      findsOneWidget,
    );
  });

  test('the omnibox opens an address or searches google', () {
    expect(
      browserTargetUri('example.com/watch')?.toString(),
      'https://example.com/watch',
    );
    expect(
      browserTargetUri('localhost:8080')?.toString(),
      'https://localhost:8080',
    );
    expect(
      browserTargetUri('cats and dogs')?.toString(),
      'https://www.google.com/search?q=cats+and+dogs',
    );
    expect(
      browserTargetUri('flutter')?.toString(),
      'https://www.google.com/search?q=flutter',
    );
    expect(browserTargetUri('   '), isNull);
  });

  testWidgets('typing an address in the omnibox shows where it goes',
      (WidgetTester tester) async {
    await openBrowser(tester);

    await tester.enterText(pageUrlField(), 'example.com/watch');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();

    expect(find.text('https://example.com/watch'), findsOneWidget);
  });

  testWidgets('tabs can be opened, switched and closed',
      (WidgetTester tester) async {
    await openBrowser(tester);

    await tester.tap(find.byTooltip('New tab'));
    await tester.pump();
    expect(find.byKey(const ValueKey('browser-tab-1')), findsOneWidget);

    // Switching between the open pages works with the chips.
    await tester.tap(find.byKey(const ValueKey('browser-tab-0')));
    await tester.pump();
    expect(find.byKey(const ValueKey('browser-tab-0')), findsOneWidget);

    // Closing the newest tab leaves the first one alone.
    await tester.tap(find.byTooltip('Close tab').last);
    await tester.pump();
    expect(find.byKey(const ValueKey('browser-tab-1')), findsNothing);
    expect(find.byKey(const ValueKey('browser-tab-0')), findsOneWidget);
  });

  testWidgets('ad blocking can be switched off and on',
      (WidgetTester tester) async {
    await openBrowser(tester);

    final shield = find.byTooltip('Ad blocking');
    expect(shield, findsOneWidget);
    // On by default: the filled shield.
    expect(find.byIcon(Icons.shield), findsOneWidget);

    await tester.tap(shield);
    await tester.pump();
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    expect(find.byIcon(Icons.shield), findsNothing);

    await tester.tap(shield);
    await tester.pump();
    expect(find.byIcon(Icons.shield), findsOneWidget);
    expect(find.byIcon(Icons.shield_outlined), findsNothing);
  });

  // ------------------------------------------------------------ video offer

  /// The browser's state, where a reported video request would land.
  WebPageTabState browserState(WidgetTester tester) =>
      tester.state<WebPageTabState>(find.byType(WebPageTab));

  testWidgets('a video the page loads is offered at the bottom',
      (WidgetTester tester) async {
    await openBrowser(tester);

    // No video found yet: no offer card.
    expect(find.byKey(const ValueKey('video-offer-toast')), findsNothing);

    browserState(tester).debugShowVideoOffer(
      'https://cdn.example.com/movies/the-thing.mp4?token=abc',
    );
    await tester.pump();

    // The offer names the video and offers a play button on the right.
    expect(find.byKey(const ValueKey('video-offer-toast')), findsOneWidget);
    expect(find.text('Play This Video?'), findsOneWidget);
    expect(
      find.text('https://cdn.example.com/movies/the-thing.mp4?token=abc'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    expect(find.byTooltip('Play'), findsOneWidget);
  });

  testWidgets('playing the offered video opens the player',
      (WidgetTester tester) async {
    await openBrowser(tester);

    browserState(tester)
        .debugShowVideoOffer('https://cdn.example.com/movies/the-thing.mp4');
    await tester.pump();

    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PlayerPage), findsOneWidget);
    // The offer was used up, not left behind under the player.
    expect(
      find.byKey(const ValueKey('video-offer-toast'), skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('the offer goes away when the user moves on',
      (WidgetTester tester) async {
    await openBrowser(tester);

    browserState(tester).debugShowVideoOffer('https://cdn.example.com/a.mp4');
    await tester.pump();
    expect(find.byKey(const ValueKey('video-offer-toast')), findsOneWidget);

    // Opening another page takes the offer with it.
    await tester.tap(find.byTooltip('New tab'));
    await tester.pump();
    expect(find.byKey(const ValueKey('video-offer-toast')), findsNothing);

    // Another video can be offered on the new page...
    browserState(tester).debugShowVideoOffer('https://cdn.example.com/b.mp4');
    await tester.pump();
    expect(find.byKey(const ValueKey('video-offer-toast')), findsOneWidget);
    // ...and switching pages takes that one too.
    await tester.tap(find.byKey(const ValueKey('browser-tab-0')));
    await tester.pump();
    expect(find.byKey(const ValueKey('video-offer-toast')), findsNothing);
  });

  // ------------------------------------------------------ shared into app

  /// Simulates Android sending a shared link over the platform channel.
  Future<void> shareLink(WidgetTester tester, String link) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'movie_player/shared_link',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onSharedLink', link),
      ),
      (_) {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  test('shared links are recognised from browser text', () {
    expect(
      parseSharedLink('https://cdn.example.com/v.mp4')?.toString(),
      'https://cdn.example.com/v.mp4',
    );
    // A sentence around the link: the first url wins, without punctuation.
    expect(
      parseSharedLink('Watch https://cdn.example.com/v.mp4 !')?.toString(),
      'https://cdn.example.com/v.mp4',
    );
    // A shared host without a scheme still counts.
    expect(
      parseSharedLink('example.com/v.mp4')?.toString(),
      'https://example.com/v.mp4',
    );
    // Local videos opened from a file manager.
    expect(
      parseSharedLink('content://media/external/video/media/7')?.scheme,
      'content',
    );
    expect(parseSharedLink('just some words'), isNull);
    expect(parseSharedLink(''), isNull);
  });

  test('the link type decides between playing and scanning', () {
    expect(isDirectVideoLink(Uri.parse('https://a.com/v.mp4')), isTrue);
    expect(isDirectVideoLink(Uri.parse('https://a.com/v.mp4?x=1')), isTrue);
    expect(isDirectVideoLink(Uri.parse('content://media/video/1')), isTrue);
    expect(isDirectVideoLink(Uri.parse('https://a.com/episode/1')), isFalse);
  });

  testWidgets('a shared video link opens the player',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MoviePlayer());
    await tester.pumpAndSettle();

    await shareLink(tester, 'https://cdn.example.com/movie.mp4');

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PlayerPage), findsOneWidget);
  });

  testWidgets('a shared web page link is ignored for now',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MoviePlayer());
    await tester.pumpAndSettle();

    await shareLink(tester, 'https://example.com/episode/1');
    await tester.pump(const Duration(milliseconds: 400));

    // No player opens and the landing page stays on its first tab.
    expect(find.byType(PlayerPage), findsNothing);
    expect(find.text('Play videos from folder'), findsOneWidget);
  });
}
