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

/// Renders a [RenderPlan] in the browser: the two lanes (the video's own
/// sound and the song lane's clips, each through a gain at its volume)
/// are mixed offline first, exact to the sample ([OfflineAudioContext]);
/// then the kept part plays, hidden and muted, into a canvas (its
/// frames), the mix plays into the recording beside it, the video
/// following the mix's clock, and the browser's MediaRecorder records
/// both, so it takes as long as the kept part is (a long video's own
/// sound, or one that won't decode, streams from the playing video
/// instead, [streamedOver]). The result is
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
  /// browser can; [soundContext] makes the context the sound alone is
  /// recorded in, as it plays.
  WebVideoEditor({
    @visibleForTesting this.soundWay,
    @visibleForTesting this.soundContext,
    @visibleForTesting this.streamedOver = _streamedOver,
  });

  final WebSoundWay? soundWay;
  final web.AudioContext Function()? soundContext;

  /// A video longer than this has its own sound streamed as it plays, in
  /// a render with the picture, rather than decoded whole
  /// ([_streamedOver]; tests make it shorter).
  final Duration streamedOver;

  web.AudioContext _soundContext() =>
      soundContext?.call() ?? web.AudioContext();

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
  Future<XFile> render(
    RenderPlan plan, {
    void Function(double done)? onProgress,
  }) async {
    final video =
        plan.input ?? (throw ArgumentError('A render needs its video'));
    if (plan.song?.clips.any((c) => c.speed != 1) ?? false) {
      throw UnsupportedError('A song at another speed can\'t be rendered yet');
    }
    if (!plan.video) return _sound(video, plan, onProgress);
    final urls = <String>[];
    final elements = <web.HTMLMediaElement>[];
    web.AudioContext? audio;
    int? frame;
    try {
      // The context the mix plays in is made and started first, while
      // Download's tap still lets it start: decoding and mixing a long
      // video can outlast that.
      final graph = plan.hasSound ? audio = web.AudioContext() : null;
      final started = graph?.resume().toDart.then<void>(
        (_) {},
        onError: (Object _) {},
      );
      final player = await _load(video, urls, elements) as web.HTMLVideoElement;
      final total = player.duration;
      final start = plan.start.inMilliseconds / 1000;
      final end = (plan.end.inMilliseconds / 1000).clamp(start, total);
      final clip = end - start;
      if (clip <= 0) throw StateError('nothing to keep');

      // The frames: the video drawn on a canvas, which is recorded.
      final canvas =
          web.document.createElement('canvas') as web.HTMLCanvasElement
            ..width = player.videoWidth
            ..height = player.videoHeight;
      final context = canvas.getContext('2d') as web.CanvasRenderingContext2D;
      final stream = canvas.captureStream(30);

      // The sound: both lanes mixed offline first (exact, to the sample),
      // then played into the recorded stream (not the speakers) as the
      // video plays, muted, following it. The video's own sound is
      // decoded whole (decodeAudioData decodes all of a file, whatever
      // part is kept): a video longer than [streamedOver], or one whose
      // sound won't decode, has it streamed from the playing video
      // instead, through its lane's gain, as before the lanes were mixed
      // offline (a video without sound then adds silence).
      final own = plan.own;
      final ownHeard = graph != null && own != null && own.volume > 0;
      final whole = Duration(milliseconds: (total * 1000).round());
      web.AudioBuffer? ownSound;
      var streamed = ownHeard && whole > streamedOver;
      if (ownHeard && !streamed) {
        try {
          ownSound = await _decode(video, whole);
        } on Object catch (e) {
          debugPrint(
            'TabCam: video edit: the video\'s own sound doesn\'t decode, '
            'streamed as it plays: $e',
          );
          streamed = true;
        }
      }
      player.muted = !streamed;
      final mixed = graph == null
          ? null
          : await _mixdown(
              plan,
              ownSound,
              await _songSound(plan),
              plan.length > _longest ? _longRate : _rate,
            );
      web.AudioBufferSourceNode? source;
      if (graph != null && (mixed != null || streamed)) {
        await started?.timeout(
          const Duration(seconds: 2),
          onTimeout: () => null,
        );
        if (graph.state != 'running') {
          throw StateError('the browser won\'t play sound here');
        }
        final sink = graph.createMediaStreamDestination();
        if (mixed != null) {
          source = graph.createBufferSource()..buffer = mixed;
          source.connect(sink);
        }
        if (streamed && own != null) {
          final input = graph.createMediaElementSource(player);
          if (own.volume != 1) {
            final gain = graph.createGain()..gain.value = own.volume;
            input.connect(gain);
            gain.connect(sink);
          } else {
            input.connect(sink);
          }
        }
        for (final t in sink.stream.getAudioTracks().toDart) {
          stream.addTrack(t);
        }
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
      // When the mix started, on its context's clock.
      double? began;
      void tick(num _) {
        if (done.isCompleted) return;
        context.drawImage(player, 0, 0, canvas.width, canvas.height);
        final at = player.currentTime;
        onProgress?.call(((at - start) / clip).clamp(0, 1).toDouble());
        if (began != null && graph != null) {
          // The video follows the sound's clock: a little slower or
          // faster while it's more than 40 ms off, back to its speed once
          // it's within 10 ms.
          final drift = (at - start) - (graph.currentTime - began);
          final rate = drift.abs() > 0.04
              ? (drift > 0 ? 0.98 : 1.02)
              : drift.abs() < 0.01
              ? 1.0
              : player.playbackRate;
          if (player.playbackRate != rate) player.playbackRate = rate;
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
      if (source != null && graph != null) {
        source.start();
        began = graph.currentTime;
      }
      tick(0);
      await done.future;
      player.pause();
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

  /// A file longer than this is decoded at [_longRate], and a kept part
  /// longer than this is mixed at it for the video, so the decoded sound
  /// fits in memory (about 384 KB a second at 48 kHz in stereo, 176 KB at
  /// 22.05 kHz). decodeAudioData decodes a whole file, whatever part of
  /// it is used, so it's the file's length that counts.
  static const _longest = Duration(minutes: 8);
  static const _longRate = 22050;

  /// A video longer than this has its own sound streamed as it plays in a
  /// render with the picture ([streamedOver]): decoded whole, even at
  /// [_longRate], it would take more than about 170 MB.
  static const _streamedOver = Duration(minutes: 16);

  /// [file]'s sound, decoded whole (as decodeAudioData does), at a rate
  /// that keeps a file [length] long in memory ([_longest]). Throws when
  /// it won't decode (a file without sound, or the browser can't).
  static Future<web.AudioBuffer> _decode(XFile file, Duration length) async {
    final rate = length > _longest ? _longRate : _rate;
    final decoder = web.OfflineAudioContext(1.toJS, 1, rate);
    final bytes = await file.readAsBytes();
    // A copy: decodeAudioData takes the buffer it's given away.
    return decoder
        .decodeAudioData(Uint8List.fromList(bytes).buffer.toJS)
        .toDart;
  }

  /// The plan's song, decoded (its file once), when it's heard: at the
  /// lower rate for a kept part over [_longest] (its length unknown here,
  /// a song that long is taken to be at least as long).
  static Future<web.AudioBuffer?> _songSound(RenderPlan plan) async {
    final song = plan.song;
    if (song == null || song.volume <= 0 || song.clips.isEmpty) return null;
    return _decode(
      song.file ?? (throw ArgumentError('A song lane needs a file')),
      plan.length,
    );
  }

  /// The plan's two lanes, decoded ([ownBuffer], the whole video's sound;
  /// [songBuffer], the song's), mixed offline at [rate], as long as the
  /// kept part: the own lane from the kept part's start, each of the
  /// song's clips where it starts, each through a gain node at its lane's
  /// volume. Null when there's nothing to mix.
  static Future<web.AudioBuffer?> _mixdown(
    RenderPlan plan,
    web.AudioBuffer? ownBuffer,
    web.AudioBuffer? songBuffer,
    int rate,
  ) async {
    final own = plan.own;
    final song = plan.song;
    if (ownBuffer == null && songBuffer == null) return null;
    final channels = [
      ?ownBuffer?.numberOfChannels,
      ?songBuffer?.numberOfChannels,
    ].fold<int>(1, max).clamp(1, 2);
    final clip = plan.length.inMilliseconds / 1000;
    final context = web.OfflineAudioContext(
      channels.toJS,
      max(1, (clip * rate).ceil()),
      rate,
    );
    void play(
      web.AudioBuffer buffer,
      double volume,
      Duration at,
      Duration from,
      Duration length,
    ) {
      final player = context.createBufferSource()..buffer = buffer;
      if (volume != 1) {
        final gain = context.createGain()..gain.value = volume;
        player.connect(gain);
        gain.connect(context.destination);
      } else {
        player.connect(context.destination);
      }
      player.start(
        at.inMilliseconds / 1000,
        from.inMilliseconds / 1000,
        length.inMilliseconds / 1000,
      );
    }

    if (own != null && ownBuffer != null) {
      play(ownBuffer, own.volume, Duration.zero, plan.start, plan.length);
    }
    if (song != null && songBuffer != null) {
      for (final c in song.clips) {
        play(songBuffer, song.volume, c.at, c.from, c.to - c.from);
      }
    }
    return context.startRendering().toDart;
  }

  /// The plan's sound alone: the video's own (the kept part) and the song
  /// lane's clips (silence between them), decoded and mixed offline as
  /// long as the kept part, then made AAC in an M4A (or a WAV) as
  /// [_soundWay] says.
  Future<XFile> _sound(
    XFile video,
    RenderPlan plan,
    void Function(double done)? onProgress,
  ) async {
    final clip = plan.length.inMilliseconds / 1000;
    if (clip <= 0) throw StateError('nothing to keep');
    if (!plan.hasSound) {
      throw ArgumentError('A video without sound has no sound to save');
    }
    // Where it'll be recorded as it plays, the context it plays in is
    // started now, while Download's tap still lets it start: reading,
    // decoding and mixing a long video can outlast that.
    final early = await _soundWay(2);
    final playing = early == WebSoundWay.recorder ? _soundContext() : null;
    final started = playing?.resume().toDart.then<void>(
      (_) {},
      onError: (Object _) {},
    );
    try {
      return await _mix(video, plan, playing, started, onProgress);
    } finally {
      if (playing != null && playing.state != 'closed') {
        unawaited(
          playing.close().toDart.then<void>((_) {}, onError: (Object _) {}),
        );
      }
    }
  }

  /// [_sound]'s work: the lanes mixed offline as long as the kept part
  /// ([_mixdown]), then made AAC in an M4A (or a WAV); recorded, if so,
  /// in [playing], once [started].
  Future<XFile> _mix(
    XFile video,
    RenderPlan plan,
    web.AudioContext? playing,
    Future<void>? started,
    void Function(double done)? onProgress,
  ) async {
    const rate = _rate;
    // The video's own sound, decoded whole (there's no playing video to
    // stream it from here): one that won't decode fails the download, with
    // the browser's reason, rather than leaving the lane out unsaid.
    final own = plan.own;
    final ownSound = own == null || own.volume <= 0
        ? null
        : await _decode(
            video,
            plan.duration > Duration.zero ? plan.duration : plan.end,
          );
    final mixed =
        await _mixdown(plan, ownSound, await _songSound(plan), rate) ??
        (throw StateError('There is no sound in the kept part'));
    final samples = [
      for (var c = 0; c < mixed.numberOfChannels; c++)
        mixed.getChannelData(c).toDart,
    ];
    var way = await _soundWay(samples.length);
    Uint8List? made;
    switch (way) {
      case WebSoundWay.encoder:
        final (frames, description) = await _encode(samples, rate);
        made = m4aBytes(
          frames,
          sampleRate: rate,
          channels: samples.length,
          config: description,
          priming: await _priming(samples.length, description),
          length: mixed.length,
        );
      case WebSoundWay.recorder:
        final live = playing ?? _soundContext();
        try {
          made = await _record(live, started, mixed, onProgress);
        } on Object catch (e) {
          // The browser won't play it (no tap it counts) or record it:
          // a WAV, as where AAC can't be made, rather than nothing.
          debugPrint('TabCam: video edit: sound not recorded, a WAV: $e');
          way = WebSoundWay.wav;
        } finally {
          if (playing == null) {
            unawaited(
              live.close().toDart.then<void>((_) {}, onError: (Object _) {}),
            );
          }
        }
      case WebSoundWay.wav:
        break;
    }
    made ??= wavBytes(samples, rate);
    final format = way.format;
    return XFile.fromData(
      made,
      name: 'sound.${format.extension}',
      mimeType: format.mimeType,
    );
  }

  /// [samples] (a list a channel, all as long, at [rate]) encoded as
  /// AAC-LC by WebCodecs' AudioEncoder, a second at a time: its frames,
  /// and the decoder's description (null when the encoder gives none): an
  /// AudioSpecificConfig (Chrome's), or an ES descriptor that holds one
  /// (WebKit's), which [m4aBytes] takes either way.
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
  /// that much later. Not where the encoder's [description] is an ES
  /// descriptor (Safari's): that's Apple's encoder itself, whose delay is
  /// 2112, and nothing need be encoded to know it.
  static Future<int> _priming(int channels, Uint8List? description) {
    if (description != null && isEsDescriptor(description)) {
      return Future.value(_usualPriming);
    }
    return _primings[channels] ??= _measurePriming(channels);
  }

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
      final (frames, description) = await _encode([
        for (var c = 0; c < channels; c++) tone,
      ], _rate);
      final file = m4aBytes(
        frames,
        sampleRate: _rate,
        channels: channels,
        config: description,
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

  /// [mixed] played in [context] into a MediaRecorder as AAC in MP4, as
  /// long as it is (where the AudioEncoder can't make AAC: an older
  /// Safari). [started]: [context] asked to start, by Download's tap.
  static Future<Uint8List> _record(
    web.AudioContext context,
    Future<void>? started,
    web.AudioBuffer mixed,
    void Function(double done)? onProgress,
  ) async {
    Timer? timer;
    try {
      await (started ?? context.resume().toDart).timeout(
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
