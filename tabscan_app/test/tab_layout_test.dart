import 'package:flutter_test/flutter_test.dart';
import 'package:tabscan_app/recognition/tab_layout.dart';

// The riffs below are made up for these tests.

String? _ascii(List<String> lines) =>
    asciiTab([for (final l in lines) OcrLine(l)]);

void main() {
  group('asciiTab', () {
    test('keeps a clean text tab as it is, its title too', () {
      const lines = [
        'Verse riff',
        'e|-------0-----|',
        'B|-----1---1---|',
        'G|---2-------2-|',
        'D|-2-----------|',
        'A|-------------|',
        'E|-------------|',
      ];
      expect(_ascii(lines), lines.join('\n'));
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
        _ascii(lines),
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

    test('names the strings when the event has no names', () {
      final tab = _ascii([
        '|---3---5---|',
        '|-----------|',
        '|-----------|',
        '|-----------|',
      ])!;
      expect(tab.split('\n').map((l) => l[0]).join(), 'GDAE');
    });

    test('separates staves and keeps the text between them', () {
      final first = [for (var i = 0; i < 6; i++) '|--$i-----|'];
      final second = [for (var i = 0; i < 6; i++) '|-----$i--|'];
      final tab = _ascii([...first, 'Chorus (play twice)', ...second])!;
      final blocks = tab.split('\n\n');
      expect(blocks, hasLength(2));
      expect(blocks[1].split('\n').first, 'Chorus (play twice)');
      expect(blocks[1].split('\n'), hasLength(7));
    });

    test('drops web addresses, page numbers and stray marks', () {
      final tab = _ascii([
        'https://tabs.example.com/made-up-riff',
        'e|---0---|',
        'B|-1-----|',
        'G|-------|',
        'D|-------|',
        'A|-------|',
        'E|-------|',
        'Page 1/2',
        'Digitalizado com CamScanner',
        '%% ~~ ^^',
        'la la la',
      ])!;
      expect(tab.split('\n').first, 'e|---0---|');
      expect(tab.split('\n').last, 'la la la');
      expect(tab, isNot(contains('Page')));
    });

    test('puts chord names at the tab\'s columns', () {
      // Letters 10 px wide; the tab lines start at x = 100 with `e|`.
      OcrLine tabLine(String text, double top) => OcrLine(
        text,
        left: 100,
        right: 100 + text.length * 10.0,
        top: top,
        bottom: top + 10,
      );
      final tab = asciiTab([
        const OcrLine(
          'Am G',
          words: [OcrWord('Am', 120), OcrWord('G', 180)],
          left: 120,
          right: 190,
          top: 0,
          bottom: 10,
        ),
        tabLine('e|-0-----3-|', 20),
        tabLine('B|-1-----0-|', 30),
        tabLine('G|-2-----0-|', 40),
        tabLine('D|-2-----0-|', 50),
        tabLine('A|-0-----2-|', 60),
        tabLine('E|-------3-|', 70),
      ])!;
      expect(tab.split('\n').take(2), ['  Am    G', 'e|-0-----3-|']);
    });

    group('with the characters\' positions', () {
      // Letters 10 px wide from x = 100, a line every 10 px. OCR reads
      // [truth] without the characters at [drop], but where each is.
      OcrLine seen(String truth, double top, {Set<int> drop = const {}}) {
        final kept = [
          for (var i = 0; i < truth.length; i++)
            if (!drop.contains(i)) i,
        ];
        return OcrLine(
          kept.map((i) => truth[i]).join(),
          chars: [
            for (final i in kept)
              OcrChar(truth[i], 100 + i * 10.0, 110 + i * 10.0),
          ],
          left: 100,
          right: 100 + truth.length * 10.0,
          top: top,
          bottom: top + 10,
        );
      }

      test('keeps a chord\'s notes in one column where OCR dropped dashes', () {
        final tab = asciiTab([
          seen('e|-0-----3-|', 0),
          seen('B|-1-----0-|', 10, drop: {4, 5, 6}),
          seen('G|-2-----0-|', 20, drop: {2}),
          seen('D|-2-----0-|', 30),
          seen('A|-0-----2-|', 40, drop: {5, 6}),
          seen('E|-------3-|', 50, drop: {2, 3, 4, 5}),
        ])!;
        expect(
          tab,
          [
            'e|-0-----3-|',
            'B|-1-----0-|',
            'G|-2-----0-|',
            'D|-2-----0-|',
            'A|-0-----2-|',
            'E|-------3-|',
          ].join('\n'),
        );
      });

      test('ends every line together', () {
        final tab = asciiTab([
          seen('e|-0-----3---|', 0),
          seen('B|-1-----0', 10),
          seen('G|-2-----0---|', 20),
          seen('D|-2-----0-|', 30, drop: {10}),
        ])!;
        final lines = tab.split('\n');
        expect(lines.map((l) => l.length).toSet(), {lines.first.length});
        expect(lines.every((l) => l.endsWith('|')), isTrue);
        expect(lines.first.indexOf('3'), 9);
        expect(lines.skip(1).map((l) => l.indexOf('0', 4)), [9, 9, 9]);
      });

      test('puts chord names at the grid\'s columns', () {
        final tab = asciiTab([
          const OcrLine(
            'Am G',
            words: [OcrWord('Am', 130), OcrWord('G', 190)],
            left: 130,
            right: 200,
            top: -10,
            bottom: 0,
          ),
          seen('e|-0-----3-|', 0),
          seen('B|-1-----0-|', 10, drop: {4, 5}),
          seen('G|-2-----0-|', 20),
          seen('D|-2-----0-|', 30),
          seen('A|-0-----2-|', 40),
          seen('E|-------3-|', 50),
        ])!;
        expect(tab.split('\n').take(2), ['   Am    G', 'e|-0-----3-|']);
      });
    });

    test('is null when there is no tab', () {
      expect(_ascii(['Intro', 'Play it slowly', '1, 2, 3, 4']), isNull);
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
      expect(
        typesetTab(
          [staff],
          const [],
          text: const [OcrLine('la la la', top: 200, bottom: 210)],
        ),
        isNull,
      );
    });

    test('keeps the chords and lyrics off the staff, in their place', () {
      final tab = typesetTab(
        [staff],
        const [Glyph('3', 50, 100, 8)],
        text: const [
          OcrLine('la la la', top: 170, bottom: 180),
          OcrLine('T', top: 105, bottom: 115), // TAB, on the staff
          OcrLine(
            '5 7',
            words: [OcrWord('5', 0), OcrWord('7', 20)],
            top: 160,
            bottom: 168,
          ), // frets just off it
          OcrLine('Verse', top: 60, bottom: 70),
          OcrLine('Am', top: 80, bottom: 90),
        ],
      )!;
      final rows = tab.split('\n');
      expect(rows.take(3), ['Verse', 'Am', 'e|--3--|']);
      expect(rows.skip(8), ['', 'la la la']);
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
