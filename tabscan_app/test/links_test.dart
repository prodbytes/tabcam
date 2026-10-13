import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabscan_app/library/capture_event.dart';
import 'package:tabscan_app/library/event_store_io.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/screens/link_page.dart';

void main() {
  group('parseLink', () {
    test('takes web links, adding https when there is no scheme', () {
      expect(
        parseLink(' youtu.be/abc123 ').toString(),
        'https://youtu.be/abc123',
      );
      expect(
        parseLink('http://example.com/riff?t=30').toString(),
        'http://example.com/riff?t=30',
      );
    });

    test('refuses what isn\'t a web link', () {
      for (final text in [
        '',
        'not a link',
        'riff',
        'javascript:alert(1)',
        'file:///etc/passwd',
        'intent://x#Intent;end',
        'mailto:me@example.com',
      ]) {
        expect(parseLink(text), isNull, reason: text);
      }
    });
  });

  test('a link from elsewhere (the cloud) with another scheme is refused', () {
    expect(
      () => EventPage.fromJson({
        'id': 'a1',
        'kind': 'link',
        'url': 'javascript:alert(1)',
      }),
      throwsFormatException,
    );
  });

  test('links are kept with the event, after a restart', () async {
    final root = await Directory.systemTemp.createTemp('tabscan');
    addTearDown(() => root.delete(recursive: true));
    final library = Library(PlatformEventStore(root));
    await library.load();
    var event = await library.create(const []);
    event = await library.addLink(
      event,
      parseLink('example.com/lesson')!,
      title: '  Lesson  ',
    );
    final reopened = Library(PlatformEventStore(root));
    await reopened.load();
    final link = reopened.events.single.pages.single;
    expect(link.isLink, isTrue);
    expect(link.hasFile, isFalse);
    expect(link.url.toString(), 'https://example.com/lesson');
    expect(link.title, 'Lesson');
    // Deleting a link page has no file to delete, and works.
    await reopened.deletePage(reopened.events.single, link);
    expect(reopened.events.single.pages, isEmpty);
  });

  testWidgets('the link dialog checks the address', (tester) async {
    (Uri, String?)? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await askForLink(context),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'riff');
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(find.text('Enter a web address (https://…)'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'example.com/x');
    await tester.enterText(find.byType(TextField).last, 'Lesson');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(result?.$1.toString(), 'https://example.com/x');
    expect(result?.$2, 'Lesson');
  });

  testWidgets('a link page shows its title and address', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LinkPage(
            page: EventPage.link(
              id: 'a',
              url: Uri.parse('https://example.com/lesson'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('https://example.com/lesson'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });
}
