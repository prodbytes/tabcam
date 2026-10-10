import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabscan_app/capture/media.dart';
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

  test('rotating a page turns it a quarter turn, as a new page', () async {
    final library = Library(PlatformScanStore(root));
    await library.load();
    final scan = await library.create([_jpeg(40, 60)]);
    final before = scan.pages.single;
    final rotated = await library.rotatePage(scan, before);
    final after = rotated.pages.single;
    // Page files never change once written (cloud sync relies on it).
    expect(after.id, isNot(before.id));
    expect(after.filter, before.filter);
    expect(await library.hasPage(scan.id, before), isFalse);
    final page = img.decodeImage(await library.original(rotated, after))!;
    expect((page.width, page.height), (60, 40));
  });

  test('a scan that never synced is deleted outright', () async {
    final library = Library(PlatformScanStore(root));
    await library.load();
    final scan = await library.create([_jpeg(40, 60)]);
    await library.delete(scan);
    expect(library.all, isEmpty);
    final reopened = Library(PlatformScanStore(root));
    await reopened.load();
    expect(reopened.all, isEmpty);
  });

  test('a synced scan leaves a tombstone, without its pages', () async {
    final library = Library(PlatformScanStore(root));
    await library.load();
    final scan = await library.create([_jpeg(40, 60)]);
    await library.setOwner(scan, 'us-east-1:me');
    await library.delete(library.all.single);
    expect(library.scans, isEmpty);
    final reopened = Library(PlatformScanStore(root));
    await reopened.load();
    expect(reopened.scans, isEmpty);
    final tombstone = reopened.all.single;
    expect(tombstone.isDeleted, isTrue);
    expect(tombstone.owner, 'us-east-1:me');
    expect(await reopened.hasPage(scan.id, scan.pages.single), isFalse);
  });

  test('changes bump updated and count as local changes', () async {
    var now = DateTime(2026, 10, 10, 12);
    final library = Library(PlatformScanStore(root), () => now);
    await library.load();
    final scan = await library.create([_jpeg(40, 60)]);
    final changes = library.localChanges.value;
    now = now.add(const Duration(minutes: 1));
    final renamed = await library.update(scan.copyWith(title: 'Riff'));
    expect(renamed.updated, now);
    expect(library.localChanges.value, changes + 1);
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

  test('photos and videos are added as pages, videos as they are', () async {
    final library = Library(PlatformScanStore(root));
    await library.load();
    var scan = await library.create([_jpeg(10, 10)]);
    final video = Uint8List.fromList(List.generate(64, (i) => i));
    final pick = MediaPick.of([
      XFile.fromData(_jpeg(20, 10), path: 'chord.JPG'),
      XFile.fromData(video, path: 'lesson.mov'),
      XFile.fromData(Uint8List(4), path: 'notes.txt'),
    ]);
    expect(pick.skipped, 1);
    scan = await library.addMedia(scan, pick.media);

    expect(scan.pages.map((p) => (p.kind, p.extension)), [
      (PageKind.image, 'img'),
      (PageKind.image, 'jpg'),
      (PageKind.video, 'mov'),
    ]);
    final saved = scan.pages.last;
    expect(await library.original(scan, saved), video);
    expect(await library.filtered(scan, saved), video);
    expect(await library.path(scan, saved), endsWith('/${saved.fileName}'));

    // They survive a restart.
    final reopened = Library(PlatformScanStore(root));
    await reopened.load();
    expect(reopened.byId(scan.id)!.pages.last.isVideo, isTrue);
  });

  test('media is recognized by extension, then by MIME type', () {
    expect(Media.of(XFile('a/clip.MP4'))!.kind, PageKind.video);
    expect(Media.of(XFile('a/page.heic'))!.extension, 'heic');
    expect(
      Media.of(XFile('a/upload', mimeType: 'video/quicktime'))!.extension,
      'mov',
    );
    expect(Media.of(XFile('a/song.mp3')), isNull);
  });

  test('scans saved before videos load as image pages', () {
    final page = ScanPage.fromJson({'id': 'abc', 'filter': 'original'});
    expect((page.kind, page.extension), (PageKind.image, 'img'));
  });

  test('extensions that could name other files are refused', () {
    expect(
      () => ScanPage.fromJson({'id': 'abc', 'extension': '../x'}),
      throwsFormatException,
    );
  });
}
