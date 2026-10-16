import 'dart:math' as math;

/// Turns what OCR read on a page into plain-text tablature. Pure Dart, so
/// it's tested without a device (test/tab_layout_test.dart).
///
/// Two kinds of page:
/// - text tabs, printed from a website: OCR reads whole lines such as
///   `e|---0---3---|`, which [asciiTab] cleans up;
/// - typeset tabs (books, Guitar Pro printouts): fret numbers sit on drawn
///   staff lines, so OCR only finds the numbers. [typesetTab] puts each one
///   on the nearest line ([findStaves] finds the lines in the image).

/// String names, high to low, by how many lines a staff has.
const Map<int, List<String>> stringNames = {
  6: ['e', 'B', 'G', 'D', 'A', 'E'],
  4: ['G', 'D', 'A', 'E'],
};

// Characters a tab line's body is made of: frets, techniques (hammer-on,
// pull-off, bend, release, slide, vibrato, mute), bar lines and spacing.
final RegExp _tabChar = RegExp(r'[-0-9|hpbrsx/\\~()<>.*: ]');

// An optional string name and bar line in front of a tab line.
final RegExp _prefix = RegExp(r'^\s*([eBGDAEbgda])?\s*[|:\]]?');

/// A word OCR read, and where it starts (image pixels).
class OcrWord {
  const OcrWord(this.text, this.left);
  final String text;
  final double left;
}

/// A character OCR read (not a space), and its box's left and right
/// (image pixels).
class OcrChar {
  const OcrChar(this.text, this.left, this.right);
  final String text;
  final double left;
  final double right;

  double get x => (left + right) / 2;
}

/// A line OCR read: its text, words, characters and box (image pixels; a
/// zero box when unknown, as in tests). [chars] are the text's characters
/// other than spaces, in order, when OCR says where each one is.
class OcrLine {
  const OcrLine(
    this.text, {
    this.words = const [],
    this.chars = const [],
    this.left = 0,
    this.right = 0,
    this.top = 0,
    this.bottom = 0,
  });

  final String text;
  final List<OcrWord> words;
  final List<OcrChar> chars;
  final double left;
  final double right;
  final double top;
  final double bottom;

  bool get located => right > left;
  double get y => (top + bottom) / 2;
}

/// A page's tab and the notations around it (chords, lyrics, section
/// names), top to bottom: a staff, or a line of text.
sealed class _Piece {}

class _Staff extends _Piece {
  _Staff(this.text);
  final String text;
}

class _Text extends _Piece {
  _Text(this.text);
  final String text;
}

/// Pieces as one text: a blank line between staves and after a staff,
/// none before a staff (chord names and labels sit right above it).
String _join(List<_Piece> pieces) {
  final out = StringBuffer();
  for (final (i, p) in pieces.indexed) {
    if (i > 0) out.write(pieces[i - 1] is _Staff ? '\n\n' : '\n');
    out.write(p is _Staff ? p.text : (p as _Text).text);
  }
  return out.toString();
}

