import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/tab_text_view.dart';

/// The Text view's selections: the vertical selection toggle, Select all
/// (Ctrl+A, ⌘A on Apple's systems) and Select phrase (Ctrl+L, ⌘L), and
/// the tools working on the selected notes alone. A made-up riff.
void main() {
  // Each line 14 characters; the lines start at 0, 15, 30, 45 (blank),
  // 46 and 61.
  const riff =
      'e|-----0-----|\n'
      'B|---1---1---|\n'
      'G|-2-------2-|\n'
      '\n'
      'e|-3---5-----|\n'
      'B|---3---5---|';
  const fretUp = 'Fret up (the selected notes, or the number under the cursor)';
  const fretDown =
      'Fret down (the selected notes, or the number under the cursor)';
  const noteUp =
      'Note up a string (the selected notes, or the one under the cursor; '
      'cycles round)';
  const spacer =
      'Spacer: a - on every line of the phrase at the cursor, or on the '
      'selected lines';
  const endsLast =
      "End together at the last end: each phrase's lines (or the selected "
      'ones) padded to the longest';

  Future<DoubtController> pump(
    WidgetTester tester, {
    String text = riff,
  }) async {
    final library = Library(PlatformEventStore());
    await library.load();
    final event = await library.update(
      (await library.create(const [])).copyWith(tabText: text),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TabTextView(library: library, eventId: event.id),
        ),
      ),
    );
    await tester.pump();
    return tester.widget<TextField>(find.byType(TextField)).controller!
        as DoubtController;
  }

  /// A click in the text, as on a computer: the cursor at its start.
  Future<void> clickText(WidgetTester tester) async {
    await tester.tapAt(
      tester.getTopLeft(find.byType(TextField)) + const Offset(20, 20),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, Finder tool) async {
    await tester.tap(tool, kind: PointerDeviceKind.mouse);
    await tester.pump();
  }

  /// [key] with Ctrl (⌘ when [meta]) held down.
  Future<void> shortcut(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool meta = false,
  }) async {
    final modifier = meta
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  /// On screen, just inside the character at [offset]: near its left
  /// edge, or near its right edge when [right] (so a drag there ends after
  /// it).
  Offset charAt(WidgetTester tester, int offset, {bool right = false}) {
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final box = editable
        .getBoxesForSelection(
          TextSelection(baseOffset: offset, extentOffset: offset + 1),
        )
        .single
        .toRect();
    return editable.localToGlobal(
      Offset(right ? box.right - 2 : box.left + 2, box.center.dy),
    );
  }

  bool focused(WidgetTester tester) => tester
      .state<EditableTextState>(find.byType(EditableText))
      .widget
      .focusNode
      .hasFocus;

  List<String> lines(TextEditingController text) => text.text.split('\n');

  testWidgets('with vertical selection on, a drag selects a block, drawn '
      'in the text; + raises its notes alone, and it stays', (tester) async {
    final text = await pump(tester);
    // Right after Overtype, then Select all and Select phrase, before −.
    final overtype = tester.getRect(find.byKey(const Key('text-overtype')));
    final vertical = tester.getRect(find.byKey(const Key('text-vertical')));
    final all = tester.getRect(find.byKey(const Key('text-select-all')));
    final phrase = tester.getRect(find.byKey(const Key('text-select-phrase')));
    final down = tester.getRect(find.byTooltip(fretDown));
    expect(vertical.size, overtype.size);
    expect(vertical.left, greaterThan(overtype.right));
    expect(all.left, greaterThan(vertical.right));
    expect(phrase.left, greaterThan(all.right));
    expect(down.left, greaterThan(phrase.right));
    expect(
      find.byTooltip(
        'Line selection: a drag selects the text line by '
        'line',
      ),
      findsOneWidget,
    );

    await clickText(tester);
    await press(tester, find.byKey(const Key('text-vertical')));
    expect(
      find.byTooltip(
        'Vertical selection: a drag selects the same columns '
        'on every line',
      ),
      findsOneWidget,
    );
    expect(focused(tester), isTrue);

    // A drag with the mouse from the 4th character of the first line to
    // the 8th of the third.
    final drag = await tester.startGesture(
      charAt(tester, 3),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await drag.moveTo(charAt(tester, 37, right: true));
    await tester.pump();
    await drag.up();
    await tester.pump();
    expect(
      text.selection,
      const TextSelection(baseOffset: 3, extentOffset: 38),
    );
    expect(text.block, [(3, 8), (18, 23), (33, 38)]);

    await press(tester, find.byTooltip(fretUp));
    expect(lines(text), [
      'e|-----1-----|',
      'B|---2---1---|',
      'G|-3-------2-|',
      '',
      'e|-3---5-----|',
      'B|---3---5---|',
    ]);
    expect(text.block, [(3, 8), (18, 23), (33, 38)]);
    expect(focused(tester), isTrue);

    // Off: the field's own selection, no block drawn.
    await press(tester, find.byKey(const Key('text-vertical')));
    expect(text.block, isEmpty);
    expect(
      text.selection,
      const TextSelection(baseOffset: 3, extentOffset: 38),
    );
  });

  testWidgets('Ctrl+L selects the phrase, again the next one too; Ctrl+A '
      'all; − and + change every selected note, or none', (tester) async {
    final text = await pump(tester);
    await clickText(tester);
    expect(text.selection, const TextSelection.collapsed(offset: 0));

    await shortcut(tester, LogicalKeyboardKey.keyL);
    expect(
      text.selection,
      const TextSelection(baseOffset: 0, extentOffset: 44),
    );
    await shortcut(tester, LogicalKeyboardKey.keyL);
    expect(
      text.selection,
      const TextSelection(baseOffset: 0, extentOffset: riff.length),
    );
    await shortcut(tester, LogicalKeyboardKey.keyL);
    expect(find.text('No more phrases below'), findsOneWidget);

    // The first phrase has a 0: none goes down.
    await press(tester, find.byTooltip(fretDown));
    expect(text.text, riff);
    expect(
      find.text("A selected note can't go further: frets go from 0 to 99"),
      findsOneWidget,
    );

    text.selection = const TextSelection.collapsed(offset: 50);
    await tester.pump();
    await shortcut(tester, LogicalKeyboardKey.keyA);
    expect(
      text.selection,
      const TextSelection(baseOffset: 0, extentOffset: riff.length),
    );
    await press(tester, find.byTooltip(fretUp));
    expect(lines(text), [
      'e|-----1-----|',
      'B|---2---2---|',
      'G|-3-------3-|',
      '',
      'e|-4---6-----|',
      'B|---4---6---|',
    ]);
    // Still all selected, for the next press.
    expect(
      text.selection,
      TextSelection(baseOffset: 0, extentOffset: text.text.length),
    );

    // From the second phrase, Ctrl+L selects it.
    text.selection = const TextSelection.collapsed(offset: 50);
    await tester.pump();
    await shortcut(tester, LogicalKeyboardKey.keyL);
    expect(
      text.selection,
      const TextSelection(baseOffset: 46, extentOffset: riff.length),
    );
  });

  testWidgets('Select all and Select phrase, the buttons, focus the text; '
      'with vertical selection on they select blocks', (tester) async {
    final text = await pump(tester);
    expect(find.byTooltip('Select all (Ctrl+A)'), findsOneWidget);
    final phrase = find.byTooltip(
      'Select the phrase; again, the next one too (Ctrl+L)',
    );
    expect(phrase, findsOneWidget);
    expect(focused(tester), isFalse);

    await press(tester, phrase);
    expect(focused(tester), isTrue);
    expect(
      text.selection,
      const TextSelection(baseOffset: 0, extentOffset: 44),
    );

    await press(tester, find.byKey(const Key('text-vertical')));
    // What was selected is a block now.
    expect(text.block, [(0, 14), (15, 29), (30, 44)]);
    // Again: the next phrase too, the blank line between.
    await press(tester, phrase);
    expect(text.block, [(0, 14), (15, 29), (30, 44), (46, 60), (61, 75)]);

    text.selection = const TextSelection.collapsed(offset: 5);
    await tester.pump();
    expect(text.block, isEmpty);
    await press(tester, find.byKey(const Key('text-select-all')));
    expect(text.block, [(0, 14), (15, 29), (30, 44), (46, 60), (61, 75)]);
  });

  testWidgets('⌘A and ⌘L on a Mac', (tester) async {
    final text = await pump(tester);
    expect(find.byTooltip('Select all (⌘A)'), findsOneWidget);
    await clickText(tester);
    await shortcut(tester, LogicalKeyboardKey.keyL, meta: true);
    expect(
      text.selection,
      const TextSelection(baseOffset: 0, extentOffset: 44),
    );
    await shortcut(tester, LogicalKeyboardKey.keyA, meta: true);
    expect(
      text.selection,
      const TextSelection(baseOffset: 0, extentOffset: riff.length),
    );
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets('a block: Copy and Ctrl+C copy it, a line of it per line; '
      'what is typed goes on each of its lines, Backspace clears it', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final text = await pump(tester);
    await clickText(tester);
    // Overtype on (it starts off).
    await press(tester, find.byKey(const Key('text-overtype')));
    await press(tester, find.byKey(const Key('text-vertical')));
    // As a drag leaves it.
    text.selection = const TextSelection(baseOffset: 3, extentOffset: 38);
    await tester.pump();

    await press(tester, find.widgetWithText(FilledButton, 'Copy'));
    expect(copied, '----0\n--1--\n2----');
    expect(find.text('Selection copied'), findsOneWidget);
    copied = null;
    await shortcut(tester, LogicalKeyboardKey.keyC);
    expect(copied, '----0\n--1--\n2----');

    // Backspace, overtype on: dashes in its place, the columns kept.
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(lines(text).take(3), [
      'e|-----------|',
      'B|-------1---|',
      'G|---------2-|',
    ]);
    expect(text.block, isEmpty);

    // Typed: the platform puts it in place of the field's selection; the
    // block takes it, on every line.
    text.selection = const TextSelection(baseOffset: 3, extentOffset: 38);
    await tester.pump();
    final before = text.text;
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: before.replaceRange(3, 38, '7'),
        selection: const TextSelection.collapsed(offset: 4),
      ),
    );
    await tester.pump();
    expect(lines(text).take(3), [
      'e|-7---------|',
      'B|-7-----1---|',
      'G|-7-------2-|',
    ]);
    expect(text.selection, const TextSelection.collapsed(offset: 4));
  });

  testWidgets('a selection: = goes on its lines alone, and ++ moves its '
      'notes, a block following them', (tester) async {
    final text = await pump(tester);
    await clickText(tester);
    // From the second phrase's first line, after `e|`, into its second.
    text.selection = const TextSelection(baseOffset: 48, extentOffset: 65);
    await tester.pump();
    await press(tester, find.byTooltip(spacer));
    expect(lines(text), [
      'e|-----0-----|',
      'B|---1---1---|',
      'G|-2-------2-|',
      '',
      'e|--3---5-----|',
      'B|----3---5---|',
    ]);
    // The selection moved right with what it had.
    expect(
      text.selection,
      const TextSelection(baseOffset: 49, extentOffset: 67),
    );

    // A block on the first 1 and the first 2, moved up a string.
    await press(tester, find.byKey(const Key('text-vertical')));
    text.selection = const TextSelection(baseOffset: 18, extentOffset: 37);
    await tester.pump();
    expect(text.block, [(18, 22), (33, 37)]);
    await press(tester, find.byTooltip(noteUp));
    expect(lines(text).take(3), [
      'e|---1-0-----|',
      'B|-2-----1---|',
      'G|---------2-|',
    ]);
    // The block on the lines they went to.
    expect(text.block, [(3, 7), (18, 22)]);
  });

  testWidgets('|> on a selection ends only its lines together', (tester) async {
    final text = await pump(tester, text: 'e|--3--|\nB|--5----|\nG|-2-|');
    await clickText(tester);
    // The first two lines.
    text.selection = const TextSelection(baseOffset: 0, extentOffset: 19);
    await tester.pump();
    await press(tester, find.byTooltip(endsLast));
    expect(text.text, 'e|--3----|\nB|--5----|\nG|-2-|');
  });
}
