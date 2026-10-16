import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Finds the page in a photo taken by hand and crops and straightens the
/// photo to it, so what's under the page (a table, a lap) doesn't show,
/// as the system document scanner does for scans. Returns the page as a
/// JPEG, or null when there's no clear page to crop to (the photo is left
/// as it is): it would rather keep a photo whole than cut a tab short.
///
/// Runs off the UI isolate where there are isolates ([compute]).
Future<Uint8List?> cropToPage(Uint8List photo) => compute(cropToPageNow, photo);

/// [cropToPage], on this isolate.
Uint8List? cropToPageNow(Uint8List photo) {
  final img.Image decoded;
  try {
    final d = img.decodeImage(photo);
    if (d == null) return null;
    // As the camera held it (EXIF orientation), as it shows.
    decoded = img.bakeOrientation(d);
  } on Object {
    return null; // a format the decoder doesn't know (HEIC): kept as is
  }
  final corners = findPage(decoded);
  if (corners == null) return null;
  final [tl, tr, br, bl] = corners;
  double dist(math.Point<double> a, math.Point<double> b) => a.distanceTo(b);
  var width = math.max(dist(tl, tr), dist(bl, br));
  var height = math.max(dist(tl, bl), dist(tr, br));
  // Not more than the photo had, nor more than a page needs.
  final scale = math.min(1.0, maxSide / math.max(width, height));
  width *= scale;
  height *= scale;
  img.Point p(math.Point<double> c) => img.Point(c.x, c.y);
  final page = img.copyRectify(
    decoded,
    topLeft: p(tl),
    topRight: p(tr),
    bottomLeft: p(bl),
    bottomRight: p(br),
    interpolation: img.Interpolation.linear,
    toImage: img.Image(width: width.round(), height: height.round()),
  );
  return img.encodeJpg(page, quality: 90);
}

/// The longest side of a cropped page, in pixels.
const int maxSide = 3000;

/// The size the page is looked for at (the longest side, in pixels).
const int _work = 400;

/// The page's corners in [photo] (top left, top right, bottom right,
/// bottom left), or null when no page stands out clearly:
///
/// 1. at a small size, in gray, the photo is split into bright and dark
///    (Otsu's threshold): paper is the bright part;
/// 2. the largest bright region is the page; it must cover between 20% and
///    92% of the photo (more: the page already fills it), and not reach
///    across from one edge of the photo to the opposite one;
/// 3. its corners are its extreme points along the diagonals, which must
///    make a convex four-sided shape, with no angle sharper than 50° or
///    wider than 130°, that the region fills (at least 85%).
@visibleForTesting
List<math.Point<double>>? findPage(img.Image photo) {
  final factor = _work / math.max(photo.width, photo.height);
  final small = factor < 1
      ? img.copyResize(
          photo,
          width: (photo.width * factor).round(),
          height: (photo.height * factor).round(),
          interpolation: img.Interpolation.average,
        )
      : photo;
  final w = small.width;
  final h = small.height;
  final n = w * h;
  final gray = Uint8List(n);
  for (final px in small) {
    gray[px.y * w + px.x] = img.getLuminance(px).round().clamp(0, 255);
  }
  final threshold = _otsu(gray);
  // Bright, closed a little so text and staff lines don't split the page.
  var bright = Uint8List(n);
  for (var i = 0; i < n; i++) {
    bright[i] = gray[i] > threshold ? 1 : 0;
  }
  bright = _close(bright, w, h);

  // The largest bright region (4-connected).
  final label = Int32List(n);
  var best = 0;
  var bestSize = 0;
  var next = 0;
  final queue = Int32List(n);
  for (var start = 0; start < n; start++) {
    if (bright[start] == 0 || label[start] != 0) continue;
    next++;
    var head = 0;
    var tail = 0;
    queue[tail++] = start;
    label[start] = next;
    while (head < tail) {
      final i = queue[head++];
      final x = i % w;
      final y = i ~/ w;
      for (final j in [
        if (x > 0) i - 1,
        if (x < w - 1) i + 1,
        if (y > 0) i - w,
        if (y < h - 1) i + w,
      ]) {
        if (bright[j] == 1 && label[j] == 0) {
          label[j] = next;
          queue[tail++] = j;
        }
      }
    }
    if (tail > bestSize) {
      bestSize = tail;
      best = next;
    }
  }
  if (best == 0) return null;
  final cover = bestSize / n;
  if (cover < 0.20 || cover > 0.92) return null;

  // Its extremes along the diagonals, and its reach.
  var tl = (0, 0, 1 << 30); // (x, y, x + y)
  var br = (0, 0, -1);
  var tr = (0, 0, -(1 << 30)); // x - y
  var bl = (0, 0, 1 << 30);
  var minX = w, maxX = -1, minY = h, maxY = -1;
  for (var i = 0; i < n; i++) {
    if (label[i] != best) continue;
    final x = i % w;
    final y = i ~/ w;
    if (x + y < tl.$3) tl = (x, y, x + y);
    if (x + y > br.$3) br = (x, y, x + y);
    if (x - y > tr.$3) tr = (x, y, x - y);
    if (x - y < bl.$3) bl = (x, y, x - y);
    minX = math.min(minX, x);
    maxX = math.max(maxX, x);
    minY = math.min(minY, y);
    maxY = math.max(maxY, y);
  }
  // Across the whole photo, side to side: not a page lying on something,
  // but the photo's background (or the page already filling it).
  if ((minX == 0 && maxX == w - 1) || (minY == 0 && maxY == h - 1)) {
    return null;
  }

  final quad = [
    for (final c in [tl, tr, br, bl])
      math.Point<double>(c.$1.toDouble(), c.$2.toDouble()),
  ];
  if (!_plausible(quad, bestSize)) return null;
  // Back to the photo's size, a little inside, so no background line shows.
  final center = quad.reduce((a, b) => a + b) * 0.25;
  return [
    for (final c in quad)
      (center + (c - center) * 0.985) * (1 / (factor < 1 ? factor : 1)),
  ];
}

