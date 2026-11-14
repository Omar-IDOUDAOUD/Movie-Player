// Smoke tests for the movie player app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:movie_player/main.dart';
import 'package:movie_player/routes/player.dart';

void main() {
  testWidgets('landing page shows the url input and the downloads button',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MoviePlayer());

    expect(find.text('Movie Player'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
    expect(find.text('Discover Downloads Folder'), findsOneWidget);
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
}
