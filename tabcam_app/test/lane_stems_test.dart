import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/stem_split.dart';
import 'package:tabcam_app/capture/video_edit.dart';

Duration s(double seconds) => Duration(milliseconds: (seconds * 1000).round());

PageEdit _read(Map<String, Object?> json) =>
    PageEdit.fromJson(jsonDecode(jsonEncode(json)))!;

void main() {
  group('LaneStems', () {
    test('not split by default: nothing for the renderers', () {
      expect(LaneStems.none.split, isFalse);
      expect(LaneStems.none.changes, isFalse);
      expect(LaneStems.none.gains, isNull);
    });

    test('split with every instrument as it is changes nothing', () {
      expect(LaneStems.all.split, isTrue);
      expect(LaneStems.all.changes, isFalse);
      expect(LaneStems.all.gains, isNull);
      expect(LaneStems.all.toJson(), isEmpty);
    });

    test('an instrument muted or turned down gives every gain, muted at 0', () {
      final stems = LaneStems.all
          .withLevel(Stem.vocals, const StemLevel(muted: true))
          .withLevel(Stem.bass, const StemLevel(volume: 0.5));
      expect(stems.changes, isTrue);
      expect(stems.gains, {'vocals': 0, 'drums': 1, 'bass': 0.5, 'other': 1});
      expect(stems.toJson(), {
        'vocals': {'muted': true},
        'bass': {'volume': 0.5},
      });
      // Put back as it is: left out again.
      final back = stems.withLevel(Stem.vocals, StemLevel.full);
      expect(back.levels.keys, ['bass']);
    });

    test('muting keeps the level', () {
      final stems = LaneStems.all.withLevel(
        Stem.drums,
        const StemLevel(volume: 0.3, muted: true),
      );
      expect(stems.of(Stem.drums).gain, 0);
      expect(LaneStems.fromJson(stems.toJson()).of(Stem.drums).volume, 0.3);
    });

    test('read: levels brought within range, a newer app\'s instrument '
        'kept, anything else not split', () {
      final read = LaneStems.fromJson({
        'vocals': {'volume': 3},
        'bass': {'volume': -1, 'muted': true},
        'drums': {'volume': 'loud'},
        'guitar': {'volume': 0.25},
        'other': 7,
      });
      expect(read.split, isTrue);
      expect(read.of(Stem.vocals), StemLevel.full);
      expect(read.of(Stem.bass), const StemLevel(volume: 0, muted: true));
      expect(read.of(Stem.drums), StemLevel.full);
      expect(read.of(Stem.other), StemLevel.full);
      expect(read.toJson()['guitar'], {'volume': 0.25});
      expect(LaneStems.fromJson(null), LaneStems.none);
      expect(LaneStems.fromJson('yes'), LaneStems.none);
    });
  });

  group('an edit\'s instruments', () {
    final edit = PageEdit(start: s(1), end: s(9));

    test('are written only when split, and read back', () {
      expect(edit.toJson().containsKey('ownStems'), isFalse);
      expect(edit.toJson().containsKey('songStems'), isFalse);
      final split = edit.copyWith(
        ownStems: LaneStems.all,
        songStems: LaneStems.all.withLevel(
          Stem.other,
          const StemLevel(volume: 0.4),
        ),
      );
      final json = split.toJson();
      expect(json['ownStems'], isEmpty);
      expect(json['songStems'], {
        'other': {'volume': 0.4},
      });
      expect(_read(json), split);
      expect(split, isNot(edit));
    });

    test('an edit before them isn\'t split', () {
      final read = _read({'v': 2, 'startMs': 0, 'endMs': 5000});
      expect(read.ownStems, LaneStems.none);
      expect(read.songStems, LaneStems.none);
    });
  });

  group('the plan', () {
    final video = XFile('/tmp/made-up-take.mp4');
    final riff = XFile('/tmp/made-up-riff.m4a');
    RenderPlan plan(PageEdit edit) => RenderPlan.of(
      edit,
      input: video,
      duration: s(10),
      inputExtension: 'mp4',
      songFile: riff,
      songLength: s(30),
    );

    test('gives the renderers a lane\'s instruments only when they change '
        'its sound', () {
      final edit = PageEdit(
        start: Duration.zero,
        end: s(10),
        trackId: 'k1',
        song: SongMode.manual,
        ownStems: LaneStems.all,
        songStems: LaneStems.all.withLevel(
          Stem.vocals,
          const StemLevel(muted: true),
        ),
      );
      final p = plan(edit);
      expect(p.own!.stems, LaneStems.all);
      expect(p.own!.asRecorded, isTrue);
      expect(p.song!.asRecorded, isFalse);
      final channel = p.toChannel(output: '/tmp/out.mp4');
      expect((channel['own']! as Map).containsKey('stems'), isFalse);
      expect((channel['song']! as Map)['stems'], {
        'vocals': 0.0,
        'drums': 1.0,
        'bass': 1.0,
        'other': 1.0,
        'bassHz': StemSplit.bassHz,
        'drumsHz': StemSplit.drumsHz,
      });
    });

    test('a video whose own instruments change is made again, not saved '
        'as it is', () {
      final whole = PageEdit(
        start: Duration.zero,
        end: s(10),
        fadeIn: Duration.zero,
        fadeOut: Duration.zero,
      );
      expect(plan(whole.copyWith(ownStems: LaneStems.all)).passthrough, isTrue);
      expect(
        plan(
          whole.copyWith(
            ownStems: LaneStems.all.withLevel(
              Stem.drums,
              const StemLevel(volume: 0.5),
            ),
          ),
        ).passthrough,
        isFalse,
      );
    });
  });

  group('StemSplit', () {
    const rate = 44100;

    /// A second of a tone at [hz], 0.5 high.
    Float64List tone(double hz, {double sign = 1}) => Float64List.fromList([
      for (var i = 0; i < rate; i++) sign * 0.5 * sin(2 * pi * hz * i / rate),
    ]);

    /// How loud [x] is over its last tenth (the filters settled).
    double rms(Float64List x) {
      final from = x.length * 9 ~/ 10;
      var sum = 0.0;
      for (var i = from; i < x.length; i++) {
        sum += x[i] * x[i];
      }
      return sqrt(sum / (x.length - from));
    }

    final full = 0.5 / sqrt2;

    /// A tone in the middle of the mix (both sides alike), split and put
    /// back with [gains]: how loud its left is.
    double middle(double hz, Map<String, double> gains) =>
        rms(StemSplit.apply([tone(hz), tone(hz)], rate, gains)[0]);

    /// A tone at the sides (the right its opposite).
    double sides(double hz, Map<String, double> gains) =>
        rms(StemSplit.apply([tone(hz), tone(hz, sign: -1)], rate, gains)[0]);

    test('every instrument as it is: as loud as it was, at every pitch', () {
      for (final hz in <double>[50, 200, 1000, 4000, 12000]) {
        expect(middle(hz, {}), closeTo(full, full * 0.02), reason: '$hz Hz');
        expect(sides(hz, {}), closeTo(full, full * 0.02), reason: '$hz Hz');
      }
    });

    test('the bass muted takes the lows away, and leaves the rest', () {
      expect(middle(60, {'bass': 0}), lessThan(full * 0.02));
      expect(middle(1000, {'bass': 0}), closeTo(full, full * 0.02));
    });

    test('the drums muted take the highs away', () {
      expect(middle(12000, {'drums': 0}), lessThan(full * 0.03));
      expect(middle(1000, {'drums': 0}), closeTo(full, full * 0.02));
    });

    test('the vocals are the middle band\'s middle, the rest its sides', () {
      expect(middle(1000, {'vocals': 0}), lessThan(full * 0.02));
      expect(sides(1000, {'vocals': 0}), closeTo(full, full * 0.02));
      expect(sides(1000, {'other': 0}), lessThan(full * 0.02));
      expect(middle(1000, {'other': 0}), closeTo(full, full * 0.02));
      // Half the vocals: half as loud.
      expect(middle(1000, {'vocals': 0.5}), closeTo(full / 2, full * 0.02));
    });

    test('a one-channel sound\'s middle band is all vocals', () {
      double mono(Map<String, double> gains) =>
          rms(StemSplit.apply([tone(1000)], rate, gains)[0]);
      expect(mono({'other': 0}), closeTo(full, full * 0.02));
      expect(mono({'vocals': 0}), lessThan(full * 0.02));
    });

    test('the filters pass what they should at their ends', () {
      // A low-pass passes 0 Hz whole; a high-pass, half the rate.
      final [b0, b1, b2, a1, a2] = StemSplit.coefficients(
        BiquadKind.lowPass,
        StemSplit.bassHz,
        rate,
      );
      expect((b0 + b1 + b2) / (1 + a1 + a2), closeTo(1, 1e-9));
      final [h0, h1, h2, ha1, ha2] = StemSplit.coefficients(
        BiquadKind.highPass,
        StemSplit.drumsHz,
        rate,
      );
      expect((h0 - h1 + h2) / (1 - ha1 + ha2), closeTo(1, 1e-9));
    });
  });
}
