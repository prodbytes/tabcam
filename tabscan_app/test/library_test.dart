import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/library/scan.dart';
import 'package:tabscan_app/library/scan_store_io.dart';
import 'package:tabscan_app/processing/page_filter.dart';

Uint8List _jpeg(int width, int height) => img.encodeJpg(
  img.Image(width: width, height: height)..clear(img.ColorRgb8(240, 240, 240)),
);

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('tabscan'));
  tearDown(() => root.delete(recursive: true));

  test('scans survive a restart, with pages, filters and text', () async {
    final library = Library(PlatformScanStore(root));
    await library.load();
    var scan = await library.create([_jpeg(40, 60), _jpeg(40, 60)]);
    scan = await library.update(
      scan.copyWith(
        title: 'My riff',
        artist: 'Me',
        tabText: 'e|--0--|',
        pages: [
          scan.pages.first.copyWith(filter: PageFilter.original),
          scan.pages.last,
        ],
      ),
    );

    final reopened = Library(PlatformScanStore(root));
    await reopened.load();
    final loaded = reopened.byId(scan.id)!;
    expect(loaded.title, 'My riff');
    expect(loaded.artist, 'Me');
    expect(loaded.tabText, 'e|--0--|');
    expect(loaded.pages.map((p) => p.filter), [
      PageFilter.original,
      PageFilter.tab,
    ]);
    expect(await reopened.original(loaded, loaded.pages.first), isNotEmpty);
  });

  test('deleting a page or a scan removes its files', () async {
    final library = Library(PlatformScanStore(root));
    await library.load();
    var scan = await library.create([_jpeg(10, 10), _jpeg(10, 10)]);
    scan = await library.deletePage(scan, scan.pages.first);
    expect(scan.pages, hasLength(1));
    expect(Directory('${root.path}/${scan.id}').listSync(), hasLength(2));

    await library.delete(scan);
    expect(library.scans, isEmpty);
    expect(Directory('${root.path}/${scan.id}').existsSync(), isFalse);
  });

  test('rotating a page turns it a quarter turn', () async {
    final library = Library(PlatformScanStore(root));
    await library.load();
    final scan = await library.create([_jpeg(40, 60)]);
    await library.rotatePage(scan, scan.pages.single);
    final page = img.decodeImage(
      await library.original(scan, scan.pages.single),
    )!;
    expect((page.width, page.height), (60, 40));
  });

  test('IDs that could name other files are refused', () {
    expect(() => checkId('../etc'), throwsFormatException);
    expect(
      () => Scan.fromJson({'id': '../x', 'created': '2026-01-01T00:00:00Z'}),
      throwsFormatException,
    );
  });

  test('the Tab filter makes a black-and-white page', () async {
    final page = img.Image(width: 120, height: 80)
      ..clear(img.ColorRgb8(200, 190, 170));
    img.drawLine(
      page,
      x1: 10,
      y1: 40,
      x2: 110,
      y2: 40,
      color: img.ColorRgb8(30, 30, 30),
      thickness: 2,
    );
    final out = img.decodePng(
      await applyFilter(img.encodeJpg(page), PageFilter.tab),
    )!;
    expect(out.getPixel(60, 40).r, 0);
    expect(out.getPixel(60, 10).r, 255);
  });
}
