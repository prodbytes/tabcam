@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/video_edit.dart';
import 'package:tabcam_app/capture/web_video_editor.dart';
import 'package:web/web.dart' as web;

/// The browser editor, in a real browser (`bash scripts/test-browser.sh`:
/// Chrome with sound allowed without a tap): a video made here (a canvas that changes colour, with a
/// tone, recorded as a take is) is trimmed, and its sound kept, taken out
/// or replaced by the same file as a track, each as a video file of the
/// kept part's length; and its sound alone, as a WAV.
void main() {
  /// A video [seconds] long, with sound, as the browser records one.
  Future<XFile> makeVideo(double seconds) async {
    final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
      ..width = 160
      ..height = 120;
    final paint = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    var n = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      paint.fillStyle = 'hsl(${(n++ * 10) % 360}, 80%, 50%)'.toJS;
      paint.fillRect(0, 0, 160, 120);
    });
    final stream = canvas.captureStream(30);
    // Chrome starts it only after a tap, unless run with
    // --autoplay-policy=no-user-gesture-required (scripts/test-browser.sh).
    final audio = web.AudioContext();
    unawaited(audio.resume().toDart);
    final tone = audio.createOscillator()..frequency.value = 440;
    final sink = audio.createMediaStreamDestination();
    tone.connect(sink);
    tone.start();
    for (final track in sink.stream.getAudioTracks().toDart) {
      stream.addTrack(track);
    }
    final recorder = web.MediaRecorder(
      stream,
      web.MediaRecorderOptions(mimeType: 'video/webm'),
    );
    final chunks = <web.Blob>[];
    final stopped = Completer<void>();
    recorder.ondataavailable = ((web.BlobEvent e) {
      if (e.data.size > 0) chunks.add(e.data);
    }).toJS;
    recorder.onstop = ((web.Event _) => stopped.complete()).toJS;
    recorder.start(200);
    await Future<void>.delayed(
      Duration(milliseconds: (seconds * 1000).round()),
    );
    recorder.stop();
    await stopped.future;
    timer.cancel();
    tone.stop();
    await audio.close().toDart;
    final blob = web.Blob(chunks.toJS, web.BlobPropertyBag(type: 'video/webm'));
    final bytes = (await blob.arrayBuffer().toDart).toDart.asUint8List();
    return XFile.fromData(bytes, name: 'made.webm', mimeType: 'video/webm');
  }

  /// What a browser makes of [file]: its length in seconds, and whether
  /// it has sound.
  Future<(double, bool)> probe(XFile file) async {
    final blob = web.Blob(
      [(await file.readAsBytes()).toJS].toJS,
      web.BlobPropertyBag(type: file.mimeType ?? ''),
    );
    final url = web.URL.createObjectURL(blob);
    final video = web.document.createElement('video') as web.HTMLVideoElement
      ..muted = true
      ..src = url;
    final loaded = Completer<void>();
    video.onloadedmetadata = ((web.Event _) => loaded.complete()).toJS;
    video.onerror = ((web.Event _) {
      if (!loaded.isCompleted) {
        loaded.completeError(StateError('probe: ${video.error?.message}'));
      }
    }).toJS;
    video.load();
    await loaded.future.timeout(const Duration(seconds: 10));
    if (video.duration.isInfinite) {
      final seeked = Completer<void>();
      video.onseeked = ((web.Event _) => seeked.complete()).toJS;
      video.currentTime = 1e101;
      await seeked.future.timeout(const Duration(seconds: 10));
    }
    web.URL.revokeObjectURL(url);
    // Whether it has sound: whether its sound decodes.
    final audio = web.AudioContext();
    var sound = true;
    try {
      await audio
          .decodeAudioData((await file.readAsBytes()).buffer.toJS)
          .toDart;
    } on Object {
      sound = false;
    } finally {
      await audio.close().toDart;
    }
    return (video.duration, sound);
  }

  Future<void> body() async {
    final video = await makeVideo(3);
    final (length, sound) = await probe(video);
    expect(length, closeTo(3, 0.6));
    expect(sound, isTrue);
    final editor = WebVideoEditor();
    // A file the browser recorded says it's endless; the editor finds
    // out its length.
    expect(
      (await editor.length(video))!.inMilliseconds / 1000,
      closeTo(3, 0.6),
    );

    final progress = <double>[];
    final trimmed = await editor.apply(
      video,
      const VideoEdit(
        start: Duration(milliseconds: 500),
        end: Duration(milliseconds: 2000),
      ),
      onProgress: progress.add,
    );
    expect(trimmed.mimeType, 'video/webm');
    expect(trimmed.name, 'edit.webm');
    expect(progress, isNotEmpty);
    expect(progress.last, closeTo(1, 0.2));
    final (kept, keptSound) = await probe(trimmed);
    expect(kept, closeTo(1.5, 0.5));
    expect(keptSound, isTrue);

    final silent = await editor.apply(
      video,
      const VideoEdit(
        start: Duration.zero,
        end: Duration(milliseconds: 1000),
        sound: EditSound.none,
      ),
    );
    final (silentLength, silentSound) = await probe(silent);
    expect(silentLength, closeTo(1, 0.5));
    expect(silentSound, isFalse);

    final tracked = await editor.apply(
      video,
      VideoEdit(
        start: Duration.zero,
        end: const Duration(milliseconds: 1000),
        sound: EditSound.track,
        track: video,
        offset: const Duration(milliseconds: -500),
      ),
    );
    final (trackedLength, trackedSound) = await probe(tracked);
    expect(trackedLength, closeTo(1, 0.5));
    expect(trackedSound, isTrue);

    // The sound alone: a WAV as long as the kept part, rendered faster
    // than it plays; the track's starts after its gap.
    Future<web.AudioBuffer> decode(XFile file) async {
      final audio = web.AudioContext();
      try {
        return await audio
            .decodeAudioData((await file.readAsBytes()).buffer.toJS)
            .toDart;
      } finally {
        await audio.close().toDart;
      }
    }

    final clock = Stopwatch()..start();
    final own = await editor.apply(
      video,
      const VideoEdit(
        start: Duration(milliseconds: 500),
        end: Duration(milliseconds: 2500),
      ),
      soundOnly: true,
    );
    expect(clock.elapsedMilliseconds, lessThan(1500));
    expect(own.mimeType, 'audio/wav');
    final ownSound = await decode(own);
    expect(ownSound.duration, closeTo(2, 0.05));

    final gapped = await editor.apply(
      video,
      VideoEdit(
        start: Duration.zero,
        end: const Duration(milliseconds: 2000),
        sound: EditSound.track,
        track: video,
        offset: const Duration(milliseconds: 1000),
      ),
      soundOnly: true,
    );
    final gappedSound = await decode(gapped);
    expect(gappedSound.duration, closeTo(2, 0.05));
    double loudest(web.AudioBuffer buffer, double from, double to) {
      final samples = buffer.getChannelData(0).toDart;
      final rate = buffer.sampleRate;
      var most = 0.0;
      for (var i = (from * rate).round(); i < (to * rate).round(); i++) {
        if (samples[i].abs() > most) most = samples[i].abs();
      }
      return most;
    }

    // Silence for its first second, the tone after.
    expect(loudest(gappedSound, 0, 0.9), lessThan(0.01));
    expect(loudest(gappedSound, 1.2, 1.9), greaterThan(0.1));

    // At half its volume, the track is half as loud.
    final quieter = await decode(
      await editor.apply(
        video,
        VideoEdit(
          start: Duration.zero,
          end: const Duration(milliseconds: 2000),
          sound: EditSound.track,
          track: video,
          offset: const Duration(milliseconds: 1000),
          trackVolume: 0.5,
        ),
        soundOnly: true,
      ),
    );
    expect(
      loudest(quieter, 1.2, 1.9),
      closeTo(loudest(gappedSound, 1.2, 1.9) / 2, 0.02),
    );
    // And with the video, it goes through the gain too.
    final quietVideo = await editor.apply(
      video,
      VideoEdit(
        start: Duration.zero,
        end: const Duration(milliseconds: 1000),
        sound: EditSound.track,
        track: video,
        trackVolume: 0.5,
      ),
    );
    final (_, quietVideoSound) = await probe(quietVideo);
    expect(quietVideoSound, isTrue);
  }

  testWidgets('the kept part, with its sound, without, or with a track; '
      'its sound alone', (tester) async {
    await tester.runAsync(() async {
      try {
        await body();
      } on Object catch (e, stack) {
        // The browser's console doesn't reach the test's output.
        debugPrint('FAILED: $e\n$stack');
        rethrow;
      }
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
}
