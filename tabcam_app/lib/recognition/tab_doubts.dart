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
  final starts = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0a) starts.add(i + 1);
  }
  final out = <(int, int)>[];
  for (final d in doubts) {
    if (d.line >= starts.length) continue;
    final lineEnd = d.line + 1 < starts.length
        ? starts[d.line + 1] - 1
        : text.length;
    final start = starts[d.line] + d.column;
    final end = start + d.note.length;
    if (end > lineEnd || text.substring(start, end) != d.note) continue;
    // The whole note: not a part of a longer one ("1" of a "12").
    bool note(int i) {
      final c = text[i];
      return c != '-' && c != '|' && c != ' ' && c != '\n';
    }

    if (start > starts[d.line] && note(start - 1)) continue;
    if (end < lineEnd && note(end)) continue;
    out.add((start, end));
  }
  out.sort((a, b) => a.$1.compareTo(b.$1));
  return out;
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
