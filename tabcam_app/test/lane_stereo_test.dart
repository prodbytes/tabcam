import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/video_edit.dart';

Duration s(double seconds) => Duration(milliseconds: (seconds * 1000).round());

PageEdit _read(Map<String, Object?> json) =>
    PageEdit.fromJson(jsonDecode(jsonEncode(json)))!;

void main() {
  group('LaneStereo', () {
    test('as recorded, in the middle: the identity, standard', () {
      expect(LaneStereo.standard.isStandard, isTrue);
      expect(LaneStereo.standard.matrix, [1, 0, 0, 1]);
    });

    test('Left and Right put one channel on both sides; Mono both at half', () {
      expect(const LaneStereo(channels: LaneChannels.left).matrix, [
        1,
        0,
        1,
        0,
      ]);
      expect(const LaneStereo(channels: LaneChannels.right).matrix, [
        0,
        1,
        0,
        1,
      ]);
      expect(const LaneStereo(channels: LaneChannels.mono).matrix, [
        0.5,
        0.5,
        0.5,
        0.5,
      ]);
    });

    test('balance turns the other side down, in a straight line', () {
      expect(const LaneStereo(balance: -0.25).matrix, [1, 0, 0, 0.75]);
      expect(const LaneStereo(balance: 1).matrix, [0, 0, 0, 1]);
      expect(
        const LaneStereo(channels: LaneChannels.left, balance: 0.5).matrix,
        [0.5, 0, 1, 0],
      );
    });

    test('balance is kept within -1 and 1, to the hundredth', () {
      expect(LaneStereo.balanceOf(-3), -1);
      expect(LaneStereo.balanceOf(0.123), 0.12);
      expect(LaneStereo.balanceOf('left'), 0);
      expect(LaneStereo.balanceOf(double.nan), 0);
      expect(LaneChannels.byName('surround'), LaneChannels.stereo);
    });
  });

  group('an edit\'s stereo', () {
    final edit = PageEdit(start: s(1), end: s(9));

    test('is written only when not the default, and read back', () {
      final json = edit.toJson();
      for (final key in [
        'ownChannels',
        'ownBalance',
        'songChannels',
        'songBalance',
      ]) {
        expect(json.containsKey(key), isFalse, reason: key);
      }
      final changed = edit.copyWith(
        ownStereo: const LaneStereo(channels: LaneChannels.left),
        songStereo: const LaneStereo(balance: -0.3),
      );
      final written = changed.toJson();
      expect(written['ownChannels'], 'left');
      expect(written.containsKey('ownBalance'), isFalse);
      expect(written['songBalance'], -0.3);
      expect(written.containsKey('songChannels'), isFalse);
      expect(_read(written), changed);
      expect(changed, isNot(edit));
    });

    test('values that aren\'t one read as the default', () {
      final read = _read({
        ...edit.toJson(),
        'ownChannels': 'surround',
        'ownBalance': 'far left',
        'songBalance': 7,
      });
      expect(read.ownStereo, LaneStereo.standard);
      expect(read.songStereo.balance, 1);
    });

    test('an edit before it is as recorded', () {
      final read = _read({'v': 2, 'startMs': 0, 'endMs': 5000});
      expect(read.ownStereo, LaneStereo.standard);
      expect(read.songStereo, LaneStereo.standard);
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

    test('carries each lane\'s stereo, and gives the renderers its matrix '
        'only when not as recorded', () {
      final edit = PageEdit(
        start: Duration.zero,
        end: s(10),
        trackId: 'k1',
        song: SongMode.manual,
        ownStereo: const LaneStereo(channels: LaneChannels.left),
      );
      final p = plan(edit);
      expect(p.own!.stereo.channels, LaneChannels.left);
      expect(p.song!.stereo, LaneStereo.standard);
      final channel = p.toChannel(output: '/tmp/out.mp4');
      expect((channel['own']! as Map)['mix'], [1, 0, 1, 0]);
      expect((channel['song']! as Map).containsKey('mix'), isFalse);
    });

    test('a video with its own sound\'s channels changed is made again, '
        'not saved as it is', () {
      final whole = PageEdit(
        start: Duration.zero,
        end: s(10),
        fadeIn: Duration.zero,
        fadeOut: Duration.zero,
      );
      expect(plan(whole).passthrough, isTrue);
      expect(
        plan(whole.copyWith(ownStereo: const LaneStereo(balance: 0.5)))
            .passthrough,
        isFalse,
      );
    });
  });
}
