import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabscan_app/library/capture_event.dart';
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/processing/page_filter.dart';
import 'package:tabscan_app/screens/event_screen.dart';
import 'package:tabscan_app/screens/file_screen.dart';

/// Lets animations finish; not pumpAndSettle (page spinners never settle).
Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late Library library;
  late String id;

  CaptureEvent event() => library.byId(id)!;

  Future<void> open(
    WidgetTester tester, {
    String? text,
    int images = 1,
    bool link = false,
  }) async {
    library = Library(PlatformEventStore(), null, (_) async => null);
    await tester.runAsync(() async {
      await library.load();
      var event = await library.create([
        for (var i = 0; i < images; i++)
          img.encodeJpg(img.Image(width: 8, height: 4)),
      ]);
      if (link) {
        event = await library.addLink(
          event,
          parseLink('example.com/lesson')!,
          title: 'Made-up lesson',
        );
      }
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

  final textTool = find.byKey(const Key('text'));
  final filesTool = find.byKey(const Key('files'));
  final view = find.byKey(const Key('view'));
  String label(WidgetTester tester) => tester
      .widget<Text>(find.descendant(of: view, matching: find.byType(Text)))
      .data!;

  testWidgets('the tools are Files, Text and Add; one Share', (tester) async {
    await open(tester);
    final tools = ['Files', 'Text', 'Add'];
    final xs = [for (final t in tools) tester.getCenter(find.text(t)).dx];
    expect(xs, [...xs]..sort());
    for (final gone in ['Scan', 'Original', 'Rotate', 'Delete', 'Read tab']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(find.byTooltip('Share'), findsOneWidget);
    expect(find.byTooltip('Share with people'), findsNothing);
    expect(find.byTooltip('Rename'), findsOneWidget);
    expect(find.byTooltip('Clone'), findsOneWidget);
  });

  testWidgets('the capture lists its files, with previews', (tester) async {
    await open(tester, images: 2, link: true);
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsOneWidget);
    expect(find.text('Made-up lesson'), findsOneWidget);
    expect(find.byType(FileThumbnail), findsNWidgets(3));
    final ys = [
      for (final t in ['Page 1', 'Page 2', 'Made-up lesson'])
        tester.getCenter(find.text(t)).dy,
    ];
    expect(ys, [...ys]..sort());
  });

  testWidgets('Text and Files switch between the text and the list', (
    tester,
  ) async {
    await open(tester, text: 'e|--0--3--|');
    await tester.tap(textTool);
    await frames(tester);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Page 1'), findsNothing);

    await tester.tap(filesTool);
    await frames(tester);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Page 1'), findsOneWidget);
  });

  testWidgets('a file opens alone; its view is Original or Scan', (
    tester,
  ) async {
    await open(tester, images: 2);
    await tester.tap(find.text('Page 1'));
    await frames(tester);
    expect(find.byType(FileScreen), findsOneWidget);
    // Only that file: titled as it, the list not showing.
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsNothing);

    // Scanned pages start processed: Scan.
    expect(label(tester), 'Scan');
    await tester.tap(view);
    await frames(tester);
    expect(label(tester), 'Original');
    expect(
      [for (final p in event().pages) p.filter],
      [PageFilter.original, PageFilter.tab],
      reason: 'Original is saved on that file only',
    );
    await tester.tap(view);
    await frames(tester);
    expect(label(tester), 'Scan');
    expect(event().pages.first.filter, PageFilter.tab);

    await tester.pageBack();
    await frames(tester);
    expect(find.byType(FileScreen), findsNothing);
    expect(find.text('Page 2'), findsOneWidget);
  });

  testWidgets('Rotate turns the file; Delete deletes it and goes back', (
    tester,
  ) async {
    await open(tester, images: 2);
    final first = event().pages.first.id;
    await tester.tap(find.text('Page 1'));
    await frames(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Rotate'));
      for (var i = 0; i < 50 && event().pages.first.id == first; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await frames(tester);
    expect(event().pages.first.id, isNot(first));
    expect(find.byType(FileScreen), findsOneWidget);
    expect(find.text('Page 1'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Delete'));
      for (var i = 0; i < 50 && event().pages.length == 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await frames(tester);
    expect(event().pages, hasLength(1));
    expect(find.byType(FileScreen), findsNothing);
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsNothing);
  });

  testWidgets('the last file can\'t be deleted', (tester) async {
    await open(tester);
    await tester.tap(find.text('Page 1'));
    await frames(tester);
    await tester.tap(find.byTooltip('Delete'));
    await frames(tester);
    expect(event().pages, hasLength(1));
    expect(find.textContaining('delete the event instead'), findsOneWidget);
    expect(find.byType(FileScreen), findsOneWidget);
  });

  testWidgets('a link has no view or Rotate', (tester) async {
    await open(tester, link: true);
    await tester.tap(find.text('Made-up lesson'));
    await frames(tester);
    expect(view, findsNothing);
    expect(find.byTooltip('Rotate'), findsNothing);
    expect(find.byTooltip('Delete'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('Text without a text tab says why', (tester) async {
    await open(tester);
    await tester.tap(textTool);
    await frames(tester);
    // No reader in this test: nothing will read it.
    expect(find.text('No text yet.'), findsOneWidget);
    expect(event().pages.single.kind, PageKind.image);
  });

  testWidgets('Add offers Document right after Scan pages', (tester) async {
    await open(tester);
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await frames(tester);
    final items = [
      'Scan pages',
      'Document',
      'Photos & videos',
      'Files',
      'Link',
    ];
    final ys = [
      for (final item in items) tester.getTopLeft(find.text(item).last).dy,
    ];
    expect(ys, [...ys]..sort());
    expect(find.text('PDF files'), findsOneWidget);
  });
}
