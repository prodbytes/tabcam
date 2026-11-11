import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:web/web.dart' as web;

import 'video_edit.dart';

/// In the browser, videos are edited by playing them through again.
VideoEditing? webVideoEditor() => WebVideoEditor();

/// Edits a video in the browser: the kept part plays, hidden, into a
/// canvas (its frames) and a Web Audio graph (its sound, or the new
/// track's, through a gain at its volume), and the browser's MediaRecorder
/// records both, so it takes as long as the kept part is. The result is
/// WebM (MP4 where only that records, Safari). The sound alone is rendered
/// offline, faster than it plays ([OfflineAudioContext]), as a WAV. All
/// in the browser: nothing is uploaded to make it.
class WebVideoEditor implements VideoEditing {
  /// The first of these the browser records (Safari: MP4 only).
  static const _types = [
    'video/webm;codecs=vp9,opus',
    'video/webm;codecs=vp8,opus',
    'video/webm',
    'video/mp4',
  ];

  @override
  Future<XFile> apply(
    XFile video,
    VideoEdit edit, {
    bool soundOnly = false,
    void Function(double done)? onProgress,
  }) async {
    if (soundOnly) return _sound(video, edit);
    final urls = <String>[];
    final elements = <web.HTMLMediaElement>[];
    web.AudioContext? audio;
    int? frame;
    try {
      final player = await _load(video, urls, elements) as web.HTMLVideoElement;
      final total = player.duration;
      final start = edit.start.inMilliseconds / 1000;
      final end = (edit.end.inMilliseconds / 1000).clamp(start, total);
      final clip = end - start;
      if (clip <= 0) throw StateError('nothing to keep');

      // The frames: the video drawn on a canvas, which is recorded.
      final canvas =
          web.document.createElement('canvas') as web.HTMLCanvasElement
            ..width = player.videoWidth
            ..height = player.videoHeight;
      final context = canvas.getContext('2d') as web.CanvasRenderingContext2D;
      final stream = canvas.captureStream(30);

      // The sound: the video's own, or the track's, through a Web Audio
      // graph into the recorded stream (not the speakers).
      web.HTMLMediaElement? track;
      ({Duration gap, Duration from, Duration to})? span;
      if (edit.sound != EditSound.none) {
        final graph = audio = web.AudioContext();
        // Started by Save's tap; without one the browser keeps it
        // suspended, and the recorder would wait for sound for ever.
        await graph.resume().toDart.timeout(
          const Duration(seconds: 2),
          onTimeout: () => null,
        );
        if (graph.state != 'running') {
          throw StateError('the browser won\'t play sound here');
        }
        final sink = graph.createMediaStreamDestination();
        web.HTMLMediaElement source;
        if (edit.sound == EditSound.track) {
          final file = edit.track;
          if (file == null) {
            throw ArgumentError('A new sound track needs a file');
          }
          source = track = await _load(file, urls, elements);
          player.muted = true;
          // The part of it that fits, as the edit says; worked out here
          // when the edit doesn't know the track's length.
          span =
              edit.trackPart ??
              trackSpan(
                Duration(milliseconds: (clip * 1000).round()),
                Duration(milliseconds: (track.duration * 1000).round()),
                edit.offset,
                trackStart: edit.trackStart,
                trackEnd: edit.trackEnd,
              );
        } else {
          source = player;
        }
        final input = graph.createMediaElementSource(source);
        if (track != null && edit.trackVolume != 1) {
          // The track as loud as the edit says.
          final gain = graph.createGain()..gain.value = edit.trackVolume;
          input.connect(gain);
          gain.connect(sink);
        } else {
          input.connect(sink);
        }
        for (final t in sink.stream.getAudioTracks().toDart) {
          stream.addTrack(t);
        }
      } else {
        player.muted = true;
      }

      final type = _types.firstWhere(
        (t) => web.MediaRecorder.isTypeSupported(t),
        orElse: () => '',
      );
      final recorder = web.MediaRecorder(
        stream,
        type.isEmpty
            ? web.MediaRecorderOptions()
            : web.MediaRecorderOptions(mimeType: type),
      );
      final chunks = <web.Blob>[];
      final stopped = Completer<void>();
      recorder.ondataavailable = ((web.BlobEvent e) {
        if (e.data.size > 0) chunks.add(e.data);
      }).toJS;
      recorder.onstop = ((web.Event _) {
        if (!stopped.isCompleted) stopped.complete();
      }).toJS;

      await _seek(player, start);
      final done = Completer<void>();
      var trackStarted = false;
      void tick(num _) {
        if (done.isCompleted) return;
        context.drawImage(player, 0, 0, canvas.width, canvas.height);
        final at = player.currentTime;
        onProgress?.call(((at - start) / clip).clamp(0, 1).toDouble());
        if (track != null && span != null && !trackStarted) {
          // The track starts once the video reaches where it comes in.
          final gap = span.gap.inMilliseconds / 1000;
          if (at - start >= gap) {
            trackStarted = true;
            track.currentTime = span.from.inMilliseconds / 1000;
            unawaited(track.play().toDart);
          }
        }
        if (at >= end || player.ended) {
          done.complete();
          return;
        }
        frame = web.window.requestAnimationFrame(tick.toJS);
      }

      // In pieces, so a long video isn't held in one buffer.
      recorder.start(1000);
      await player.play().toDart;
      tick(0);
      await done.future;
      player.pause();
      track?.pause();
      if (recorder.state != 'inactive') recorder.stop();
      await stopped.future;

      final mime = (type.isEmpty ? recorder.mimeType : type).split(';').first;
      final blob = web.Blob(chunks.toJS, web.BlobPropertyBag(type: mime));
      final bytes = (await blob.arrayBuffer().toDart).toDart.asUint8List();
      final extension = mime == 'video/mp4' ? 'mp4' : 'webm';
      return XFile.fromData(bytes, name: 'edit.$extension', mimeType: mime);
    } finally {
      if (frame case final f?) web.window.cancelAnimationFrame(f);
      for (final element in elements) {
        element.pause();
        element.removeAttribute('src');
      }
      for (final url in urls) {
        web.URL.revokeObjectURL(url);
      }
      if (audio != null) unawaited(audio.close().toDart);
    }
  }

