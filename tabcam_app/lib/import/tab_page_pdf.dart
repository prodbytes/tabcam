import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart' show PdfColors, PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;

import 'tab_page.dart';

/// [page] printed as a PDF, as a browser prints a page: the title, then the
/// tab's text in a monospace font (columns stay lined up), over as many A4
/// pages as it takes, with the address and the date at the foot of each.
/// PDF readers then read it as any PDF with text ([PdfTabReader]).
Future<Uint8List> tabPagePdf(TabPage page, {DateTime? printed}) {
  final lines = page.text.split('\n').map(_latin1).toList();
  const format = PdfPageFormat.a4;
  const margin = 36.0;
  // Courier is 0.6 em wide: the longest line fits the page, 9 pt at most.
  final widest = lines.fold(1, (w, l) => math.max(w, l.length));
  final size = math.max(
    4.0,
    math.min(9.0, (format.width - 2 * margin) / (0.6 * widest)),
  );
  final mono = pw.TextStyle(font: pw.Font.courier(), fontSize: size);
  final small = pw.TextStyle(
    font: pw.Font.helvetica(),
    fontSize: 7,
    color: PdfColors.grey700,
  );
  final day = (printed ?? DateTime.now()).toIso8601String().substring(0, 10);
  final doc = pw.Document(title: page.title, creator: 'TabCam')
    ..addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(margin),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(_latin1(page.url.toString()), style: small),
            ),
            pw.Text(
              '$day  ${context.pageNumber}/${context.pagesCount}',
              style: small,
            ),
          ],
        ),
        build: (_) => [
          if (page.title.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 12),
              child: pw.Text(
                _latin1(page.title),
                style: pw.TextStyle(
                  font: pw.Font.helveticaBold(),
                  fontSize: 14,
                ),
              ),
            ),
          // A blank line keeps its height: it parts staves.
          for (final line in lines)
            line.isEmpty
                ? pw.SizedBox(height: size * 1.2)
                : pw.Text(line, style: mono, softWrap: false),
        ],
      ),
    );
  return doc.save();
}

/// [text] in the PDF's standard fonts' characters (Latin-1): typographic
/// quotes and dashes as plain ones, anything else as `?`.
String _latin1(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    out.write(switch (rune) {
      < 0x100 => String.fromCharCode(rune),
      0x2018 || 0x2019 || 0x2032 => "'",
      0x201C || 0x201D || 0x2033 => '"',
      0x2013 || 0x2014 || 0x2212 => '-',
      0x2026 => '...',
      0x266D => 'b',
      0x266F => '#',
      _ => '?',
    });
  }
  return '$out';
}
