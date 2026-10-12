import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:tabscan_app/capture/media.dart';
import 'package:tabscan_app/library/capture_event.dart';
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/recognition/auto_reader.dart';
import 'package:tabscan_app/recognition/pdf_reader.dart';
import 'package:tabscan_app/recognition/tab_layout.dart';

// Made-up riffs: tests never use published songs' tabs.
const _riff = [
  'e|-0-----3-|',
  'B|-1-----0-|',
  'G|-2-----0-|',
  'D|-2-----0-|',
  'A|-0-----2-|',
  'E|-------3-|',
];

/// A page's text as PDFium gives it: lines with their characters' boxes,
/// in a 6 pt monospace grid, from the top of an A4 page down.
(String, List<CharBox>) _page(List<String> lines, {double x0 = 50}) {
  final text = StringBuffer();
  final boxes = <CharBox>[];
  for (final (row, line) in lines.indexed) {
    if (row > 0) {
      text.write('\r\n');
      boxes.addAll([
        (left: 0, top: 0, right: 0, bottom: 0),
        (left: 0, top: 0, right: 0, bottom: 0),
      ]);
    }
    final top = 800.0 - row * 12;
    for (var i = 0; i < line.length; i++) {
      text.write(line[i]);
      boxes.add((
        left: x0 + i * 6,
        top: top,
        right: x0 + i * 6 + 6,
        bottom: top - 10,
      ));
    }
  }
  return ('$text', boxes);
}

Media _pdf(Uint8List bytes) =>
    Media(XFile.fromData(bytes, name: 'riff.pdf'), PageKind.pdf, 'pdf');

void main() {
  group('a PDF page\'s text', () {
    test('lays out as a tab, chord names at their columns', () {
      final (text, boxes) = _page([
        'Verse',
        '  Am    G',
        ..._riff,
        '',
        'la la',
      ]);
      final lines = pdfLines(text, boxes);
      expect(lines.first.text, 'Verse');
      expect(lines[1].words.map((w) => w.text), ['Am', 'G']);
      final tab = asciiTab(lines)!;
      expect(tab.split('\n').take(3), ['Verse', '  Am    G', 'e|-0-----3-|']);
      expect(tab, endsWith('\n\nla la'));
    });

    test('a page without tab has none', () {
      final (text, boxes) = _page(['Lesson notes', 'Practice slowly']);
      expect(asciiTab(pdfLines(text, boxes)), isNull);
    });
  });

  group('reading by itself', () {
    late Library library;
    late List<String> calls;
    setUp(() async {
      library = Library(PlatformEventStore(), null, (_) async => null);
      await library.load();
      calls = [];
    });

    AutoReader reader({bool supported = true, String? pdfText = 'e|-0-|'}) =>
        AutoReader(
          library: library,
          supported: supported,
          read: (pages) async {
            calls.add('ocr ${pages.length}');
            return 'B|-1-|';
          },
          readPdf: (pdf, ocr) async {
            calls.add('pdf ${ocr == null ? 'text only' : 'with ocr'}');
            return pdfText;
          },
        )..start();

    Future<void> settle() async {
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test('a PDF is read into the text tab, in page order', () async {
      final r = reader();
      await settle();
      var event = await library.create([
        img.encodeJpg(img.Image(width: 8, height: 8)),
      ]);
      event = await library.addMedia(event, [
        _pdf(Uint8List.fromList([1])),
      ]);
      await settle();
      expect(calls, contains('pdf with ocr'), reason: '$calls');
      expect(library.byId(event.id)!.tabText, 'B|-1-|\n\ne|-0-|');
      r.dispose();
    });

    test(
      'where the device can\'t OCR (the web), a PDF\'s text is still read',
      () async {
        final r = reader(supported: false);
        await settle();
        final event = await library.addMedia(await library.create(const []), [
          _pdf(Uint8List.fromList([1])),
        ]);
        await settle();
        expect(calls, ['pdf text only']);
        expect(library.byId(event.id)!.tabText, 'e|-0-|');
        expect(r.stateOf(event.id), isNull);
        r.dispose();
      },
    );

    test(
      'on the web, a scanned PDF says what it needs (not "no tab")',
      () async {
        final r = reader(supported: false, pdfText: null);
        await settle();
        final event = await library.addMedia(await library.create(const []), [
          _pdf(Uint8List.fromList([1])),
        ]);
        await settle();
        expect(r.stateOf(event.id), ReadState.unsupported);
        r.dispose();
      },
    );

    test('a PDF without tab says so', () async {
      final r = reader(pdfText: null);
      await settle();
      final event = await library.addMedia(await library.create(const []), [
        _pdf(Uint8List.fromList([1])),
      ]);
      await settle();
      expect(r.stateOf(event.id), ReadState.noTab);
      r.dispose();
    });
  });

  test('a real PDF of a made-up riff, read by its text', () async {
    final doc = pw.Document()
      ..addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final line in ['Verse', ..._riff])
                pw.Text(line, style: pw.TextStyle(font: pw.Font.courier())),
            ],
          ),
        ),
      );
    final bytes = await doc.save();
    // The plain-Dart PDFium (downloaded once), as the app's isn't loadable
    // in tests; then what PdfTabReader does with each page's text.
    String? text;
    try {
      await pdfrxInitialize(tmpPath: Directory.systemTemp.path);
      final pdf = await PdfDocument.openData(bytes);
      final raw = (await pdf.pages.single.loadText())!;
      text = asciiTab(
        pdfLines(raw.fullText, [
          for (final r in raw.charRects)
            (left: r.left, top: r.top, right: r.right, bottom: r.bottom),
        ]),
      );
      await pdf.dispose();
    } on Object catch (e) {
      markTestSkipped('PDFium isn\'t available here: $e');
      return;
    }
    expect(text, isNotNull);
    expect(text!.split('\n').first, 'Verse');
    expect(text, contains('e|-0-----3-|'));
    expect(text, contains('E|-------3-|'));
  });
}
