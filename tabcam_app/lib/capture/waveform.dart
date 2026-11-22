import 'dart:math';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'sound_reader.dart';

/// A file's sound as the video editor's lanes draw it: its loudest
/// sample in each [perSecond]th of a second, from 0 to 1, scaled so the
/// loudest of all is 1 (a quiet take shows as well as a loud song).
class Waveform {
  Waveform(this.peaks, {this.perSecond = Waveform.buckets});

  /// The loudest sample in each bucket, 0 to 1.
  final Float32List peaks;

  /// Buckets a second.
  final int perSecond;

  /// The rate the sound is read at for it: enough for its outline, little
  /// to keep (a 3-minute file, 720 000 samples, read once).
  static const rate = 4000;

  /// Buckets a second: one every 5 ms, finer than a point of the lanes
  /// zoomed in all the way on most videos.
  static const buckets = 200;

  /// The longest sound read for it; past it, none is drawn.
  static const longest = Duration(minutes: 30);

  /// [samples] ([rate] a second, −1 to 1) as a waveform.
  factory Waveform.of(
    Float32List samples, {
    int rate = Waveform.rate,
    int perSecond = buckets,
  }) {
    final per = max(1, rate ~/ perSecond);
    final peaks = Float32List((samples.length + per - 1) ~/ per);
    var loudest = 0.0;
    for (var b = 0; b < peaks.length; b++) {
      var peak = 0.0;
      final end = min(samples.length, (b + 1) * per);
      for (var i = b * per; i < end; i++) {
        final v = samples[i].abs();
        if (v > peak) peak = v;
      }
      peaks[b] = peak;
      if (peak > loudest) loudest = peak;
    }
    // Scaled to the loudest; a silent file stays flat.
    if (loudest > 0.001) {
      for (var b = 0; b < peaks.length; b++) {
        peaks[b] = min(1, peaks[b] / loudest);
      }
    }
    return Waveform(peaks, perSecond: perSecond);
  }

  /// How long it is.
  Duration get length =>
      Duration(microseconds: peaks.length * 1000000 ~/ perSecond);

  /// The loudest between [from] and [to] (at least one bucket), 0 where
  /// it has no sound.
  double peak(Duration from, Duration to) {
    if (peaks.isEmpty) return 0;
    var a = from.inMicroseconds * perSecond ~/ 1000000;
    var b = to.inMicroseconds * perSecond ~/ 1000000;
    if (b <= a) b = a + 1;
    if (b <= 0 || a >= peaks.length) return 0;
    a = max(0, a);
    b = min(peaks.length, b);
    var peak = 0.0;
    for (var i = a; i < b; i++) {
      if (peaks[i] > peak) peak = peaks[i];
    }
    return peak;
  }

  /// The reader waveforms are read with: the platform's
  /// ([SoundReader.open]). A test counting the readers opened, or the
  /// calls on the sound's channel, for something else gives waveforms
  /// none.
  @visibleForTesting
  static SoundReader? Function() opener = SoundReader.open;

  /// Whether this platform has a reader for it ([SoundReader]): none on a
  /// desktop build, where no file need be fetched for one.
  static bool get canRead {
    final reader = opener();
    reader?.close();
    return reader != null;
  }

  /// [file]'s waveform, its first [length] (at most [longest]), read with
  /// the device's own decoders ([SoundReader]); null where it can't be
  /// read (no reader here, no sound in it, a format not decoded). Never
  /// throws.
  static Future<Waveform?> read(XFile file, Duration length) async {
    if (length <= Duration.zero) return null;
    final reader = opener();
    if (reader == null) return null;
    try {
      final samples = await reader.samples(
        file,
        from: Duration.zero,
        length: length > longest ? longest : length,
        rate: rate,
      );
      if (samples == null || samples.isEmpty) return null;
      return Waveform.of(samples);
    } on Object catch (e) {
      debugPrint('TabCam: waveform: not read: $e');
      return null;
    } finally {
      reader.close();
    }
  }
}

/// Where a lane's sound is along the video: from [at] to [end] on the
/// video's clock, its own sound from [from].
typedef WaveSpan = ({Duration at, Duration end, Duration from});

