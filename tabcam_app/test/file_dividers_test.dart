import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/take_log.dart';
import 'package:tabcam_app/cloud/ocr_api.dart';
import 'package:tabcam_app/recognition/file_dividers.dart';
import 'package:tabcam_app/recognition/necklines.dart';
import 'package:tabcam_app/recognition/tab_doubts.dart';
import 'package:tabcam_app/recognition/tab_layout.dart';
import 'package:tabcam_app/screens/tab_editing.dart';

// Made-up riffs: tests never use published songs' tabs.
const _riffA = 'e|---0---3---|\nB|-1---1-----|';
const _riffB = 'G|-2---2b4r2-|\nD|-------5---|';

/// A text read from two files, the first named with dashes enough to pass
/// for a string line.
final _two = joinFileTexts([
  (name: 'a---b---c.pdf', text: _riffA),
  (name: 'Page 2', text: _riffB),
]).text;

void main() {
  group('the divider', () {
    test('the file\'s name between bars, filled out to 40 characters', () {
      expect(
        fileDivider('sheet-1.pdf'),
        '―― sheet-1.pdf ―――――――――――――――――――――――――',
      );
      expect(fileDivider('sheet-1.pdf').length, dividerWidth);
      expect(fileDivider('Page 2'), startsWith('―― Page 2 ――'));
    });

    test('a long name is cut, ending in …, with two bars after it', () {
      final divider = fileDivider('${'riff ' * 30}end');
      final name = divider.substring(3, divider.length - 3);
      expect(name.runes.length, dividerNameMax);
      expect(name, endsWith('…'));
      expect(divider, endsWith(' ――'));
      expect(isFileDivider(divider), isTrue);
    });

    test('odd characters: on one line, spaces collapsed, kept as named', () {
      expect(
        fileDivider('  my\nriff\t|--0--|  ação ♫.pdf '),
        startsWith('―― my riff |--0--| ação ♫.pdf ―'),
      );
      expect(fileDivider('x\r\ny').contains('\n'), isFalse);
      expect(isFileDivider(fileDivider('')), isTrue);
    });

    test('recognised; a tab line, lyrics or dashes alone aren\'t one', () {
      expect(isFileDivider(fileDivider('Page 1')), isTrue);
      expect(isFileDivider('  ${fileDivider('Page 1')}  '), isTrue);
      expect(isFileDivider('e|---0---3---|'), isFalse);
      expect(isFileDivider('-- Page 1 ------'), isFalse);
      expect(isFileDivider('la la ―'), isFalse);
    });
  });

  group('joining files\' texts', () {
    test('one file: its text alone, no divider', () {
      final joined = joinFileTexts([(name: 'Page 1', text: _riffA)]);
      expect(joined.text, _riffA);
      expect(joined.tops, [0]);
    });

    test('two files: each one\'s text after its divider, the first too', () {
      final joined = joinFileTexts([
        (name: 'sheet-1.pdf', text: _riffA),
        (name: 'Page 2', text: _riffB),
      ]);
      expect(
        joined.text,
        '${fileDivider('sheet-1.pdf')}\n$_riffA\n\n'
        '${fileDivider('Page 2')}\n$_riffB',
      );
      final lines = joined.text.split('\n');
      expect(joined.tops, [1, 5]);
      expect(lines[1], 'e|---0---3---|');
      expect(lines[5], 'G|-2---2b4r2-|');
    });

    test('none: no text', () {
      expect(joinFileTexts(const []).text, '');
    });
  });

  group('nothing reads a divider as tab', () {
    final divider = fileDivider('a---b---c.pdf');

    test('the string lines\' test', () {
      expect('-'.allMatches(divider).length, greaterThanOrEqualTo(3));
      expect(isTabLine(divider), isFalse);
    });

    test('Cam\'s necklines: in none, and none of its own', () {
      expect(necklines(_two), [_riffA, _riffB]);
      // Chords only: the blocks, without the dividers.
      final chords = joinFileTexts([
        (name: 'Page 1', text: 'Am  C  G'),
        (name: 'Page 2', text: 'F  G  Am'),
      ]).text;
      expect(necklines(chords), ['Am  C  G', 'F  G  Am']);
      // Right under a staff (the blank line deleted): it still ends it.
      expect(necklines('$_riffA\n$divider\n$_riffB'), [_riffA, _riffB]);
    });

    test('a take\'s necklines keep their indexes', () {
      final lines = necklines(_two);
      final tab = TakeTab.of(lines, [(Duration.zero, 0), (Duration.zero, 1)]);
      expect(tab.lines, [_riffA, _riffB]);
    });

    test('Fix lines the staves up and leaves the dividers as they are', () {
      final ragged = joinFileTexts([
        (name: '1-2-3-4.pdf', text: 'e|--0--3-|\nB|--1-|'),
        (name: '5-6-7-8.pdf', text: 'G|--2--|\nD|--2--2--|'),
      ]).text;
      final tidy = reformatTab(ragged).split('\n');
      expect(tidy[0], fileDivider('1-2-3-4.pdf'));
      expect(tidy[1].length, tidy[2].length);
      expect(tidy[4], fileDivider('5-6-7-8.pdf'));
      expect(tidy[5].length, tidy[6].length);
    });

    TextEditingValue at(String text, int line, int column) {
      final lines = text.split('\n');
      final offset =
          lines.take(line).fold(0, (n, l) => n + l.length + 1) + column;
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: offset),
      );
    }

    test('the spacer and the bar go into the staff, not the divider', () {
      final spaced = insertSpacer(at(_two, 1, 4))!.text.split('\n');
      expect(spaced[0], divider);
      expect(spaced[1], 'e|----0---3---|');
      expect(spaced[2], 'B|-1----1-----|');
      final barred = insertBar(at(_two, 1, 4))!.text.split('\n');
      expect(barred[0], divider);
    });

    test('ending the lines together leaves the dividers', () {
      final aligned = alignEnds(at(_two, 1, 0))!.text.split('\n');
      expect(aligned[0], divider);
      expect(aligned[4], fileDivider('Page 2'));
      final trimmed = trimEnds(at(_two, 1, 0));
      if (trimmed != null) {
        expect(trimmed.text.split('\n')[0], divider);
      }
    });

    test('backspace on a divider leaves no dash, as on text', () {
      final old = at(_two, 0, 4);
      final erased = TextEditingValue(
        text: old.text.replaceRange(3, 4, ''),
        selection: const TextSelection.collapsed(offset: 3),
      );
      final value = OvertypeFormatter(() => true).formatEditUpdate(old, erased);
      expect(value.text.split('\n')[0], startsWith('―― ---b---c.pdf ―'));
    });

    test('the cloud\'s doubts and auto-correct\'s corrections stay on their '
        'notes, by their lines in the whole text', () {
      const doubts = [TabDoubt(1, 5, '0'), TabDoubt(5, 7, '2b4r2')];
      expect(standingDoubts(_two, doubts), doubts);
      final fixed = applyCorrections(_two, const [
        TabCorrection(id: 'c1', line: 6, column: 9, old: '5', replacement: '7'),
      ]).split('\n');
      expect(fixed[0], divider);
      expect(fixed[6], 'D|-------7---|');
    });
  });
}
