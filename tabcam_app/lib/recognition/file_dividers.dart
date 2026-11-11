/// The dividing lines a text tab read from several files has: one at the
/// start of each file's part, with the file's name, so the reader sees
/// where one file's tab ends and the next one's begins:
///
/// ```
/// ―― sheet-1.pdf ―――――――――――――――――――――――――
/// e|---0---3---|
/// ...
///
/// ―― Page 2 ――――――――――――――――――――――――――――――
/// G|-2---2b4r2-|
/// ```
///
/// Drawn with `―` (U+2015, the horizontal bar, in the tab's font), which
/// nothing reads as tab: not a dash to the string lines' test
/// ([isTabLine]), Fix, OCR's slips or the cloud's auto-correct. Every
/// reader of the text tab treats a divider as a line of text, never as
/// tab ([isFileDivider]).
library;

/// The character a divider is drawn with.
const String dividerBar = '―';

/// A divider's least width, in characters, its name included: a short
/// name's line is filled out to it with [dividerBar]s.
const int dividerWidth = 40;

/// The longest name a divider shows: a longer one is cut, ending in `…`.
const int dividerNameMax = 60;

/// The divider before the part of the text read from the file called
/// [name] (its name in the capture's list): `―― name ――――…`, at least
/// [dividerWidth] long. The name on one line, its spaces collapsed, cut
/// to [dividerNameMax] characters.
String fileDivider(String name) {
  var shown = name
      .replaceAll(RegExp(r'[\x00-\x1f\x7f  ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (shown.runes.length > dividerNameMax) {
    shown =
        '${String.fromCharCodes(shown.runes.take(dividerNameMax - 1)).trimRight()}…';
  }
  final head = shown.isEmpty ? '$dividerBar$dividerBar' : '―― $shown';
  final fill = dividerWidth - head.runes.length - 1;
  return '$head ${dividerBar * (fill < 2 ? 2 : fill)}';
}

final RegExp _divider = RegExp(
  '^\\s*$dividerBar$dividerBar.*$dividerBar\\s*\$',
);

/// Whether [line] is a file's divider ([fileDivider]): text, never tab.
bool isFileDivider(String line) => _divider.hasMatch(line);

/// The texts read from a capture's files ([parts], each its file's name
/// and text, in the files' order) as one text tab: joined by a blank line,
/// and, when there are two or more, each after its file's divider (the
/// first too). With one, its text alone. Also where each part's text
/// starts ([tops], its first line's index), for what's kept by line (the
/// cloud's doubtful notes).
({String text, List<int> tops}) joinFileTexts(
  List<({String name, String text})> parts,
) {
  final divided = parts.length > 1;
  final out = <String>[];
  final tops = <int>[];
  var line = 0;
  for (final part in parts) {
    final text = part.text;
    if (divided) {
      out.add(fileDivider(part.name));
      line++;
    }
    tops.add(line);
    out.add(text);
    // Its lines, then the blank line before the next part.
    line += '\n'.allMatches(text).length + 2;
    out.add('');
  }
  if (out.isNotEmpty) out.removeLast();
  return (text: out.join('\n'), tops: tops);
}