  /// The edit's sound alone: the video's own (the kept part) or the
  /// track's (silence first, then the part that fits), decoded and mixed
  /// offline into a WAV as long as the kept part.
  Future<XFile> _sound(XFile video, VideoEdit edit) async {
    final clip = edit.length.inMilliseconds / 1000;
    if (clip <= 0) throw StateError('nothing to keep');
    final XFile source;
    switch (edit.sound) {
      case EditSound.none:
        throw ArgumentError('A video without sound has no sound to save');
      case EditSound.original:
        source = video;
      case EditSound.track:
        source = edit.track ?? (throw ArgumentError('No track'));
    }
    // Any rate does: the context resamples to it.
    const rate = 44100;
    final decoder = web.OfflineAudioContext(1.toJS, 1, rate);
    final bytes = await source.readAsBytes();
    final buffer = await decoder
        .decodeAudioData(Uint8List.fromList(bytes).buffer.toJS)
        .toDart;
    final channels = buffer.numberOfChannels.clamp(1, 2);
    final context = web.OfflineAudioContext(
      channels.toJS,
      (clip * rate).ceil(),
      rate,
    );
    final player = context.createBufferSource()..buffer = buffer;
    if (edit.sound == EditSound.track && edit.trackVolume != 1) {
      // The track as loud as the edit says.
      final gain = context.createGain()..gain.value = edit.trackVolume;
      player.connect(gain);
      gain.connect(context.destination);
    } else {
      player.connect(context.destination);
    }
    if (edit.sound == EditSound.original) {
      player.start(0, edit.start.inMilliseconds / 1000, clip);
    } else {
      // The part of it that fits, as the edit says; worked out here when
      // the edit doesn't know the track's length.
      final span =
          edit.trackPart ??
          trackSpan(
            edit.length,
            Duration(milliseconds: (buffer.duration * 1000).round()),
            edit.offset,
            trackStart: edit.trackStart,
            trackEnd: edit.trackEnd,
          );
      // None of it falls in the kept part: silence.
      if (span != null) {
        player.start(
          span.gap.inMilliseconds / 1000,
          span.from.inMilliseconds / 1000,
          (span.to - span.from).inMilliseconds / 1000,
        );
      }
    }
    final mixed = await context.startRendering().toDart;
    final wav = wavBytes([
      for (var c = 0; c < mixed.numberOfChannels; c++)
        mixed.getChannelData(c).toDart,
    ], rate);
    return XFile.fromData(wav, name: 'sound.wav', mimeType: 'audio/wav');
  }

  @override
  Future<Duration?> length(XFile file) async {
    final urls = <String>[];
    final elements = <web.HTMLMediaElement>[];
    try {
      final element = await _load(file, urls, elements);
      return Duration(milliseconds: (element.duration * 1000).round());
    } finally {
      for (final element in elements) {
        element.pause();
        element.removeAttribute('src');
      }
      for (final url in urls) {
        web.URL.revokeObjectURL(url);
      }
    }
  }

  /// [file] in a hidden media element (a `<video>`, which plays sound
  /// files too), loaded enough to know its length and size.
  static Future<web.HTMLMediaElement> _load(
    XFile file,
    List<String> urls,
    List<web.HTMLMediaElement> elements,
  ) async {
    final bytes = await file.readAsBytes();
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: file.mimeType ?? ''),
    );
    final url = web.URL.createObjectURL(blob);
    urls.add(url);
    final element = web.document.createElement('video') as web.HTMLVideoElement
      ..preload = 'auto'
      ..playsInline = true
      ..src = url;
    elements.add(element);
    final loaded = Completer<void>();
    element.onloadeddata = ((web.Event _) {
      if (!loaded.isCompleted) loaded.complete();
    }).toJS;
    element.onerror = ((web.Event _) {
      if (!loaded.isCompleted) {
        loaded.completeError(StateError('${file.name} can\'t be played'));
      }
    }).toJS;
    element.load();
    await loaded.future.timeout(const Duration(seconds: 30));
    if (element.duration.isInfinite) {
      // A file the browser recorded (a take: MediaRecorder writes no
      // length) says it's endless until it's sought past its end; then
      // it knows.
      await _seek(element, 1e101);
      await _seek(element, 0);
    }
    if (element.duration.isNaN || element.duration.isInfinite) {
      throw StateError('${file.name} has no known length');
    }
    return element;
  }

  static Future<void> _seek(web.HTMLMediaElement element, double to) async {
    if ((element.currentTime - to).abs() < 0.001) return;
    final seeked = Completer<void>();
    element.onseeked = ((web.Event _) {
      if (!seeked.isCompleted) seeked.complete();
    }).toJS;
    element.currentTime = to;
    try {
      await seeked.future.timeout(const Duration(seconds: 10));
    } finally {
      element.onseeked = null;
    }
  }
}
