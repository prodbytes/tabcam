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

/// The tab lines OCR read on a text tab, as clean plain text: one block per
/// staff, string names added when missing, every line of a staff the same
/// length. Null when fewer than four lines look like tab.
String? asciiTab(List<String> lines) {
  final staves = <List<String>>[];
  var staff = <String>[];
  for (final raw in lines) {
    final body = _tabBody(raw);
    if (body != null) {
      staff.add(body);
      continue;
    }
    if (staff.isNotEmpty) staves.add(staff);
    staff = <String>[];
  }
  if (staff.isNotEmpty) staves.add(staff);
  staves.removeWhere((s) => s.length < 4);
  if (staves.isEmpty) return null;
  return staves.map(_formatAsciiStaff).join('\n\n');
}

/// The body of a tab line, after its string name, with OCR's usual
/// misreadings fixed; null if the line isn't tab.
String? _tabBody(String line) {
  var body = line.replaceFirst(_prefix, '');
  body = body
      .replaceAll(RegExp(r'[—–_=‒−]'), '-')
      .replaceAll(RegExp(r'[Oo]'), '0')
      .replaceAll(RegExp(r'[lI!]'), '1')
      .replaceAll(RegExp(r'[S]'), '5')
      .replaceAll(RegExp(r'\s+$'), '');
  if (body.endsWith('|')) body = body.substring(0, body.length - 1);
  if (body.length < 4) return null;
  final tabChars = _tabChar.allMatches(body).length;
  final dashes = '-'.allMatches(body).length;
  if (tabChars < body.length * 0.8 || dashes < body.length * 0.3) return null;
  return body.replaceAll(' ', '-');
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
/// glyphs at about the same x are one column (a chord). Null when no glyph
/// falls on a staff.
String? typesetTab(List<List<double>> staves, List<Glyph> glyphs) {
  final blocks = <String>[];
  for (final lines in staves) {
    final gap = (lines.last - lines.first) / (lines.length - 1);
    final top = lines.first - gap / 2, bottom = lines.last + gap / 2;
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
    blocks.add(
      [for (var i = 0; i < lines.length; i++) '${names[i]}|${rows[i]}--|']
          .join('\n'),
    );
  }
  return blocks.isEmpty ? null : blocks.join('\n\n');
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