/// A convex quadrilateral with no very sharp or very wide corner, that
/// the region ([area] pixels) mostly fills.
bool _plausible(List<math.Point<double>> q, int area) {
  double cross(
    math.Point<double> o,
    math.Point<double> a,
    math.Point<double> b,
  ) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  var sign = 0;
  for (var i = 0; i < 4; i++) {
    final c = cross(q[i], q[(i + 1) % 4], q[(i + 2) % 4]);
    if (c == 0) return false;
    final s = c > 0 ? 1 : -1;
    if (sign != 0 && s != sign) return false;
    sign = s;
  }
  for (var i = 0; i < 4; i++) {
    final a = q[(i + 3) % 4] - q[i];
    final b = q[(i + 1) % 4] - q[i];
    final cos = (a.x * b.x + a.y * b.y) / (a.magnitude * b.magnitude);
    final angle = math.acos(cos.clamp(-1.0, 1.0)) * 180 / math.pi;
    if (angle < 50 || angle > 130) return false;
  }
  var shoelace = 0.0;
  for (var i = 0; i < 4; i++) {
    final a = q[i];
    final b = q[(i + 1) % 4];
    shoelace += a.x * b.y - b.x * a.y;
  }
  final quadArea = shoelace.abs() / 2;
  return quadArea > 0 && area / quadArea >= 0.85 && area / quadArea <= 1.15;
}

/// Otsu's threshold: the gray level that best splits [gray] in two.
int _otsu(Uint8List gray) {
  final hist = List<int>.filled(256, 0);
  for (final g in gray) {
    hist[g]++;
  }
  final total = gray.length;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumB = 0.0;
  var wB = 0;
  var best = 0.0;
  var threshold = 127;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB;
    final mF = (sum - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      threshold = t;
    }
  }
  return threshold;
}

/// A morphological close (a dilation, then an erosion, 3×3, twice):
/// fills the thin dark marks inside the page.
Uint8List _close(Uint8List m, int w, int h) {
  Uint8List pass(Uint8List src, bool dilate) {
    final out = Uint8List(src.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var hit = !dilate;
        for (var dy = -1; dy <= 1 && hit != dilate; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            final yy = y + dy;
            if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
            final v = src[yy * w + xx] == 1;
            if (dilate && v) {
              hit = true;
              break;
            }
            if (!dilate && !v) {
              hit = false;
              break;
            }
          }
        }
        out[y * w + x] = hit ? 1 : 0;
      }
    }
    return out;
  }

  var r = m;
  for (var i = 0; i < 2; i++) {
    r = pass(r, true);
  }
  for (var i = 0; i < 2; i++) {
    r = pass(r, false);
  }
  return r;
}