/// The tab lines OCR read on a text tab, as clean plain text: one block per
/// staff, string names added when missing, every line of a staff the same
/// length; the page's other notations (chords, lyrics, section names) kept
/// in their place, chords at the tab's columns when OCR says where its
/// words are. When OCR says where each character is, a staff's characters
/// go on one grid of columns ([_gridStaff]), so a chord's notes line up
/// even where OCR dropped or added dashes. Null when fewer than four lines
/// look like tab.
String? asciiTab(List<OcrLine> lines) {
  final pieces = <_Piece>[];
  var staff = <OcrLine>[];
  // Where a tab line's text starts, and its letters' width, to place the
  // words of the text lines at the tab's columns.
  final origins = <double>[], widths = <double>[], shifts = <double>[];
  void close() {
    if (staff.length >= 4) {
      final grid = _gridStaff(staff);
      if (grid != null) {
        pieces.add(_Staff(grid.text));
        // Column 0 of the body starts half a column left of its center, and
        // the formatted line starts `e|`.
        origins.add(grid.origin - grid.width / 2);
        widths.add(grid.width);
        shifts.add(2);
      } else {
        pieces.add(
          _Staff(_formatAsciiStaff([for (final l in staff) _tabBody(l.text)!])),
        );
        for (final raw in staff) {
          final length = raw.text.trimRight().length;
          if (raw.located && length > 0) {
            origins.add(raw.left);
            widths.add((raw.right - raw.left) / length);
            // The formatted line starts `e|`, whatever the read one did.
            shifts.add(2.0 - _prefix.firstMatch(raw.text)!.end);
          }
        }
      }
    }
    staff = <OcrLine>[];
  }

  for (final raw in lines) {
    if (_tabBody(raw.text) != null) {
      staff.add(raw);
      continue;
    }
    close();
    if (isNotation(raw.text)) pieces.add(_Text(raw.text.trim()));
  }
  close();
  if (!pieces.any((p) => p is _Staff)) return null;
  if (widths.isNotEmpty) {
    final (origin, width, shift) = (
      _median(origins),
      _median(widths),
      _median(shifts),
    );
    var t = 0;
    for (final raw in lines) {
      if (_tabBody(raw.text) != null || !isNotation(raw.text)) continue;
      while (pieces[t] is! _Text) {
        t++;
      }
      if (raw.located && raw.words.isNotEmpty) {
        pieces[t] = _Text(
          placeWords([
            for (final w in raw.words)
              (w.text, ((w.left - origin) / width + shift).round()),
          ]),
        );
      }
      t++;
    }
  }
  return _join(pieces);
}

/// A staff laid out by where OCR saw each character: its text, the center
/// of its body's first column and a column's width (image pixels). Every
/// line's body characters go at the column their x implies, measured from
/// the staff's start (the median of where the lines' bodies start) in the
/// staff's character pitch (the median gap between neighbouring
/// characters), so a chord's notes share a column even where OCR dropped
/// or doubled dashes; the gaps are dashes, and every line ends at the same
/// column. Null when a line doesn't say where its characters are.
({String text, double origin, double width})? _gridStaff(List<OcrLine> staff) {
  final bodies = <List<OcrChar>>[];
  for (final line in staff) {
    final body = _bodyChars(line);
    if (body == null || body.isEmpty) return null;
    bodies.add(body);
  }
  final pitches = <double>[
    for (final body in bodies)
      for (var i = 1; i < body.length; i++)
        if (body[i].x > body[i - 1].x) body[i].x - body[i - 1].x,
  ];
  if (pitches.isEmpty) return null;
  final width = _median(pitches);
  final origin = _median([for (final body in bodies) body.first.x]);
  final rows = <List<String>>[];
  for (final body in bodies) {
    final row = <String>[];
    for (final c in body) {
      var column = math.max(0, ((c.x - origin) / width).round());
      if (c.text == '-') {
        while (row.length <= column) {
          row.add('-');
        }
        continue;
      }
      // A note never overwrites another: it takes the next free column.
      while (column < row.length && row[column] != '-') {
        column++;
      }
      while (row.length <= column) {
        row.add('-');
      }
      row[column] = c.text;
    }
    rows.add(row);
  }
  final names = stringNames[rows.length];
  final columns = rows.map((r) => r.length).reduce(math.max);
  return (
    text: [
      for (final (i, row) in rows.indexed)
        '${names?[i] ?? ' '}|${row.join().padRight(columns, '-')}|',
    ].join('\n'),
    origin: origin,
    width: width,
  );
}

