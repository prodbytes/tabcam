import '../screens/tab_editing.dart';
import 'file_dividers.dart';

/// A text tab cut into necklines, the way the camera view shows it: one
/// staff (a run of string lines) at a time, with the lines right above it
/// (chord names, a section name). Text that isn't over a staff (lyrics
/// after it, notes at the end) is left out. A tab with no string lines at
/// all (chords only) is cut at its blank lines instead. A file's divider
/// ([isFileDivider], in a text read from several files) is in none: it
/// ends a staff, as a blank line does, and heads nothing.
List<String> necklines(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final necklines = <String>[];
  final header = <String>[];
  final staff = <String>[];
  void close() {
    if (staff.isNotEmpty) necklines.add([...header, ...staff].join('\n'));
    header.clear();
    staff.clear();
  }

  for (final line in lines) {
    if (line.trim().isEmpty || isFileDivider(line)) {
      close();
    } else if (isTabLine(line)) {
      staff.add(line.trimRight());
    } else {
      // Text after a staff ends it, and heads the next one.
      if (staff.isNotEmpty) close();
      header.add(line.trimRight());
    }
  }
  close();
  if (necklines.isNotEmpty) return necklines;
  // A divider parts blocks as a blank line does.
  final undivided = [for (final line in lines) isFileDivider(line) ? '' : line]
      .join('\n');
  return [
    for (final block in undivided.split(RegExp(r'\n\s*\n')))
      if (block.trim().isNotEmpty)
        block.trimRight().replaceFirst(RegExp(r'^\s*\n'), ''),
  ];
}
