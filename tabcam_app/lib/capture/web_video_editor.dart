import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'edit_formats.dart';
import 'm4a.dart';
import 'video_edit.dart';

/// In the browser, videos are edited by playing them through again.
VideoEditing? webVideoEditor() => WebVideoEditor();

/// Edits a video in the browser: the kept part plays, hidden, into a
/// canvas (its frames) and a Web Audio graph (its sound, or the new
/// track's, through a gain at its volume), and the browser's MediaRecorder
/// records both, so it takes as long as the kept part is. The result is
/// MP4 (H.264 and AAC) where the browser records it (Chrome, Edge,
/// Safari), WebM where it can't (Firefox) ([videoRecorderTypes]). The
/// sound alone is mixed offline, faster than it plays
/// ([OfflineAudioContext]), and made AAC in an M4A: by WebCodecs'
/// AudioEncoder (written to the file here, [m4aBytes]), or, without one
/// that encodes AAC, by MediaRecorder as it plays; a WAV where AAC can't
/// be made at all ([WebSoundWay]). All in the browser: nothing is
/// uploaded to make it.
class WebVideoEditor implements VideoEditing {
  /// [soundWay], for tests, makes the sound alone that way, whatever the
  /// browser can.
  WebVideoEditor({@visibleForTesting this.soundWay});

  final WebSoundWay? soundWay;

  /// The sound alone's rate: any does, the context resamples to it.
  static const _rate = 44100;

  /// The AAC encoder's bits a second.
  static const _bitrate = 160000;

  Future<EditFormats>? _formats;

  @override
  Future<EditFormats> formats() => _formats ??= () async {
    final type = videoRecorderType((t) => web.MediaRecorder.isTypeSupported(t));
    return EditFormats(
      video: type == null ? EditFormat.webm : EditFormat.recorded(type),
      sound: (await _soundWay(2)).format,
    );
  }();

  /// How the sound alone, with [channels], is made here.
  Future<WebSoundWay> _soundWay(int channels) async =>
      soundWay ??
      WebSoundWay.best(
        encoder: await _canEncode(channels),
        recorder:
            web.window.has('MediaRecorder') &&
            web.MediaRecorder.isTypeSupported(soundRecorderType),
      );

  /// Whether WebCodecs' AudioEncoder encodes AAC here (not Firefox's, nor
  /// Chrome's on Linux).
  static Future<bool> _canEncode(int channels) async {
    if (!web.window.has('AudioEncoder')) return false;
    try {
      final support = await _AudioEncoder.isConfigSupported(_aac(channels))
          .toDart;
      return support.supported;
    } on Object {
      return false;
    }
  }

  static _AudioEncoderConfig _aac(int channels) => _AudioEncoderConfig(
    codec: 'mp4a.40.2',
    sampleRate: _rate,
    numberOfChannels: channels,
    bitrate: _bitrate,
  );

