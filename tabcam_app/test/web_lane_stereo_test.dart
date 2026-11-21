@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/edit_formats.dart';
import 'package:tabcam_app/capture/video_edit.dart';
import 'package:tabcam_app/capture/web_video_editor.dart';
import 'package:web/web.dart' as web;

/// A lane's channels and balance in the browser's offline mix
/// (`bash scripts/test-browser.sh test/web_lane_stereo_test.dart`): a
/// made-up tone recorded on the left only, its left put on both sides;
/// panned; and a one-channel sound panned.
void main() {
  const rate = 44100;
  const second = Duration(seconds: 1);

  Float32List tone() => Float32List.fromList([
    for (var i = 0; i < rate; i++) 0.5 * sin(2 * pi * 440 * i / rate),
  ]);

  XFile wav(List<Float32List> channels) => XFile.fromData(
    wavBytes(channels, rate),
    name: 'made-up.wav',
    mimeType: 'audio/wav',
  );

  Future<web.AudioBuffer> render(XFile input, LaneStereo stereo) async {
    final file = await WebVideoEditor(soundWay: WebSoundWay.wav).render(
      RenderPlan.of(
        PageEdit(
          start: Duration.zero,
          end: second,
          ownStereo: stereo,
          fadeIn: Duration.zero,
          fadeOut: Duration.zero,
        ),
        input: input,
        duration: second,
        inputExtension: 'wav',
        kind: RenderKind.sound,
      ),
    );
    final audio = web.AudioContext();
    try {
      return await audio
          .decodeAudioData((await file.readAsBytes()).buffer.toJS)
          .toDart;
    } finally {
      await audio.close().toDart;
    }
  }

  double loudest(web.AudioBuffer buffer, int channel) {
    final samples = buffer.getChannelData(channel).toDart;
    var most = 0.0;
    // Past the start and before the end.
    for (var i = 2000; i < samples.length - 2000; i++) {
      most = max(most, samples[i].abs());
    }
    return most;
  }

  testWidgets('the left on both sides, a balance, and a one-channel sound', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final leftOnly = wav([tone(), Float32List(rate)]);

      final asIs = await render(leftOnly, LaneStereo.standard);
      expect(asIs.numberOfChannels, 2);
      expect(loudest(asIs, 0), closeTo(0.5, 0.02));
      expect(loudest(asIs, 1), lessThan(0.001));

      final both = await render(
        leftOnly,
        const LaneStereo(channels: LaneChannels.left),
      );
      expect(both.numberOfChannels, 2);
      expect(loudest(both, 0), closeTo(0.5, 0.02));
      expect(loudest(both, 1), closeTo(0.5, 0.02));

      final leaning = await render(
        leftOnly,
        const LaneStereo(channels: LaneChannels.left, balance: 0.5),
      );
      expect(loudest(leaning, 0), closeTo(0.25, 0.02));
      expect(loudest(leaning, 1), closeTo(0.5, 0.02));

      final mono = await render(wav([tone()]), const LaneStereo(balance: 1));
      expect(mono.numberOfChannels, 2);
      expect(loudest(mono, 0), lessThan(0.001));
      expect(loudest(mono, 1), closeTo(0.5, 0.02));
    });
  });
}
