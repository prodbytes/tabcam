import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/screens/link_page.dart';
import 'package:tabcam_app/screens/youtube_link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'fakes.dart';

void main() {
  // Made-up video IDs, not real videos.
  const id = 'Riff_Lesson';

  group('youTubeVideoId', () {
    String? of(String url) => youTubeVideoId(Uri.parse(url));

    test('finds the video in each kind of YouTube link', () {
      for (final url in [
        'https://www.youtube.com/watch?v=$id',
        'https://youtube.com/watch?v=$id&list=abc',
        'https://m.youtube.com/watch?v=$id',
        'https://music.youtube.com/watch?v=$id',
        'https://youtu.be/$id',
        'http://youtu.be/$id?si=share',
        'https://youtu.be/$id?t=90',
        'https://www.youtube.com/shorts/$id',
        'https://www.youtube.com/live/$id',
        'https://www.youtube.com/embed/$id',
        'https://www.youtube-nocookie.com/embed/$id',
      ]) {
        expect(of(url), id, reason: url);
      }
    });

    test('other links are not videos', () {
      for (final url in [
        'https://example.com/watch?v=$id',
        'https://notyoutube.com/watch?v=$id',
        'https://youtu.be.example.com/$id',
        'https://www.youtube.com/',
        'https://www.youtube.com/@channel',
        'https://www.youtube.com/playlist?list=abc',
        'https://www.youtube.com/watch?v=short',
        'https://youtu.be/',
        'https://youtu.be/$id<script>',
        'ftp://youtu.be/$id',
      ]) {
        expect(of(url), isNull, reason: url);
      }
    });
  });

  Future<void> show(WidgetTester tester, String url) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LinkPage(
          page: EventPage.link(id: 'a', url: Uri.parse(url)),
        ),
      ),
    ),
  );

  testWidgets('a YouTube link shows as a video, with no player', (
    tester,
  ) async {
    await show(tester, 'https://youtu.be/$id');
    expect(find.byIcon(Icons.smart_display), findsOneWidget);
    expect(find.text('Play'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);

    await show(tester, 'https://example.com/lesson');
    expect(find.byIcon(Icons.link), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('a YouTube link opens outside the app, at its start time', (
    tester,
  ) async {
    final launcher = FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    await show(tester, 'https://youtu.be/$id?t=90');
    await tester.tap(find.text('Open'));
    await tester.pump();
    final (url, options) = launcher.launched.single;
    expect(url, 'https://youtu.be/$id?t=90');
    expect(options.mode, PreferredLaunchMode.externalApplication);
    expect(options.webOnlyWindowName, '_blank');
  });

  test('only web links are launched', () async {
    final launcher = FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    expect(await launchLink(Uri.parse('javascript:alert(1)')), isFalse);
    expect(await launchLink(Uri.parse('intent://x#Intent;end')), isFalse);
    expect(launcher.launched, isEmpty);
  });
}