/// A tab line's body characters (after its string name and bar, without
/// the closing bar), misreadings fixed as [_tabBody] does; null when OCR
/// didn't say where each character is.
List<OcrChar>? _bodyChars(OcrLine line) {
  final visible = line.text.replaceAll(RegExp(r'\s'), '');
  if (line.chars.length != visible.length ||
      line.chars.map((c) => c.text).join() != visible) {
    return null;
  }
  final prefix = _prefix.firstMatch(line.text)!.group(0)!;
  final skip = prefix.replaceAll(RegExp(r'\s'), '').length;
  final body = [
    for (final c in line.chars.skip(skip))
      OcrChar(_fixTabChars(c.text), c.left, c.right),
  ];
  if (body.isNotEmpty && body.last.text == '|') body.removeLast();
  return body;
}

/// OCR's usual misreadings on a tab line fixed: long dashes, `_` and `=`
/// are `-`; `O` and `o` are 0; `l`, `I` and `!` are 1; `S` is 5.
String _fixTabChars(String text) => text
    .replaceAll(RegExp(r'[—–_=‒−]'), '-')
    .replaceAll(RegExp(r'[Oo]'), '0')
    .replaceAll(RegExp(r'[lI!]'), '1')
    .replaceAll(RegExp(r'[S]'), '5');

/// Words at their columns ([text], column), at least a space apart.
String placeWords(List<(String, int)> words) {
  final out = StringBuffer();
  for (final (text, column) in [...words]..sort((a, b) => a.$2 - b.$2)) {
    final gap = out.isEmpty ? column : column - out.length;
    out.write(' ' * math.max(gap, out.isEmpty ? 0 : 1));
    out.write(text);
  }
  return out.toString();
}

final RegExp _url = RegExp(
  r'https?://|www\.|\.(com|net|org|br)\b'
  r'|camscanner|scanned with|digitalizado com|escaneado con',
  caseSensitive: false,
);
final RegExp _pageNumber = RegExp(
  r'^(page\s*)?\d+(\s*(/|of)\s*\d+)?$',
  caseSensitive: false,
);
final RegExp _odd = RegExp(r"[^A-Za-z0-9À-ÿ\s#/()'’,.!?:;&+\-]");

/// Whether a line of text OCR read is a notation worth keeping beside the
/// tab (chord names, lyrics, a section's name), not noise: a web address,
/// a page number, a garbled tab line, stray marks.
bool isNotation(String line) {
  final text = line.trim();
  if (text.isEmpty || _url.hasMatch(text) || _pageNumber.hasMatch(text)) {
    return false;
  }
  if (!RegExp('[A-Za-zÀ-ÿ]').hasMatch(text)) return false;
  if ('-'.allMatches(text).length >= text.length * 0.3) return false;
  return _odd.allMatches(text).length <= text.length * 0.2;
}

/// The body of a tab line, after its string name, with OCR's usual
/// misreadings fixed; null if the line isn't tab.
String? _tabBody(String line) {
  var body = _fixTabChars(line.replaceFirst(_prefix, ''))
      .replaceAll(RegExp(r'\s+$'), '');
  if (body.endsWith('|')) body = body.substring(0, body.length - 1);
  if (body.length < 4) return null;
  final tabChars = _tabChar.allMatches(body).length;
  final dashes = '-'.allMatches(body).length;
  if (tabChars < body.length * 0.8 || dashes < body.length * 0.3) return null;
  return body.replaceAll(' ', '-');
}

/// Fix's tidying of a text tab, typed or read: each staff's strings
/// lined up, nothing else touched. Consecutive tab lines are a staff (two
/// or more); in one, OCR's usual slips are fixed (long dashes, `O` for 0,
/// spaces), strings without a name are named (`e B G D A E`, bass
/// `G D A E`; names written on every string are kept), and the bars line up: each measure is padded
/// with dashes to its widest string, so every string ends together and a
/// measure's notes stay in it. Every other line (chords, lyrics, notes,
/// blank lines) stays as it is, and a lone tab-like line too.
String reformatTab(String text) {
  final out = <String>[];
  var raws = <String>[];
  var bodies = <String>[];
  void close() {
    if (bodies.length >= 2) {
      // The names as written when every string has one; else the usual
      // ones for the count (or as written, or none).
      final given = [for (final r in raws) _prefix.firstMatch(r)?.group(1)];
      final names = stringNames[bodies.length];
      final labels = [
        for (final (i, name) in given.indexed)
          given.every((n) => n != null) ? name! : names?[i] ?? name ?? ' ',
      ];
      out.addAll(_alignMeasures(labels, bodies));
    } else {
      out.addAll(raws.map((r) => r.trimRight()));
    }
    raws = [];
    bodies = [];
  }

  for (final raw in text.split('\n')) {
    final body = _tabBody(raw);
    if (body != null) {
      raws.add(raw);
      bodies.add(body);
      continue;
    }
    close();
    out.add(raw.trimRight());
  }
  close();
  return out.join('\n');
}

