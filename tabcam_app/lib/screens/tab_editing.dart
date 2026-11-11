import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../cloud/ocr_api.dart';
import '../recognition/file_dividers.dart';

/// Edits to a text tab that keep its columns lined up: overtype, + and −
/// on a fret, ++ and −− moving a note across strings, and auto-correct's
/// corrections.

/// A string line: dashes are what's between its notes. Never a file's
/// divider ([isFileDivider]), whatever dashes its name has.
bool isTabLine(String line) =>
    '-'.allMatches(line).length >= 3 && !isFileDivider(line);

/// What fills the room a note leaves: a dash on a string line, else a space.
String _filler(String line) => isTabLine(line) ? '-' : ' ';

({int start, int end}) _lineAt(String text, int offset) {
  final start = text.lastIndexOf('\n', offset - 1) + 1;
  final end = text.indexOf('\n', offset);
  return (start: start, end: end < 0 ? text.length : end);
}

/// Writes [note] over [line] at [column] in place of [width] characters:
/// a longer note takes the dashes after it, a shorter one leaves dashes,
/// so the notes after it stay in their columns where there's room.
String _put(String line, int column, int width, String note) {
  final fill = _filler(line);
  var end = column + width;
  var extra = note.length - width;
  while (extra > 0 && end < line.length && line[end] == '-') {
    end++;
    extra--;
  }
  final padded = note.length < width
      ? note + fill * (width - note.length)
      : note;
  return line.substring(0, column) + padded + line.substring(end);
}

/// [text] with [corrections] applied; one whose note isn't where it says
/// any more is skipped.
String applyCorrections(String text, Iterable<TabCorrection> corrections) {
  final lines = text.split('\n');
  final sorted = [...corrections]
    ..sort(
      (a, b) => a.line != b.line
          ? a.line.compareTo(b.line)
          : b.column.compareTo(a.column),
    );
  for (final c in sorted) {
    if (c.line >= lines.length) continue;
    final line = lines[c.line];
    final end = c.column + c.old.length;
    if (end > line.length || line.substring(c.column, end) != c.old) continue;
    lines[c.line] = _put(line, c.column, c.old.length, c.replacement);
  }
  return lines.join('\n');
}

/// Overtype: what's typed replaces the characters after the cursor on its
/// line, instead of pushing them right, and backspace leaves a dash on a
/// string line, so the columns stay put. Off: typing inserts as usual.
class OvertypeFormatter extends TextInputFormatter {
  OvertypeFormatter(this.enabled);

  final bool Function() enabled;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!enabled() ||
        !oldValue.selection.isValid ||
        !oldValue.selection.isCollapsed ||
        newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    final (old, now) = (oldValue.text, newValue.text);
    final at = oldValue.selection.baseOffset;
    final grown = now.length - old.length;
    // Typed at the cursor: [at, at + grown) is new, the rest unchanged.
    if (grown > 0 &&
        now.startsWith(old.substring(0, at)) &&
        now.endsWith(old.substring(at))) {
      final typed = now.substring(at, at + grown);
      if (typed.contains('\n')) return newValue;
      final after = at + grown;
      final line = _lineAt(now, after);
      final drop = (line.end - after).clamp(0, grown);
      return newValue.copyWith(
        text: now.substring(0, after) + now.substring(after + drop),
      );
    }
    // Backspace: the character before the cursor became a dash.
    if (grown == -1 &&
        at > 0 &&
        old[at - 1] != '\n' &&
        now == old.substring(0, at - 1) + old.substring(at)) {
      final line = _lineAt(old, at);
      if (!isTabLine(old.substring(line.start, line.end))) return newValue;
      return TextEditingValue(
        text: '${old.substring(0, at - 1)}-${old.substring(at)}',
        selection: TextSelection.collapsed(offset: at - 1),
      );
    }
    return newValue;
  }
}

/// + and −: the number under the cursor (one or two digits) goes up or
/// down by one, from 0 to 99, keeping the columns lined up. Null when
/// there's no number there. The cursor ends at the number's start, so the
/// next press works on it too.
TextEditingValue? bumpNumber(TextEditingValue value, int delta) {
  final text = value.text;
  final number = _numberAt(value);
  if (number == null) return null;
  final (start, end) = number;
  final n = int.parse(text.substring(start, end)) + delta;
  if (n < 0 || n > 99) return null;
  final line = _lineAt(text, start);
  final row = text.substring(line.start, line.end);
  final column = start - line.start;
  final changed = _put(row, column, end - start, '$n');
  return TextEditingValue(
    text: text.replaceRange(line.start, line.end, changed),
    selection: TextSelection.collapsed(offset: start),
  );
}

