import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/screens/tab_text_view.dart';
import 'package:tabcam_app/sound/ding_sound.dart';

/// Rescan's ding, made in the app: soft, no click at either end, and a WAV
/// file the phones can play. And the time Rescan shows.
void main() {
  test('the ding is soft and starts and ends at silence', () {
    final samples = dingSamples(44100);
    expect(samples.length, 44100 * 7 ~/ 10);
    final peak = samples.map((s) => s.abs()).reduce((a, b) => a > b ? a : b);
    expect(peak, lessThanOrEqualTo(dingPeak));
    expect(peak, greaterThan(dingPeak / 2)); // it's heard
    expect(samples.first, 0);
    expect(samples.last.abs(), lessThan(1e-6));
  });

  test('the ding is a 16-bit mono PCM WAV file', () {
    final wav = dingWav();
    final b = ByteData.sublistView(wav);
    String tag(int at) => String.fromCharCodes(wav.sublist(at, at + 4));
    expect(tag(0), 'RIFF');
    expect(b.getUint32(4, Endian.little), wav.length - 8);
    expect(tag(8), 'WAVE');
    expect(tag(12), 'fmt ');
    expect(b.getUint16(20, Endian.little), 1); // PCM
    expect(b.getUint16(22, Endian.little), 1); // mono
    expect(b.getUint32(24, Endian.little), 44100);
    expect(b.getUint16(34, Endian.little), 16);
    expect(tag(36), 'data');
    expect(b.getUint32(40, Endian.little), 44100 * 7 ~/ 10 * 2);
    expect(wav.length, 44 + 44100 * 7 ~/ 10 * 2);
  });

  test('elapsed time is m:ss, h:mm:ss from an hour', () {
    expect(elapsedText(Duration.zero), '0:00');
    expect(elapsedText(const Duration(milliseconds: 7900)), '0:07');
    expect(elapsedText(const Duration(minutes: 2, seconds: 5)), '2:05');
    expect(elapsedText(const Duration(minutes: 59, seconds: 59)), '59:59');
    expect(
      elapsedText(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
    expect(elapsedText(const Duration(seconds: -3)), '0:00');
  });
}
