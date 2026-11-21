import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/screens/tab_editing.dart';

/// The Text view's selections as the tools see them: a vertical block or
/// the text selected, and the tools working on the selected notes alone.
/// A made-up riff, two phrases with a blank line between them.
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
  final lines = riff.split('\n');
  // Lines 0 to 2, columns 3 to 7: the 0, the first 1 and the first 2.
  const block = TextBlock(top: 0, bottom: 2, left: 3, right: 8);

  group('TextBlock', () {
    test('a drag draws it between its corners, either way round', () {
      expect(
        TextBlock.corners(
          riff,
          const TextSelection(baseOffset: 3, extentOffset: 38),
        ),
        block,
      );
      expect(
        TextBlock.corners(
          riff,
          const TextSelection(baseOffset: 38, extentOffset: 3),
        ),
        block,
      );
      // From the top right to the bottom left.
      expect(
        TextBlock.corners(
          riff,
          const TextSelection(baseOffset: 8, extentOffset: 33),
        ),
        block,
      );
      // Straight down: the column right of where it started.
      expect(
        TextBlock.corners(
          riff,
          const TextSelection(baseOffset: 7, extentOffset: 37),
        ),
        const TextBlock(top: 0, bottom: 2, left: 7, right: 8),
      );
    });

    test('its spans, ranges, text and selection', () {
      expect(block.spans(lines), [
        (line: 0, start: 3, end: 8),
        (line: 1, start: 3, end: 8),
        (line: 2, start: 3, end: 8),
      ]);
      expect(block.ranges(lines), [(3, 8), (18, 23), (33, 38)]);
      expect(spansText(lines, block.spans(lines)), '----0\n--1--\n2----');
      expect(
        block.selectionIn(lines),
        const TextSelection(baseOffset: 3, extentOffset: 38),
      );
      // Whole lines: every column the longest has; the blank line in it
      // has none.
      final whole = TextBlock.whole(lines, 2, 4);
      expect(whole, const TextBlock(top: 2, bottom: 4, left: 0, right: 14));
      expect(whole.ranges(lines), [(30, 44), (46, 60)]);
    });
  });

  test('the text selected spans its lines, its ends where they are', () {
    expect(
      selectionSpans(
        riff,
        const TextSelection(baseOffset: 7, extentOffset: 21),
      ),
      [(line: 0, start: 7, end: 14), (line: 1, start: 0, end: 6)],
    );
    // From the end of a line to the start of another: just the line
    // between.
    expect(
      selectionSpans(
        riff,
        const TextSelection(baseOffset: 14, extentOffset: 30),
      ),
      [(line: 1, start: 0, end: 14)],
    );
    expect(selectionSpans(riff, const TextSelection.collapsed(offset: 5)), []);
  });

  group('+ and − on a selection', () {
    test('raise or lower every note it takes, the rest as it was', () {
      final up = bumpSelected(riff, block.spans(lines), 1);
      expect(up.failure, isNull);
      expect(up.text!.split('\n').take(3), [
        'e|-----1-----|',
        'B|---2---1---|',
        'G|-3-------2-|',
      ]);
      expect(up.text!.split('\n').skip(3), lines.skip(3));
    });

    test('none moves when one would go below 0, or there are none', () {
      expect(bumpSelected(riff, block.spans(lines), -1), (
        text: null,
        failure: SelectionFailure.outOfRange,
      ));
      const dashes = TextBlock(top: 0, bottom: 2, left: 12, right: 13);
      expect(bumpSelected(riff, dashes.spans(lines), 1), (
        text: null,
        failure: SelectionFailure.noNotes,
      ));
    });

    test('only notes on string lines, a 9 taking the dash after it', () {
      const text = 'Verse 2\ne|--9--|';
      final all = selectionSpans(
        text,
        const TextSelection(baseOffset: 0, extentOffset: text.length),
      );
      expect(bumpSelected(text, all, 1).text, 'Verse 2\ne|--10-|');
    });
  });

  group('++ and −− on a selection', () {
    test('move every note it takes up a string together', () {
      // The first 1 and the first 2.
      const two = TextBlock(top: 1, bottom: 2, left: 3, right: 7);
      final moved = moveSelected(riff, two.spans(lines), -1);
      expect(moved.failure, isNull);
      expect(moved.rows, [0, 1]);
      expect(moved.text!.split('\n').take(3), [
        'e|---1-0-----|',
        'B|-2-----1---|',
        'G|---------2-|',
      ]);
    });

    test('notes swap strings when both move; none when one has no room', () {
      const text = 'e|--1--|\nB|--2--|';
      final both = const TextBlock(
        top: 0,
        bottom: 1,
        left: 4,
        right: 5,
      ).spans(text.split('\n'));
      expect(moveSelected(text, both, -1).text, 'e|--2--|\nB|--1--|');
      final one = const TextBlock(
        top: 0,
        bottom: 0,
        left: 4,
        right: 5,
      ).spans(text.split('\n'));
      expect(moveSelected(text, one, -1), (
        text: null,
        rows: null,
        failure: SelectionFailure.noRoom,
      ));
    });
  });

  test('| and = go on the selected string lines alone', () {
    expect(barOnLines(riff, [0, 1], 5)!.split('\n').take(3), [
      'e|---|--0-----|',
      'B|---|1---1---|',
      'G|-2-------2-|',
    ]);
    expect(spacerOnLines(riff, [4, 5], 2)!.split('\n').skip(4), [
      'e|--3---5-----|',
      'B|----3---5---|',
    ]);
    // The blank line isn't a string line.
    expect(barOnLines(riff, [3], 0), isNull);
    expect(spacerOnLines(riff, [3], 0), isNull);
  });

  test('|> and <| on a selection end only its lines together', () {
    const ragged = 'e|--3--|\nB|--5----|\nG|-2-|';
    const value = TextEditingValue(text: ragged);
    expect(
      alignEnds(value, lines: (top: 0, bottom: 1))!.text,
      'e|--3----|\nB|--5----|\nG|-2-|',
    );
    expect(alignEnds(value)!.text, 'e|--3----|\nB|--5----|\nG|-2-----|');
    expect(
      trimEnds(value, lines: (top: 1, bottom: 2))!.text,
      'e|--3--|\nB|--5-|\nG|-2--|',
    );
    // One line alone: no phrase to line up.
    expect(alignEnds(value, lines: (top: 1, bottom: 1)), isNull);
  });

  test('the phrases around, below and above a line', () {
    expect(phrasesAround(lines, 1, 1), (top: 0, bottom: 2));
    expect(phrasesAround(lines, 2, 4), (top: 0, bottom: 5));
    expect(phrasesAround(lines, 3, 3), isNull);
    expect(phraseBelow(lines, 2), (top: 4, bottom: 5));
    expect(phraseBelow(lines, 5), isNull);
    expect(phraseAbove(lines, 3), (top: 0, bottom: 2));
    expect(phraseAbove(lines, 0), isNull);
  });

  group('typing over a block', () {
    test('overtype: the columns stay put', () {
      final cleared = replaceBlock(riff, block, typed: '', overtype: true);
      expect(cleared.text.split('\n').take(3), [
        'e|-----------|',
        'B|-------1---|',
        'G|---------2-|',
      ]);
      expect(cleared.cursor, 3);
      final typed = replaceBlock(riff, block, typed: '7', overtype: true);
      expect(typed.text.split('\n').take(3), [
        'e|-7---------|',
        'B|-7-----1---|',
        'G|-7-------2-|',
      ]);
      expect(typed.cursor, 4);
      // Pasted lines, one a line.
      final pasted = replaceBlock(
        riff,
        block,
        typed: '1\n2\n3',
        overtype: true,
      );
      expect(pasted.text.split('\n').take(3), [
        'e|-1---------|',
        'B|-2-----1---|',
        'G|-3-------2-|',
      ]);
    });

    test('insert: the lines close up', () {
      expect(
        replaceBlock(
          riff,
          block,
          typed: '',
          overtype: false,
        ).text.split('\n').take(3),
        ['e|------|', 'B|--1---|', 'G|----2-|'],
      );
    });

    test('the formatter types on every line of the block', () {
      final formatter = BlockFormatter(() => block, overtype: () => true);
      const selected = TextSelection(baseOffset: 3, extentOffset: 38);
      const old = TextEditingValue(text: riff, selection: selected);
      final typed = formatter.formatEditUpdate(
        old,
        TextEditingValue(
          text: riff.replaceRange(3, 38, '7'),
          selection: const TextSelection.collapsed(offset: 4),
        ),
      );
      expect(
        typed.text,
        replaceBlock(riff, block, typed: '7', overtype: true).text,
      );
      expect(typed.selection, const TextSelection.collapsed(offset: 4));
      // No block: as typed.
      final plain = BlockFormatter(() => null, overtype: () => true);
      final now = TextEditingValue(text: riff.replaceRange(3, 38, '7'));
      expect(plain.formatEditUpdate(old, now), now);
    });
  });
}