/// The number (one or two digits) at the cursor, or just before it, as
/// its start and end offsets; null when there's none.
(int, int)? _numberAt(TextEditingValue value) {
  final text = value.text;
  final at = value.selection.isValid ? value.selection.baseOffset : -1;
  if (at < 0) return null;
  bool digit(int i) =>
      i >= 0 && i < text.length && '0123456789'.contains(text[i]);
  // The digit at the cursor, or else the one just before it.
  final hit = digit(at) ? at : (digit(at - 1) ? at - 1 : -1);
  if (hit < 0) return null;
  var (start, end) = (hit, hit + 1);
  while (digit(start - 1)) {
    start--;
  }
  while (digit(end)) {
    end++;
  }
  if (end - start > 2) return null;
  return (start, end);
}

/// Why [moveNote] couldn't move a note.
enum MoveNoteFailure {
  /// The cursor isn't on a fret number on a string line.
  noNote,

  /// No other string of the staff has room for it at its column.
  noRoom,
}

/// ++ and −−: the note under the cursor moves to the string above
/// ([delta] −1) or below (+1), in the same column, cycling within its
/// staff (the string lines around it): up from the first string is the
/// last. A string whose spot holds another note is skipped. Dashes fill
/// the room it leaves, so the columns stay lined up, and the cursor
/// follows the note. [failure] says why when it can't move.
({TextEditingValue? moved, MoveNoteFailure? failure}) moveNote(
  TextEditingValue value,
  int delta,
) {
  const noNote = (moved: null, failure: MoveNoteFailure.noNote);
  final number = _numberAt(value);
  if (number == null) return noNote;
  final (start, end) = number;
  final text = value.text;
  final lines = text.split('\n');
  // The note's line and column.
  var row = 0, offset = 0;
  while (offset + lines[row].length < start) {
    offset += lines[row].length + 1;
    row++;
  }
  if (!isTabLine(lines[row])) return noNote;
  final column = start - offset;
  final width = end - start;
  final (first, last) = _staffAround(lines, row);
  final strings = last - first + 1;
  bool free(String line) {
    for (var i = column; i < column + width; i++) {
      if (i < line.length && line[i] != '-') return false;
    }
    return true;
  }

  for (var step = 1; step < strings; step++) {
    final to = first + (row - first + delta * step) % strings;
    final target = lines[to];
    if (!free(target)) continue;
    final note = text.substring(start, end);
    lines[row] = _put(lines[row], column, width, '');
    // A short string line is lengthened with dashes to reach the column.
    final padded = target.padRight(column + width, '-');
    lines[to] = padded.replaceRange(column, column + width, note);
    var at = column;
    for (var i = 0; i < to; i++) {
      at += lines[i].length + 1;
    }
    return (
      moved: TextEditingValue(
        text: lines.join('\n'),
        selection: TextSelection.collapsed(offset: at),
      ),
      failure: null,
    );
  }
  return (moved: null, failure: MoveNoteFailure.noRoom);
}

/// A string's name and its first bar, as `e|`, `B |` or `F#|`.
final RegExp _namedString = RegExp(r'^\s*[A-Ga-g][#b]?\s*\|');

/// A string line, even a short one: dashes ([isTabLine]), or a string's
/// name and a bar (`B|-5|`, too short for three dashes).
bool _isStringLine(String line) =>
    isTabLine(line) || _namedString.hasMatch(line);

/// The staff around string line [row]: the first and last of the string
/// lines ([_isStringLine]) next to each other there.
(int, int) _staffAround(List<String> lines, int row) {
  var first = row, last = row;
  while (first > 0 && _isStringLine(lines[first - 1])) {
    first--;
  }
  while (last < lines.length - 1 && _isStringLine(lines[last + 1])) {
    last++;
  }
  return (first, last);
}

/// The line and column of [offset] in [lines] (the text split at its
/// newlines).
(int, int) _rowColumn(List<String> lines, int offset) {
  var row = 0, start = 0;
  while (row < lines.length - 1 && start + lines[row].length < offset) {
    start += lines[row].length + 1;
    row++;
  }
  return (row, offset - start);
}

