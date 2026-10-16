import '../screens/tab_editing.dart';

/// A text tab cut into necklines, the way the camera view shows it: one
/// staff (a run of string lines) at a time, with the lines right above it
/// (chord names, a section name). Text that isn't over a staff (lyrics
/// after it, notes at the end) is left out. A tab with no string lines at
/// all (chords only) is cut at its blank lines instead.
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
    if (line.trim().isEmpty) {
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
  return [
    for (final block in text.split(RegExp(r'\n\s*\n')))
      if (block.trim().isNotEmpty) block.trimRight(),
  ];
}
