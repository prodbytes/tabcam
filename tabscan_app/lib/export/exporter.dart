import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../library/capture_event.dart';
import '../processing/page_filter.dart';

/// What an event can be shared as.
enum ShareFormat {
  /// Every image page (filtered) in one PDF, then the text tab if it was
  /// read. Videos are left out.
  pdf('PDF'),

  /// The text tab, as plain text: pastes anywhere, monospaced.
  text('Text tab'),

  /// Each page as a file: images filtered, videos as they are.
  files('Files');

  const ShareFormat(this.label);
  final String label;
}

abstract final class Exporter {
  /// The event as a PDF: a page per scanned page, fitted to A4, then the
  /// text tab in Courier.
  static Future<Uint8List> pdf(
    CaptureEvent event,
    List<Uint8List> filteredPages,
  ) {
    final doc = pw.Document(
      title: event.title,
      author: event.artist.isEmpty ? null : event.artist,
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
    final text = event.tabText;
    if (text != null && text.trim().isNotEmpty) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(36),
          build: (_) => [
            pw.Header(level: 1, text: event.title),
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

  /// Opens the system's share sheet with the event in [format].
  static Future<void> share(
    CaptureEvent event,
    ShareFormat format,
    Future<Uint8List> Function(EventPage page) filteredPage,
  ) async {
    final name = event.fileName;
    switch (format) {
      case ShareFormat.text:
        await SharePlus.instance.share(
          ShareParams(text: event.tabText ?? '', subject: event.title),
        );
      case ShareFormat.pdf:
        final pages = [
          for (final p in event.pages)
            if (!p.isVideo) await filteredPage(p),
        ];
        final bytes = await pdf(event, pages);
        await SharePlus.instance.share(
          ShareParams(
            subject: event.title,
            files: [XFile.fromData(bytes, mimeType: 'application/pdf')],
            fileNameOverrides: ['$name.pdf'],
          ),
        );
      case ShareFormat.files:
        final files = <XFile>[];
        final names = <String>[];
        for (final (i, page) in event.pages.indexed) {
          final (extension, mime) = _type(page);
          files.add(XFile.fromData(await filteredPage(page), mimeType: mime));
          names.add('$name ${i + 1}.$extension');
        }
        await SharePlus.instance.share(
          ShareParams(
            subject: event.title,
            files: files,
            fileNameOverrides: names,
          ),
        );
    }
    debugPrint('Shared ${event.id} as ${format.name}');
  }

  /// A shared page's extension and MIME type: PNG for an image with the
  /// Tab filter, otherwise the page's own.
  static (String, String) _type(EventPage page) {
    if (!page.isVideo && page.filter != PageFilter.original) {
      return ('png', 'image/png');
    }
    final extension = page.extension == 'img' ? 'jpg' : page.extension;
    return (
      extension,
      switch (extension) {
        'png' => 'image/png',
        'heic' || 'heif' => 'image/heic',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        'mov' => 'video/quicktime',
        'webm' => 'video/webm',
        '3gp' => 'video/3gpp',
        'mp4' || 'm4v' => 'video/mp4',
        _ => 'image/jpeg',
      },
    );
  }
}
