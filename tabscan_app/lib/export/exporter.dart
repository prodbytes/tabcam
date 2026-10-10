import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../library/scan.dart';
import '../processing/page_filter.dart';

/// What a scan can be shared as.
enum ShareFormat {
  /// Every page (filtered) in one PDF, then the text tab if it was read.
  pdf('PDF'),

  /// The text tab, as plain text: pastes anywhere, monospaced.
  text('Text tab'),

  /// Each page (filtered) as an image.
  images('Images');

  const ShareFormat(this.label);
  final String label;
}

abstract final class Exporter {
  /// The scan as a PDF: a page per scanned page, fitted to A4, then the
  /// text tab in Courier.
  static Future<Uint8List> pdf(Scan scan, List<Uint8List> filteredPages) {
    final doc = pw.Document(
      title: scan.title,
      author: scan.artist.isEmpty ? null : scan.artist,
      creator: 'TabScan',
    );
    for (final bytes in filteredPages) {
      final image = pw.MemoryImage(bytes);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(18),
          build: (_) =>
              pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
    }
    final text = scan.tabText;
    if (text != null && text.trim().isNotEmpty) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(36),
          build: (_) => [
            pw.Header(level: 1, text: scan.title),
            for (final line in text.split('\n'))
              pw.Text(
                line.isEmpty ? ' ' : line,
                style: pw.TextStyle(font: pw.Font.courier(), fontSize: 9),
              ),
          ],
        ),
      );
    }
    return doc.save();
  }

  /// Opens the system's share sheet with the scan in [format].
  static Future<void> share(
    Scan scan,
    ShareFormat format,
    Future<Uint8List> Function(ScanPage page) filteredPage,
  ) async {
    final name = scan.fileName;
    switch (format) {
      case ShareFormat.text:
        await SharePlus.instance.share(
          ShareParams(text: scan.tabText ?? '', subject: scan.title),
        );
      case ShareFormat.pdf:
        final pages = [for (final p in scan.pages) await filteredPage(p)];
        final bytes = await pdf(scan, pages);
        await SharePlus.instance.share(
          ShareParams(
            subject: scan.title,
            files: [XFile.fromData(bytes, mimeType: 'application/pdf')],
            fileNameOverrides: ['$name.pdf'],
          ),
        );
      case ShareFormat.images:
        final files = <XFile>[];
        final names = <String>[];
        for (final (i, page) in scan.pages.indexed) {
          final png = page.filter != PageFilter.original;
          files.add(
            XFile.fromData(
              await filteredPage(page),
              mimeType: png ? 'image/png' : 'image/jpeg',
            ),
          );
          names.add('$name ${i + 1}.${png ? 'png' : 'jpg'}');
        }
        await SharePlus.instance.share(
          ShareParams(
            subject: scan.title,
            files: files,
            fileNameOverrides: names,
          ),
        );
    }
    debugPrint('Shared ${scan.id} as ${format.name}');
  }
}