/// Waveforms read, kept by key (a file's) so a row built anew, or a file
/// played along again, draws at once without reading it again: the last
/// [size] asked for. One that couldn't be read is kept too (none).
class WaveCache {
  WaveCache._();

  static const size = 6;

  /// Most recently asked for last.
  static final _kept = <String, Future<Waveform?>>{};
  static final _read = <String, Waveform?>{};

  /// [key]'s waveform: the one kept, or [read]'s.
  static Future<Waveform?> of(String key, Future<Waveform?> Function() read) {
    final future = _kept.remove(key) ?? _reading(key, read);
    _kept[key] = future;
    while (_kept.length > size) {
      _read.remove(_kept.keys.first);
      _kept.remove(_kept.keys.first);
    }
    return future;
  }

  static Future<Waveform?> _reading(
    String key,
    Future<Waveform?> Function() read,
  ) async {
    Waveform? wave;
    try {
      wave = await read();
    } on Object catch (e) {
      debugPrint('TabCam: waveform: not read: $e');
    }
    if (_kept.containsKey(key)) _read[key] = wave;
    return wave;
  }

  /// [key]'s waveform if it's read already, so it's drawn from the first
  /// frame.
  static Waveform? ready(String key) => _read[key];

  @visibleForTesting
  static void clear() {
    _kept.clear();
    _read.clear();
  }
}

/// Draws [wave] over a lane's bar, [length] of video across its width:
/// each point's loudest, mirrored about the middle, where [spans] put the
/// sound along the video; brighter in the part kept ([start] to [end]),
/// dim outside it.
class WavePainter extends CustomPainter {
  WavePainter({
    required this.wave,
    required this.length,
    required this.spans,
    this.rates,
    required this.start,
    required this.end,
    required this.color,
  });

  final Waveform wave;
  final Duration length;
  final List<WaveSpan> spans;

  /// How fast each of [spans]' sound goes along the axis, if not 1: the
  /// wave's seconds in one of the axis's (a take that played along a song
  /// slowed to 0.5×, drawn on the song's axis, goes 2 to 1).
  final List<double>? rates;
  final Duration start;
  final Duration end;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final ms = length.inMicroseconds;
    if (ms <= 0 || size.width <= 0 || spans.isEmpty) return;
    final kept = Path();
    final cut = Path();
    final middle = size.height / 2;
    final reach = size.height * 0.4;
    // Only what's on screen (a zoomed lane is many screens wide).
    final clip = canvas.getLocalClipBounds();
    final first = max(0, clip.left.floor());
    final last = min(size.width.ceil(), clip.right.ceil());
    Duration timeAt(num x) =>
        Duration(microseconds: (x / size.width * ms).round());
    for (var x = first; x < last; x++) {
      final t0 = timeAt(x);
      final t1 = timeAt(x + 1);
      var peak = 0.0;
      for (final (i, span) in spans.indexed) {
        if (t1 <= span.at || t0 >= span.end) continue;
        final a = t0 < span.at ? span.at : t0;
        final b = t1 > span.end ? span.end : t1;
        final rate = rates?[i] ?? 1;
        peak = max(
          peak,
          wave.peak(
            span.from + (a - span.at) * rate,
            span.from + (b - span.at) * rate,
          ),
        );
      }
      if (peak <= 0) continue;
      final h = max(0.5, peak * reach);
      final mid = timeAt(x + 0.5);
      (mid >= start && mid <= end ? kept : cut)
        ..moveTo(x + 0.5, middle - h)
        ..lineTo(x + 0.5, middle + h);
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(kept, stroke..color = color.withValues(alpha: 0.55));
    canvas.drawPath(cut, stroke..color = color.withValues(alpha: 0.2));
  }

  @override
  bool shouldRepaint(WavePainter old) =>
      old.wave != wave ||
      old.length != length ||
      !listEquals(old.spans, spans) ||
      !listEquals(old.rates, rates) ||
      old.start != start ||
      old.end != end ||
      old.color != color;
}
