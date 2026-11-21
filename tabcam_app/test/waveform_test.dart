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
}
