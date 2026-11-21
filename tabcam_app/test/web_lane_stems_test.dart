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

/// A lane split into its instruments in the browser's offline mix
/// (`bash scripts/test-browser.sh test/web_lane_stems_test.dart`): made-up
/// tones, low and in the middle of the mix, or in the middle band at its
/// sides, each taken away when its instrument is muted, the rest left as
/// it is; and a one-channel sound, whose middle band is all vocals.
void main() {
  const rate = 44100;
  const second = Duration(seconds: 1);

  Float32List tone(double hz, {double sign = 1}) => Float32List.fromList([
    for (var i = 0; i < rate; i++) sign * 0.5 * sin(2 * pi * hz * i / rate),
  ]);

  XFile wav(List<Float32List> channels) => XFile.fromData(
    wavBytes(channels, rate),
    name: 'made-up.wav',
    mimeType: 'audio/wav',
  );

  Future<web.AudioBuffer> render(XFile input, LaneStems stems) async {
    final file = await WebVideoEditor(soundWay: WebSoundWay.wav).render(
      RenderPlan.of(
        PageEdit(
          start: Duration.zero,
          end: second,
          ownStems: stems,
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

  /// The loudest sample of [channel] over its second half (the filters
  /// settled), before its very end.
  double loudest(web.AudioBuffer buffer, int channel) {
    final samples = buffer.getChannelData(channel).toDart;
    var most = 0.0;
    for (var i = samples.length ~/ 2; i < samples.length - 2000; i++) {
      most = max(most, samples[i].abs());
    }
    return most;
  }

  LaneStems muted(Stem stem) =>
      LaneStems.all.withLevel(stem, const StemLevel(muted: true));

  testWidgets('each instrument muted takes its part away', (tester) async {
    await tester.runAsync(() async {
      final low = wav([tone(60), tone(60)]);
      final middle = wav([tone(1000), tone(1000)]);
      final sides = wav([tone(1000), tone(1000, sign: -1)]);

      // Split, all as they are: the sound as it is.
      final asIs = await render(middle, LaneStems.all);
      expect(asIs.numberOfChannels, 2);
      expect(loudest(asIs, 0), closeTo(0.5, 0.02));

      final noBass = await render(low, muted(Stem.bass));
      expect(noBass.numberOfChannels, 2);
      expect(loudest(noBass, 0), lessThan(0.02));
      expect(loudest(noBass, 1), lessThan(0.02));
      expect(
        loudest(await render(middle, muted(Stem.bass)), 0),
        closeTo(0.5, 0.02),
      );

      final noVocals = await render(middle, muted(Stem.vocals));
      expect(loudest(noVocals, 0), lessThan(0.02));
      expect(loudest(noVocals, 1), lessThan(0.02));
      final sidesKept = await render(sides, muted(Stem.vocals));
      expect(loudest(sidesKept, 0), closeTo(0.5, 0.02));
      expect(loudest(sidesKept, 1), closeTo(0.5, 0.02));

      final noOther = await render(sides, muted(Stem.other));
      expect(loudest(noOther, 0), lessThan(0.02));
      expect(
        loudest(await render(middle, muted(Stem.other)), 0),
        closeTo(0.5, 0.02),
      );

      final mono = wav([tone(1000)]);
      expect(
        loudest(await render(mono, muted(Stem.other)), 0),
        closeTo(0.5, 0.02),
      );
      expect(
        loudest(await render(mono, muted(Stem.vocals)), 0),
        lessThan(0.02),
      );
    });
  });
}
