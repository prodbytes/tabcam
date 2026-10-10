import 'package:flutter_test/flutter_test.dart';
import 'package:tabscan_app/recognition/tab_layout.dart';

// The riffs below are made up for these tests.
void main() {
  group('asciiTab', () {
    test('keeps a clean text tab as it is', () {
      const lines = [
        'Verse riff',
        'e|-------0-----|',
        'B|-----1---1---|',
        'G|---2-------2-|',
        'D|-2-----------|',
        'A|-------------|',
        'E|-------------|',
      ];
      expect(asciiTab(lines), lines.skip(1).join('\n'));
    });

    test('fixes OCR misreadings and pads lines to one length', () {
      const lines = [
        'e|—————O———|',
        'B|———l—————',
        'G|-—2——————|',
        'D|________|',
        'A|--S--',
        'E|---------|',
      ];
      expect(
        asciiTab(lines),
        [
          'e|-----0---|',
          'B|---1-----|',
          'G|--2------|',
          'D|---------|',
          'A|--5------|',
          'E|---------|',
        ].join('\n'),
      );
    });

    test('names the strings when the scan has no names', () {
      final tab = asciiTab([
        '|---3---5---|',
        '|-----------|',
        '|-----------|',
        '|-----------|',
      ])!;
      expect(tab.split('\n').map((l) => l[0]).join(), 'GDAE');
    });

    test('separates staves and ignores text between them', () {
      final tab = asciiTab([
        for (var i = 0; i < 6; i++) '|--$i-----|',
        'Chorus (play twice)',
        for (var i = 0; i < 6; i++) '|-----$i--|',
      ])!;
      expect(tab.split('\n\n'), hasLength(2));
    });

    test('is null when there is no tab', () {
      expect(asciiTab(['Intro', 'Play it slowly', '1, 2, 3, 4']), isNull);
    });
  });

  group('groupStaves', () {
    test('finds six-line and four-line staves, not five-line ones', () {
      final ys = [
        for (var i = 0; i < 6; i++) 100.0 + i * 12, // guitar
        for (var i = 0; i < 5; i++) 300.0 + i * 10, // notation
        for (var i = 0; i < 4; i++) 500.0 + i * 14, // bass
      ];
      final staves = groupStaves(ys, maxGap: 60);
      expect(staves.map((s) => s.length), [6, 4]);
      expect(staves.first.first, 100);
      expect(staves.last.first, 500);
    });
  });

  group('findStaves', () {
    test('finds the lines drawn on a page', () {
      const w = 200, h = 200;
      final dark = List<bool>.filled(w * h, false);
      for (var i = 0; i < 6; i++) {
        final y = 40 + i * 20;
        for (var x = 10; x < 190; x++) {
          // Gaps where fret numbers break the line.
          if (x % 50 < 6) continue;
          dark[y * w + x] = true;
          dark[(y + 1) * w + x] = true;
        }
      }
      final staves = findStaves(dark, w, h);
      expect(staves, hasLength(1));
      expect(staves.single, [40.5, 60.5, 80.5, 100.5, 120.5, 140.5]);
    });
  });

  group('typesetTab', () {
    const staff = [100.0, 110.0, 120.0, 130.0, 140.0, 150.0];

    test('puts each fret on its nearest line, chords in one column', () {
      final tab = typesetTab(
        [staff],
        const [
          Glyph('3', 50, 151, 8), // E
          Glyph('2', 80, 139, 8), // A
          Glyph('0', 110, 129, 8), // D
          Glyph('0', 140, 121, 8), // G, a chord with B and e
          Glyph('1', 141, 110, 8),
          Glyph('3', 140, 99, 8),
        ],
      )!;
      final rows = tab.split('\n');
      expect(rows.map((r) => r[0]).join(), 'eBGDAE');
      // Every string's row is the same length, and the chord lines up.
      expect(rows.map((r) => r.length).toSet(), hasLength(1));
      final chord = rows[0].indexOf('3');
      expect(rows[1][chord], '1');
      expect(rows[2][chord], '0');
      expect(rows[5].indexOf('3'), lessThan(rows[4].indexOf('2')));
    });

    test('keeps two-digit frets aligned', () {
      final tab = typesetTab(
        [staff],
        const [Glyph('12', 50, 100, 8), Glyph('9', 50, 110, 8)],
      )!;
      final rows = tab.split('\n');
      expect(rows[0], startsWith('e|--12'));
      expect(rows[1], startsWith('B|--9-'));
    });

    test('is null when nothing is on a staff', () {
      expect(typesetTab([staff], const [Glyph('5', 50, 400, 8)]), isNull);
    });
  });

  group('fretText', () {
    test('reads frets and mutes, fixing misreadings', () {
      expect(fretText('7'), '7');
      expect(fretText('12'), '12');
      expect(fretText('O'), '0');
      expect(fretText('l2'), '12');
      expect(fretText('X'), 'x');
      expect(fretText('-5-'), '5');
    });

    test('ignores words that are not frets', () {
      expect(fretText('TAB'), isNull);
      expect(fretText('Verse'), isNull);
      expect(fretText('123'), isNull);
    });
  });
}