/// A staff's lines with their bars lined up: measure by measure, each
/// padded to the widest string's, then the closing bar.
List<String> _alignMeasures(List<String> labels, List<String> bodies) {
  final measures = [for (final b in bodies) b.split('|')];
  final count = measures.map((m) => m.length).reduce(math.max);
  final widths = [
    for (var k = 0; k < count; k++)
      measures.map((m) => k < m.length ? m[k].length : 0).reduce(math.max),
  ];
  return [
    for (final (i, m) in measures.indexed)
      '${labels[i]}|${[for (var k = 0; k < count; k++) (k < m.length ? m[k] : '').padRight(widths[k], '-')].join('|')}|',
  ];
}

String _formatAsciiStaff(List<String> bodies) {
  final names = stringNames[bodies.length];
  final width = bodies.map((b) => b.length).reduce(math.max);
  return [
    for (var i = 0; i < bodies.length; i++)
      '${names?[i] ?? ' '}|${bodies[i].padRight(width, '-')}|',
  ].join('\n');
}

/// A horizontal line found in the image: its center row and thickness.
class StaffLine {
  const StaffLine(this.y, this.thickness);
  final double y;
  final double thickness;
}

/// The staves in a binarized page: groups of six (guitar) or four (bass)
/// evenly spaced horizontal lines. Five-line groups (standard notation) are
/// left out.
///
/// [dark] is the page row by row, true where it's ink. A row is part of a
/// line when at least [minDarkFraction] of it is ink: staff lines cross
/// most of the page, broken only by the fret numbers on them, while a row
/// through text is mostly paper.
List<List<double>> findStaves(
  List<bool> dark,
  int width,
  int height, {
  double minDarkFraction = 0.45,
}) {
  final minDark = (width * minDarkFraction).round();
  final lines = <StaffLine>[];
  int? start;
  for (var y = 0; y <= height; y++) {
    final isLine = y < height && _darkInRow(dark, width, y) >= minDark;
    if (isLine) {
      start ??= y;
    } else if (start != null) {
      lines.add(StaffLine((start + y - 1) / 2, (y - start).toDouble()));
      start = null;
    }
  }
  return groupStaves(lines.map((l) => l.y).toList(), maxGap: height / 10);
}

int _darkInRow(List<bool> dark, int width, int y) {
  var count = 0;
  final row = y * width;
  for (var x = 0; x < width; x++) {
    if (dark[row + x]) count++;
  }
  return count;
}

/// Groups line positions (sorted, top to bottom) into staves: runs of lines
/// with about the same gap, no larger than [maxGap], that have six or four
/// lines.
List<List<double>> groupStaves(List<double> ys, {required double maxGap}) {
  final staves = <List<double>>[];
  var group = <double>[];
  void close() {
    if (stringNames.containsKey(group.length)) staves.add(group);
    group = <double>[];
  }

  for (final y in ys) {
    if (group.isEmpty) {
      group.add(y);
      continue;
    }
    final gap = y - group.last;
    final expected = group.length > 1 ? group[1] - group[0] : gap;
    final even = (gap - expected).abs() <= expected * 0.3;
    if (gap <= maxGap && gap > 0 && even) {
      group.add(y);
    } else {
      close();
      group.add(y);
    }
  }
  close();
  return staves;
}

