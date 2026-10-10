import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../processing/page_filter.dart';
import 'tab_layout.dart';

/// Reads tablature from page photos with Google ML Kit's on-device text
/// recognition (Android and iOS only), then lays it out as plain text
/// (tab_layout.dart).
class TabReader {
  /// Whether this platform can read tabs: ML Kit has no web or desktop
  /// version.
  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// The tab on each page, joined by blank lines; null if none was found.
  static Future<String?> read(List<Uint8List> pages) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final found = <String>[];
      for (final page in pages) {
        final tab = await _readPage(recognizer, page);
        if (tab != null) found.add(tab);
      }
      return found.isEmpty ? null : found.join('\n\n');
    } finally {
      await recognizer.close();
    }
  }

  static Future<String?> _readPage(
    TextRecognizer recognizer,
    Uint8List page,
  ) async {
    // OCR and line detection see the same image, so their coordinates
    // agree: the page upright and scaled, in grayscale.
    final prepared = await compute(_prepare, page);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/tabscan-ocr-${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(prepared.png, flush: true);
    try {
      final text = await recognizer.processImage(
        InputImage.fromFilePath(file.path),
      );
      final lines = [
        for (final block in text.blocks)
          for (final line in block.lines) line.text,
      ];
      return asciiTab(lines) ?? typesetTab(prepared.staves, _glyphs(text));
    } finally {
      await file.delete().catchError((_) => file);
    }
  }

  /// Fret numbers, one per word: ML Kit reads digits on different staff
  /// lines as different words, and a two-digit fret as one.
  static List<Glyph> _glyphs(RecognizedText text) => [
    for (final block in text.blocks)
      for (final line in block.lines)
        for (final element in line.elements)
          if (fretText(element.text) case final fret?)
            Glyph(
              fret,
              element.boundingBox.center.dx,
              element.boundingBox.center.dy,
              element.boundingBox.height,
            ),
  ];
}

class _Prepared {
  const _Prepared(this.png, this.staves);
  final Uint8List png;
  final List<List<double>> staves;
}

_Prepared _prepare(Uint8List bytes) {
  final page = img.grayscale(decodePage(bytes));
  final staves = findStaves(darkPixels(page), page.width, page.height);
  return _Prepared(img.encodePng(page), staves);
}
