import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/page_image.dart';
import 'package:tabcam_app/screens/tab_text_view.dart';

const _riff = '''
e|--0--3--|
B|--1--1--|
''';

void main() {
  /// A capture with [scans] photographed pages and a text tab.
  Future<(Library, String)> capture(WidgetTester tester, int scans) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late String id;
    await tester.runAsync(() async {
      await library.load();
      final event = await library.create([
        for (var i = 0; i < scans; i++)
          img.encodeJpg(img.Image(width: 8, height: 8)),
      ]);
      id = (await library.update(event.copyWith(tabText: _riff))).id;
    });
    return (library, id);
  }

  Future<void> show(
    WidgetTester tester,
    Library library,
    String id,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TabTextView(library: library, eventId: id),
        ),
      ),
    );
    await tester.pump();
  }

  Axis split(WidgetTester tester) =>
      tester.widget<Flex>(find.byKey(const Key('text-review-split'))).direction;

  testWidgets('Review shows the scanned pages beside the text, side by side '
      'on a wide screen; the text stays editable; again, it hides them', (
    tester,
  ) async {
    final (library, id) = await capture(tester, 2);
    await show(tester, library, id, const Size(1200, 800));
    expect(find.byKey(const Key('text-review-scans')), findsNothing);

    await tester.tap(find.byKey(const Key('text-review')));
    await tester.pump();
    expect(find.byKey(const Key('text-review-scans')), findsOneWidget);
    expect(split(tester), Axis.horizontal);
    expect(find.byType(PageImage), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);

    // Two pages: a button for each switches between them.
    final first = tester.widget<PageImage>(find.byType(PageImage)).page.id;
    await tester.tap(find.byKey(const ValueKey('text-review-page-1')));
    await tester.pump();
    final second = tester.widget<PageImage>(find.byType(PageImage)).page.id;
    expect(second, isNot(first));

    await tester.tap(find.byKey(const Key('text-review')));
    await tester.pump();
    expect(find.byKey(const Key('text-review-scans')), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('on a phone held upright, the page shows above the text; '
      'one page, no page buttons', (tester) async {
    final (library, id) = await capture(tester, 1);
    await show(tester, library, id, const Size(400, 850));
    await tester.tap(find.byKey(const Key('text-review')));
    await tester.pump();
    expect(split(tester), Axis.vertical);
    expect(find.byKey(const ValueKey('text-review-page-0')), findsNothing);
  });

  testWidgets('the separator between the page and the text drags, side '
      'by side and one above the other; a double tap: half and half', (
    tester,
  ) async {
    final (library, id) = await capture(tester, 1);
    await show(tester, library, id, const Size(1200, 800));
    await tester.tap(find.byKey(const Key('text-review')));
    await tester.pump();
    final scans = find.byKey(const Key('text-review-scans'));
    final handle = find.byKey(const Key('text-review-handle'));
    final before = tester.getSize(scans).width;
    await tester.drag(handle, const Offset(200, 0));
    await tester.pump();
    expect(tester.getSize(scans).width, closeTo(before + 200, 1));
    // Not past the text's smallest: it stays at least 120 px.
    await tester.drag(handle, const Offset(2000, 0));
    await tester.pump();
    expect(
      tester.getSize(find.byType(TextField)).width,
      greaterThanOrEqualTo(100),
    );
    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(scans).width, closeTo(before, 1));

    // On a phone held upright, the page above: dragged down, taller.
    await show(tester, library, id, const Size(400, 850));
    final height = tester.getSize(scans).height;
    await tester.drag(handle, const Offset(0, 150));
    await tester.pump();
    expect(tester.getSize(scans).height, greaterThan(height + 100));
    // The double tap's wait, over.
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('without scanned pages, no Review', (tester) async {
    final (library, id) = await capture(tester, 0);
    await show(tester, library, id, const Size(1200, 800));
    expect(find.byKey(const Key('text-review')), findsNothing);
    expect(find.text('Copy'), findsOneWidget);
  });
}
