import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/cloud/ocr_api.dart';
import 'package:tabcam_app/screens/tab_editing.dart';

// Made-up riffs: tests never use published songs' tabs.
const _riff = 'Am      G\ne|---0---3---|\nB|-1---8-----|';

TextEditingValue _at(String text, int offset) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: offset),
);

TabCorrection _fix(int line, int column, String old, String replacement) =>
    TabCorrection(
      id: '$line.$column',
      line: line,
      column: column,
      old: old,
      replacement: replacement,
    );

void main() {
  group('corrections', () {
    test('replace, remove and add notes, keeping the columns', () {
      final fixed = applyCorrections(_riff, [
        _fix(2, 7, '8', '3'),
        _fix(1, 5, '0', ''),
        _fix(2, 3, '1', '12'),
        _fix(1, 11, '', '5'),
      ]);
      expect(fixed, 'Am      G\ne|-------3-5-|\nB|-12--3-----|');
    });

    test('a correction whose note moved is skipped', () {
      expect(applyCorrections(_riff, [_fix(2, 7, '9', '3')]), _riff);
      expect(applyCorrections(_riff, [_fix(9, 0, '', '3')]), _riff);
    });
  });

  group('overtype', () {
    final on = OvertypeFormatter(() => true);
    final off = OvertypeFormatter(() => false);
    const line = 'e|---0---|';

    test('typing replaces the character after the cursor', () {
      final typed = on.formatEditUpdate(_at(line, 3), _at('e|-5--0---|', 4));
      expect(typed.text, 'e|-5-0---|');
      expect(typed.selection.baseOffset, 4);
    });

    test('at the end of a line it adds, and newlines insert', () {
      expect(on.formatEditUpdate(_at('e|-', 3), _at('e|-7', 4)).text, 'e|-7');
      final enter = on.formatEditUpdate(_at(line, 3), _at('e|-\n--0---|', 4));
      expect(enter.text, 'e|-\n--0---|');
    });

    test('backspace leaves a dash on a string line', () {
      final back = on.formatEditUpdate(_at(line, 6), _at('e|------|', 5));
      expect(back.text, 'e|-------|');
      expect(back.selection.baseOffset, 5);
      expect(on.formatEditUpdate(_at('la la', 5), _at('la l', 4)).text, 'la l');
    });

    test('off, typing inserts', () {
      expect(
        off.formatEditUpdate(_at(line, 3), _at('e|-5--0---|', 4)).text,
        'e|-5--0---|',
      );
    });
  });

  group('+ and −', () {
    test('one or two digits under the cursor, or just before it', () {
      expect(bumpNumber(_at('e|--15--|', 4), 1)!.text, 'e|--16--|');
      expect(bumpNumber(_at('e|--15--|', 5), 1)!.text, 'e|--16--|');
      expect(bumpNumber(_at('e|--15--|', 6), -1)!.text, 'e|--14--|');
      expect(bumpNumber(_at('e|--5---|', 4), 1)!.text, 'e|--6---|');
      expect(bumpNumber(_at('e|--5---|', 4), 1)!.selection.baseOffset, 4);
    });

    test('9 to 10 takes a dash, 10 to 9 leaves one', () {
      expect(bumpNumber(_at('e|--9---|', 4), 1)!.text, 'e|--10--|');
      expect(bumpNumber(_at('e|--10--|', 4), -1)!.text, 'e|--9---|');
    });

    test('nothing to change', () {
      expect(bumpNumber(_at('e|------|', 3), 1), isNull);
      expect(bumpNumber(_at('e|--0---|', 4), -1), isNull);
      expect(bumpNumber(_at('e|--99--|', 4), 1), isNull);
      expect(bumpNumber(_at('e|-123--|', 4), 1), isNull);
    });
  });

  group('++ and −−', () {
    const staff = 'Am\ne|--5--|\nB|-----|\nG|--7--|';
    // The 5 on e, at column 4 of line 1 (offset 3 + 4).
    final five = _at(staff, 7);

    test('down a string, dashes left behind, the cursor follows', () {
      final (:moved, :failure) = moveNote(five, 1);
      expect(failure, isNull);
      expect(moved!.text, 'Am\ne|-----|\nB|--5--|\nG|--7--|');
      expect(moved.selection.baseOffset, 'Am\ne|-----|\n'.length + 4);
    });

    test('a string with a note there is skipped', () {
      final (:moved, failure: _) = moveNote(
        _at('e|--5--|\nB|-----|\nG|--7--|', 4),
        -1,
      );
      // Up from e cycles to G, taken, so to B.
      expect(moved!.text, 'e|-----|\nB|--5--|\nG|--7--|');
    });

    test('cycles from the last string to the first, two digits too', () {
      final (:moved, failure: _) = moveNote(_at('e|------|\nB|--12--|', 14), 1);
      expect(moved!.text, 'e|--12--|\nB|------|');
      expect(moved.selection.baseOffset, 4);
    });

    test('nothing to move, or no room', () {
      expect(moveNote(_at(staff, 1), 1).failure, MoveNoteFailure.noNote);
      expect(moveNote(_at('e|------|', 3), 1).failure, MoveNoteFailure.noNote);
      expect(
        moveNote(_at('e|--5--|\nB|--7--|', 4), 1).failure,
        MoveNoteFailure.noRoom,
      );
      expect(moveNote(_at('e|--5--|', 4), 1).failure, MoveNoteFailure.noRoom);
    });
  });

  group('| (bar line)', () {
    const staff = 'Am\ne|--3--5--|\nB|-5------|\nG|---------|';

    test('a | on every string of the staff, at the cursor\'s column', () {
      // The cursor on the first string, column 6 (after "e|--3-").
      final barred = insertBar(_at(staff, 3 + 6))!;
      expect(barred.text, 'Am\ne|--3-|-5--|\nB|-5--|----|\nG|----|-----|');
      // Just after the new bar, on the cursor's line.
      expect(barred.selection.baseOffset, 3 + 7);
    });

    test('from any string of the staff, other lines untouched', () {
      final fromLast = insertBar(_at(staff, 3 + 12 + 12 + 6))!;
      expect(fromLast.text, insertBar(_at(staff, 3 + 6))!.text);
      expect(fromLast.text.split('\n').first, 'Am');
    });

    test('a short string is lengthened with dashes to the column', () {
      expect(
        insertBar(_at('e|--3--5--|\nB|-5', 7))!.text,
        'e|--3--|5--|\nB|-5---|',
      );
    });

    test('only the cursor\'s staff', () {
      const two = 'e|--3--|\nB|--5--|\n\ne|--7--|\nB|--8--|';
      expect(
        insertBar(_at(two, 3))!.text,
        'e|-|-3--|\nB|-|-5--|\n\ne|--7--|\nB|--8--|',
      );
    });

    test('a string too short for three dashes is in the staff', () {
      expect(
        insertBar(_at('e|--3--5--|\nB|-5|', 7))!.text,
        'e|--3--|5--|\nB|-5---|',
      );
    });

    test('nothing off the strings', () {
      expect(insertBar(_at(staff, 1)), isNull);
      expect(insertBar(_at('la la la', 2)), isNull);
    });
  });

  group('= (spacer)', () {
    // A made-up riff, a chord name over it.
    const staff = 'Am\ne|--3--5--|\nB|-5---6--|\nG|--|';

    test('a dash down the phrase at the cursor, before the note there', () {
      // On the e line's 3.
      final spaced = insertSpacer(_at(staff, 3 + 4))!;
      expect(spaced.text, 'Am\ne|---3--5--|\nB|-5----6--|\nG|---|');
      // Just after the new dash: still before the 3.
      expect(spaced.text[spaced.selection.baseOffset], '3');
    });

    test('pressed again, one more dash each time', () {
      final once = insertSpacer(_at(staff, 3 + 4))!;
      final twice = insertSpacer(once)!;
      expect(twice.text, 'Am\ne|----3--5--|\nB|-5-----6--|\nG|----|');
    });

    test('at a line\'s end or in its closing bar: before the bar', () {
      // At the very end of the e line, after its closing bar.
      expect(
        insertSpacer(_at(staff, 3 + 11))!.text,
        'Am\ne|--3--5---|\nB|-5---6---|\nG|---|',
      );
    });

    test('never in a line\'s name or opening bar', () {
      final spaced = insertSpacer(_at(staff, 3))!;
      expect(spaced.text, 'Am\ne|---3--5--|\nB|--5---6--|\nG|---|');
      expect(spaced.selection.baseOffset, 3 + 3);
      expect(insertSpacer(_at('e|\nB|-5-|', 0))!.text, 'e|-\nB|--5-|');
    });

    test('only the cursor\'s phrase; nothing off the lines', () {
      const two = 'e|--3--|\nB|--5--|\n\ne|--7--|\nB|--8--|';
      expect(
        insertSpacer(_at(two, 3))!.text,
        'e|---3--|\nB|---5--|\n\ne|--7--|\nB|--8--|',
      );
      expect(insertSpacer(_at(staff, 1)), isNull);
      expect(insertSpacer(_at('la la la', 2)), isNull);
    });
  });

  group('|> (end together at the last end)', () {
    test('every string padded to the longest, before its closing bar', () {
      const ragged = 'e|--3--5--7--|\nB|-5---|\nG|---------';
      expect(
        alignEnds(_at(ragged, 0))!.text,
        'e|--3--5--7--|\nB|-5---------|\nG|-----------|',
      );
    });

    test('a double closing bar is every string\'s', () {
      expect(
        alignEnds(_at('e|--3--||\nB|-5-|', 0))!.text,
        'e|--3--||\nB|-5---||',
      );
    });

    test('every staff, other lines and trailing spaces', () {
      const two = 'Am\ne|--3--|  \nB|-5|\nla la\n\ne|-7|\nB|--8--|';
      expect(
        alignEnds(_at(two, 0))!.text,
        'Am\ne|--3--|\nB|-5---|\nla la\n\ne|-7---|\nB|--8--|',
      );
    });

    test('the cursor stays in its line, at the end when it was there', () {
      const ragged = 'e|--3--5--|\nB|-5-|';
      // At the end of the short string.
      final atEnd = alignEnds(_at(ragged, ragged.length))!;
      expect(atEnd.selection.baseOffset, atEnd.text.length);
      // On its 5: it stays on it.
      final onNote = alignEnds(_at(ragged, 12 + 3))!;
      expect(onNote.text[onNote.selection.baseOffset], '5');
    });

    test('already lined up: the same text; no staff: null', () {
      const even = 'e|--3--|\nB|-5---|';
      expect(alignEnds(_at(even, 0))!.text, even);
      expect(alignEnds(_at('e|--3--|', 0)), isNull);
      expect(alignEnds(_at('just words', 0)), isNull);
    });
  });

  group('<| (end together at the first end)', () {
    test('every line cut to the shortest, before its closing bar', () {
      const ragged = 'e|--3--------|\nB|-5---|\nG|-----------';
      expect(trimEnds(_at(ragged, 0))!.text, 'e|--3--|\nB|-5---|\nG|-----|');
    });

    test('a note past the shortest end isn\'t cut: one dash after it', () {
      const ragged = 'e|--3--5--7-----|\nB|-5|\nG|--------';
      expect(
        trimEnds(_at(ragged, 0))!.text,
        'e|--3--5--7-|\nB|-5--------|\nG|----------|',
      );
      // A note right at its line's end keeps its place, no dash added.
      expect(
        trimEnds(_at('e|--3--7|\nB|-5----------|', 0))!.text,
        'e|--3--7|\nB|-5----|',
      );
    });

    test('every phrase, the double closing bar every line\'s', () {
      const two = 'e|--3-----||\nB|-5---|\nla la\n\ne|-7|\nB|--8-----|';
      expect(
        trimEnds(_at(two, 0))!.text,
        'e|--3--||\nB|-5---||\nla la\n\ne|-7--|\nB|--8-|',
      );
    });

    test('the cursor in what was cut goes to the new end', () {
      const ragged = 'e|--3------|\nB|-5--|';
      final cut = trimEnds(_at(ragged, 9))!;
      expect(cut.text, 'e|--3-|\nB|-5--|');
      expect(cut.selection.baseOffset, 6);
      // At the end of the line: still at its end.
      final atEnd = trimEnds(_at(ragged, 12))!;
      expect(atEnd.selection.baseOffset, 7);
    });

    test('already together: the same text; no phrase: null', () {
      const even = 'e|--3--|\nB|-5---|';
      expect(trimEnds(_at(even, 0))!.text, even);
      expect(trimEnds(_at('e|--3--|', 0)), isNull);
      expect(trimEnds(_at('just words', 0)), isNull);
    });
  });

  group('New phrase (empty phrase)', () {
    const strings = ['e', 'B', 'G', 'D', 'A', 'E'];

    void expectStaff(List<String> lines) {
      expect(lines, hasLength(6));
      for (final (i, line) in lines.indexed) {
        expect(line, hasLength(newStaffWidth));
        expect(line, '${strings[i]}|${'-' * 77}|');
      }
    }

    test('in an empty text, the staff alone, the cursor after e|', () {
      final added = newStaff(_at('', 0));
      expectStaff(added.text.split('\n'));
      expect(added.selection.baseOffset, 2);
    });

    test('under the cursor\'s line, a blank line between', () {
      const text = 'Intro\nla la';
      final added = newStaff(_at(text, 2));
      final lines = added.text.split('\n');
      expect(lines.first, 'Intro');
      expect(lines[1], '');
      expectStaff(lines.sublist(2, 8));
      expect(lines[8], '');
      expect(lines.last, 'la la');
      // On the new first string, after its bar.
      expect(added.selection.baseOffset, 'Intro\n\n'.length + 2);
    });

    test('under the whole staff the cursor is on', () {
      const text = 'e|--3--|\nB|-5---|\n\nla la';
      final lines = newStaff(_at(text, 3)).text.split('\n');
      expect(lines.sublist(0, 2), ['e|--3--|', 'B|-5---|']);
      expect(lines[2], '');
      expectStaff(lines.sublist(3, 9));
      // The blank line that was there stays the only one.
      expect(lines.sublist(9), ['', 'la la']);
    });
  });
}
