import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/tab_editing.dart';
import 'package:tabcam_app/screens/tab_text_view.dart';

/// A made-up riff, long enough to scroll down.
final _riff = List.filled(20, 'e|--3--5--7--|\nB|-5--------8-|\n').join('\n');

void main() {
  group('columnRuler', () {
    test('numbers every fifth column, its last figure on it, dots between', () {
      expect(columnRuler(12), '····5···10··');
      expect(columnRuler(4), '····');
      expect(columnRuler(0), '');
      final long = columnRuler(105);
      expect(long.length, 105);
      expect(long.substring(90), '···95··100··105');
    });

    test('cursorColumn is the cursor\'s column on its line', () {
      TextEditingValue at(int offset) => TextEditingValue(
        text: 'e|--3\nB|-5',
        selection: TextSelection.collapsed(offset: offset),
      );
      expect(cursorColumn(at(0)), 0);
      expect(cursorColumn(at(4)), 4);
      expect(cursorColumn(at(5)), 5);
      expect(cursorColumn(at(6)), 0);
      expect(cursorColumn(at(9)), 3);
      expect(
        cursorColumn(
          const TextEditingValue(
            text: 'e|--3',
            selection: TextSelection(baseOffset: 1, extentOffset: 3),
          ),
        ),
        isNull,
      );
      expect(cursorColumn(const TextEditingValue(text: 'e|--3')), isNull);
    });
  });

  testWidgets('the ruler stands over the text\'s columns, marks the '
      'cursor\'s, zooms and scrolls sideways with it, and stays put as it '
      'scrolls down', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
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

    final ruler = find.byKey(const Key('text-ruler'));
    expect(ruler, findsOneWidget);
    RenderParagraph paragraph() => tester.renderObject(
      find.descendant(of: ruler, matching: find.byType(RichText)),
    );
    expect(paragraph().text.toPlainText(), startsWith('····5···10···15'));

    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    // The left of column [i] (from 0) in the ruler and in the text's
    // first line, on screen.
    double rulerX(int i) {
      final p = paragraph();
      final box = p.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
      );
      return p.localToGlobal(Offset(box.first.left, 0)).dx;
    }

    double textX(int i) {
      final box = editable.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
      );
      return editable.localToGlobal(Offset(box.first.left, 0)).dx;
    }

    void linedUp() {
      for (final i in [0, 4, 9, 13]) {
        expect(rulerX(i), closeTo(textX(i), 0.5), reason: 'column $i');
      }
    }

    linedUp();
    // Over the text.
    expect(
      tester.getBottomLeft(ruler).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(EditableText)).dy),
    );

    // The cursor's column marked: the character it's before.
    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    controller.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();
    TextStyle? styleAt(int i) {
      final spans = (paragraph().text as TextSpan).children!.single;
      var at = 0;
      for (final span in (spans as TextSpan).children!.cast<TextSpan>()) {
        if (i < at + span.text!.length) return span.style;
        at += span.text!.length;
      }
      return null;
    }

    final marked = Theme.of(tester.element(ruler)).colorScheme.primaryContainer;
    expect(styleAt(4)?.backgroundColor, marked);
    expect(styleAt(3)?.backgroundColor, isNull);
    // On the next line, the same counting from its start (after its
    // first two characters).
    controller.selection = TextSelection.collapsed(
      offset: _riff.indexOf('\n') + 1 + 2,
    );
    await tester.pump();
    expect(styleAt(2)?.backgroundColor, marked);
    expect(styleAt(4)?.backgroundColor, isNull);

    // Zoomed in: still lined up.
    await tester.tap(find.byKey(const Key('text-zoom-in')));
    await tester.pumpAndSettle();
    linedUp();

    // Scrolled sideways: with the text.
    final across = find.ancestor(
      of: ruler,
      matching: find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      ),
    );
    final sideways = tester.widget<SingleChildScrollView>(across).controller!;
    sideways.jumpTo(60);
    await tester.pump();
    linedUp();

    // Scrolled down: the ruler stays at the top.
    final top = tester.getTopLeft(ruler).dy;
    final down = tester
        .widget<SingleChildScrollView>(
          find
              .descendant(
                of: across,
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is SingleChildScrollView &&
                      w.scrollDirection == Axis.vertical,
                ),
              )
              .first,
        )
        .controller!;
    down.jumpTo(200);
    await tester.pump();
    expect(tester.getTopLeft(ruler).dy, top);
    expect(down.offset, 200);
  });

  testWidgets('no ruler in Columns, which is for reading', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
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
    expect(find.byKey(const Key('text-ruler')), findsOneWidget);
    await tester.tap(find.byKey(const Key('text-columns')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('text-ruler')), findsNothing);
  });
}
