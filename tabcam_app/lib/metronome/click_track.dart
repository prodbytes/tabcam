/// What the metronome plays: time signatures, which clicks are accented,
/// and the clicks themselves as sound (a WAV of whole bars, for the phones;
/// the web plays the same clicks with Web Audio).
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// How strongly a click sounds: the bar's first beat, the first beat of a
/// group (compound and odd meters: 6/8's second half), or any other beat.
enum Accent {
  bar(1760, 1.0),
  group(1320, 0.8),
  beat(880, 0.6);

  const Accent(this.hertz, this.volume);

  /// The click's pitch.
  final double hertz;

  /// Its loudness, 0 to 1.
  final double volume;
}

/// A time signature: [beats] clicks a bar, each a [unit] note (4: a
/// quarter, 8: an eighth). The metronome clicks every [unit] note at its
/// BPM, the bar's first accented, and in eighth-note meters the first of
/// each group of [groups].
class TimeSignature {
  const TimeSignature(this.beats, this.unit, [this.groups = const []]);

  final int beats;
  final int unit;

  /// The groups' sizes (6/8: 3 + 3), when it has groups.
  final List<int> groups;

  static const twoFour = TimeSignature(2, 4);
  static const threeFour = TimeSignature(3, 4);
  static const fourFour = TimeSignature(4, 4);
  static const fiveFour = TimeSignature(5, 4);
  static const sixEight = TimeSignature(6, 8, [3, 3]);
  static const sevenEight = TimeSignature(7, 8, [2, 2, 3]);
  static const nineEight = TimeSignature(9, 8, [3, 3, 3]);
  static const twelveEight = TimeSignature(12, 8, [3, 3, 3, 3]);

  /// The ones the metronome offers, the most common.
  static const common = [
    twoFour,
    threeFour,
    fourFour,
    fiveFour,
    sixEight,
    sevenEight,
    nineEight,
    twelveEight,
  ];

  /// "4/4".
  String get label => '$beats/$unit';

  /// The common signature [label] names, or null.
  static TimeSignature? byLabel(String? label) =>
      common.where((s) => s.label == label).firstOrNull;

  /// Each click's accent, the bar's first [Accent.bar].
  List<Accent> get accents {
    final starts = <int>{};
    var at = 0;
    for (final g in groups) {
      starts.add(at);
      at += g;
    }
    return [
      for (var i = 0; i < beats; i++)
        i == 0
            ? Accent.bar
            : starts.contains(i)
            ? Accent.group
            : Accent.beat,
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is TimeSignature && other.beats == beats && other.unit == unit;

  @override
  int get hashCode => Object.hash(beats, unit);

  @override
  String toString() => label;
}

/// A click: a short tone that dies away fast, as a metronome's.
const clickLength = Duration(milliseconds: 40);

/// One click's samples (-1 to 1) at [rate] samples a second.
Float64List clickSamples(Accent accent, int rate) {
  final n = rate * clickLength.inMicroseconds ~/ 1000000;
  final samples = Float64List(n);
  for (var i = 0; i < n; i++) {
    final t = i / rate;
    // A quick fade in (no pop), then an exponential decay.
    final attack = math.min(1.0, i / (rate * 0.001));
    final decay = math.exp(-t * 90);
    samples[i] =
        accent.volume *
        attack *
        decay *
        math.sin(2 * math.pi * accent.hertz * t);
  }
  return samples;
}

/// How long one click lasts at [bpm]: a minute over [bpm].
Duration beatLength(int bpm) => Duration(microseconds: 60000000 ~/ bpm);

/// A WAV (16-bit mono PCM at [rate]) of whole bars of [signature] at
/// [bpm], at least [least] long, to loop: every bar starts with its
/// accented click, so the loop's seam falls between bars.
Uint8List clickTrackWav({
  required int bpm,
  required TimeSignature signature,
  Duration least = const Duration(seconds: 20),
  int rate = 22050,
}) {
  final beatSamples = rate * 60 / bpm;
  final barSamples = beatSamples * signature.beats;
  final bars = math.max(
    1,
    (least.inMicroseconds / 1e6 * rate / barSamples).ceil(),
  );
  final total = (barSamples * bars).round();
  final pcm = Int16List(total);
  final clicks = {for (final a in Accent.values) a: clickSamples(a, rate)};
  final accents = signature.accents;
  for (var bar = 0; bar < bars; bar++) {
    for (var beat = 0; beat < signature.beats; beat++) {
      final start = ((bar * signature.beats + beat) * beatSamples).round();
      final click = clicks[accents[beat]]!;
      for (var i = 0; i < click.length && start + i < total; i++) {
        pcm[start + i] = (click[i] * 32767).round().clamp(-32768, 32767);
      }
    }
  }
  return _wav(pcm, rate);
}

Uint8List _wav(Int16List pcm, int rate) {
  final data = pcm.lengthInBytes;
  final out = ByteData(44 + data);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      out.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  out.setUint32(4, 36 + data, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  out.setUint32(16, 16, Endian.little); // the fmt chunk's size
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, 1, Endian.little); // mono
  out.setUint32(24, rate, Endian.little);
  out.setUint32(28, rate * 2, Endian.little); // bytes a second
  out.setUint16(32, 2, Endian.little); // bytes a sample
  out.setUint16(34, 16, Endian.little); // bits a sample
  ascii(36, 'data');
  out.setUint32(40, data, Endian.little);
  final bytes = out.buffer.asUint8List();
  bytes.setRange(
    44,
    44 + data,
    pcm.buffer.asUint8List(pcm.offsetInBytes, data),
  );
  return bytes;
}
