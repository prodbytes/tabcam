import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabscan_app/export/exporter.dart';
import 'package:tabscan_app/library/capture_event.dart';
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/screens/event_screen.dart';

/// Lets the screen settle. Not pumpAndSettle: an image's spinner never
/// settles in a test.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

CaptureEvent _event({bool hideImages = false}) => CaptureEvent(
  id: 'a1',
  title: 'Riff',
  created: DateTime(2026, 10, 10),
  tabText: 'e|--0--3--|\n',
  hideImages: hideImages,
  pages: [
    const EventPage(id: 'p1', extension: 'jpg'),
    const EventPage(id: 'p2', kind: PageKind.video, extension: 'mp4'),
    EventPage.link(id: 'p3', url: Uri.parse('https://example.com/lesson')),
  ],
);

void main() {
  test('hidden images leave only the videos and links visible', () {
    expect(_event().visiblePages.map((p) => p.id), ['p1', 'p2', 'p3']);
    expect(_event(hideImages: true).visiblePages.map((p) => p.id), [
      'p2',
      'p3',
    ]);
    // The images are kept.
    expect(_event(hideImages: true).pages, hasLength(3));
  });

  test('the setting is saved, in the cloud copy too', () {
    for (final local in [true, false]) {
      final json = _event(hideImages: true).toJson(local: local);
      expect(json['hideImages'], isTrue);
      expect(CaptureEvent.fromJson(json).hideImages, isTrue);
    }
    expect(_event().toJson().containsKey('hideImages'), isFalse);
    expect(CaptureEvent.fromJson(_event().toJson()).hideImages, isFalse);
  });

  test('a clone keeps the images hidden', () async {
    final library = Library(PlatformEventStore());
    await library.load();
    final page = img.encodeJpg(img.Image(width: 8, height: 8));
    final event = await library.update(
      (await library.create([page])).copyWith(hideImages: true),
    );
    final copy = await library.clone(event);
    expect(copy.hideImages, isTrue);
  });

  test('Files leaves hidden images out of the zip', () async {
    final event = _event(hideImages: true);
    final bytes = await Exporter.zip(event, [
      Uint8List.fromList([1, 2, 3]),
    ]);
    final names = ZipDecoder().decodeBytes(bytes).map((f) => f.name);
    expect(names, ['Riff 1.mp4', 'tab.txt', 'links.txt']);
  });

  testWidgets('the owner hides the images: the text tab, then the rest', (
    tester,
  ) async {
    final library = Library(PlatformEventStore());
    late String id;
    await tester.runAsync(() async {
      await library.load();
      final page = img.encodeJpg(img.Image(width: 8, height: 8));
      var event = await library.create([page]);
      event = await library.addLink(event, parseLink('example.com/lesson')!);
      id = (await library.update(event.copyWith(tabText: 'e|--0--3--|'))).id;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EventScreen(library: library, eventId: id),
      ),
    );
    await _frames(tester);
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);

    // No button for it on the event screen: set on the event.
    expect(find.byTooltip('Hide images'), findsNothing);
    await tester.runAsync(() async {
      await library.update(library.byId(id)!.copyWith(hideImages: true));
    });
    await _frames(tester);
    // The text tab first, then the link: the image is gone.
    expect(find.text('Text tab'), findsOneWidget);
    expect(find.text('e|--0--3--|'), findsOneWidget);
    expect(find.text('Page 1'), findsNothing);
    expect(
      tester.getCenter(find.text('Text tab')).dy,
      lessThan(tester.getCenter(find.text('example.com')).dy),
    );
    expect(find.byTooltip('Show images'), findsNothing);
    // A tap on it shows the Text view.
    await tester.tap(find.text('Text tab'));
    await _frames(tester);
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.byKey(const Key('files')));
    await _frames(tester);

    await tester.runAsync(() async {
      await library.update(library.byId(id)!.copyWith(hideImages: false));
    });
    await _frames(tester);
    expect(find.text('Text tab'), findsNothing);
  });

  testWidgets('only the owner can hide the images', (tester) async {
    final library = Library(PlatformEventStore());
    late String id;
    await tester.runAsync(() async {
      await library.load();
      final event = await library.create(const []);
      final link = await library.addLink(
        event,
        parseLink('example.com/lesson')!,
      );
      id = (await library.update(
        link.copyWith(sharedBy: 'owner@example.com', hideImages: true),
      )).id;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EventScreen(library: library, eventId: id),
      ),
    );
    await _frames(tester);
    expect(find.byTooltip('Hide images'), findsNothing);
    expect(find.byTooltip('Show images'), findsNothing);
    // Hidden by the owner: the person it's shared with sees it so too.
    expect(find.text('No text tab yet'), findsOneWidget);
  });
}
