import 'package:flutter/services.dart';

import '../cloud/ocr_api.dart';

/// Edits to a text tab that keep its columns lined up: overtype, + and −
/// on a fret, and auto-correct's corrections.

/// A string line: dashes are what's between its notes.
bool isTabLine(String line) => '-'.allMatches(line).length >= 3;

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
