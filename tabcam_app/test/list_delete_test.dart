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

  /// A capture of a photo and a link, open on its list.
  Future<String> open(WidgetTester tester, {bool readOnly = false}) async {
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
      id = event.id;
    });
    await tester.pumpWidget(
      MaterialApp(home: EventScreen(library: library, eventId: id)),
    );
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

    // The last file stays: the event is deleted instead.
    final photo = library.byId(id)!.pages.single;
    await tester.tap(find.byKey(ValueKey('delete-${photo.id}')));
    await frames(tester);
    expect(find.textContaining('keeps at least one page'), findsOneWidget);
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
