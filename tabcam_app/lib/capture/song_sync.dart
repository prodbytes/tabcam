import 'dart:math';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

import 'sound_reader.dart';
import 'take_log.dart';

/// Finds the song played along in a take's own sound, to line the two up
/// as well as they can be: the log has where Cam noted the song playing
/// (the player's word, and the take's lag), good to a tenth of a second
/// or so; the take's microphone heard the song from the speaker, so
/// where it really is can be measured, to the millisecond, and kept with
/// the log ([TakeLog.sync]). On the device, from the files it has:
/// nothing is uploaded. See specs/cam.md, "What a take keeps".
///
/// Each of the song's longer segments is looked for on its own, in a
/// window from its middle (the song's intro may be quiet, and a clock
/// that runs a little off is then off by half as much at either end):
/// the take's sound there against the song's, by their cross-correlation
/// ([offsetOf]).
abstract final class SongSync {
  /// The sample rate the sounds are compared at: 8 kHz is plenty to tell
  /// a millisecond, and cheap.
  static const int rate = 8000;

  /// The most of a segment compared.
  static const Duration window = Duration(seconds: 12);

  /// How far either way from where the log has it the song is looked
  /// for: the lag's error, the player's, and a speaker's delay (a
  /// Bluetooth one's can be a quarter of a second).
  static const Duration reach = Duration(milliseconds: 600);

  /// The shortest segment looked for: less can match by chance.
  static const Duration shortest = Duration(seconds: 3);

  /// The most segments measured (the longest): the rest take the song's
  /// shift.
  static const int most = 6;

  /// How clearly a match must stand out to count ([SoundOffset.score]): a
  /// match by chance, over this many places, stays under 5, and a guitar
  /// in the song's key and time, without the song, under 10 or so; the
  /// song from a speaker, even well under the guitar, is over 20.
  static const double clear = 14;

  /// How many times higher than the next best place, a twentieth of a
  /// second or more away, a match must stand ([SoundOffset.lead]): one
  /// of two about as good, a beat apart, could be the wrong one.
  static const double ahead = 1.3;

  /// Tests compare on their own thread (no other runs under a fake clock).
  @visibleForTesting
  static bool inline = false;

  /// Measures where the song [log] lines up ([TakeLog.linedSong]) is in
  /// [take], whose sound is compared with [song]'s, both read with
  /// [reader]. Null when it can't be told now (a file that can't be
  /// read here: worth another try elsewhere); found in none of its
  /// segments, a sync that says so ([SyncFrom.none]). Before each
  /// segment it waits for [wait] (a take recording, which comes first).
  static Future<TakeSync?> measure({
    required TakeLog log,
    required XFile take,
    required XFile song,
    required SoundReader reader,
    Future<void> Function()? wait,
  }) async {
    final segments = [...log.linedSong]
      ..removeWhere((s) => s.to - s.at < shortest.inMilliseconds)
      ..sort((a, b) => (b.to - b.at).compareTo(a.to - a.at));
    if (segments.isEmpty) return null;
    final page = segments.first.page;
    final clips = <SyncClip>[];
    var read = false;
    for (final s in segments.take(most)) {
      await wait?.call();
      final length = s.to - s.at;
      final part = min(length, window.inMilliseconds);
      final skip = (length - part) ~/ 2;
      // Where the log has the part: in the file, and in the song.
      final inFile = log.songFileMs(s, synced: false) + skip;
      final inSong = s.from + skip;
      final from = max(0, inFile - reach.inMilliseconds);
      final heard = await reader.samples(
        take,
        from: Duration(milliseconds: from),
        length: Duration(
          milliseconds: inFile + part + reach.inMilliseconds - from,
        ),
        rate: rate,
      );
      final played = await reader.samples(
        song,
        from: Duration(milliseconds: inSong),
        length: Duration(milliseconds: part),
        rate: rate,
      );
      if (heard == null || played == null) continue;
      read = true;
      final of = (
        heard: heard,
        played: played,
        expected: (inFile - from) * rate ~/ 1000,
        reach: reach.inMilliseconds * rate ~/ 1000,
      );
      // Off the screen's thread (but on the web, which has one).
      final found = inline ? _offsetOf(of) : await compute(_offsetOf, of);
      if (found == null || found.score < clear || found.lead < ahead) continue;
      clips.add(
        SyncClip(
          at: s.at,
          ms: (found.samples * 1000 / rate).round(),
          score: (found.score * 10).round() / 10,
        ),
      );
    }
    if (!read) return null;
    if (clips.isEmpty) return TakeSync(page: page, from: SyncFrom.none);
    final shifts = [for (final c in clips) c.ms]..sort();
    clips.sort((a, b) => a.at.compareTo(b.at));
    return TakeSync(
      page: page,
      from: SyncFrom.sound,
      ms: shifts[(shifts.length - 1) ~/ 2],
      clips: List.unmodifiable(clips),
    );
  }

