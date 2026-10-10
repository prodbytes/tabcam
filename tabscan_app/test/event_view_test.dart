import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabscan_app/library/capture_event.dart';
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/processing/page_filter.dart';
import 'package:tabscan_app/screens/event_screen.dart';

/// Lets animations finish; not pumpAndSettle (page spinners never settle).
Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late Library library;
  late String id;

  Future<void> open(WidgetTester tester, {String? text}) async {
    library = Library(PlatformEventStore(), null, (_) async => null);
    await tester.runAsync(() async {
      await library.load();
      var event = await library.create([
        img.encodeJpg(img.Image(width: 8, height: 8)),
      ]);
      if (text != null) {
        event = await library.update(event.copyWith(tabText: text));
      }
      id = event.id;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EventScreen(library: library, eventId: id),
      ),
    );
    await frames(tester);
  }

  final view = find.byKey(const Key('view'));
  String label(WidgetTester tester) => tester
      .widget<Text>(find.descendant(of: view, matching: find.byType(Text)))
      .data!;

  testWidgets('the first tool cycles Original, Scan and Text', (tester) async {
    await open(tester, text: 'e|--0--3--|');
    // Scanned pages start processed: Scan.
    expect(label(tester), 'Scan');
    expect(find.text('Read tab'), findsNothing);

    await tester.tap(view);
    await frames(tester);
    expect(label(tester), 'Text');
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('1 / 1'), findsNothing);

    await tester.tap(view);
    await frames(tester);
    expect(label(tester), 'Original');
    expect(
      library.byId(id)!.pages.single.filter,
      PageFilter.original,
      reason: 'Original is saved on the image pages',
    );

    await tester.tap(view);
    await frames(tester);
    expect(label(tester), 'Scan');
    expect(library.byId(id)!.pages.single.filter, PageFilter.tab);
  });

  testWidgets('it\'s the first tool, and Read tab is gone', (tester) async {
    await open(tester);
    final tools = ['Scan', 'Add', 'Rotate', 'Delete'];
    final xs = [for (final t in tools) tester.getCenter(find.text(t)).dx];
    expect(xs, [...xs]..sort());
    expect(find.text('Read tab'), findsNothing);
  });

  testWidgets('Text without a text tab says why', (tester) async {
    await open(tester);
    await tester.tap(view);
    await frames(tester);
    // No reader in this test: nothing will read it.
    expect(find.text('No text yet.'), findsOneWidget);
    expect(library.byId(id)!.pages.single.kind, PageKind.image);
  });
}
