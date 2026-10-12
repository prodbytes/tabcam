import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabscan_app/library/capture_event.dart';
import 'package:tabscan_app/screens/link_page.dart';
import 'package:tabscan_app/screens/youtube_player_view.dart';

void main() {
  // Made-up video IDs, not real videos.
  const id = 'Riff_Lesson';

  group('youTubeVideo', () {
    YouTubeVideo? of(String url) => youTubeVideo(Uri.parse(url));

    test('finds the video in each kind of YouTube link', () {
      for (final url in [
        'https://www.youtube.com/watch?v=$id',
        'https://youtube.com/watch?v=$id&list=abc',
        'https://m.youtube.com/watch?v=$id',
        'https://music.youtube.com/watch?v=$id',
        'https://youtu.be/$id',
        'http://youtu.be/$id?si=share',
        'https://www.youtube.com/shorts/$id',
        'https://www.youtube.com/live/$id',
        'https://www.youtube.com/embed/$id',
        'https://www.youtube-nocookie.com/embed/$id',
      ]) {
        expect(of(url)?.id, id, reason: url);
        expect(of(url)?.start, isNull, reason: url);
      }
    });

    test('starts where the link says', () {
      expect(of('https://youtu.be/$id?t=90')?.start, 90);
      expect(of('https://youtu.be/$id?t=90s')?.start, 90);
      expect(of('https://www.youtube.com/watch?v=$id&t=1m30s')?.start, 90);
      expect(of('https://www.youtube.com/watch?v=$id&t=1h2m3s')?.start, 3723);
      expect(of('https://www.youtube.com/embed/$id?start=45')?.start, 45);
      expect(of('https://youtu.be/$id?t=0')?.start, isNull);
      expect(of('https://youtu.be/$id?t=soon')?.start, isNull);
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

  testWidgets('a YouTube link has Play; other links don\'t', (tester) async {
    await show(tester, 'https://youtu.be/$id');
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.byIcon(Icons.smart_display), findsOneWidget);

    await show(tester, 'https://example.com/lesson');
    expect(find.text('Play'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(find.byIcon(Icons.link), findsOneWidget);
  });

  testWidgets('a video that can\'t play here goes back to the link', (
    tester,
  ) async {
    // Tests have no web view, so the player can't start.
    await show(tester, 'https://youtu.be/$id');
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump();
    expect(find.text('This video can\'t be played here'), findsOneWidget);
    expect(find.text('Play'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('https://youtu.be/$id'), findsOneWidget);
  });
}
