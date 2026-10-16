import 'tab_layout.dart';

/// A character's box on a PDF page, in PDF points (y grows upwards).
typedef CharBox = ({double left, double top, double right, double bottom});

/// A PDF page's text as OCR-like lines, top to bottom: each line's text,
/// box and words (with where they start), so [asciiTab] lays them out as
/// it does a photo's (tab lines, chord names at their columns, lyrics).
/// [boxes] has one box per character of [text].
List<OcrLine> pdfLines(String text, List<CharBox> boxes) {
  final lines = <OcrLine>[];
  var start = 0;
  void close(int end) {
    final chars = <int>[
      for (var i = start; i < end; i++)
        if (i < boxes.length && text[i] != '\r') i,
    ];
    final line = text.substring(start, end).replaceAll('\r', '');
    start = end + 1;
    if (line.trim().isEmpty || chars.isEmpty) return;
    final visible = [
      for (final i in chars)
        if (text[i].trim().isNotEmpty) i,
    ];
    if (visible.isEmpty) return;
    // Image-like coordinates: y grows downwards.
    final words = <OcrWord>[];
    var word = StringBuffer();
    double? left;
    for (final i in chars) {
      if (text[i].trim().isEmpty) {
        if (word.isNotEmpty) words.add(OcrWord('$word', left!));
        word = StringBuffer();
        left = null;
      } else {
        left ??= boxes[i].left;
        word.write(text[i]);
      }
    }
    if (word.isNotEmpty) words.add(OcrWord('$word', left!));
    lines.add(
      OcrLine(
        line.trimRight(),
        words: words,
        left: boxes[visible.first].left,
        right: boxes[visible.last].right,
        top: -visible.map((i) => boxes[i].top).reduce((a, b) => a > b ? a : b),
        bottom: -visible
            .map((i) => boxes[i].bottom)
            .reduce((a, b) => a < b ? a : b),
      ),
    );
  }

  for (var i = 0; i < text.length; i++) {
    if (text[i] == '\n') close(i);
  }
  close(text.length);
  return lines..sort((a, b) => a.y.compareTo(b.y));
}
