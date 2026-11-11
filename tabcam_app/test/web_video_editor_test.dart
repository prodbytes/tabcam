@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/edit_formats.dart';
import 'package:tabcam_app/capture/video_edit.dart';
import 'package:tabcam_app/capture/web_video_editor.dart';
import 'package:web/web.dart' as web;

/// The browser editor, in a real browser (`bash scripts/test-browser.sh`:
/// Chrome with sound allowed without a tap): a video made here (a canvas that changes colour, with a
/// tone, recorded as a take is) is trimmed, and its sound kept, taken out
/// or replaced by the same file as a track, each as an MP4 of the kept
/// part's length that says its length; and its sound alone, AAC in an M4A
/// (by WebCodecs, or recorded as it plays), or a WAV where AAC can't be
/// made.
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

  /// [probe], and whether the file says its length as it loads (one
  /// MediaRecorder wrote as WebM doesn't: it's sought to its end).
  Future<(double, bool, bool)> probeAll(XFile file) async {
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
    final known = video.duration.isFinite;
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
    return (video.duration, sound, known);
  }

  /// What a browser makes of [file]: its length in seconds, and whether
  /// it has sound.
  Future<(double, bool)> probe(XFile file) async {
    final (length, sound, _) = await probeAll(file);
    return (length, sound);
  }

  /// The type of [file]'s first box (an MP4's or M4A's is `ftyp`) and
  /// its brand.
  Future<(String, String)> firstBox(XFile file) async {
    final bytes = await file.readAsBytes();
    return (
      String.fromCharCodes(bytes.sublist(4, 8)),
      String.fromCharCodes(bytes.sublist(8, 12)),
    );
  }

  Future<void> body() async {
    final video = await makeVideo(3);
    final (length, sound) = await probe(video);
    expect(length, closeTo(3, 0.6));
    expect(sound, isTrue);
    final editor = WebVideoEditor();
    // Chrome records MP4 and encodes AAC.
    expect(await editor.formats(), EditFormats.standard);
    // A file the browser recorded says it's endless; the editor finds
    // out its length.
    final videoLength = (await editor.length(video))!;
    expect(videoLength.inMilliseconds / 1000, closeTo(3, 0.6));

    /// The plan Download renders of [edit], the video itself as its
    /// track, if any.
    RenderPlan plan(PageEdit edit, {RenderKind kind = RenderKind.video}) =>
        RenderPlan.of(
          edit,
          input: video,
          duration: videoLength,
          inputExtension: 'webm',
          songFile: video,
          songLength: videoLength,
          kind: kind,
        );

    final progress = <double>[];
    final trimmed = await editor.render(
      plan(
        const PageEdit(
          start: Duration(milliseconds: 500),
          end: Duration(milliseconds: 2000),
        ),
      ),
      onProgress: progress.add,
    );
    expect(trimmed.mimeType, 'video/mp4');
    expect(trimmed.name, 'edit.mp4');
    expect((await firstBox(trimmed)).$1, 'ftyp');
    expect(progress, isNotEmpty);
    expect(progress.last, closeTo(1, 0.2));
    final (kept, keptSound, keptKnown) = await probeAll(trimmed);
    expect(kept, closeTo(1.5, 0.5));
    expect(keptSound, isTrue);
    // An MP4 the recorder wrote says its length, so it seeks.
    expect(keptKnown, isTrue);

    final silent = await editor.render(
      plan(
        PageEdit.fromSound(
          start: Duration.zero,
          end: Duration(milliseconds: 1000),
          sound: EditSound.none,
        ),
      ),
    );
    expect(silent.name, 'edit.mp4');
    final (silentLength, silentSound) = await probe(silent);
    expect(silentLength, closeTo(1, 0.5));
    expect(silentSound, isFalse);

    final tracked = await editor.render(
      plan(
        PageEdit.fromSound(
          start: Duration.zero,
          end: Duration(milliseconds: 1000),
          sound: EditSound.track,
          trackId: 'k1',
          offset: Duration(milliseconds: -500),
        ),
      ),
    );
    final (trackedLength, trackedSound) = await probe(tracked);
    expect(trackedLength, closeTo(1, 0.5));
    expect(trackedSound, isTrue);

    // The sound alone: AAC in an M4A as long as the kept part (the
    // encoder's delay cut), made faster than it plays; the track's starts
    // after its gap.
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

    /// The track's sound alone, starting a second in, at [volume].
    RenderPlan gappedAt(double volume) => plan(
      PageEdit.fromSound(
        start: Duration.zero,
        end: const Duration(milliseconds: 2000),
        sound: EditSound.track,
        trackId: 'k1',
        offset: const Duration(milliseconds: 1000),
        trackVolume: volume,
      ),
      kind: RenderKind.sound,
    );

    final clock = Stopwatch()..start();
    final own = await editor.render(
      plan(
        const PageEdit(
          start: Duration(milliseconds: 500),
          end: Duration(milliseconds: 2500),
        ),
        kind: RenderKind.sound,
      ),
    );
    expect(clock.elapsedMilliseconds, lessThan(1500));
    expect(own.mimeType, 'audio/mp4');
    expect(own.name, 'sound.m4a');
    expect(await firstBox(own), ('ftyp', 'M4A '));
    final ownSound = await decode(own);
    expect(ownSound.duration, closeTo(2, 0.01));

    final gapped = await editor.render(gappedAt(1));
    final gappedSound = await decode(gapped);
    expect(gapped.name, 'sound.m4a');
    expect(gappedSound.duration, closeTo(2, 0.01));
    double loudest(web.AudioBuffer buffer, double from, double to) {
      final samples = buffer.getChannelData(0).toDart;
      final rate = buffer.sampleRate;
      var most = 0.0;
      for (var i = (from * rate).round(); i < (to * rate).round(); i++) {
        if (samples[i].abs() > most) most = samples[i].abs();
      }
      return most;
    }

    // Silence for its first second, the tone after: where it is, the
    // encoder's delay cut.
    expect(loudest(gappedSound, 0, 0.98), lessThan(0.01));
    expect(loudest(gappedSound, 1.02, 1.9), greaterThan(0.1));

    // At half its volume, the track is half as loud.
    final quieter = await decode(await editor.render(gappedAt(0.5)));
    expect(
      loudest(quieter, 1.2, 1.9),
      closeTo(loudest(gappedSound, 1.2, 1.9) / 2, 0.02),
    );
    // Recorded as it plays, where WebCodecs can't make AAC (an older
    // Safari): an M4A about as long, the track at its volume too.
    final recorder = WebVideoEditor(soundWay: WebSoundWay.recorder);
    final recorded = await recorder.render(gappedAt(1));
    expect(recorded.mimeType, 'audio/mp4');
    expect(recorded.name, 'sound.m4a');
    expect((await firstBox(recorded)).$1, 'ftyp');
    final recordedSound = await decode(recorded);
    expect(recordedSound.duration, closeTo(2, 0.3));
    final recordedQuieter = await decode(await recorder.render(gappedAt(0.5)));
    expect(
      loudest(recordedQuieter, 1.3, 1.7) / loudest(recordedSound, 1.3, 1.7),
      closeTo(0.5, 0.1),
    );

    // Where the browser won't play it to be recorded (Safari, once
    // Download's tap is too long ago): a WAV rather than nothing.
    final unplayed = await WebVideoEditor(
      soundWay: WebSoundWay.recorder,
      soundContext: () => web.AudioContext()..close(),
    ).render(gappedAt(0.5));
    expect(unplayed.mimeType, 'audio/wav');
    expect(unplayed.name, 'sound.wav');
    expect((await decode(unplayed)).duration, closeTo(2, 0.001));

    // Where AAC can't be made at all (Firefox): a WAV, as long exactly.
    final wav = await WebVideoEditor(soundWay: WebSoundWay.wav)
        .render(gappedAt(0.5));
    expect(wav.mimeType, 'audio/wav');
    expect(wav.name, 'sound.wav');
    final wavSound = await decode(wav);
    expect(wavSound.duration, closeTo(2, 0.001));
    expect(
      loudest(wavSound, 1.2, 1.9),
      closeTo(loudest(gappedSound, 1.2, 1.9) / 2, 0.02),
    );

    // The song lane in pieces (as later steps make it): each clip where
    // it comes in, silence between them.
    final pieces = await decode(
      await WebVideoEditor(soundWay: WebSoundWay.wav).render(
        RenderPlan(
          start: Duration.zero,
          end: const Duration(milliseconds: 2000),
          input: video,
          video: false,
          format: EditFormat.wav,
          own: null,
          song: SongLane(
            file: video,
            clips: const [
              SongClip(
                at: Duration(milliseconds: 200),
                from: Duration(milliseconds: 500),
                to: Duration(milliseconds: 800),
              ),
              SongClip(
                at: Duration(milliseconds: 1200),
                from: Duration(milliseconds: 500),
                to: Duration(milliseconds: 800),
              ),
            ],
          ),
        ),
      ),
    );
    expect(loudest(pieces, 0, 0.18), lessThan(0.01));
    expect(loudest(pieces, 0.25, 0.45), greaterThan(0.1));
    expect(loudest(pieces, 0.55, 1.15), lessThan(0.01));
    expect(loudest(pieces, 1.25, 1.45), greaterThan(0.1));
    expect(loudest(pieces, 1.55, 1.95), lessThan(0.01));

    // With the video, a track trimmed at its end stops there: the rest
    // of the video is silent.
    final cut = await decode(
      await editor.render(
        plan(
          PageEdit.fromSound(
            start: Duration.zero,
            end: Duration(milliseconds: 1500),
            sound: EditSound.track,
            trackId: 'k1',
            trackStart: Duration(milliseconds: 500),
            trackEnd: Duration(milliseconds: 900),
          ),
        ),
      ),
    );
    expect(loudest(cut, 0.1, 0.3), greaterThan(0.05));
    expect(loudest(cut, 0.75, 1.3), lessThan(0.02));

    // And with the video, it goes through the gain too: its recorded
    // sound is about half as loud as the same edit's at 100%.
    RenderPlan withVideo(double volume) => plan(
      PageEdit.fromSound(
        start: Duration.zero,
        end: const Duration(milliseconds: 1500),
        sound: EditSound.track,
        trackId: 'k1',
        trackVolume: volume,
      ),
    );
    final quietVideo = await editor.render(withVideo(0.5));
    expect(quietVideo.name, 'edit.mp4');
    final (_, quietVideoSound) = await probe(quietVideo);
    expect(quietVideoSound, isTrue);
    final loudVideo = await editor.render(withVideo(1));
    // Past the recorder's start and before its end; compressed, so
    // within a margin.
    final ratio =
        loudest(await decode(quietVideo), 0.4, 1.0) /
        loudest(await decode(loudVideo), 0.4, 1.0);
    expect(ratio, closeTo(0.5, 0.12));

    // The two lanes, mixed: the video's own sound at half, and the same
    // file as the song a second in, at 40% (together under full scale,
    // so nothing clips). Mixed offline, the sound alone is the sum of
    // each lane's, to the sample (a WAV, so nothing's lost).
    final wavs = WebVideoEditor(soundWay: WebSoundWay.wav);
    PageEdit lanes({bool own = true, bool song = true}) => PageEdit(
      start: Duration.zero,
      end: const Duration(milliseconds: 2000),
      ownVolume: 0.5,
      ownMuted: !own,
      song: SongMode.manual,
      songMuted: !song,
      trackId: 'k1',
      offset: const Duration(milliseconds: 1000),
      trackVolume: 0.4,
    );
    Future<web.AudioBuffer> soundOf(PageEdit edit) async =>
        decode(await wavs.render(plan(edit, kind: RenderKind.sound)));
    final mixed = await soundOf(lanes());
    final ownOnly = await soundOf(lanes(song: false));
    final songOnly = await soundOf(lanes(own: false));
    expect(mixed.duration, closeTo(2, 0.001));
    final m = mixed.getChannelData(0).toDart;
    final o = ownOnly.getChannelData(0).toDart;
    final g = songOnly.getChannelData(0).toDart;
    var off = 0.0;
    for (var i = 0; i < m.length; i++) {
      off = max(off, (m[i] - (o[i] + g[i])).abs());
    }
    expect(off, lessThan(0.001));
    // The own lane all along, the song only after its second of silence.
    expect(loudest(ownOnly, 0.1, 1.9), greaterThan(0.05));
    expect(loudest(songOnly, 0, 0.98), lessThan(0.01));
    expect(loudest(songOnly, 1.05, 1.9), greaterThan(0.05));

    // With the video, the own lane goes through its gain too, and both
    // lanes are heard.
    RenderPlan ownAt(double volume) => plan(
      PageEdit(
        start: Duration.zero,
        end: const Duration(milliseconds: 1500),
        ownVolume: volume,
      ),
    );
    final quietOwn = await decode(await editor.render(ownAt(0.5)));
    final loudOwn = await decode(await editor.render(ownAt(1)));
    expect(
      loudest(quietOwn, 0.4, 1.0) / loudest(loudOwn, 0.4, 1.0),
      closeTo(0.5, 0.12),
    );
    final bothVideo = await editor.render(plan(lanes()));
    final (bothLength, bothSound) = await probe(bothVideo);
    expect(bothLength, closeTo(2, 0.5));
    expect(bothSound, isTrue);
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
  }, timeout: const Timeout(Duration(minutes: 3)));
}