/// The offset of [row]'s [column] in [lines].
int _offsetOf(List<String> lines, int row, int column) {
  var at = column;
  for (var i = 0; i < row; i++) {
    at += lines[i].length + 1;
  }
  return at;
}

/// |: a bar line across the staff at the cursor's column. A `|` goes into
/// every string of the staff the cursor is on, at that column, pushing the
/// rest of each string right by one, so the columns stay lined up. A
/// string too short to reach the column is lengthened with dashes, and
/// the new bar becomes its closing bar. The
/// cursor ends just after the new bar. Null when the cursor isn't on a
/// string line.
TextEditingValue? insertBar(TextEditingValue value) {
  if (!value.selection.isValid) return null;
  final lines = value.text.split('\n');
  final (row, column) = _rowColumn(lines, value.selection.start);
  if (!_isStringLine(lines[row])) return null;
  final (first, last) = _staffAround(lines, row);
  for (var i = first; i <= last; i++) {
    final line = lines[i].trimRight();
    if (line.length <= column) {
      // A string that ends before the column: lengthened with dashes,
      // and the new bar is its closing bar (in place of the one it had).
      final body = line.replaceFirst(RegExp(r'\|+$'), '');
      lines[i] = '${body.padRight(column, '-')}|';
    } else {
      lines[i] = '${line.substring(0, column)}|${line.substring(column)}';
    }
  }
  return TextEditingValue(
    text: lines.join('\n'),
    selection: TextSelection.collapsed(
      offset: _offsetOf(lines, row, column + 1),
    ),
  );
}

/// The bars that close [line] (`|` or `||`), or none.
String _closingBars(String line) =>
    RegExp(r'\|+$').firstMatch(line)?.group(0) ?? '';

/// A line's opening: its string's name and first bar (`e|`), or a bar
/// alone (`|---`).
final RegExp _opening = RegExp(r'^\s*(?:[A-Ga-g][#b]?\s*)?\|');

/// =: a spacer, a dash down the phrase at the cursor's column. A `-` goes
/// into every line of the phrase the cursor is on, at that column,
/// pushing the rest of each line right by one, so the columns stay lined
/// up. A line that ends before the column (or the cursor in its closing
/// bar) gets its dash at its end, before its closing bar, and none goes
/// into a line's name or opening bar. The cursor ends just after the new
/// dash, still before the note it was before. Null when the cursor isn't
/// on a line of a phrase.
TextEditingValue? insertSpacer(TextEditingValue value) {
  if (!value.selection.isValid) return null;
  final lines = value.text.split('\n');
  final (row, column) = _rowColumn(lines, value.selection.start);
  if (!_isStringLine(lines[row])) return null;
  final (first, last) = _staffAround(lines, row);
  var cursorColumn = column + 1;
  for (var i = first; i <= last; i++) {
    final line = lines[i].trimRight();
    final end = line.length - _closingBars(line).length;
    final opening = _opening.firstMatch(line)?.end ?? 0;
    // A line that's only its opening (`e|`) gets the dash after it.
    final at = opening > end
        ? line.length
        : math.max(math.min(column, end), opening);
    lines[i] = '${line.substring(0, at)}-${line.substring(at)}';
    if (i == row) cursorColumn = at + 1;
  }
  return TextEditingValue(
    text: lines.join('\n'),
    selection: TextSelection.collapsed(
      offset: _offsetOf(lines, row, cursorColumn),
    ),
  );
}

/// |>: every phrase's lines end together, at the last end. In each phrase
/// (two or more lines next to each other), each line is padded with
/// dashes to the longest one, before its closing bar, and every line gets
/// the phrase's closing bar (the longest run of `|` that ends one of
/// them), so the bars at the end line up. Trailing spaces go. The cursor
/// stays where it was in its line (after the padding when it was at the
/// line's end). Null when the text has no phrase.
TextEditingValue? alignEnds(TextEditingValue value) => _endTogether(
  value,
  (bodies) => bodies.map((b) => b.length).reduce(math.max),
);

