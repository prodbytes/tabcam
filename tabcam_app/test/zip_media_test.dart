import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/media.dart';
import 'package:tabcam_app/library/capture_event.dart';

/// A zip of [files] (path → bytes).
Uint8List _zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final MapEntry(:key, :value) in files.entries) {
    archive.addFile(ArchiveFile.bytes(key, value));
  }
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  test("a zip's files are added in its place, in its order", () async {
    final pick = await MediaPick.from([
      XFile.fromData(Uint8List(3), path: 'cover.jpg'),
      XFile.fromData(
        _zip({
          'riff/page 1.png': [1],
          'riff/lesson.m4a': [2],
          'riff/notes.txt': [3],
          'riff/tab.pdf': [4],
          '__MACOSX/riff/._page 1.png': [5],
          'riff/.DS_Store': [6],
          'inner.zip': _zip({
            'solo.mp4': [7],
          }),
        }),
        path: 'Riff.ZIP',
      ),
    ]);
    expect(
      [for (final m in pick.media) m.file.name],
      ['cover.jpg', 'page 1.png', 'lesson.m4a', 'tab.pdf', 'solo.mp4'],
    );
    expect(
      [for (final m in pick.media) m.kind],
      [
        PageKind.image,
        PageKind.image,
        PageKind.audio,
        PageKind.pdf,
        PageKind.video,
      ],
    );
    expect(await pick.media[2].file.readAsBytes(), [2]);
    // notes.txt; macOS's files aren't counted.
    expect(pick.skipped, 1);
  });

  test('a zip by its MIME type is unzipped too', () async {
    final pick = await MediaPick.from([
      XFile.fromData(
        _zip({
          'a.jpg': [1],
        }),
        path: 'download',
        mimeType: 'application/zip',
      ),
    ]);
    expect([for (final m in pick.media) m.file.name], ['a.jpg']);
  });

  test("a zip that can't be read is skipped", () async {
    final pick = await MediaPick.from([
      XFile.fromData(Uint8List.fromList([1, 2, 3]), path: 'broken.zip'),
    ]);
    expect(pick.media, isEmpty);
    expect(pick.skipped, 1);
  });

  test('a zip with too many files is skipped', () async {
    final pick = await MediaPick.from([
      XFile.fromData(
        _zip({
          for (var i = 0; i <= MediaPick.maxZipEntries; i++) 'p$i.jpg': [1],
        }),
        path: 'many.zip',
      ),
    ]);
    expect(pick.media, isEmpty);
    expect(pick.skipped, 1);
  });

  test('zips are offered in the Files picker', () {
    expect(Media.extensions, contains('zip'));
    expect(Media.of(XFile('x.zip')), isNull);
  });
}
