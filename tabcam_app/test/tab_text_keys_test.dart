import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/tab_text_view.dart';

/// The Text view's keyboard: the arrow keys move the cursor, and a press
/// on an editing tool (with a mouse, as on a computer, where a tap
/// outside the field would unfocus it) keeps the focus in the text.
void main() {
  const riff = 'e|--3--5--|\nB|-5------|';

  Future<TextEditingController> pump(WidgetTester tester) async {
    final library = Library(PlatformEventStore());
    await library.load();
    final event = await library.update(
      (await library.create(const [])).copyWith(tabText: riff),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TabTextView(library: library, eventId: event.id),
        ),
      ),
    );
    await tester.pump();
    return tester.widget<TextField>(find.byType(TextField)).controller!;
  }

  Future<void> clickText(WidgetTester tester) async {
    await tester.tapAt(
      tester.getTopLeft(find.byType(TextField)) + const Offset(20, 20),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
  }

  bool focused(WidgetTester tester) => tester
      .state<EditableTextState>(find.byType(EditableText))
      .widget
      .focusNode
      .hasFocus;

  testWidgets('the arrow keys move the cursor', (tester) async {
    final text = await pump(tester);
    await clickText(tester);
    expect(text.selection.baseOffset, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(text.selection.baseOffset, 1);
    // Down a line: the same column on the second string.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(text.selection.baseOffset, 13);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(text.selection.baseOffset, 12);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(text.selection.baseOffset, 0);
  });

  testWidgets('a tool pressed with the mouse keeps the focus in the text', (
    tester,
  ) async {
    final text = await pump(tester);
    await clickText(tester);
    // The cursor on the 5 of the first string.
    text.selection = const TextSelection.collapsed(offset: 7);
    await tester.pump();
    expect(focused(tester), isTrue);

    await tester.tap(
      find.byTooltip('Fret up (the number under the cursor)'),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(text.text, 'e|--3--6--|\nB|-5------|');
    expect(focused(tester), isTrue, reason: 'the tool keeps the focus');
    expect(text.selection.baseOffset, 7);

    // So the next keys still go to the text.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(text.selection.baseOffset, 8);

    for (final tool in [
      'Overtype: typing replaces characters, columns stay put',
      'Note up a string (cycles round)',
      'Note down a string (cycles round)',
      'Fret down (the number under the cursor)',
    ]) {
      await tester.tap(find.byTooltip(tool), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(focused(tester), isTrue, reason: '$tool keeps the focus');
    }
  });

  testWidgets('|, || and = edit the staff and keep the focus in the text', (
    tester,
  ) async {
    final text = await pump(tester);
    await clickText(tester);
    // The cursor on the first string, after "e|--3".
    text.selection = const TextSelection.collapsed(offset: 5);
    await tester.pump();

    Future<void> press(String tooltip) async {
      await tester.tap(find.byTooltip(tooltip), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(focused(tester), isTrue, reason: '$tooltip keeps the focus');
    }

    await press('Bar line: a | across every string, at the cursor');
    expect(text.text, 'e|--3|--5--|\nB|-5-|-----|');
    expect(text.selection.baseOffset, 6);

    // Ragged now: the first string one shorter.
    text.value = const TextEditingValue(
      text: 'e|--3--5-|\nB|-5------|',
      selection: TextSelection.collapsed(offset: 0),
    );
    await tester.pump();
    await press('Line up the ends: every string ends with the longest');
    expect(text.text, 'e|--3--5--|\nB|-5------|');
    // Pressed again, nothing to do: it says so.
    await press('Line up the ends: every string ends with the longest');
    expect(find.text('Every string already ends together'), findsOneWidget);

    await press('Empty staff: six strings, e B G D A E, 80 characters wide');
    final lines = text.text.split('\n');
    expect(lines, hasLength(2 + 1 + 6));
    expect(lines.last, 'E|${'-' * 77}|');
    // The next key types on the new first string, after its bar.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(text.selection.baseOffset, text.text.indexOf('e|---') + 3);
  });
}