/// <|: every phrase's lines end together, at the first end. In each
/// phrase, each line is cut to the shortest one (the dashes before its
/// closing bar go) and every line gets the phrase's closing bar, as with
/// |>. Notes are never cut: where one stands past that end, the lines end
/// together one dash after the last note instead (right after it when its
/// line had no dash there). The cursor stays where it was in its line, or
/// at the new end when what it was on was cut. Null when the text has no
/// phrase.
TextEditingValue? trimEnds(TextEditingValue value) =>
    _endTogether(value, (bodies) {
      final shortest = bodies.map((b) => b.length).reduce(math.min);
      // How short each line can get and keep its notes, and a dash after
      // the last one when it had one.
      final kept = bodies
          .map((b) {
            final notes = b.replaceFirst(RegExp(r'-+$'), '').length;
            return notes < b.length ? notes + 1 : notes;
          })
          .reduce(math.max);
      return math.max(shortest, kept);
    });

/// Every phrase's lines made [widthOf] their bodies (each line without
/// its closing bar) wide, padded with dashes or cut, then given the
/// phrase's closing bar: [alignEnds] and [trimEnds].
TextEditingValue? _endTogether(
  TextEditingValue value,
  int Function(List<String> bodies) widthOf,
) {
  final lines = value.text.split('\n');
  final (row, column) = value.selection.isValid
      ? _rowColumn(lines, value.selection.start)
      : (-1, 0);
  var cursorColumn = column;
  var staves = 0;
  var i = 0;
  while (i < lines.length) {
    if (!_isStringLine(lines[i])) {
      i++;
      continue;
    }
    final (first, last) = _staffAround(lines, i);
    i = last + 1;
    if (last == first) continue;
    staves++;
    final trimmed = [for (var k = first; k <= last; k++) lines[k].trimRight()];
    final bodies = [
      for (final t in trimmed)
        t.substring(0, t.length - _closingBars(t).length),
    ];
    final closing = trimmed
        .map(_closingBars)
        .fold('', (longest, b) => b.length > longest.length ? b : longest);
    final width = widthOf(bodies);
    for (var k = first; k <= last; k++) {
      final body = bodies[k - first];
      final line =
          '${body.length > width ? body.substring(0, width) : body.padRight(width, '-')}'
          '$closing';
      // The cursor past the body (in the closing bar, or after it)
      // follows the line's end; one in dashes that were cut goes to it.
      if (k == row && column > body.length) {
        cursorColumn = math.min(width + column - body.length, line.length);
      } else if (k == row) {
        cursorColumn = math.min(column, width);
      }
      lines[k] = line;
    }
  }
  if (staves == 0) return null;
  return TextEditingValue(
    text: lines.join('\n'),
    selection: row < 0
        ? value.selection
        : TextSelection.collapsed(offset: _offsetOf(lines, row, cursorColumn)),
  );
}

/// How wide New phrase makes each line, its name and both bars included.
const newStaffWidth = 80;

/// New phrase: an empty six-line phrase in standard tuning,
/// `e B G D A E`, each line its string's name, a bar, dashes and a
/// closing bar, [newStaffWidth] characters in all. It goes under the
/// cursor's line, or under its whole phrase when the cursor is on one,
/// with a blank line between it and the text around it. The cursor ends
/// on the first line, just after its bar, to write the first note.
TextEditingValue newStaff(TextEditingValue value) {
  final staff = [
    for (final name in const ['e', 'B', 'G', 'D', 'A', 'E'])
      '$name|${'-' * (newStaffWidth - 3)}|',
  ];
  if (value.text.trim().isEmpty) {
    return TextEditingValue(
      text: staff.join('\n'),
      selection: const TextSelection.collapsed(offset: 2),
    );
  }
  final lines = value.text.split('\n');
  var after = lines.length - 1;
  if (value.selection.isValid) {
    final (row, _) = _rowColumn(lines, value.selection.start);
    after = _isStringLine(lines[row]) ? _staffAround(lines, row).$2 : row;
  }
  final before = lines[after].trim().isEmpty ? <String>[] : [''];
  final next = after + 1 < lines.length && lines[after + 1].trim().isNotEmpty
      ? ['']
      : <String>[];
  lines.insertAll(after + 1, [...before, ...staff, ...next]);
  return TextEditingValue(
    text: lines.join('\n'),
    selection: TextSelection.collapsed(
      offset: _offsetOf(lines, after + 1 + before.length, 2),
    ),
  );
}
