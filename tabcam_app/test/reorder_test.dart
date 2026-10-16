import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/library/event_store_io.dart' as io;
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/event_screen.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  final jpeg = img.encodeJpg(img.Image(width: 8, height: 8));

  group('reorderPages', () {
    late Directory root;
    setUp(() async => root = await Directory.systemTemp.createTemp('tabcam'));
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

  /// Opens an event with a photo, a link and another link (made up), as
  /// [readOnly] or [hideImages] say; or with the photo alone ([single]).
  Future<(Library, String)> open(
    WidgetTester tester, {
    bool readOnly = false,
    bool hideImages = false,
    bool single = false,
  }) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late String id;
    await tester.runAsync(() async {
      await library.load();
      var event = await library.create([jpeg]);
      if (!single) {
        event = await library.addLink(
          event,
          Uri.parse('https://example.com/lesson'),
          title: 'Lesson',
        );
        event = await library.addLink(
          event,
          Uri.parse('https://example.com/drill'),
          title: 'Drill',
        );
      }
      if (readOnly || hideImages) {
        event = await library.update(
          event.copyWith(readOnly: readOnly, hideImages: hideImages),
        );
      }
      id = event.id;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EventScreen(library: library, eventId: id),
      ),
    );
    await frames(tester);
    return (library, id);
  }

  /// Drags [pageId]'s row by its handle [dy] pixels, and lets it save.
  Future<void> drag(WidgetTester tester, String pageId, double dy) async {
    final handle = find.byKey(ValueKey('drag-$pageId'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, dy / 10));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await frames(tester);
  }

  double top(WidgetTester tester, String pageId) =>
      tester.getTopLeft(find.byKey(ValueKey('file-$pageId'))).dy;

  testWidgets('a file dragged by its handle moves in the list, and is saved', (
    tester,
  ) async {
    final (library, id) = await open(tester);
    final [photo, lesson, drill] = [
      for (final p in library.byId(id)!.pages) p.id,
    ];
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));
    // No separate Reorder: the list itself reorders.
    expect(find.byKey(const Key('reorder')), findsNothing);
    expect(find.byIcon(Icons.swap_vert), findsNothing);

    // The last link, above the photo.
    await drag(tester, drill, -(top(tester, drill) - top(tester, photo)) - 20);

    expect(library.byId(id)!.pages.map((p) => p.id), [drill, photo, lesson]);
    expect(top(tester, drill), lessThan(top(tester, photo)));
    expect(top(tester, photo), lessThan(top(tester, lesson)));

    // The rename pencil is still on each row.
    expect(find.byKey(ValueKey('rename-$drill')), findsOneWidget);
  });

  testWidgets('with the images hidden, they keep their places', (tester) async {
    final (library, id) = await open(tester, hideImages: true);
    final [photo, lesson, drill] = [
      for (final p in library.byId(id)!.pages) p.id,
    ];
    expect(find.byKey(ValueKey('file-$photo')), findsNothing);
    expect(find.byKey(const Key('text-tab')), findsOneWidget);

    await drag(tester, drill, -(top(tester, drill) - top(tester, lesson)) - 20);

    expect(library.byId(id)!.pages.map((p) => p.id), [photo, drill, lesson]);
    // The text tab stays first.
    expect(
      tester.getTopLeft(find.byKey(const Key('text-tab'))).dy,
      lessThan(top(tester, drill)),
    );
  });

  testWidgets('no drag handles on a read-only capture', (tester) async {
    await open(tester, readOnly: true);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
    expect(find.byType(ReorderableDragStartListener), findsNothing);
  });

  testWidgets('no drag handles with a single file', (tester) async {
    await open(tester, single: true);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
    expect(find.byKey(const Key('reorder')), findsNothing);
  });
}