/// A fret number (or a mute, `x`) OCR found, and where: its box's center
/// and height in image pixels.
class Glyph {
  const Glyph(this.text, this.x, this.y, this.height);
  final String text;
  final double x;
  final double y;
  final double height;
}

/// Plain-text tab from the [staves] found in the image and the fret
/// [glyphs] OCR read on it. Each glyph goes on its staff's nearest line;
/// glyphs at about the same x are one column (a chord). The [text] lines
/// OCR read off the staves that are notations (chord names, lyrics,
/// section names) go in their place, top to bottom. Null when no glyph
/// falls on a staff.
String? typesetTab(
  List<List<double>> staves,
  List<Glyph> glyphs, {
  List<OcrLine> text = const [],
}) {
  final blocks = <(double, _Piece)>[];
  final bands = <(double, double)>[];
  for (final lines in staves) {
    final gap = (lines.last - lines.first) / (lines.length - 1);
    final top = lines.first - gap / 2, bottom = lines.last + gap / 2;
    bands.add((top, bottom));
    final onStaff = glyphs.where((g) => g.y >= top && g.y <= bottom).toList()
      ..sort((a, b) => a.x.compareTo(b.x));
    if (onStaff.isEmpty) continue;
    final unit = _median(onStaff.map((g) => g.height).toList());

    // Columns: glyphs closer than half a glyph height in x.
    final columns = <List<Glyph>>[];
    for (final g in onStaff) {
      if (columns.isNotEmpty && g.x - columns.last.first.x < unit * 0.5) {
        columns.last.add(g);
      } else {
        columns.add([g]);
      }
    }

    final rows = List.generate(lines.length, (_) => StringBuffer('-'));
    double? lastX;
    for (final column in columns) {
      final x = column.first.x;
      final width = column.map((g) => g.text.length).reduce(math.max);
      // Dashes before the column grow with the distance from the last one.
      final spacing = lastX == null
          ? 1
          : ((x - lastX) / unit).round().clamp(1, 8);
      lastX = x;
      final cells = List.filled(lines.length, '-' * width);
      for (final g in column) {
        cells[_nearest(lines, g.y)] = g.text.padRight(width, '-');
      }
      for (var i = 0; i < lines.length; i++) {
        rows[i]
          ..write('-' * spacing)
          ..write(cells[i]);
      }
    }
    final names = stringNames[lines.length]!;
    blocks.add((
      top,
      _Staff(
        [for (var i = 0; i < lines.length; i++) '${names[i]}|${rows[i]}--|']
            .join('\n'),
      ),
    ));
  }
  if (blocks.isEmpty) return null;
  for (final line in text) {
    final onStaff = bands.any((b) => line.y >= b.$1 && line.y <= b.$2);
    final frets =
        line.words.isNotEmpty &&
        line.words.every((w) => fretText(w.text) != null);
    if (!onStaff && !frets && isNotation(line.text)) {
      blocks.add((line.y, _Text(line.text.trim())));
    }
  }
  blocks.sort((a, b) => a.$1.compareTo(b.$1));
  return _join([for (final (_, piece) in blocks) piece]);
}

int _nearest(List<double> lines, double y) {
  var best = 0;
  for (var i = 1; i < lines.length; i++) {
    if ((lines[i] - y).abs() < (lines[best] - y).abs()) best = i;
  }
  return best;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

/// The fret text in an OCR'd word, with misreadings fixed: `O` is 0, `l`
/// and `I` are 1, `X` is a mute. Null when it isn't a fret.
String? fretText(String word) {
  final text = word
      .replaceAll(RegExp(r'[Oo]'), '0')
      .replaceAll(RegExp(r'[lI|!]'), '1')
      .replaceAll('X', 'x')
      .replaceAll(RegExp(r'[^0-9x]'), '');
  if (RegExp(r'^([0-9]{1,2}|x)$').hasMatch(text)) return text;
  return null;
}
