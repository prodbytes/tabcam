import 'dart:math' as math;
import 'dart:typed_data';

/// How long the ding lasts.
const dingDuration = Duration(milliseconds: 700);

/// How loud the ding gets at most (1 is full scale): soft, not an alarm.
const dingPeak = 0.3;

/// The ding's partials: (frequency in Hz, share of the sound, how fast it
/// dies away per second). A bell-like E6, its octave, and a fainter,
/// slightly off partial (2.76 times) that makes it ring like a bell. The
/// shares add up to 1, so the sound never goes past [dingPeak].
const _partials = [
  (1318.51, 0.7, 5.0),
  (2637.02, 0.2, 8.0),
  (3639.0, 0.1, 14.0),
];

/// The ding, as samples from −1 to 1 at [sampleRate]: made here, so it's
/// the same sound on every device and ships with no file. It rises in 5 ms
/// (no click) and fades out over its last 30 ms (no cut).
Float32List dingSamples(int sampleRate) {
  final n = sampleRate * dingDuration.inMilliseconds ~/ 1000;
  final attack = sampleRate * 5 ~/ 1000;
  final release = sampleRate * 30 ~/ 1000;
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    var v = 0.0;
    for (final (frequency, share, decay) in _partials) {
      v += share * math.exp(-decay * t) * math.sin(2 * math.pi * frequency * t);
    }
    final ramp = math.min(1.0, math.min(i / attack, (n - 1 - i) / release));
    out[i] = v * ramp * dingPeak;
  }
  return out;
}

/// [samples] (from −1 to 1) as a WAV file: 16-bit PCM, mono, at
/// [sampleRate].
Uint8List wavFile(Float32List samples, int sampleRate) {
  const le = Endian.little;
  final size = samples.length * 2;
  final b = ByteData(44 + size);
  void tag(int at, String name) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(at + i, name.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + size, le);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, le); // the format's size
  b.setUint16(20, 1, le); // PCM
  b.setUint16(22, 1, le); // mono
  b.setUint32(24, sampleRate, le);
  b.setUint32(28, sampleRate * 2, le); // bytes a second
  b.setUint16(32, 2, le); // bytes a sample
  b.setUint16(34, 16, le); // bits a sample
  tag(36, 'data');
  b.setUint32(40, size, le);
  for (var i = 0; i < samples.length; i++) {
    b.setInt16(44 + 2 * i, (samples[i].clamp(-1.0, 1.0) * 32767).round(), le);
  }
  return b.buffer.asUint8List();
}

/// The ding as a WAV file at 44.1 kHz, for the phones' players.
Uint8List dingWav() => wavFile(dingSamples(44100), 44100);
