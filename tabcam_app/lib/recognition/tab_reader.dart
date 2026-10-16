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
      for (final (i, page) in pages.indexed) {
        final watch = Stopwatch()..start();
        final tab = await _readPage(recognizer, page);
        _log(
          'page ${i + 1}/${pages.length}: '
          '${tab == null ? 'no tab' : '${tab.split('\n').length} lines of tab'}'
          ' in ${watch.elapsedMilliseconds} ms',
        );
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
    _log(
      '${page.length} bytes -> ${prepared.width}x${prepared.height}, '
      '${prepared.staves.length} drawn staves',
    );
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/tabcam-ocr-${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(prepared.png, flush: true);
    try {
      final text = await recognizer.processImage(
        InputImage.fromFilePath(file.path),
      );
      // Top to bottom: chords and lyrics go where they are on the page.
      final lines = [
        for (final block in text.blocks)
          for (final line in block.lines)
            OcrLine(
              line.text,
              words: [
                for (final e in line.elements)
                  OcrWord(e.text, e.boundingBox.left),
              ],
              chars: [for (final e in line.elements) ..._chars(e)],
              left: line.boundingBox.left,
              right: line.boundingBox.right,
              top: line.boundingBox.top,
              bottom: line.boundingBox.bottom,
            ),
      ]..sort((a, b) => a.y.compareTo(b.y));
      final glyphs = _glyphs(text);
      _log(
        'OCR: ${text.blocks.length} blocks, ${lines.length} lines, '
        '${glyphs.length} frets; first lines: '
        '${lines.take(5).map((l) => '"${l.text}"').join(' ')}',
      );
      final ascii = asciiTab(lines);
      if (ascii != null) {
        _log('read as a text tab');
        return ascii;
      }
      final typeset = typesetTab(prepared.staves, glyphs, text: lines);
      _log(
        typeset == null
            ? 'neither a text nor a typeset tab'
            : 'read as a typeset tab',
      );
      return typeset;
    } finally {
      await file.delete().catchError((_) => file);
    }
  }

  static void _log(String message) => debugPrint('TabCam: read tab: $message');

  /// Where each of an element's characters is: its symbols' boxes, or,
  /// when ML Kit gives none, the element's box shared evenly between them.
  static List<OcrChar> _chars(TextElement element) {
    final symbols = [
      for (final s in element.symbols)
        if (s.text.trim().isNotEmpty) s,
    ];
    final text = element.text.replaceAll(RegExp(r'\s'), '');
    if (symbols.map((s) => s.text).join() == text) {
      return [
        for (final s in symbols)
          OcrChar(s.text, s.boundingBox.left, s.boundingBox.right),
      ];
    }
    final box = element.boundingBox;
    final step = box.width / (text.isEmpty ? 1 : text.length);
    return [
      for (var i = 0; i < text.length; i++)
        OcrChar(text[i], box.left + i * step, box.left + (i + 1) * step),
    ];
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
  const _Prepared(this.png, this.width, this.height, this.staves);
  final Uint8List png;
  final int width;
  final int height;
  final List<List<double>> staves;
}

_Prepared _prepare(Uint8List bytes) {
  final page = img.grayscale(decodePage(bytes));
  final staves = findStaves(darkPixels(page), page.width, page.height);
  return _Prepared(img.encodePng(page), page.width, page.height, staves);
}
