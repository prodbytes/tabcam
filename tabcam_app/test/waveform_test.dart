import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/waveform.dart';

void main() {
  /// [seconds] of a made-up riff's outline: silent, then a note at
  /// [level] from [from] to [to] seconds, at [Waveform.rate].
  Float32List riff(double seconds, double from, double to, double level) {
    const rate = Waveform.rate;
    return Float32List.fromList([
      for (var i = 0; i < seconds * rate; i++)
        i >= from * rate && i < to * rate
            ? level * sin(2 * pi * 220 * i / rate)
            : 0,
    ]);
  }

  test('a bucket every 5 ms, its loudest sample, scaled to the loudest', () {
    final wave = Waveform.of(riff(2, 0.5, 1, 0.25));
    expect(wave.peaks, hasLength(400));
    expect(wave.length, const Duration(seconds: 2));
    // Silent before the note, loud (scaled to 1) during it.
    expect(wave.peak(Duration.zero, const Duration(milliseconds: 490)), 0);
    expect(
      wave.peak(
        const Duration(milliseconds: 500),
        const Duration(milliseconds: 1000),
      ),
      closeTo(1, 0.01),
    );
    expect(wave.peak(const Duration(milliseconds: 1010), wave.length), 0);
    // A span narrower than a bucket reads that bucket; past the end, 0.
    expect(
      wave.peak(
        const Duration(milliseconds: 700),
        const Duration(milliseconds: 701),
      ),
      greaterThan(0.5),
    );
    expect(
      wave.peak(const Duration(seconds: 5), const Duration(seconds: 6)),
      0,
    );
  });

  test('a silent file stays flat', () {
    final wave = Waveform.of(Float32List(Waveform.rate));
    expect(wave.peaks.every((p) => p == 0), isTrue);
  });

  testWidgets('the painter draws where the spans put the sound', (
    tester,
  ) async {
    final wave = Waveform.of(riff(1, 0, 1, 1));
    final painter = WavePainter(
      wave: wave,
      length: const Duration(seconds: 4),
      spans: [
        (
          at: const Duration(seconds: 2),
          end: const Duration(seconds: 3),
          from: Duration.zero,
        ),
      ],
      start: Duration.zero,
      end: const Duration(seconds: 4),
      color: Colors.white,
    );
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: const Key('lane'),
          child: CustomPaint(size: const Size(400, 40), painter: painter),
        ),
      ),
    );
    // Same inputs: no repaint; a moved span: a repaint.
    expect(painter.shouldRepaint(painter), isFalse);
    expect(
      WavePainter(
        wave: wave,
        length: const Duration(seconds: 4),
        spans: [
          (
            at: Duration.zero,
            end: const Duration(seconds: 1),
            from: Duration.zero,
          ),
        ],
        start: Duration.zero,
        end: const Duration(seconds: 4),
        color: Colors.white,
      ).shouldRepaint(painter),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'a span\'s rate fits its sound into the axis\'s time: a take of a '
    'song slowed to 0.5×, two seconds of its sound in each of the song\'s',
    () {
      // Loud for its first half second only.
      final wave = Waveform.of(riff(1, 0, 0.5, 1));
      // Where the sound is drawn, in px of a 400 px lane 4 s long, its span
      // from 2 s to 3 s.
      (double, double) drawn(List<double>? rates) {
        final canvas = _Recording();
        WavePainter(
          wave: wave,
          length: const Duration(seconds: 4),
          spans: [
            (
              at: const Duration(seconds: 2),
              end: const Duration(seconds: 3),
              from: Duration.zero,
            ),
          ],
          rates: rates,
          start: Duration.zero,
          end: const Duration(seconds: 4),
          color: Colors.white,
        ).paint(canvas, const Size(400, 40));
        final bounds = canvas.paths.first.getBounds();
        return (bounds.left, bounds.right);
      }

      // As it is: its loud half second over the span's first half.
      final (left, right) = drawn(null);
      expect(left, closeTo(200, 1));
      expect(right, closeTo(250, 1));
      // A take of the song at 0.5× (rate 2: two of the take's seconds in
      // each of the song's): its loud half second in a quarter of the
      // song's.
      final (slowLeft, slowRight) = drawn(const [2]);
      expect(slowLeft, closeTo(200, 1));
      expect(slowRight, closeTo(225, 1));
      // At 2× (rate 0.5): its loud half second over the whole span.
      final (fastLeft, fastRight) = drawn(const [0.5]);
      expect(fastLeft, closeTo(200, 1));
      expect(fastRight, closeTo(300, 1));
    },
  );

  group('WaveCache', () {
    setUp(WaveCache.clear);
    tearDown(WaveCache.clear);
    final wave = Waveform(Float32List.fromList([0.5]));

    test('reads a file once, ready once read', () async {
      var reads = 0;
      Future<Waveform?> read() async {
        reads++;
        return wave;
      }

      expect(WaveCache.ready('a'), isNull);
      final first = WaveCache.of('a', read);
      final second = WaveCache.of('a', read);
      expect(await first, wave);
      expect(await second, wave);
      expect(reads, 1);
      expect(WaveCache.ready('a'), wave);
    });

    test('keeps the last six asked for', () async {
      var reads = 0;
      Future<Waveform?> read() async {
        reads++;
        return wave;
      }

      for (var i = 0; i < WaveCache.size + 1; i++) {
        await WaveCache.of('f$i', read);
      }
      expect(reads, WaveCache.size + 1);
      // The first, asked for longest ago, is gone; the last six aren't.
      expect(WaveCache.ready('f0'), isNull);
      expect(WaveCache.ready('f${WaveCache.size}'), wave);
      await WaveCache.of('f0', read);
      expect(reads, WaveCache.size + 2);
      await WaveCache.of('f${WaveCache.size}', read);
      expect(reads, WaveCache.size + 2);
    });

    test('a read that fails is none, and isn\'t tried again', () async {
      var reads = 0;
      Future<Waveform?> read() async {
        reads++;
        throw StateError('no file');
      }

      expect(await WaveCache.of('x', read), isNull);
      expect(await WaveCache.of('x', read), isNull);
      expect(reads, 1);
    });
  });
}

/// A canvas that keeps the paths drawn on it, its clip the whole lane.
class _Recording implements Canvas {
  final paths = <Path>[];

  @override
  void drawPath(Path path, Paint paint) => paths.add(path);

  @override
  Rect getLocalClipBounds() => const Rect.fromLTWH(0, 0, 400, 40);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
