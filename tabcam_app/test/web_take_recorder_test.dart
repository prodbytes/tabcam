@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/web_take_recorder.dart';
import 'package:web/web.dart' as web;

/// The browser recorder, in a real browser (`flutter test --platform
/// chrome`): a fake camera (a canvas's stream in a `<video>`, inside a
/// platform view as camera_web's is) is recorded as it comes, nothing
/// drawn over it.
void main() {
  testWidgets('a take is the camera as it comes, as a video file: no tab '
      'drawn in', (tester) async {
    await tester.runAsync(() async {
      // The "camera": a canvas that changes colour, streamed to a video.
      final source =
          web.document.createElement('canvas') as web.HTMLCanvasElement
            ..width = 320
            ..height = 240;
      final paint = source.getContext('2d') as web.CanvasRenderingContext2D;
      var n = 0;
      final timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
        paint.fillStyle = 'hsl(${(n++ * 10) % 360}, 80%, 50%)'.toJS;
        paint.fillRect(0, 0, 320, 240);
      });
      final view = web.document.createElement('flt-platform-view');
      final video = web.document.createElement('video') as web.HTMLVideoElement
        ..muted = true
        ..autoplay = true
        ..srcObject = source.captureStream(30);
      view.append(video);
      web.document.body!.append(view);
      // Gone however the test ends, so the next sees no camera.
      addTearDown(() => view.remove());
      await video.play().toDart;
      while (video.videoWidth == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      // The "microphone", through the recorder's own seam: what it was
      // asked for is kept. (It gives no track: a test's page can't make
      // sound without a tap, and a silent track holds the recording up.)
      final asked = <Object?>[];
      final recorder = WebTakeRecorder(
        getUserMedia: (constraints) async {
          asked.add(constraints.audio.dartify());
          return web.MediaStream();
        },
      );
      // Opened when Cam opens, once, without the processing for calls.
      await recorder.prepare();
      expect(asked, hasLength(1));
      final mic = asked.single as Map;
      expect(mic['echoCancellation'], isFalse);
      expect(mic['noiseSuppression'], isFalse);
      expect(mic['autoGainControl'], isFalse);
      expect(recorder.msSinceStart(), isNull);
      await recorder.start();
      // Back once it records: how long ago it started, the take's lag.
      final since = recorder.msSinceStart();
      expect(since, isNotNull);
      expect(since, inInclusiveRange(0, 1000));
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      final take = await recorder.stop();
      // Its microphone had no live track, so the take asked again, the
      // same way.
      expect(asked, hasLength(2));
      expect(asked.last, asked.first);
      recorder.dispose();
      timer.cancel();
      view.remove();

      expect(take.mimeType, anyOf('video/webm', 'video/mp4'));
      final bytes = await take.readAsBytes();
      expect(bytes.length, greaterThan(1000));

      // Played back: the frame is the camera's, one colour, top to bottom
      // (no band darkens its bottom: the tab is kept apart, in the take's
      // log, and the editor draws it).
      final url = web.URL.createObjectURL(
        web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: take.mimeType!)),
      );
      final playback =
          web.document.createElement('video') as web.HTMLVideoElement
            ..muted = true
            ..src = url;
      final loaded = Completer<void>();
      playback.onloadeddata = ((web.Event _) => loaded.complete()).toJS;
      await loaded.future;
      // Frames as it plays (the first may still be dark while the
      // decoder starts): the first lit one is looked at.
      await playback.play().toDart;
      final frame =
          web.document.createElement('canvas') as web.HTMLCanvasElement
            ..width = playback.videoWidth
            ..height = playback.videoHeight;
      final grab = frame.getContext('2d') as web.CanvasRenderingContext2D;
      double brightness(double y) {
        final d = grab.getImageData(0, y.toInt(), frame.width, 1).data.toDart;
        var sum = 0;
        for (var i = 0; i < d.length; i += 4) {
          sum += d[i] + d[i + 1] + d[i + 2];
        }
        return sum / (d.length / 4) / 3;
      }

      var top = 0.0;
      var bottom = 0.0;
      final seen = <String>[];
      for (var i = 0; i < 20 && top <= 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        grab.drawImage(playback, 0, 0);
        top = brightness(frame.height * 0.1);
        bottom = brightness(frame.height - 3);
        seen.add('${playback.currentTime}: $top/$bottom');
      }
      playback.pause();
      expect(top, greaterThan(40), reason: '$seen');
      expect(bottom, closeTo(top, top * 0.15), reason: '$seen');
      web.URL.revokeObjectURL(url);
    });
  });

  testWidgets('no camera showing yet: no take starts', (tester) async {
    await tester.runAsync(() async {
      final recorder = WebTakeRecorder(
        getUserMedia: (_) async => web.MediaStream(),
      );
      await expectLater(recorder.start(), throwsStateError);
      recorder.dispose();
    });
  });

  testWidgets('no take without its sound: a refused microphone says so; '
      'a microphone lent to the camera, should the recorder fail', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // The "camera": a canvas's stream, without sound (as the web's
      // camera is opened).
      final source =
          web.document.createElement('canvas') as web.HTMLCanvasElement
            ..width = 32
            ..height = 24;
      final view = web.document.createElement('flt-platform-view');
      final cameraStream = source.captureStream(30);
      final video = web.document.createElement('video') as web.HTMLVideoElement
        ..muted = true
        ..srcObject = cameraStream;
      view.append(video);
      web.document.body!.append(view);

      // Refused: no sound, none lent.
      final refused = WebTakeRecorder(
        getUserMedia: (_) async => throw StateError('NotAllowedError'),
      );
      expect(await refused.hasSound(), isFalse);
      expect(await refused.lendSoundToCamera(), isFalse);
      expect(cameraStream.getAudioTracks().toDart, isEmpty);
      refused.dispose();

      // A microphone (Web Audio's, live, silent): sound, and its track
      // goes onto the camera's stream for the camera's own recording.
      final context = web.AudioContext();
      final mic = context.createMediaStreamDestination().stream;
      final recorder = WebTakeRecorder(getUserMedia: (_) async => mic);
      expect(await recorder.hasSound(), isTrue);
      expect(await recorder.lendSoundToCamera(), isTrue);
      final lent = cameraStream.getAudioTracks().toDart;
      expect(lent, hasLength(1));
      expect(lent.single.id, mic.getAudioTracks().toDart.single.id);
      // Lent once: asked again, nothing more is added.
      expect(await recorder.lendSoundToCamera(), isTrue);
      expect(cameraStream.getAudioTracks().toDart, hasLength(1));
      recorder.dispose();
      await context.close().toDart;
      view.remove();
    });
  });
}
