@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/song_sync.dart';
import 'package:tabcam_app/capture/take_log.dart';
import 'package:tabcam_app/capture/video_edit.dart' show wavBytes;
import 'package:tabcam_app/capture/web_sound_reader.dart';
import 'package:web/web.dart' as web;

import 'song_sync_test.dart' show heardFrom, mixed, riff;

/// The browser's sound reader, in a real browser
/// (`bash scripts/test-browser.sh`): files made here (WAVs of made-up
/// riffs) decoded by Web Audio at the rate asked for, a part of one read
/// where it is, and a song found in a take's sound from them; and in a
/// video the browser records as it records a take (a WebM), with the song
/// played into it.
void main() {
  XFile wav(Float32List samples, int rate, {int channels = 1}) =>
      XFile.fromData(
        wavBytes([for (var c = 0; c < channels; c++) samples], rate),
        mimeType: 'audio/wav',
        name: 'sound.wav',
      );

  test(
    'a part of a file, mixed to one channel at the rate asked for',
    () async {
      // A second of silence, then a 440 Hz tone, in stereo at 48 kHz.
      final samples = Float32List(48000 * 3);
      for (var i = 48000; i < samples.length; i++) {
        samples[i] = 0.5 * sin(2 * pi * 440 * i / 48000);
      }
      final reader = WebSoundReader();
      final file = wav(samples, 48000, channels: 2);
      final part = await reader.samples(
        file,
        from: const Duration(milliseconds: 500),
        length: const Duration(seconds: 1),
        rate: 8000,
      );
      expect(part!.length, 8000);
      double level(int from, int to) {
        var sum = 0.0;
        for (var i = from; i < to; i++) {
          sum += part[i] * part[i];
        }
        return sqrt(sum / (to - from));
      }

      // Silent until the tone starts, half a second in; then the tone's
      // level (0.5 / √2).
      expect(level(0, 3900), lessThan(0.01));
      expect(level(4100, 8000), closeTo(0.354, 0.02));
      // Past its end: what there is; beyond it, none.
      final last = await reader.samples(
        file,
        from: const Duration(milliseconds: 2500),
        length: const Duration(seconds: 2),
        rate: 8000,
      );
      expect(last!.length, closeTo(4000, 2));
      expect(
        await reader.samples(
          file,
          from: const Duration(seconds: 5),
          length: const Duration(seconds: 1),
          rate: 8000,
        ),
        isNull,
      );
      reader.close();
    },
  );

  test('not a sound file: none', () async {
    final reader = WebSoundReader();
    expect(
      await reader.samples(
        XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'x.mp4'),
        from: Duration.zero,
        length: const Duration(seconds: 1),
        rate: 8000,
      ),
      isNull,
    );
  });

  test('a song found in a take, from the files', () async {
    // The song at 44.1 kHz; the take at 48 kHz heard it from 5 s on the
    // take's clock, 0.2 s of lag after, and 83 ms later still.
    const songRate = 44100;
    const takeRate = 48000;
    Float32List at(Float32List sound, int rate) {
      // The riffs are made at 8 kHz: each sample held, to the file's rate.
      final out = Float32List(sound.length * rate ~/ SongSync.rate);
      for (var i = 0; i < out.length; i++) {
        out[i] = sound[i * SongSync.rate ~/ rate];
      }
      return out;
    }

    final song = riff(20, 11);
    final take = mixed([
      heardFrom(
        song,
        length: 30 * SongSync.rate,
        delay: 5283 * SongSync.rate / 1000,
      ),
      riff(30, 12, bpm: 103),
    ]);
    final reader = WebSoundReader();
    final sync = await SongSync.measure(
      log: const TakeLog(
        burned: false,
        lagMs: 200,
        song: [SongSegment(at: 5000, to: 25000, page: 'song', from: 0)],
      ),
      take: wav(at(take, takeRate), takeRate),
      song: wav(at(song, songRate), songRate),
      reader: reader,
    );
    reader.close();
    expect(sync!.found, isTrue);
    expect(sync.ms, closeTo(83, 1));
  });
  test('a song found in a video the browser recorded, as a take is', () async {
    // A made-up riff, played into the recording half a second or so after
    // it starts (as a song from the speaker is heard by the microphone).
    final song = riff(5, 21);
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
    final audio = web.AudioContext();
    unawaited(audio.resume().toDart);
    final buffer = audio.createBuffer(1, song.length, SongSync.rate.toDouble());
    buffer.copyToChannel(song.toJS, 0);
    final source = audio.createBufferSource()..buffer = buffer;
    final sink = audio.createMediaStreamDestination();
    source.connect(sink);
    for (final track in sink.stream.getAudioTracks().toDart) {
      stream.addTrack(track);
    }
    final recorder = web.MediaRecorder(
      stream,
      web.MediaRecorderOptions(mimeType: 'video/webm'),
    );
    final chunks = <web.Blob>[];
    final started = Completer<void>();
    final stopped = Completer<void>();
    recorder.ondataavailable = ((web.BlobEvent e) {
      if (e.data.size > 0) chunks.add(e.data);
    }).toJS;
    recorder.onstart = ((web.Event _) => started.complete()).toJS;
    recorder.onstop = ((web.Event _) => stopped.complete()).toJS;
    recorder.start(200);
    await started.future;
    final clock = Stopwatch()..start();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final noted = clock.elapsedMilliseconds;
    source.start();
    await Future<void>.delayed(const Duration(milliseconds: 5600));
    recorder.stop();
    await stopped.future;
    timer.cancel();
    await audio.close().toDart;
    final blob = web.Blob(chunks.toJS, web.BlobPropertyBag(type: 'video/webm'));
    final take = XFile.fromData(
      (await blob.arrayBuffer().toDart).toDart.asUint8List(),
      name: 'take.webm',
      mimeType: 'video/webm',
    );

    final reader = WebSoundReader();
    final sync = await SongSync.measure(
      log: TakeLog(
        burned: false,
        song: [SongSegment(at: noted, to: noted + 5000, page: 'song', from: 0)],
      ),
      take: take,
      song: wav(song, SongSync.rate),
      reader: reader,
    );
    reader.close();
    // Found, within what a browser's timers and its recorder's start are
    // off by.
    expect(sync!.found, isTrue, reason: '$sync');
    expect(sync.ms.abs(), lessThan(400), reason: '$sync');
    // ignore: avoid_print
    print(
      'The browser\'s take: the song found ${sync.ms} ms from where it '
      'was noted (score ${sync.clips.single.score})',
    );
  });
}
