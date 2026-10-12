import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabscan_app/library/event_store_io.dart' as io;
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/screens/event_screen.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  final jpeg = img.encodeJpg(img.Image(width: 8, height: 8));

  group('reorderPages', () {
    late Directory root;
    setUp(() async => root = await Directory.systemTemp.createTemp('tabscan'));
    tearDown(() => root.delete(recursive: true));

    test('saves the new order, across a restart', () async {
      final library = Library(io.PlatformEventStore(root));
      await library.load();
      var event = await library.create([jpeg, jpeg]);
      event = await library.addLink(event, Uri.parse('https://example.com/a'));
      final [a, b, c] = [for (final p in event.pages) p.id];

      await library.reorderPages(event.id, [c, a, b]);
      expect(library.byId(event.id)!.pages.map((p) => p.id), [c, a, b]);

      final reopened = Library(io.PlatformEventStore(root));
      await reopened.load();
      expect(reopened.byId(event.id)!.pages.map((p) => p.id), [c, a, b]);
    });

    test('pages left out keep their places', () async {
      final library = Library(io.PlatformEventStore(root));
      await library.load();
      var event = await library.create([jpeg]);
      event = await library.addLink(event, Uri.parse('https://example.com/a'));
      event = await library.addLink(event, Uri.parse('https://example.com/b'));
      final [image, a, b] = [for (final p in event.pages) p.id];

      // As with the images hidden: only the links are listed.
      await library.reorderPages(event.id, [b, a, 'gone']);
      expect(library.byId(event.id)!.pages.map((p) => p.id), [image, b, a]);
    });
  });

  testWidgets('Reorder drags a page and keeps showing it', (tester) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late String id;
    await tester.runAsync(() async {
      await library.load();
      var event = await library.create([jpeg]);
      event = await library.addLink(
        event,
        Uri.parse('https://example.com/lesson'),
        title: 'Lesson',
      );
      id = event.id;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EventScreen(library: library, eventId: id),
      ),
    );
    await frames(tester);
    final before = library.byId(id)!.pages.map((p) => p.id).toList();

    await tester.tap(find.byKey(const Key('reorder')));
    await frames(tester);
    expect(find.text('Drag to reorder'), findsOneWidget);
    expect(find.text('1. Photo'), findsOneWidget);
    expect(find.text('2. Lesson'), findsOneWidget);

    // Drag the link above the photo.
    final handle = find.byIcon(Icons.drag_handle).last;
    final drag = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await drag.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await drag.up();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await frames(tester);

    expect(library.byId(id)!.pages.map((p) => p.id), before.reversed);
    expect(find.text('1. Lesson'), findsOneWidget);

    // Closed, the photo still shows, now second.
    await tester.tapAt(const Offset(10, 10));
    await frames(tester);
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('no Reorder with a single page', (tester) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late String id;
    await tester.runAsync(() async {
      await library.load();
      id = (await library.create([jpeg])).id;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EventScreen(library: library, eventId: id),
      ),
    );
    await frames(tester);
    expect(find.byKey(const Key('reorder')), findsNothing);
  });
}
