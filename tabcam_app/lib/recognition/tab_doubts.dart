/// A note a read wasn't sure of: likely wrong, shown in red in the Text
/// view for the user to check against the page. Where it is in the text
/// tab ([line] and [column], from 0) and what was read there ([note]).
class TabDoubt {
  const TabDoubt(this.line, this.column, this.note);

  final int line;
  final int column;
  final String note;

  /// As saved: `[line, column, note]`.
  List<Object> toJson() => [line, column, note];

  /// From [toJson]'s form; null for anything else.
  static TabDoubt? fromJson(Object? json) {
    if (json case [final int line, final int column, final String note]
        when line >= 0 && column >= 0 && note.isNotEmpty) {
      return TabDoubt(line, column, note);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is TabDoubt &&
      other.line == line &&
      other.column == column &&
      other.note == note;

  @override
  int get hashCode => Object.hash(line, column, note);
}

/// Where in [text] the [doubts] still stand, as (start, end) offsets: only
/// those whose note is still where it was read. A note the user changed
/// (fixed) or moved isn't doubtful any more.
List<(int, int)> doubtRanges(String text, Iterable<TabDoubt> doubts) {
  final starts = _lineStarts(text);
  final out = [for (final d in doubts) ?_rangeOf(text, starts, d)];
  out.sort((a, b) => a.$1.compareTo(b.$1));
  return out;
}

/// The standing doubt (doubtRanges) the cursor at [offset] is on: inside
/// its note, or right beside it (a character to its left or right, on its
/// line). The nearest when two are that close; null when none is.
TabDoubt? doubtAt(String text, Iterable<TabDoubt> doubts, int offset) {
  final starts = _lineStarts(text);
  TabDoubt? found;
  var distance = 2;
  for (final d in doubts) {
    final range = _rangeOf(text, starts, d);
    if (range == null) continue;
    final (start, end) = range;
    // Not across the line's start or end.
    final lineStart = starts[d.line];
    final lineEnd = d.line + 1 < starts.length
        ? starts[d.line + 1] - 1
        : text.length;
    if (offset < lineStart || offset > lineEnd) continue;
    final away = offset < start
        ? start - offset
        : offset > end
        ? offset - end
        : 0;
    if (away < distance) {
      found = d;
      distance = away;
    }
  }
  return found;
}

/// Where each of [text]'s lines starts.
List<int> _lineStarts(String text) {
  final starts = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0a) starts.add(i + 1);
  }
  return starts;
}

/// Where [d] is in [text] (its lines starting at [starts]), if it still
/// stands: its note where it was read, whole.
(int, int)? _rangeOf(String text, List<int> starts, TabDoubt d) {
  if (d.line >= starts.length) return null;
  final lineEnd = d.line + 1 < starts.length
      ? starts[d.line + 1] - 1
      : text.length;
  final start = starts[d.line] + d.column;
  final end = start + d.note.length;
  if (end > lineEnd || text.substring(start, end) != d.note) return null;
  // The whole note: not a part of a longer one ("1" of a "12").
  bool note(int i) {
    final c = text[i];
    return c != '-' && c != '|' && c != ' ' && c != '\n';
  }

  if (start > starts[d.line] && note(start - 1)) return null;
  if (end < lineEnd && note(end)) return null;
  return (start, end);
}

/// The [doubts] that still stand in [text] (doubtRanges).
List<TabDoubt> standingDoubts(String text, List<TabDoubt> doubts) {
  if (doubts.isEmpty) return doubts;
  final ranges = doubtRanges(text, doubts).toSet();
  final starts = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0a) starts.add(i + 1);
  }
  return [
    for (final d in doubts)
      if (d.line < starts.length &&
          ranges.contains((
            starts[d.line] + d.column,
            starts[d.line] + d.column + d.note.length,
          )))
        d,
  ];
}