  @override
  Future<XFile> apply(
    XFile video,
    VideoEdit edit, {
    bool soundOnly = false,
    void Function(double done)? onProgress,
  }) async {
    if (soundOnly) return _sound(video, edit, onProgress);
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

      final type = videoRecorderType(
        (t) => web.MediaRecorder.isTypeSupported(t),
      );
      final recorder = web.MediaRecorder(
        stream,
        type == null
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

      // Named by what was recorded: MP4, or WebM where it can't be.
      final format = EditFormat.recorded(type ?? recorder.mimeType);
      final blob = web.Blob(
        chunks.toJS,
        web.BlobPropertyBag(type: format.mimeType),
      );
      final bytes = (await blob.arrayBuffer().toDart).toDart.asUint8List();
      return XFile.fromData(
        bytes,
        name: 'edit.${format.extension}',
        mimeType: format.mimeType,
      );
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
  /// offline as long as the kept part, then made AAC in an M4A (or a WAV)
  /// as [_soundWay] says.
  Future<XFile> _sound(
    XFile video,
    VideoEdit edit,
    void Function(double done)? onProgress,
  ) async {
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
    const rate = _rate;
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
    final samples = [
      for (var c = 0; c < mixed.numberOfChannels; c++)
        mixed.getChannelData(c).toDart,
    ];
    final way = await _soundWay(samples.length);
    final format = way.format;
    final Uint8List made;
    switch (way) {
      case WebSoundWay.encoder:
        final (frames, config) = await _encode(samples, rate);
        made = m4aBytes(
          frames,
          sampleRate: rate,
          channels: samples.length,
          config: config,
          priming: await _priming(samples.length),
          length: mixed.length,
        );
      case WebSoundWay.recorder:
        made = await _record(mixed, onProgress);
      case WebSoundWay.wav:
        made = wavBytes(samples, rate);
    }
    return XFile.fromData(
      made,
      name: 'sound.${format.extension}',
      mimeType: format.mimeType,
    );
  }

  /// [samples] (a list a channel, all as long, at [rate]) encoded as
  /// AAC-LC by WebCodecs' AudioEncoder, a second at a time: its frames,
  /// and the decoder's config (null when the encoder gives none).
  static Future<(List<Uint8List>, Uint8List?)> _encode(
    List<Float32List> samples,
    int rate,
  ) async {
    final channels = samples.length;
    final frames = <Uint8List>[];
    Uint8List? config;
    Object? failed;
    final encoder = _AudioEncoder(
      _AudioEncoderInit(
        output: ((_EncodedAudioChunk chunk, _ChunkMetadata? metadata) {
          final bytes = JSUint8Array.withLength(chunk.byteLength);
          chunk.copyTo(bytes);
          frames.add(Uint8List.fromList(bytes.toDart));
          final description = metadata?.decoderConfig?.description;
          if (config == null && description != null) {
            config = _bytesOf(description);
          }
        }).toJS,
        error: ((JSAny? e) {
          failed ??= e ?? 'the encoder failed';
        }).toJS,
      ),
    );
    try {
      encoder.configure(_aac(channels));
      final length = samples.first.length;
      for (var at = 0; at < length; at += rate) {
        final n = min(rate, length - at);
        // Each channel's piece, one after another.
        final planar = Float32List(n * channels);
        for (var c = 0; c < channels; c++) {
          planar.setRange(c * n, (c + 1) * n, samples[c], at);
        }
        final data = _AudioData(
          _AudioDataInit(
            format: 'f32-planar',
            sampleRate: rate,
            numberOfFrames: n,
            numberOfChannels: channels,
            timestamp: at * 1000000 ~/ rate,
            data: planar.toJS,
          ),
        );
        encoder.encode(data);
        data.close();
      }
      await encoder.flush().toDart;
    } finally {
      if (encoder.state != 'closed') encoder.close();
    }
    if (failed != null) throw StateError('AAC: $failed');
    return (frames, config);
  }

  /// The encoder's delay here: the samples of silence it puts before the
  /// sound (Apple's AAC encoder, under Chrome and Safari on a Mac, puts
  /// 2112), which the M4A's edit list skips. Measured once: a tone after
  /// [_lead] samples of silence, encoded, written and decoded, starts
  /// that much later.
  static Future<int> _priming(int channels) =>
      _primings[channels] ??= _measurePriming(channels);
  static final _primings = <int, Future<int>>{};
  static const _lead = 4096;

  /// Apple's, where it can't be measured.
  static const _usualPriming = 2112;

  static Future<int> _measurePriming(int channels) async {
    try {
      final n = _lead + _rate ~/ 10;
      final tone = Float32List(n);
      for (var i = _lead; i < n; i++) {
        tone[i] = 0.5 * sin(2 * pi * 440 * (i - _lead) / _rate);
      }
      final (frames, config) = await _encode([
        for (var c = 0; c < channels; c++) tone,
      ], _rate);
      final file = m4aBytes(
        frames,
        sampleRate: _rate,
        channels: channels,
        config: config,
      );
      final decoder = web.OfflineAudioContext(channels.toJS, 1, _rate);
      final decoded = await decoder
          .decodeAudioData(Uint8List.fromList(file).buffer.toJS)
          .toDart;
      final onset = decoded
          .getChannelData(0)
          .toDart
          .indexWhere((s) => s.abs() > 0.05);
      if (onset < 0) return _usualPriming;
      return max(0, onset - _lead);
    } on Object catch (e) {
      debugPrint('TabCam: video edit: AAC delay unknown: $e');
      return _usualPriming;
    }
  }

  /// [mixed] played into a MediaRecorder as AAC in MP4, as long as it is
  /// (where the AudioEncoder can't make AAC: an older Safari).
  static Future<Uint8List> _record(
    web.AudioBuffer mixed,
    void Function(double done)? onProgress,
  ) async {
    final context = web.AudioContext();
    Timer? timer;
    try {
      // Started by Download's tap, as the video's sound is.
      await context.resume().toDart.timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      if (context.state != 'running') {
        throw StateError('the browser won\'t play sound here');
      }
      final sink = context.createMediaStreamDestination();
      final player = context.createBufferSource()..buffer = mixed;
      player.connect(sink);
      final recorder = web.MediaRecorder(
        sink.stream,
        web.MediaRecorderOptions(mimeType: soundRecorderType),
      );
      final chunks = <web.Blob>[];
      final stopped = Completer<void>();
      final ended = Completer<void>();
      recorder.ondataavailable = ((web.BlobEvent e) {
        if (e.data.size > 0) chunks.add(e.data);
      }).toJS;
      recorder.onstop = ((web.Event _) {
        if (!stopped.isCompleted) stopped.complete();
      }).toJS;
      player.onended = ((web.Event _) {
        if (!ended.isCompleted) ended.complete();
      }).toJS;
      recorder.start(1000);
      final began = context.currentTime;
      player.start();
      timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        final done = (context.currentTime - began) / mixed.duration;
        onProgress?.call(done.clamp(0, 1).toDouble());
      });
      await ended.future;
      if (recorder.state != 'inactive') recorder.stop();
      await stopped.future;
      final blob = web.Blob(
        chunks.toJS,
        web.BlobPropertyBag(type: EditFormat.m4a.mimeType),
      );
      return (await blob.arrayBuffer().toDart).toDart.asUint8List();
    } finally {
      timer?.cancel();
      unawaited(context.close().toDart);
    }
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

// WebCodecs' audio encoding, which package:web doesn't have yet.

@JS('AudioEncoder')
extension type _AudioEncoder._(JSObject _) implements JSObject {
  external factory _AudioEncoder(_AudioEncoderInit init);
  external static JSPromise<_AudioEncoderSupport> isConfigSupported(
    _AudioEncoderConfig config,
  );
  external String get state;
  external void configure(_AudioEncoderConfig config);
  external void encode(_AudioData data);
  external JSPromise<JSAny?> flush();
  external void close();
}

extension type _AudioEncoderInit._(JSObject _) implements JSObject {
  external factory _AudioEncoderInit({
    required JSFunction output,
    required JSFunction error,
  });
}

extension type _AudioEncoderConfig._(JSObject _) implements JSObject {
  external factory _AudioEncoderConfig({
    required String codec,
    required int sampleRate,
    required int numberOfChannels,
    required int bitrate,
  });
}

extension type _AudioEncoderSupport._(JSObject _) implements JSObject {
  external bool get supported;
}

@JS('AudioData')
extension type _AudioData._(JSObject _) implements JSObject {
  external factory _AudioData(_AudioDataInit init);
  external void close();
}

extension type _AudioDataInit._(JSObject _) implements JSObject {
  external factory _AudioDataInit({
    required String format,
    required int sampleRate,
    required int numberOfFrames,
    required int numberOfChannels,
    required int timestamp,
    required JSObject data,
  });
}

extension type _EncodedAudioChunk._(JSObject _) implements JSObject {
  external int get byteLength;
  external void copyTo(JSObject destination);
}

extension type _ChunkMetadata._(JSObject _) implements JSObject {
  external _DecoderConfig? get decoderConfig;
}

extension type _DecoderConfig._(JSObject _) implements JSObject {
  /// An ArrayBuffer or a view of one.
  external JSObject? get description;
}

/// A copy of the bytes of [source], an ArrayBuffer or a view of one.
Uint8List _bytesOf(JSObject source) {
  if (source.has('buffer')) {
    final buffer = source.getProperty<JSArrayBuffer>('buffer'.toJS).toDart;
    int number(String name) =>
        source.getProperty<JSNumber>(name.toJS).toDartInt;
    return Uint8List.fromList(
      buffer.asUint8List(number('byteOffset'), number('byteLength')),
    );
  }
  return Uint8List.fromList(_Bytes(source).toDart);
}

/// A view of an ArrayBuffer's bytes.
@JS('Uint8Array')
extension type _Bytes._(JSUint8Array _) implements JSUint8Array {
  external factory _Bytes(JSObject source);
}
