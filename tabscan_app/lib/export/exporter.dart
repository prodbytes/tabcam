import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../library/capture_event.dart';
import '../processing/page_filter.dart';
import 'capture_link.dart';

/// What an event can be shared as.
enum ShareFormat {
  /// The capture's link ([CaptureLink]): it opens in TabScan for its owner
  /// and the people it's shared with. The default.
  link('Link'),

  /// Every image page (filtered) in one PDF, then the text tab if it was
  /// read, then the links. Videos, and images the owner hid
  /// ([CaptureEvent.hideImages]), are left out.
  pdf('PDF'),

  /// The text tab and the links, as plain text: pastes anywhere.
  text('Text'),

  /// One zip of everything: each image (filtered) and video, the text tab
  /// (`tab.txt`) and the links (`links.txt`); images the owner hid are
  /// left out.
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
    final links = event.pages.where((p) => p.isLink).toList();
    if (links.isNotEmpty) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(36),
          build: (_) => [
            pw.Header(level: 1, text: 'Links'),
            for (final link in links)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.UrlLink(
                  destination: link.url.toString(),
                  child: pw.Text(
                    linkLine(link),
                    style: const pw.TextStyle(color: PdfColors.blue800),
                  ),
                ),
              ),
          ],
        ),
      );
    }
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
      case ShareFormat.link:
        await SharePlus.instance.share(
          ShareParams(
            text: CaptureLink.of(event).toString(),
            subject: event.title,
          ),
        );
      case ShareFormat.text:
        await SharePlus.instance.share(
          ShareParams(text: shareText(event), subject: event.title),
        );
      case ShareFormat.pdf:
        final pages = [
          for (final p in event.visiblePages)
            if (p.isImage) await filteredPage(p),
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
        final bytes = await zip(event, [
          for (final p in event.visiblePages)
            if (p.hasFile) await filteredPage(p),
        ]);
        await SharePlus.instance.share(
          ShareParams(
            subject: event.title,
            files: [XFile.fromData(bytes, mimeType: 'application/zip')],
            fileNameOverrides: ['$name.zip'],
          ),
        );
    }
    debugPrint('Shared ${event.id} as ${format.name}');
  }

  /// Files: a zip of [files], the event's visible image and video pages'
  /// bytes in page order (images filtered), named as
  /// `<name> <n>.<extension>`; then
  /// `tab.txt` (the text tab) and `links.txt` (a link per line), when
  /// there are any. Pictures and videos are stored as they are: they're
  /// compressed already.
  static Future<Uint8List> zip(CaptureEvent event, List<Uint8List> files) =>
      compute(_zip, (event, files));

  static Uint8List _zip((CaptureEvent, List<Uint8List>) args) {
    final (event, files) = args;
    final name = event.fileName;
    final archive = Archive();
    for (final (i, page)
        in event.visiblePages.where((p) => p.hasFile).indexed) {
      final (extension, _) = _type(page);
      final bytes = files[i];
      archive.add(
        ArchiveFile.noCompress(
          '$name ${i + 1}.$extension',
          bytes.length,
          bytes,
        ),
      );
    }
    final tab = event.tabText?.trimRight();
    if (tab != null && tab.isNotEmpty) {
      archive.add(ArchiveFile.string('tab.txt', '$tab\n'));
    }
    final links = [
      for (final p in event.pages)
        if (p.isLink) linkLine(p),
    ];
    if (links.isNotEmpty) {
      archive.add(ArchiveFile.string('links.txt', '${links.join('\n')}\n'));
    }
    return ZipEncoder().encodeBytes(archive);
  }

  /// What Text shares: the text tab, then each link on a line; null when
  /// there's neither.
  static String? shareText(CaptureEvent event) {
    final links = [
      for (final p in event.pages)
        if (p.isLink) linkLine(p),
    ];
    final tab = event.tabText?.trimRight();
    final parts = [
      if (tab != null && tab.isNotEmpty) tab,
      if (links.isNotEmpty) links.join('\n'),
    ];
    return parts.isEmpty ? null : parts.join('\n\n');
  }

  /// A link as a line of text: "Lesson: https://…", or the address.
  static String linkLine(EventPage link) =>
      link.title == null ? '${link.url}' : '${link.title}: ${link.url}';

  /// A shared page's extension and MIME type: PNG for an image with the
  /// Tab filter, otherwise the page's own.
  static (String, String) _type(EventPage page) {
    if (page.isImage && page.filter != PageFilter.original) {
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
