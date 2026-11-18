import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/event_screen.dart';

Future<void> frames(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late Library library;

  /// A capture of a photo and a link, open on its list, over Home.
  Future<String> open(
    WidgetTester tester, {
    bool readOnly = false,
    bool shared = false,
  }) async {
    late String id;
    await tester.runAsync(() async {
      library = Library(PlatformEventStore(), null, (_) async => null);
      await library.load();
      var event = await library.create([
        img.encodeJpg(img.Image(width: 8, height: 8)),
      ]);
      event = await library.addLink(
        event,
        Uri.parse('https://example.com/lesson'),
      );
      if (readOnly) {
        event = await library.update(event.copyWith(readOnly: true));
      }
      if (shared) {
        event = await library.update(event.copyWith(sharedBy: 'pat'));
      }
      id = event.id;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EventScreen(library: library, eventId: id),
              ),
            ),
            child: const Text('Home'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Home'));
    await frames(tester);
    return id;
  }

  testWidgets('a file is deleted from the list, once confirmed', (
    tester,
  ) async {
    final id = await open(tester);
    final link = library.byId(id)!.pages.last;
    final delete = find.byKey(ValueKey('delete-${link.id}'));

    // Cancelled: it stays.
    await tester.tap(delete);
    await frames(tester);
    expect(find.text('Delete "example.com"?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await frames(tester);
    expect(library.byId(id)!.pages, hasLength(2));

    // Confirmed: it's gone.
    await tester.tap(delete);
    await frames(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await frames(tester);
    expect(library.byId(id)!.pages, hasLength(1));
    expect(find.text('example.com'), findsNothing);
    // To the trash, with Undo.
    expect(library.byId(id)!.deletedPages, hasLength(1));
    expect(find.textContaining('Deleted "example.com"'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await frames(tester);

    // The last file: the capture goes with it, once confirmed (it says
    // so), to the trash, and the app is back on Home.
    final event = library.byId(id)!;
    final photo = event.pages.single;
    final deleteLast = find.byKey(ValueKey('delete-${photo.id}'));
    await tester.tap(deleteLast);
    await frames(tester);
    expect(find.text('Delete "${event.title}"?'), findsOneWidget);
    expect(
      find.textContaining('is its only file, so the capture goes with it'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await frames(tester);
    expect(library.byId(id)!.pages, hasLength(1));
    expect(find.byType(EventScreen), findsOneWidget);

    await tester.tap(deleteLast);
    await frames(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await frames(tester);
    expect(library.byId(id), isNull);
    expect(library.byIdAll(id)!.isTrashed, isTrue);
    expect(library.byIdAll(id)!.pages, hasLength(1));
    expect(find.byType(EventScreen), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(find.textContaining('Deleted "${event.title}"'), findsOneWidget);
    // Undo brings it back, file and all.
    await tester.tap(find.text('Undo'));
    await frames(tester);
    expect(library.byId(id)!.pages.single.id, photo.id);
  });

  testWidgets('on a capture shared with the user to edit, the last file '
      'stays, and it says why', (tester) async {
    final id = await open(tester, shared: true);
    final link = library.byId(id)!.pages.last;
    await tester.runAsync(() => library.deletePage(library.byId(id)!, link));
    await frames(tester);
    final photo = library.byId(id)!.pages.single;
    await tester.tap(find.byKey(ValueKey('delete-${photo.id}')));
    await frames(tester);
    expect(find.textContaining('keeps at least one file'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(library.byId(id)!.pages, hasLength(1));
  });

  testWidgets('read only, there\'s no delete button', (tester) async {
    final id = await open(tester, readOnly: true);
    for (final page in library.byId(id)!.pages) {
      expect(find.byKey(ValueKey('delete-${page.id}')), findsNothing);
    }
  });
}
