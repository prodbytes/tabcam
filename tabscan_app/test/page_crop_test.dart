import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabscan_app/processing/page_crop.dart';

/// A photo of a page (a made-up riff's staff: six lines and some fret
/// numbers' worth of dark marks) lying askew on a dark table.
img.Image photoOfPage({
  int width = 1200,
  int height = 1600,
  List<(int, int)> corners = const [
    (260, 220),
    (980, 300),
    (940, 1380),
    (180, 1300),
  ],
}) {
  final photo = img.Image(width: width, height: height)
    ..clear(img.ColorRgb8(70, 55, 45)); // a wooden table
  img.fillPolygon(
    photo,
    vertices: [for (final (x, y) in corners) img.Point(x, y)],
    color: img.ColorRgb8(238, 236, 228),
  );
  // Staff lines and marks inside the page.
  for (var line = 0; line < 6; line++) {
    final y = 500 + line * 40;
    img.drawLine(
      photo,
      x1: 330,
      y1: y,
      x2: 860,
      y2: y + 30,
      color: img.ColorRgb8(30, 30, 30),
      thickness: 3,
    );
  }
  for (var i = 0; i < 8; i++) {
    img.fillRect(
      photo,
      x1: 360 + i * 60,
      y1: 610,
      x2: 380 + i * 60,
      y2: 640,
      color: img.ColorRgb8(20, 20, 20),
    );
  }
  return photo;
}

void main() {
  test('a page on a table: its corners are found', () {
    final corners = findPage(photoOfPage())!;
    final expected = [(260, 220), (980, 300), (940, 1380), (180, 1300)];
    for (final (i, (x, y)) in expected.indexed) {
      // Within 4% of the photo (the work size, and a little inset).
      expect(
        corners[i].distanceTo(math.Point(x.toDouble(), y.toDouble())),
        lessThan(64),
        reason: 'corner $i: ${corners[i]} vs ($x, $y)',
      );
    }
  });

  test('cropped and straightened to the page, without the table', () {
    final out = img.decodeJpg(cropToPageNow(img.encodeJpg(photoOfPage()))!)!;
    // Portrait, like the page (about 740 × 1080).
    expect(out.width, inInclusiveRange(650, 820));
    expect(out.height, inInclusiveRange(980, 1180));
    // The corners are paper now, not table.
    for (final (x, y) in [
      (8, 8),
      (out.width - 9, 8),
      (8, out.height - 9),
      (out.width - 9, out.height - 9),
    ]) {
      expect(
        img.getLuminance(out.getPixel(x, y)),
        greaterThan(180),
        reason: 'corner ($x, $y)',
      );
    }
  });

  test('a page that already fills the photo is left as it is', () {
    final full = photoOfPage(
      corners: const [(0, 0), (1199, 0), (1199, 1599), (0, 1599)],
    );
    expect(findPage(full), isNull);
    expect(cropToPageNow(img.encodeJpg(full)), isNull);
  });

  test('no page in the photo: left as it is', () {
    final table = img.Image(width: 800, height: 600)
      ..clear(img.ColorRgb8(70, 55, 45));
    img.fillCircle(
      table,
      x: 400,
      y: 300,
      radius: 60,
      color: img.ColorRgb8(240, 240, 240),
    );
    expect(findPage(table), isNull);
  });

  test('what the decoder can\'t read is left as it is', () {
    expect(
      cropToPageNow(
        img.encodeJpg(img.Image(width: 2, height: 2)).sublist(0, 10),
      ),
      isNull,
    );
  });
}
