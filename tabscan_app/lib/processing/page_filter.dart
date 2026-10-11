import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../l10n/language.dart';

/// How a page is shown, shared and read. The original photo is always
/// kept; a filter is applied on the way out.
enum PageFilter {
  /// The page as scanned.
  original,

  /// Black ink on white paper: shadows and paper tint removed, so thin tab
  /// lines and small fret numbers stay sharp in a PDF or on a print.
  tab;

  /// The filter's name, as shown.
  String label(AppLocalizations l10n) => switch (this) {
    original => l10n.eventViewOriginal,
    tab => l10n.eventFilterTab,
  };

  static PageFilter byName(String? name) =>
      values.firstWhere((f) => f.name == name, orElse: () => tab);
}

/// Pages are scaled down to at most this many pixels on their long side:
/// enough for OCR and print, small enough to process quickly.
const int maxPageSide = 2400;

/// The page's image with [filter] applied, as PNG (tab) or the original
/// bytes. Runs off the UI isolate where the platform has isolates.
Future<Uint8List> applyFilter(Uint8List bytes, PageFilter filter) async {
  if (filter == PageFilter.original) return bytes;
  return compute(_tabPng, bytes);
}

Uint8List _tabPng(Uint8List bytes) =>
    img.encodePng(binarize(decodePage(bytes)));

/// Decodes a page, upright (EXIF orientation applied) and scaled to
/// [maxPageSide].
img.Image decodePage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Not an image');
  var page = img.bakeOrientation(decoded);
  final side = page.width > page.height ? page.width : page.height;
  if (side > maxPageSide) {
    page = page.width >= page.height
        ? img.copyResize(page, width: maxPageSide)
        : img.copyResize(page, height: maxPageSide);
  }
  return page;
}

/// The page in black and white: adaptive thresholding, each pixel against
/// the mean of its neighborhood (a window of 1/24 of the page width), so
/// uneven lighting and shadows across the page don't matter.
img.Image binarize(img.Image page) {
  final w = page.width, h = page.height;
  final dark = darkPixels(page);
  final out = img.Image(width: w, height: h, numChannels: 1);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out.setPixelR(x, y, dark[y * w + x] ? 0 : 255);
    }
  }
  return out;
}

/// Which pixels are ink, row by row: darker than 88% of their
/// neighborhood's mean brightness (a box of 1/24 of the page width),
/// computed with an integral image.
List<bool> darkPixels(img.Image page) {
  final w = page.width, h = page.height;
  final lum = Uint8List(w * h);
  for (final p in page) {
    lum[p.y * w + p.x] = p.luminance.toInt().clamp(0, 255);
  }
  // integral[(y + 1) * (w + 1) + (x + 1)]: sum of lum above and left of x, y.
  final integral = Uint32List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var row = 0;
    for (var x = 0; x < w; x++) {
      row += lum[y * w + x];
      integral[(y + 1) * (w + 1) + x + 1] = integral[y * (w + 1) + x + 1] + row;
    }
  }
  final r = (w / 48).round().clamp(4, 64);
  final dark = List<bool>.filled(w * h, false);
  for (var y = 0; y < h; y++) {
    final y0 = (y - r).clamp(0, h - 1), y1 = (y + r).clamp(0, h - 1) + 1;
    for (var x = 0; x < w; x++) {
      final x0 = (x - r).clamp(0, w - 1), x1 = (x + r).clamp(0, w - 1) + 1;
      final sum =
          integral[y1 * (w + 1) + x1] -
          integral[y0 * (w + 1) + x1] -
          integral[y1 * (w + 1) + x0] +
          integral[y0 * (w + 1) + x0];
      final mean = sum / ((x1 - x0) * (y1 - y0));
      dark[y * w + x] = lum[y * w + x] < mean * 0.88;
    }
  }
  return dark;
}

/// The page turned a quarter turn clockwise, as JPEG.
Future<Uint8List> rotatedPage(Uint8List bytes) => compute(_rotate, bytes);

Uint8List _rotate(Uint8List bytes) =>
    img.encodeJpg(img.copyRotate(decodePage(bytes), angle: 90), quality: 90);