  static SoundOffset? _offsetOf(
    ({Float32List heard, Float32List played, int expected, int reach}) of,
  ) => offsetOf(
    of.heard,
    of.played,
    expected: of.expected,
    reach: of.reach,
    rate: rate,
  );

  /// Where [played] (the song's samples) is in [heard] (the take's),
  /// looked for within [reach] samples either way of [expected] (where
  /// its first sample would be in [heard]): how many samples later than
  /// that it is (to a fraction), and how clearly. Null when there's too
  /// little to compare, or either is silent.
  ///
  /// The generalized cross-correlation, its phase weighted (GCC-PHAT):
  /// the two spectra multiplied, each frequency's level mostly taken
  /// out, so the match is a sharp peak whatever the speaker, the room
  /// and the microphone did to the song's tone, and the guitar played
  /// over it only raises the floor. Frequencies under 100 Hz (hum, a
  /// phone's handling) and over 3.6 kHz are left out.
  static SoundOffset? offsetOf(
    Float32List heard,
    Float32List played, {
    required int expected,
    required int reach,
    int rate = SongSync.rate,
  }) {
    if (played.length < rate || heard.length < rate) return null;
    final from = max(expected - reach, -(played.length - rate));
    final to = min(expected + reach, heard.length - rate);
    if (to - from < 8) return null;
    // Long enough that nothing wraps round into the places looked at.
    final room = max(heard.length, to + played.length) + max(0, -from);
    var n = 1;
    while (n < room) {
      n <<= 1;
    }
    final (hr, hi) = (Float64List(n), Float64List(n));
    final (pr, pi) = (Float64List(n), Float64List(n));
    if (!_fill(hr, heard) || !_fill(pr, played)) return null;
    fft(hr, hi);
    fft(pr, pi);
    // heard × conj(played), each bin's level mostly taken out.
    final low = (100 * n / rate).ceil();
    final high = (min(3600, rate * 0.45) * n / rate).floor();
    for (var k = 0; k <= n ~/ 2; k++) {
      final j = k == 0 ? 0 : n - k;
      if (k < low || k > high) {
        hr[k] = hi[k] = hr[j] = hi[j] = 0;
        continue;
      }
      final re = hr[k] * pr[k] + hi[k] * pi[k];
      final im = hi[k] * pr[k] - hr[k] * pi[k];
      final level = sqrt(re * re + im * im);
      final w = level <= 0 ? 0.0 : 1 / pow(level, _whiten);
      hr[k] = re * w;
      hi[k] = im * w;
      // The other half mirrors it (the sounds are real).
      hr[j] = hr[k];
      hi[j] = -hi[k];
    }
    fft(hr, hi, inverse: true);
    // hr[d]: how well played, moved d samples on, matches heard (d under
    // 0 wraps round to the end).
    double at(int d) => hr[d < 0 ? d + n : d];
    var best = from;
    for (var d = from + 1; d <= to; d++) {
      if (at(d) > at(best)) best = d;
    }
    // At the edge of where it's looked for: the top may be further out
    // (a speaker later than any expected), so it's no match.
    if (best == from || best == to) return null;
    // The rest: how high the others stand, away from the peak.
    var (sum, squares, count) = (0.0, 0.0, 0);
    for (var d = from; d <= to; d++) {
      if ((d - best).abs() <= rate ~/ 500) continue;
      final v = at(d);
      sum += v;
      squares += v * v;
      count++;
    }
    if (count < 4) return null;
    final mean = sum / count;
    final spread = sqrt(max(0, squares / count - mean * mean));
    if (spread <= 0) return null;
    // Between samples: the top of the parabola through the peak and its
    // neighbours.
    final (a, b, c) = (at(best - 1), at(best), at(best + 1));
    final bend = a - 2 * b + c;
    final fraction = bend < 0 ? (0.5 * (a - c) / bend).clamp(-0.5, 0.5) : 0.0;
    // The next best place, away from the peak and the room's echoes of
    // it: a match that is one stands well above it; music matched with
    // other music in time with it has several about as good, a beat
    // apart.
    var next = double.negativeInfinity;
    for (var d = from; d <= to; d++) {
      if ((d - best).abs() > rate ~/ 20 && at(d) > next) next = at(d);
    }
    return SoundOffset(
      best + fraction - expected,
      (at(best) - mean) / spread,
      next <= mean ? double.infinity : (at(best) - mean) / (next - mean),
    );
  }

