import 'dart:math';
import 'dart:typed_data';

import '../library/page_edit.dart';

/// How a lane's sound is split into its instruments ([Stem]) for now: a
/// rough split by pitch and by place in the mix, not a model that knows
/// the instruments (that comes later; the edit's levels stay as they are).
///
/// Each channel goes through a three-band crossover (Linkwitz-Riley, 24 dB
/// an octave): **the bass** under [bassHz], **the drums** over [drumsHz],
/// and the band between them split by where it sits in the mix: **the
/// vocals** its middle (what both channels have alike, `(L + R) / 2` on
/// both sides), **the rest** its sides (`(L − R) / 2`, the left's, and its
/// opposite on the right). The four add up to the sound as it was, through
/// two all-pass filters (its phase turned at the crossovers, not its
/// level), so a split lane with every instrument as it is sounds as it
/// did; the renderers don't process it at all then (`LaneStems.gains`).
/// A one-channel sound has no sides: its middle band is all vocals.
///
/// Every renderer does the same, from the same numbers (the channel's
/// `stems`, [toChannel]): the web's offline mix with Web Audio's IIR
/// filters on [coefficients], Android's `StemsProcessor`
/// (`VideoEdit.kt`) and iOS's tap (`AppDelegate.swift`), each a copy of
/// [apply].
abstract final class StemSplit {
  /// Where the bass ends and the middle band starts.
  static const bassHz = 200.0;

  /// Where the middle band ends and the drums start.
  static const drumsHz = 4000.0;

  /// Each filter's Q: a Butterworth's, two in a row making a
  /// Linkwitz-Riley's.
  static const q = 0.7071067811865476;

  /// The renderers' `stems`: each instrument's gain by its name ([gains],
  /// `LaneStems.gains`) and the crossover's frequencies.
  static Map<String, Object?> toChannel(Map<String, double> gains) => {
    ...gains,
    'bassHz': bassHz,
    'drumsHz': drumsHz,
  };

  /// A low-pass, high-pass or all-pass biquad at [hz] for [rate] samples a
  /// second (the Audio EQ Cookbook's, Q [q]), as `[b0, b1, b2, a1, a2]`,
  /// divided by `a0`.
  static List<double> coefficients(BiquadKind kind, double hz, num rate) {
    final w = 2 * pi * min(hz, rate * 0.45) / rate;
    final cosW = cos(w);
    final alpha = sin(w) / (2 * q);
    final a0 = 1 + alpha;
    final (b0, b1, b2) = switch (kind) {
      BiquadKind.lowPass => ((1 - cosW) / 2, 1 - cosW, (1 - cosW) / 2),
      BiquadKind.highPass => ((1 + cosW) / 2, -(1 + cosW), (1 + cosW) / 2),
      BiquadKind.allPass => (1 - alpha, -2 * cosW, 1 + alpha),
    };
    return [b0 / a0, b1 / a0, b2 / a0, -2 * cosW / a0, (1 - alpha) / a0];
  }

  /// The filters of each band, in the order the sound goes through them:
  /// the bass (two low-passes at [bassHz], and an all-pass at [drumsHz],
  /// so it turns as the rest does there); the rest above the bass (two
  /// high-passes at [bassHz]), then, from it, the middle band (two
  /// low-passes at [drumsHz]) and the drums (two high-passes at
  /// [drumsHz]).
  static ({
    List<List<double>> bass,
    List<List<double>> above,
    List<List<double>> middle,
    List<List<double>> drums,
  })
  bands(num rate) {
    final low = coefficients(BiquadKind.lowPass, bassHz, rate);
    final high = coefficients(BiquadKind.highPass, bassHz, rate);
    final midLow = coefficients(BiquadKind.lowPass, drumsHz, rate);
    final midHigh = coefficients(BiquadKind.highPass, drumsHz, rate);
    return (
      bass: [low, low, coefficients(BiquadKind.allPass, drumsHz, rate)],
      above: [high, high],
      middle: [midLow, midLow],
      drums: [midHigh, midHigh],
    );
  }

  /// [channels] (one or two, [rate] samples a second) split and put back
  /// together with each instrument at its gain in [gains] (by its name;
  /// one left out at 1), as the renderers do it.
  static List<Float64List> apply(
    List<Float64List> channels,
    num rate,
    Map<String, double> gains,
  ) {
    double gain(Stem s) => gains[s.name] ?? 1;
    final bass = gain(Stem.bass);
    final drums = gain(Stem.drums);
    final vocals = gain(Stem.vocals);
    final other = gain(Stem.other);
    final split = [for (final c in channels) _Bands(rate)..run(c)];
    if (channels.length != 2) {
      return [
        for (final b in split)
          Float64List.fromList([
            for (var i = 0; i < b.bass.length; i++)
              bass * b.bass[i] + drums * b.drums[i] + vocals * b.middle[i],
          ]),
      ];
    }
    // The middle band: its middle the vocals', its sides the rest's.
    final same = (vocals + other) / 2;
    final cross = (vocals - other) / 2;
    final [l, r] = split;
    final n = l.bass.length;
    final left = Float64List(n);
    final right = Float64List(n);
    for (var i = 0; i < n; i++) {
      left[i] =
          bass * l.bass[i] +
          drums * l.drums[i] +
          same * l.middle[i] +
          cross * r.middle[i];
      right[i] =
          bass * r.bass[i] +
          drums * r.drums[i] +
          cross * l.middle[i] +
          same * r.middle[i];
    }
    return [left, right];
  }
}

/// A biquad's kind ([StemSplit.coefficients]).
enum BiquadKind { lowPass, highPass, allPass }

/// One channel through [StemSplit.bands]: its three bands.
class _Bands {
  _Bands(num rate) : _filters = StemSplit.bands(rate);

  final ({
    List<List<double>> bass,
    List<List<double>> above,
    List<List<double>> middle,
    List<List<double>> drums,
  })
  _filters;

  late Float64List bass, middle, drums;

  void run(Float64List x) {
    bass = _through(_filters.bass, x);
    final above = _through(_filters.above, x);
    middle = _through(_filters.middle, above);
    drums = _through(_filters.drums, above);
  }

  /// [x] through [filters], one after another (transposed direct form II,
  /// in doubles, as the renderers do).
  static Float64List _through(List<List<double>> filters, Float64List x) {
    var y = x;
    for (final [b0, b1, b2, a1, a2] in filters) {
      final out = Float64List(y.length);
      var z1 = 0.0, z2 = 0.0;
      for (var i = 0; i < y.length; i++) {
        final v = y[i];
        final o = b0 * v + z1;
        z1 = b1 * v - a1 * o + z2;
        z2 = b2 * v - a2 * o;
        out[i] = o;
      }
      y = out;
    }
    return y;
  }
}
