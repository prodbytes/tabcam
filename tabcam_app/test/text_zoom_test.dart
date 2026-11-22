import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/tab_text_view.dart';
import 'package:tabcam_app/screens/text_zoom.dart';

/// A made-up riff, long and wide: 30 phrases of six strings, each line
/// about 240 characters, so it scrolls both ways at any zoom.
final _riff = [
  for (var i = 0; i < 30; i++)
    [
      for (final s in 'eBGDAE'.split(''))
        '$s|${'--${i % 10}--${(i + 3) % 10}--|' * 20}',
    ].join('\n'),
].join('\n\n');

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final library = Library(PlatformEventStore());
  await library.load();
  final event = await library.update(
    (await library.create(const [])).copyWith(tabText: _riff),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TabTextView(library: library, eventId: event.id),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double _editorSize(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).style!.fontSize!;

/// The scroll along [axis] that holds [of].
ScrollPosition _scroll(WidgetTester tester, Axis axis, Finder of) {
  for (final e
      in find.ancestor(of: of, matching: find.byType(Scrollable)).evaluate()) {
    final state = (e as StatefulElement).state as ScrollableState;
    if (axisDirectionToAxis(state.axisDirection) == axis) return state.position;
  }
  throw StateError('no $axis scroll');
}

void main() {
  test('nextTextZoom goes one step, from between two as well', () {
    expect(nextTextZoom(1, 1), 1.25);
    expect(nextTextZoom(1, -1), 0.75);
    expect(nextTextZoom(1.1, 1), 1.25);
    expect(nextTextZoom(1.1, -1), 1.0);
    expect(nextTextZoom(textZooms.last, 1), textZooms.last);
    expect(nextTextZoom(textZooms.first, -1), textZooms.first);
    expect(clampTextZoom(9), textZooms.last);
    expect(clampTextZoom(0.1), textZooms.first);
  });

  testWidgets('Zoom in and Zoom out size the text; the % puts it back', (
    tester,
  ) async {
    await _open(tester);
    expect(_editorSize(tester), 15);
    // No percentage at the usual size.
    expect(find.byKey(const Key('text-zoom')), findsNothing);

    // Scrolled down a way, a button's zoom keeps the top left of what
    // shows where it is.
    final down = _scroll(tester, Axis.vertical, find.byType(TextField));
    down.jumpTo(200);
    await tester.pump();
    await tester.tap(find.byKey(const Key('text-zoom-in')));
    await tester.pumpAndSettle();
    expect(_editorSize(tester), 15 * 1.25);
    expect(find.text('125%'), findsOneWidget);
    expect(down.pixels, closeTo(250, 0.01));
    expect(_scroll(tester, Axis.horizontal, find.byType(TextField)).pixels, 0);

    await tester.tap(find.byKey(const Key('text-zoom-out')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('text-zoom-out')));
    await tester.pumpAndSettle();
    expect(_editorSize(tester), 15 * 0.75);

    await tester.tap(find.byKey(const Key('text-zoom')));
    await tester.pumpAndSettle();
    expect(_editorSize(tester), 15);

    // Zoomed in all the way, Zoom in is off.
    for (var i = 0; i < textZooms.length; i++) {
      await tester.tap(find.byKey(const Key('text-zoom-in')));
      await tester.pumpAndSettle();
    }
    expect(_editorSize(tester), 15 * textZooms.last);
    final zoomIn = tester.widget<IconButton>(
      find.byKey(const Key('text-zoom-in')),
    );
    expect(zoomIn.onPressed, isNull);
    // Its widest lines don't wrap: the editor is as many times wider.
    expect(tester.getSize(find.byType(TextField)).width, 1600 * textZooms.last);
  });

  testWidgets('Drag to move: a drag, a mouse\'s too, moves the text', (
    tester,
  ) async {
    await _open(tester);
    final editor = find.byType(TextField);
    final down = _scroll(tester, Axis.vertical, editor);
    final across = _scroll(tester, Axis.horizontal, editor);
    final middle = tester.getCenter(find.byType(TabTextView));

    // Off, nothing is over the text: a drag edits or selects it.
    expect(find.byKey(const Key('text-drag-layer')), findsNothing);

    await tester.tap(find.byKey(const Key('text-drag')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('text-drag-layer')), findsOneWidget);
    expect(find.byTooltip('Stop moving the tab'), findsOneWidget);

    await tester.dragFrom(
      middle,
      const Offset(-200, -250),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(down.pixels, greaterThan(150));
    expect(across.pixels, greaterThan(150));

    // Dragged back past the start, it stops there.
    await tester.dragFrom(
      middle,
      const Offset(600, 600),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    expect(down.pixels, 0);
    expect(across.pixels, 0);

    // The wheel still scrolls over the layer.
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(middle));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
    await tester.pump();
    expect(down.pixels, 120);

    // Off again: the layer goes, the text is edited as before.
    await tester.tap(find.byKey(const Key('text-drag')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('text-drag-layer')), findsNothing);
  });

  testWidgets('Ctrl + the wheel zooms about the pointer, and doesn\'t scroll', (
    tester,
  ) async {
    await _open(tester);
    final down = _scroll(tester, Axis.vertical, find.byType(TextField));
    final middle = tester.getCenter(find.byType(TabTextView));
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(middle));

    // Without Ctrl, the wheel scrolls as before.
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 300)));
    await tester.pumpAndSettle();
    expect(_editorSize(tester), 15);
    expect(down.pixels, 300);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -100)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final ratio = _editorSize(tester) / 15;
    expect(ratio, greaterThan(1.15));
    // What was under the pointer is still there: the text grew about it,
    // and the wheel didn't scroll it too.
    final at = middle.dy - tester.getTopLeft(find.byType(TextMover)).dy;
    expect(down.pixels, closeTo((300 + at) * ratio - at, 1));
  });

  testWidgets('Two fingers pinched apart zoom in', (tester) async {
    await _open(tester);
    final middle = tester.getCenter(find.byType(TabTextView));
    final a = await tester.startGesture(middle - const Offset(50, 0));
    final b = await tester.startGesture(middle + const Offset(50, 0));
    await a.moveBy(const Offset(-50, 0));
    await b.moveBy(const Offset(50, 0));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    // From 100 px apart to 200: twice the size.
    expect(_editorSize(tester), closeTo(30, 0.01));
  });

  testWidgets('Two columns zoom and move too', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('text-columns')));
    await tester.pumpAndSettle();
    final left = find.byKey(const Key('text-column-left'));
    final right = find.byKey(const Key('text-column-right'));
    // The tab's span, in the column's text (under the default style's).
    double size(Finder column) {
      final text = tester
          .widget<RichText>(
            find.descendant(of: column, matching: find.byType(RichText)),
          )
          .text;
      return (text as TextSpan).children!.first.style!.fontSize!;
    }

    expect(size(left), 15);

    await tester.tap(find.byKey(const Key('text-zoom-in')));
    await tester.pumpAndSettle();
    expect(size(left), 15 * 1.25);
    expect(size(right), 15 * 1.25);

    await tester.tap(find.byKey(const Key('text-drag')));
    await tester.pumpAndSettle();
    final down = _scroll(tester, Axis.vertical, left);
    final leftAcross = _scroll(
      tester,
      Axis.horizontal,
      find.descendant(of: left, matching: find.byType(RichText)),
    );
    final rightAcross = _scroll(
      tester,
      Axis.horizontal,
      find.descendant(of: right, matching: find.byType(RichText)),
    );
    // A drag on the right column moves it sideways, and both down.
    final onRight =
        tester.getTopLeft(find.byType(TabTextView)) + const Offset(750, 400);
    await tester.dragFrom(
      onRight,
      const Offset(-200, -200),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(down.pixels, greaterThan(150));
    expect(rightAcross.pixels, greaterThan(150));
    expect(leftAcross.pixels, 0);
  });
}
