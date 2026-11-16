// Verifies the web-page video scraper against a real page.
// Run with: dart run tool/scan_example.dart [pageUrl]
import 'dart:convert';
import 'dart:io';

import 'package:movie_player/routes/web_video_extractor_1.dart';

Future<void> main(List<String> args) async {
  final page = Uri.parse(
    args.isNotEmpty
        ? args.first
        : 'https://www.qisat.tv/episode/'
            '%d9%85%d8%b3%d9%84%d8%b3%d9%84-%d8%b9%d9%84%d9%8a-'
            '%d9%83%d8%a7%d8%b1%d8%a7-%d8%a7%d9%84%d8%ad%d9%84%d9%82%d8%a9-1/',
  );

  stdout.writeln('Scanning $page ...');
  try {
    final videos = await findVideosOnPage(page);
    stdout.writeln('Found ${videos.length} video(s):');
    for (final video in videos) {
      stdout.writeln('  ${jsonEncode(video.toString())}');
    }
    if (videos.isEmpty) exitCode = 1;
  } catch (error) {
    stderr.writeln('Failed: $error');
    exitCode = 1;
  }
}
