@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/web_take_recorder.dart';
import 'package:web/web.dart' as web;

/// The browser recorder, in a real browser (`flutter test --platform
/// chrome`): a fake camera (a canvas's stream in a `<video>`, inside a
/// platform view as camera_web's is) is recorded with the tab drawn in.
void main() {
  testWidgets('a take is recorded with the tab, as a video file', (
    tester,
  ) async {
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
      await video.play().toDart;
      while (video.videoWidth == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final recorder = WebTakeRecorder();
      var line = 'e|--0--3--|\nB|--1--1--|';
      await recorder.start(() => line);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      line = 'e|--5--7--|\nB|--5--8--|';
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final take = await recorder.stop();
      recorder.dispose();
      timer.cancel();
      view.remove();

      expect(take.mimeType, anyOf('video/webm', 'video/mp4'));
      final bytes = await take.readAsBytes();
      expect(bytes.length, greaterThan(1000));

      // Played back: the band darkens the bottom of the frame, not the top.
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
      // A decoded frame or two in.
      await playback.play().toDart;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      playback.pause();
      final frame =
          web.document.createElement('canvas') as web.HTMLCanvasElement
            ..width = playback.videoWidth
            ..height = playback.videoHeight;
      final grab = frame.getContext('2d') as web.CanvasRenderingContext2D
        ..drawImage(playback, 0, 0);
      double brightness(double y) {
        final d = grab.getImageData(0, y.toInt(), frame.width, 1).data.toDart;
        var sum = 0;
        for (var i = 0; i < d.length; i += 4) {
          sum += d[i] + d[i + 1] + d[i + 2];
        }
        return sum / (d.length / 4) / 3;
      }

      final top = brightness(frame.height * 0.1);
      final bottom = brightness(frame.height - 3);
      expect(bottom, lessThan(top * 0.6));
      web.URL.revokeObjectURL(url);
    });
  });
}
