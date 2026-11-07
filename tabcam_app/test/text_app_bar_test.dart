import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/dictionary/dictionary_sidebar.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/event_screen.dart';
import 'package:tabcam_app/screens/tab_text_view.dart';

const _riff = 'e|--3--5--|\nB|-5------|';

/// The event screen on its Text view (the text marked Verified), in a
/// window [width] wide, the dictionary's sidebar closed.
Future<Library> _textView(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final library = Library(PlatformEventStore());
  late CaptureEvent event;
  await tester.runAsync(() async {
    await library.load();
    final page = img.encodeJpg(img.Image(width: 8, height: 8));
    event = await library.update(
      (await library.create([page])).copyWith(
        title: 'A made-up riff with a long name',
        tabText: _riff,
        tabTextCorrect: true,
      ),
    );
  });
  await tester.pumpWidget(
    MaterialApp(
      home: EventScreen(library: library, eventId: event.id),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  // A capture opens on its files: the Text tool shows the tab.
  await tester.tap(find.byKey(const Key('text')));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  expect(find.byType(TabTextView), findsOneWidget);
  return library;
}

Finder _inAppBar(Finder finder) =>
    find.descendant(of: find.byType(AppBar), matching: finder);

void main() {
  testWidgets('on a computer, Copy and Verified are in the app bar, '
      'labelled, with every other button', (tester) async {
    final library = await _textView(tester, 1200);
    expect(_inAppBar(find.text('Copy')), findsOneWidget);
    expect(_inAppBar(find.text('Verified')), findsOneWidget);
    // Not on the line above the text any more.
    expect(
      find.descendant(
        of: find.byType(TabTextView),
        matching: find.text('Copy'),
      ),
      findsNothing,
    );
    expect(_inAppBar(find.byKey(const Key('download-all'))), findsOneWidget);
    expect(_inAppBar(find.byKey(const Key('dictionary'))), findsOneWidget);
    expect(find.byKey(const Key('event-more')), findsNothing);

    // Right of the title.
    expect(
      tester.getTopLeft(_inAppBar(find.text('Copy'))).dx,
      greaterThan(
        tester.getTopRight(find.text('A made-up riff with a long name')).dx,
      ),
    );

    // Verified, pressed in the app bar, unmarks the text, and the button
    // says so at once.
    await tester.tap(_inAppBar(find.text('Verified')));
    await tester.pump();
    await tester.pump();
    final id = library.events.single.id;
    expect(library.byId(id)!.tabTextCorrect, isFalse);
    expect(
      _inAppBar(find.widgetWithIcon(FilledButton, Icons.check_circle_outline)),
      findsOneWidget,
    );
  });

  testWidgets('on a phone, Copy and Verified are icons beside the title, '
      'the rest in a menu, and the tools fit at full size', (tester) async {
    final library = await _textView(tester, 390);
    expect(_inAppBar(find.byTooltip('Copy')), findsOneWidget);
    expect(_inAppBar(find.byKey(const Key('text-verified'))), findsOneWidget);
    expect(_inAppBar(find.byKey(const Key('download-all'))), findsNothing);
    expect(_inAppBar(find.byKey(const Key('dictionary'))), findsNothing);

    // The title keeps room to be read.
    final title = tester.getRect(find.text('A made-up riff with a long name'));
    expect(title.width, greaterThan(100));

    // The editing tools, unscaled: 40 wide, all of them on screen.
    final plus = tester.getRect(
      find.byTooltip('Fret up (the number under the cursor)'),
    );
    expect(plus.width, closeTo(40, 0.5));
    final overtype = tester.getRect(find.byKey(const Key('text-overtype')));
    expect(overtype.right, lessThanOrEqualTo(390 - 16 + 0.5));

    // Verified, as an icon, toggles.
    await tester.tap(find.byKey(const Key('text-verified')));
    await tester.pump();
    await tester.pump();
    expect(library.byId(library.events.single.id)!.tabTextCorrect, isFalse);

    // The menu: Dictionary, Rename, Clone, Download all and Share.
    await tester.tap(find.byKey(const Key('event-more')));
    await tester.pumpAndSettle();
    for (final key in [
      'more-dictionary',
      'more-rename',
      'more-clone',
      'more-download-all',
      'more-share',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    // Dictionary shows its sidebar.
    addTearDown(DictionaryState.instance.clear);
    await tester.tap(find.byKey(const Key('more-dictionary')));
    await tester.pumpAndSettle();
    expect(DictionaryState.instance.open, isTrue);
  });
}
