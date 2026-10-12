import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

import 'pdf_lines.dart';
import 'tab_layout.dart';

export 'pdf_lines.dart';

/// Reads a PDF's tab: from its text where it has one (a tab printed from
/// a website, or typeset), page by page; else, a scanned PDF, its pages as
/// images, read by [ocr] (the device's OCR, where there is one). Null when
/// no page has tab.
abstract final class PdfTabReader {
  /// The longest side a scanned page is rendered at, for OCR.
  static const int renderSize = 2400;

  static Future<String?> read(
    Uint8List pdf, {
    Future<String?> Function(List<Uint8List> pages)? ocr,
  }) async {
    await pdfrxFlutterInitialize();
    final doc = await PdfDocument.openData(pdf);
    try {
      final found = <String>[];
      for (final page in doc.pages) {
        final raw = await page.loadText();
        if (raw == null || raw.fullText.trim().isEmpty) continue;
        final boxes = [
          for (final r in raw.charRects)
            (left: r.left, top: r.top, right: r.right, bottom: r.bottom),
        ];
        final tab = asciiTab(pdfLines(raw.fullText, boxes));
        if (tab != null) found.add(tab);
      }
      _log('${doc.pages.length} pages, ${found.length} with tab in their text');
      if (found.isNotEmpty) return found.join('\n\n');
      if (ocr == null) return null;
      final images = <Uint8List>[
        for (final page in doc.pages) ?await _render(page),
      ];
      _log('no tab in the text: ${images.length} pages rendered for OCR');
      return images.isEmpty ? null : await ocr(images);
    } finally {
      await doc.dispose();
    }
  }

  static Future<Uint8List?> _render(PdfPage page) async {
    final scale =
        renderSize / (page.width > page.height ? page.width : page.height);
    final width = (page.width * scale).round();
    final height = (page.height * scale).round();
    final image = await page.render(
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
      backgroundColor: 0xffffffff,
    );
    if (image == null) return null;
    try {
      final picture = img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: image.pixels.buffer,
        numChannels: 4,
        order: img.ChannelOrder.bgra,
      );
      return img.encodePng(picture);
    } finally {
      image.dispose();
    }
  }

  static void _log(String message) =>
      debugPrint('TabScan: read tab: PDF: $message');
}