  /// How much of each frequency's level is taken out (1: all of it, the
  /// phase alone; 0: none, the plain cross-correlation): most of it, so
  /// a frequency the song hardly has doesn't count as much as one it's
  /// loud in.
  static const double _whiten = 0.8;

  /// [samples] into [into] (the rest zeros), its mean taken out; false
  /// when it's silent.
  static bool _fill(Float64List into, Float32List samples) {
    var sum = 0.0;
    for (final v in samples) {
      sum += v;
    }
    final mean = sum / samples.length;
    var energy = 0.0;
    for (var i = 0; i < samples.length; i++) {
      final v = samples[i] - mean;
      into[i] = v;
      energy += v * v;
    }
    return energy / samples.length > 1e-10;
  }

  /// The Fourier transform of [re] + i·[im], in place (their length a
  /// power of two); [inverse]: back again (not scaled: a peak's place
  /// and its height over the rest don't change with it).
  static void fft(Float64List re, Float64List im, {bool inverse = false}) {
    final n = re.length;
    assert(n > 0 && n & (n - 1) == 0 && im.length == n);
    // Bit-reversed order.
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final (r, m) = (re[i], im[i]);
        re[i] = re[j];
        im[i] = im[j];
        re[j] = r;
        im[j] = m;
      }
    }
    for (var size = 2; size <= n; size <<= 1) {
      final half = size >> 1;
      final angle = (inverse ? 2 : -2) * pi / size;
      final (stepR, stepI) = (cos(angle), sin(angle));
      for (var start = 0; start < n; start += size) {
        var (wr, wi) = (1.0, 0.0);
        for (var k = 0; k < half; k++) {
          final (a, b) = (start + k, start + k + half);
          final tr = re[b] * wr - im[b] * wi;
          final ti = re[b] * wi + im[b] * wr;
          re[b] = re[a] - tr;
          im[b] = im[a] - ti;
          re[a] += tr;
          im[a] += ti;
          final next = wr * stepR - wi * stepI;
          wi = wr * stepI + wi * stepR;
          wr = next;
        }
      }
    }
  }
}

/// Where a sound was found in another ([SongSync.offsetOf]): [samples]
/// later than expected (earlier when negative), and how clearly: how far
/// the match stands above the others, in their spread ([score]).
@immutable
class SoundOffset {
  const SoundOffset(this.samples, this.score, [this.lead = double.infinity]);

  final double samples;
  final double score;

  /// How many times higher the match stands than the next best place,
  /// a twentieth of a second or more away.
  final double lead;

  @override
  String toString() =>
      'SoundOffset($samples samples, score $score, lead $lead)';
}
