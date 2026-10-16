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
}
