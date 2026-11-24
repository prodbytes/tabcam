import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;
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
  _barInto(lines, [for (var i = first; i <= last; i++) i], column);
  return TextEditingValue(
    text: lines.join('\n'),
    selection: TextSelection.collapsed(
      offset: _offsetOf(lines, row, column + 1),
    ),
  );
}

/// A `|` into each of [rows] of [lines] at [column], pushing the rest of
/// the line right by one; a line too short to reach the column is
/// lengthened with dashes, and the bar becomes its closing bar.
void _barInto(List<String> lines, Iterable<int> rows, int column) {
  for (final i in rows) {
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
  final at = _spacerInto(lines, [
    for (var i = first; i <= last; i++) i,
  ], column);
  return TextEditingValue(
    text: lines.join('\n'),
    selection: TextSelection.collapsed(
      offset: _offsetOf(lines, row, (at[row] ?? column) + 1),
    ),
  );
}

/// A `-` into each of [rows] of [lines] at [column], pushing the rest of
/// the line right by one: a line that ends before the column (or [column]
/// in its closing bar) gets it at its end, before its closing bar, and
/// none goes into a line's name or opening bar. Returns the column each
/// row got its dash at.
Map<int, int> _spacerInto(List<String> lines, Iterable<int> rows, int column) {
  final put = <int, int>{};
  for (final i in rows) {
    final line = lines[i].trimRight();
    final end = line.length - _closingBars(line).length;
    final opening = _opening.firstMatch(line)?.end ?? 0;
    // A line that's only its opening (`e|`) gets the dash after it.
    final at = opening > end
        ? line.length
        : math.max(math.min(column, end), opening);
    lines[i] = '${line.substring(0, at)}-${line.substring(at)}';
    put[i] = at;
  }
  return put;
}

/// |>: every phrase's lines end together, at the last end. In each phrase
/// (two or more lines next to each other), each line is padded with
/// dashes to the longest one, before its closing bar, and every line gets
/// the phrase's closing bar (the longest run of `|` that ends one of
/// them), so the bars at the end line up. Trailing spaces go. The cursor
/// stays where it was in its line (after the padding when it was at the
/// line's end). Null when the text has no phrase.
///
/// With [lines] (a selection's, first to last), only those lines: each
/// phrase's lines among them end together, the rest of the text as it
/// was.
TextEditingValue? alignEnds(
  TextEditingValue value, {
  ({int top, int bottom})? lines,
}) => _endTogether(
  value,
  (bodies) => bodies.map((b) => b.length).reduce(math.max),
  only: lines,
);

/// <|: every phrase's lines end together, at the first end. In each
/// phrase, each line is cut to the shortest one (the dashes before its
/// closing bar go) and every line gets the phrase's closing bar, as with
/// |>. Notes are never cut: where one stands past that end, the lines end
/// together one dash after the last note instead (right after it when its
/// line had no dash there). The cursor stays where it was in its line, or
/// at the new end when what it was on was cut. Null when the text has no
/// phrase. With [lines], only those, as [alignEnds].
TextEditingValue? trimEnds(
  TextEditingValue value, {
  ({int top, int bottom})? lines,
}) => _endTogether(value, (bodies) {
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
}, only: lines);

/// Every phrase's lines made [widthOf] their bodies (each line without
/// its closing bar) wide, padded with dashes or cut, then given the
/// phrase's closing bar: [alignEnds] and [trimEnds]. With [only], just
/// the phrases' lines from its top to its bottom.
TextEditingValue? _endTogether(
  TextEditingValue value,
  int Function(List<String> bodies) widthOf, {
  ({int top, int bottom})? only,
}) {
  final lines = value.text.split('\n');
  final (row, column) = value.selection.isValid
      ? _rowColumn(lines, value.selection.start)
      : (-1, 0);
  var cursorColumn = column;
  var staves = 0;
  final top = math.max(only?.top ?? 0, 0);
  final bottom = math.min(only?.bottom ?? lines.length - 1, lines.length - 1);
  var i = top;
  while (i <= bottom) {
    if (!_isStringLine(lines[i])) {
      i++;
      continue;
    }
    final (around, end) = _staffAround(lines, i);
    final first = math.max(around, top);
    final last = math.min(end, bottom);
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

/// The strings' names in a new phrase, top to bottom (high E first).
const _stringNames = ['e', 'B', 'G', 'D', 'A', 'E'];

/// New phrase: an empty six-line phrase in standard tuning,
/// `e B G D A E`, each line its string's name, a bar, dashes and a
/// closing bar, [newStaffWidth] characters in all. It goes under the
/// cursor's line, or under its whole phrase when the cursor is on one,
/// with a blank line between it and the text around it. The cursor ends
/// on the first line, just after its bar, to write the first note.
TextEditingValue newStaff(TextEditingValue value) => _addStaff(value, [
  for (final name in _stringNames) '$name|${'-' * (newStaffWidth - 3)}|',
], 2);

/// [value] with [staff] under the cursor's line, or under its whole
/// phrase when the cursor is on one (at the end without a cursor), a
/// blank line between it and the text around it; the cursor on its line
/// [row] (its first), at [column].
TextEditingValue _addStaff(
  TextEditingValue value,
  List<String> staff,
  int column, {
  int row = 0,
}) {
  if (value.text.trim().isEmpty) {
    return TextEditingValue(
      text: staff.join('\n'),
      selection: TextSelection.collapsed(offset: _offsetOf(staff, row, column)),
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
      offset: _offsetOf(lines, after + 1 + before.length + row, column),
    ),
  );
}

/// What one string gets of [columns] (each a fret per string, low E to
/// high E, null for a string not played): each column as wide as its
/// widest fret, its fret or dashes, and a dash after it.
String _columnsOn(List<List<int?>> columns, int string) => [
  for (final column in columns)
    '${(column[string]?.toString() ?? '').padRight(column.map((f) => '${f ?? ''}'.length).reduce(math.max), '-')}-',
].join();

/// The dictionary's +: writes [columns] (each a fret per string, low E to
/// high E, null for a string not played: a chord's voicing is one, a
/// scale one per note) into the tab.
///
/// With the cursor on a six-line phrase, on any of its lines, or on the
/// line just above it (its line of names, or a heading), they go in
/// across the phrase, each fret on its own string wherever the cursor
/// is ([_phraseAt]): high E on the first line, or, when the lines' names
/// read `E A D G B e` from the top, low E there. Six-line phrases that
/// touch (twelve string lines, no blank between) are each one. They go
/// in at the cursor's column, pushing the rest of each line right, so the
/// columns stay lined up; but never inside a note (a cursor in `12`, on
/// any line, puts them before it), never run together with the note
/// before them (a dash goes first on every line when one ends there), and
/// never into a line's name or opening bar. A line too short to reach
/// the column is lengthened with dashes before its closing bar. Anywhere
/// else (another line, a phrase of other than six lines, no cursor), they
/// go in a new phrase as [newStaff]'s (at least [newStaffWidth] wide)
/// under the cursor's line or phrase. Either way the cursor ends just
/// after them, on its line (on the phrase's first from the line above
/// it), so the next one written follows them.
///
/// With a [name] (the chord's or the scale's), it goes above the phrase,
/// over the columns' first column ([nameAbove]); the columns are then at
/// least as wide as the name and a space, dashes after them, so the
/// names of chords written one after another don't run together.
TextEditingValue writeColumns(
  TextEditingValue value,
  List<List<int?>> columns, {
  String? name,
}) {
  final strings = _stringNames.length;
  final label = name?.trim() ?? '';
  final wide = columns.isEmpty ? 0 : _columnsOn(columns, 0).length;
  final width = label.isEmpty ? wide : math.max(wide, label.length + 1);
  final lines = value.text.split('\n');
  final phrase = value.selection.isValid && value.text.isNotEmpty
      ? _phraseAt(lines, value.selection.start, strings)
      : null;
  if (phrase != null) {
    final (:first, :row, :column) = phrase;
    final last = first + strings - 1;
    final lowOnTop = _lowOnTop(lines.sublist(first, last + 1));
    // What line k of the phrase gets: its string's frets.
    String on(int k) => _columnsOn(
      columns,
      lowOnTop ? k : strings - 1 - k,
    ).padRight(width, '-');
    // Past the end of the cursor's line (its closing bar), just before
    // its closing bar; never in a line's name or opening bar.
    final line = lines[row].trimRight();
    final end = line.length - _closingBars(line).length;
    var opening = 0;
    for (var k = first; k <= last; k++) {
      opening = math.max(opening, _opening.firstMatch(lines[k])?.end ?? 0);
    }
    var at = math.max(math.min(column, end), opening);
    // Not inside a note on any line: before it.
    bool digit(String line, int i) =>
        i >= 0 && i < line.length && _digits.hasMatch(line[i]);
    for (var moved = true; moved;) {
      moved = false;
      for (var k = first; k <= last; k++) {
        while (at > opening && digit(lines[k], at - 1) && digit(lines[k], at)) {
          at--;
          moved = true;
        }
      }
    }
    // A note ending at the column on any line: a dash first, on every
    // line, so the columns stay lined up.
    final lead =
        [
          for (var k = first; k <= last; k++)
            digit(lines[k].trimRight(), at - 1),
        ].any((d) => d)
        ? '-'
        : '';
    for (var k = first; k <= last; k++) {
      final line = lines[k].trimRight();
      final closing = _closingBars(line);
      var body = line.substring(0, line.length - closing.length);
      if (body.length < at) body = body.padRight(at, '-');
      lines[k] =
          '${body.substring(0, at)}$lead${on(k - first)}'
          '${body.substring(at)}$closing';
    }
    // Over the chord: after the dash put first, if one was.
    final added = label.isEmpty
        ? 0
        : nameAbove(
            lines,
            first,
            at,
            lead.length + width,
            '${' ' * lead.length}$label',
          );
    return TextEditingValue(
      text: lines.join('\n'),
      selection: TextSelection.collapsed(
        offset: _offsetOf(lines, row + added, at + lead.length + width),
      ),
    );
  }
  // A new phrase: line k is string strings - 1 - k (high E on top).
  String on(int k) => _columnsOn(columns, strings - 1 - k).padRight(width, '-');
  final room = math.max(newStaffWidth - 4, width);
  return _addStaff(
    value,
    [
      // The name over the columns, which start after `e|-`.
      if (label.isNotEmpty) '${' ' * 3}$label',
      for (var k = 0; k < strings; k++)
        '${_stringNames[k]}|-${on(k).padRight(room, '-')}|',
    ],
    3 + width,
    row: label.isEmpty ? 0 : 1,
  );
}

final RegExp _digits = RegExp(r'[0-9]');

/// The six-line phrase the dictionary's + writes into with the cursor at
/// [offset] in [lines]: its [first] line, the line the cursor ends on
/// ([row], one of the phrase's) and the cursor's [column]. The cursor on
/// one of its lines, or on the line just above it (a line of names or a
/// heading: not blank, not a string line), whose column then counts on
/// the phrase's first line. String lines that touch, a multiple of
/// [strings] of them, are that many phrases: the cursor's is the one it's
/// in. Null for any other line, or a phrase of other than [strings]
/// lines.
({int first, int row, int column})? _phraseAt(
  List<String> lines,
  int offset,
  int strings,
) {
  var (row, column) = _rowColumn(lines, offset);
  if (!_isStringLine(lines[row])) {
    final below = row + 1;
    if (lines[row].trim().isEmpty ||
        below >= lines.length ||
        !_isStringLine(lines[below])) {
      return null;
    }
    row = below;
  }
  var (first, last) = _staffAround(lines, row);
  final count = last - first + 1;
  if (count % strings != 0) return null;
  first += (row - first) ~/ strings * strings;
  return (first: first, row: row, column: column);
}

/// Whether [phrase]'s lines run low E to high E from the top: their
/// names, where they have them, read `E A D G B E` more than the usual
/// `e B G D A E`.
bool _lowOnTop(List<String> phrase) {
  const high = 'EBGDAE', low = 'EADGBE';
  var highs = 0, lows = 0;
  for (final (k, line) in phrase.indexed) {
    final name = _stringName.firstMatch(line)?.group(1)?.toUpperCase();
    if (name == null || k >= high.length) continue;
    if (name == high[k]) highs++;
    if (name == low[k]) lows++;
  }
  return lows > highs;
}

/// A string line's name, before its opening bar (`e` in `e|--0--|`).
final RegExp _stringName = RegExp(r'^\s*([A-Ga-g])[#b]?\s*\|');

/// Writes [name] above the phrase whose first line is [first], at
/// [column], where [width] characters were just put into each of its
/// lines. The line above takes it when it's a line of names: text, not a
/// string line, with room there ([width] spaces go into it at [column],
/// so the names after stay over their notes, and the name goes in them,
/// clear of the text before it). Otherwise (no line above, a blank one,
/// or text in the way, such as a heading like "Intro") a line of its own
/// goes in above the phrase. Returns how many lines were added (0 or 1).
int nameAbove(
  List<String> lines,
  int first,
  int column,
  int width,
  String name,
) {
  final above = first - 1;
  if (above >= 0) {
    final line = lines[above];
    if (line.trim().isNotEmpty && !_isStringLine(line)) {
      final padded = line.padRight(column);
      // Clear of what's before it: a space, or the line's start.
      if (column == 0 || padded[column - 1] == ' ') {
        lines[above] =
            '${padded.substring(0, column)}${name.padRight(width)}'
                    '${padded.substring(column)}'
                .trimRight();
        return 0;
      }
    }
  }
  lines.insert(first, '${' ' * column}$name');
  return 1;
}

/// Where to break [text] in two for the Text view's two columns: the
/// first column is `text.substring(0, leftEnd)`, the second
/// `text.substring(rightStart)` (the blank lines between them dropped).
/// The break is the line boundary nearest the middle (by lines) that
/// doesn't cut a phrase: after a blank line if there's one, else between
/// two lines that aren't both string lines; only failing both, the middle
/// line. Null when there's nothing to break: fewer than two non-blank
/// lines.
({int leftEnd, int rightStart})? splitInHalf(String text) {
  final lines = text.split('\n');
  if (lines.where((l) => l.trim().isNotEmpty).length < 2) return null;
  // Line i starts at starts[i].
  final starts = <int>[0];
  for (final line in lines) {
    starts.add(starts.last + line.length + 1);
  }
  bool blank(int i) => lines[i].trim().isEmpty;
  // The boundaries b (the second column from line b) with text on both
  // sides.
  final firstText = lines.indexWhere((l) => l.trim().isNotEmpty);
  final lastText = lines.lastIndexWhere((l) => l.trim().isNotEmpty);
  final all = [for (var b = firstText + 1; b <= lastText; b++) b];
  final middle = (firstText + lastText + 1) / 2;
  int? nearest(bool Function(int b) ok) {
    int? best;
    for (final b in all.where(ok)) {
      if (best == null || (b - middle).abs() < (best - middle).abs()) {
        best = b;
      }
    }
    return best;
  }

  var cut =
      nearest((b) => blank(b - 1) && !blank(b)) ??
      nearest((b) => !(isTabLine(lines[b - 1]) && isTabLine(lines[b]))) ??
      middle.floor();
  // The first column ends at its last line with text; the second starts
  // at its first.
  var end = cut;
  while (end > 0 && blank(end - 1)) {
    end--;
  }
  while (cut < lines.length && blank(cut)) {
    cut++;
  }
  return (leftEnd: math.max(0, starts[end] - 1), rightStart: starts[cut]);
}

// Selections: with notes selected, the tools work on them alone.

/// One line's part of a selection: on line [line], the columns from
/// [start] up to [end] (not included).
typedef LineSpan = ({int line, int start, int end});

/// A vertical selection: on each line from [top] to [bottom], the columns
/// from [left] up to [right] (not included). A line too short to reach
/// them has the part of them it reaches, or none.
@immutable
class TextBlock {
  const TextBlock({
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
  });

  /// The block a drag from [selection]'s base to its extent draws in
  /// [text]: the two at opposite corners. One column wide at least: a
  /// drag straight down takes the column right of where it started.
  factory TextBlock.corners(String text, TextSelection selection) {
    final lines = text.split('\n');
    final (r1, c1) = _rowColumn(lines, selection.baseOffset);
    final (r2, c2) = _rowColumn(lines, selection.extentOffset);
    final left = math.min(c1, c2);
    return TextBlock(
      top: math.min(r1, r2),
      bottom: math.max(r1, r2),
      left: left,
      right: math.max(math.max(c1, c2), left + 1),
    );
  }

  /// Lines [top] to [bottom] of [lines], whole: every column the longest
  /// of them has.
  factory TextBlock.whole(List<String> lines, int top, int bottom) => TextBlock(
    top: top,
    bottom: bottom,
    left: 0,
    right: [for (var i = top; i <= bottom; i++) lines[i].length]
        .reduce(math.max),
  );

  final int top;
  final int bottom;
  final int left;
  final int right;

  /// Its part of each of its lines in [lines].
  List<LineSpan> spans(List<String> lines) => [
    for (var i = top; i <= bottom && i < lines.length; i++)
      (
        line: i,
        start: math.min(left, lines[i].length),
        end: math.min(right, lines[i].length),
      ),
  ];

  /// Its characters in [lines], as ranges of the text's offsets: one for
  /// each line that reaches it.
  List<(int, int)> ranges(List<String> lines) {
    final out = <(int, int)>[];
    var at = 0;
    for (var i = 0; i < lines.length && i <= bottom; i++) {
      if (i >= top) {
        final start = math.min(left, lines[i].length);
        final end = math.min(right, lines[i].length);
        if (end > start) out.add((at + start, at + end));
      }
      at += lines[i].length + 1;
    }
    return out;
  }

  /// The text selection standing for it in [lines]: from its top left
  /// corner to its bottom right, each kept within its line.
  TextSelection selectionIn(List<String> lines) {
    final last = math.min(bottom, lines.length - 1);
    final first = math.min(top, last);
    return TextSelection(
      baseOffset: _offsetOf(lines, first, math.min(left, lines[first].length)),
      extentOffset: _offsetOf(lines, last, math.min(right, lines[last].length)),
    );
  }

  TextBlock copyWith({int? top, int? bottom, int? left, int? right}) =>
      TextBlock(
        top: top ?? this.top,
        bottom: bottom ?? this.bottom,
        left: left ?? this.left,
        right: right ?? this.right,
      );

  @override
  bool operator ==(Object other) =>
      other is TextBlock &&
      other.top == top &&
      other.bottom == bottom &&
      other.left == left &&
      other.right == right;

  @override
  int get hashCode => Object.hash(top, bottom, left, right);

  @override
  String toString() => 'TextBlock(lines $top–$bottom, columns $left–$right)';
}

/// The line and column of [offset] in [text].
(int, int) lineColumn(String text, int offset) =>
    _rowColumn(text.split('\n'), offset);

/// The offset of [line]'s [column] in [text], each kept within the text.
int offsetAt(String text, int line, int column) {
  final lines = text.split('\n');
  final row = math.min(line, lines.length - 1);
  return _offsetOf(lines, row, math.min(column, lines[row].length));
}

/// The lines and columns [selection] takes in [text]: its first line from
/// the start's column, the lines in between whole, its last line up to
/// the end's column. A first line it takes nothing of (it starts at the
/// line's end) and a last one (it ends at its start) aren't in it. Empty
/// for a cursor.
List<LineSpan> selectionSpans(String text, TextSelection selection) {
  if (!selection.isValid || selection.isCollapsed) return const [];
  final lines = text.split('\n');
  final (r1, c1) = _rowColumn(lines, selection.start);
  final (r2, c2) = _rowColumn(lines, selection.end);
  final spans = [
    for (var i = r1; i <= r2; i++)
      (line: i, start: i == r1 ? c1 : 0, end: i == r2 ? c2 : lines[i].length),
  ];
  return [
    for (final (k, s) in spans.indexed)
      if (s.end > s.start || (k > 0 && k < spans.length - 1)) s,
  ];
}

/// What [spans] take of [lines], a line each: a vertical selection's text.
String spansText(List<String> lines, List<LineSpan> spans) =>
    spans.map((s) => lines[s.line].substring(s.start, s.end)).join('\n');

/// Why the tools couldn't change a selection's notes.
enum SelectionFailure {
  /// No fret number on the selection's string lines.
  noNotes,

  /// + or − would take one of them below 0 or past 99.
  outOfRange,

  /// ++ or −−: one of them had no string with room for it.
  noRoom,
}

/// The fret numbers (one or two digits) that [spans] take, whole or in
/// part, on the string lines of [lines] ([tabLines]: only lines with
/// dashes, [isTabLine]), each as its line and columns; left to right on
/// each line, the lines top to bottom.
List<LineSpan> _notesIn(
  List<String> lines,
  List<LineSpan> spans, {
  bool tabLines = false,
}) => [
  for (final s in spans)
    if (tabLines ? isTabLine(lines[s.line]) : _isStringLine(lines[s.line]))
      for (final m in RegExp(r'\d+').allMatches(lines[s.line]))
        if (m.end - m.start <= 2 && m.start < s.end && m.end > s.start)
          (line: s.line, start: m.start, end: m.end),
];

/// + and − on a selection ([spans]): every fret number on its string
/// lines, whole or in part, goes up or down by one, keeping the columns
/// lined up as [bumpNumber] does. They change together: none does when
/// there's none, or when one would go below 0 or past 99 (so a riff keeps
/// its shape), and [failure] says which.
({String? text, SelectionFailure? failure}) bumpSelected(
  String text,
  List<LineSpan> spans,
  int delta,
) {
  final lines = text.split('\n');
  final notes = _notesIn(lines, spans);
  if (notes.isEmpty) return (text: null, failure: SelectionFailure.noNotes);
  int fret(LineSpan n) =>
      int.parse(lines[n.line].substring(n.start, n.end)) + delta;
  if (notes.any((n) => fret(n) < 0 || fret(n) > 99)) {
    return (text: null, failure: SelectionFailure.outOfRange);
  }
  // From the right, so one that grows doesn't move those still to change.
  for (final n in notes.reversed) {
    lines[n.line] = _put(lines[n.line], n.start, n.end - n.start, '${fret(n)}');
  }
  return (text: lines.join('\n'), failure: null);
}

/// ++ and −− on a selection ([spans]): every fret number on its string
/// lines, whole or in part, moves to the string above ([delta] −1) or
/// below (+1), in the same column, cycling within its phrase, as
/// [moveNote] moves one: a string whose spot holds a note that isn't
/// moving is skipped. They move together: none does when one has no
/// string with room for it, or when there's none, and [failure] says
/// which. [rows] are the lines they went to.
({String? text, List<int>? rows, SelectionFailure? failure}) moveSelected(
  String text,
  List<LineSpan> spans,
  int delta,
) {
  final lines = text.split('\n');
  final notes = _notesIn(lines, spans, tabLines: true);
  if (notes.isEmpty) {
    return (text: null, rows: null, failure: SelectionFailure.noNotes);
  }
  // All of them lifted first, dashes in their place, so none stands in
  // another's way; then each put down, those ahead first.
  final lifted = [
    for (final n in notes) (n, lines[n.line].substring(n.start, n.end)),
  ];
  for (final (n, _) in lifted) {
    lines[n.line] = _put(lines[n.line], n.start, n.end - n.start, '');
  }
  lifted.sort(
    (a, b) => delta < 0
        ? a.$1.line.compareTo(b.$1.line)
        : b.$1.line.compareTo(a.$1.line),
  );
  final rows = <int>[];
  for (final (n, note) in lifted) {
    final (first, last) = _staffAround(lines, n.line);
    final strings = last - first + 1;
    bool free(String line) {
      for (var i = n.start; i < n.end; i++) {
        if (i < line.length && line[i] != '-') return false;
      }
      return true;
    }

    int? to;
    for (var step = 1; step < strings && to == null; step++) {
      final row = first + (n.line - first + delta * step) % strings;
      if (free(lines[row])) to = row;
    }
    if (to == null) {
      return (text: null, rows: null, failure: SelectionFailure.noRoom);
    }
    // A short string line is lengthened with dashes to reach the column.
    lines[to] = lines[to]
        .padRight(n.end, '-')
        .replaceRange(n.start, n.end, note);
    rows.add(to);
  }
  return (text: lines.join('\n'), rows: rows, failure: null);
}

/// | on a selection: a bar into each string line among [rows] (the
/// selection's lines), at [column] (its first column), as [insertBar]
/// puts one into each string of a phrase; the other lines as they were.
/// Null when none of [rows] is a string line.
String? barOnLines(String text, Iterable<int> rows, int column) {
  final lines = text.split('\n');
  final strings = [
    for (final r in rows)
      if (r < lines.length && _isStringLine(lines[r])) r,
  ];
  if (strings.isEmpty) return null;
  _barInto(lines, strings, column);
  return lines.join('\n');
}

/// = on a selection: a dash into each line of a phrase among [rows] (the
/// selection's lines), at [column] (its first column), as [insertSpacer]
/// puts one down a phrase; the other lines as they were. Null when none of
/// [rows] is a phrase's line.
String? spacerOnLines(String text, Iterable<int> rows, int column) {
  final lines = text.split('\n');
  final strings = [
    for (final r in rows)
      if (r < lines.length && _isStringLine(lines[r])) r,
  ];
  if (strings.isEmpty) return null;
  _spacerInto(lines, strings, column);
  return lines.join('\n');
}

/// The phrases lines [top] to [bottom] of [lines] reach, whole: from the
/// first line of the phrase of the first string line among them to the
/// last line of the phrase of the last. Null when none is a string line.
({int top, int bottom})? phrasesAround(
  List<String> lines,
  int top,
  int bottom,
) {
  int? first, last;
  for (var i = math.max(top, 0); i <= bottom && i < lines.length; i++) {
    if (_isStringLine(lines[i])) {
      first ??= i;
      last = i;
    }
  }
  if (first == null || last == null) return null;
  return (
    top: _staffAround(lines, first).$1,
    bottom: _staffAround(lines, last).$2,
  );
}

/// The first phrase below line [row] of [lines], or null.
({int top, int bottom})? phraseBelow(List<String> lines, int row) {
  for (var i = row + 1; i < lines.length; i++) {
    if (_isStringLine(lines[i])) {
      final (first, last) = _staffAround(lines, i);
      return (top: first, bottom: last);
    }
  }
  return null;
}

/// The last phrase above line [row] of [lines], or null.
({int top, int bottom})? phraseAbove(List<String> lines, int row) {
  for (var i = math.min(row, lines.length) - 1; i >= 0; i--) {
    if (_isStringLine(lines[i])) {
      final (first, last) = _staffAround(lines, i);
      return (top: first, bottom: last);
    }
  }
  return null;
}

/// Typing, pasting or deleting over a vertical selection ([block]): what's
/// [typed] ('' to delete) goes on each of its lines in place of its
/// columns, a line of it on each when it has several lines, else the same
/// on all. With [overtype] the columns stay put: a shorter text is padded
/// with dashes on a string line (spaces elsewhere), a longer one takes the
/// dashes after it ([_put]); without, the rest of each line closes up or
/// moves right. A line too short to reach the block is filled out to it,
/// when there's something to put on it. Returns the text, and the cursor:
/// after what went on the block's first line.
({String text, int cursor}) replaceBlock(
  String text,
  TextBlock block, {
  required String typed,
  required bool overtype,
}) {
  final lines = text.split('\n');
  final pieces = typed.split('\n');
  for (var i = block.top; i <= block.bottom && i < lines.length; i++) {
    final k = i - block.top;
    final piece = pieces.length == 1
        ? pieces.single
        : (k < pieces.length ? pieces[k] : '');
    var line = lines[i];
    if (line.length < block.left) {
      if (piece.isEmpty) continue;
      line = line.padRight(block.left, _filler(line));
    }
    final end = math.min(block.right, line.length);
    lines[i] = overtype
        ? _put(line, block.left, end - block.left, piece)
        : line.replaceRange(block.left, end, piece);
  }
  final top = math.min(block.top, lines.length - 1);
  return (
    text: lines.join('\n'),
    cursor: _offsetOf(
      lines,
      top,
      math.min(block.left + pieces.first.length, lines[top].length),
    ),
  );
}

/// Typing over a vertical selection: what's typed, pasted or deleted goes
/// on every line of the [block] ([replaceBlock]), instead of in place of
/// the text from its first corner to its last (the field's own selection,
/// which stands for it).
class BlockFormatter extends TextInputFormatter {
  BlockFormatter(this.block, {required this.overtype});

  /// The vertical selection, or null (none: typing as usual).
  final TextBlock? Function() block;
  final bool Function() overtype;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final selected = block();
    final s = oldValue.selection;
    if (selected == null || !s.isValid || s.isCollapsed) return newValue;
    final (old, now) = (oldValue.text, newValue.text);
    final before = old.substring(0, s.start);
    final after = old.substring(s.end);
    final typedLength = now.length - before.length - after.length;
    // Only the selection replaced: by what's typed, or nothing.
    if (typedLength < 0 || !now.startsWith(before) || !now.endsWith(after)) {
      return newValue;
    }
    final (:text, :cursor) = replaceBlock(
      old,
      selected,
      typed: now.substring(s.start, s.start + typedLength),
      overtype: overtype(),
    );
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }
}

/// The Text view's column ruler for [columns] columns, one character
/// each, counted from 1: every fifth column numbered, the number's last
/// figure on its column (`····5···10···15`), a dot on each of the others.
String columnRuler(int columns) {
  if (columns <= 0) return '';
  final chars = List.filled(columns, '·');
  for (var c = 5; c <= columns; c += 5) {
    final n = '$c';
    chars.setRange(c - n.length, c, n.split(''));
  }
  return chars.join();
}

/// The column the cursor is on in [value] (from 0, on its line: the
/// character it's before, which overtype would replace); null with no
/// cursor, or a selection.
int? cursorColumn(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid || !selection.isCollapsed) return null;
  final at = selection.baseOffset.clamp(0, value.text.length);
  return at == 0 ? 0 : at - (value.text.lastIndexOf('\n', at - 1) + 1);
}
