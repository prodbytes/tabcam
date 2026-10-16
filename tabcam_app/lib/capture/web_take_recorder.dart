import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'take_overlay.dart';
import 'web_head_tracker.dart' show cameraVideo;

/// In the browser, takes are recorded with the tab in them.
TakeRecorder? webTakeRecorder() => WebTakeRecorder();

/// Records a take in the browser with the tab drawn in: each frame, the
/// camera preview's `<video>` ([cameraVideo]) and the band for the
/// neckline showing ([renderBand]) along its bottom go onto a canvas,
/// and the browser's MediaRecorder records the canvas with the camera's
/// sound. All in the browser: nothing is uploaded to make it.
class WebTakeRecorder implements TakeRecorder {
  web.MediaRecorder? _recorder;
  web.MediaStream? _mic;
  int? _frame;
  String? Function() _neckline = () => null;
  final List<web.Blob> _chunks = [];
  Completer<void>? _stopped;
  String _type = 'video/webm';

  /// Bands drawn so far, by their neckline (null while it's being drawn).
  final Map<String, web.ImageBitmap?> _bands = {};

  /// Necklines whose band couldn't be drawn: their text goes on the
  /// canvas as it is instead.
  final Set<String> _plain = {};

  /// The first of these the browser records (Safari: MP4 only).
  static const _types = [
    'video/webm;codecs=vp9,opus',
    'video/webm;codecs=vp8,opus',
    'video/webm',
    'video/mp4',
  ];

  @override
  Future<void> start(String? Function() neckline) async {
    final video = cameraVideo(null);
    if (video == null || video.videoWidth == 0) {
      throw StateError('the camera isn\'t showing yet');
    }
    _neckline = neckline;
    final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
      ..width = video.videoWidth
      ..height = video.videoHeight;
    final context = canvas.getContext('2d') as web.CanvasRenderingContext2D;

    void draw(num _) {
      final video = cameraVideo(null);
      if (video != null) {
        context.drawImage(video, 0, 0, canvas.width, canvas.height);
      }
      if (_neckline() case final text?) {
        if (_plain.contains(text)) {
          _drawPlain(context, canvas.width, canvas.height, text);
        } else if (_bands[text] case final band?) {
          // As wide as the video, along its bottom.
          final height = canvas.width * band.height / band.width;
          context.drawImage(
            band,
            0,
            canvas.height - height,
            canvas.width,
            height,
          );
        } else if (!_bands.containsKey(text)) {
          _bands[text] = null;
          unawaited(_drawBand(text));
        }
      }
      _frame = web.window.requestAnimationFrame(draw.toJS);
    }

    if (neckline() case final text?) await _drawBand(text);
    draw(0);

    // The camera's own sound; else the microphone's.
    final stream = canvas.captureStream(30);
    var audio = _audioOf(video.srcObject);
    if (audio.isEmpty) {
      try {
        final mic = _mic = await web.window.navigator.mediaDevices
            .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
            .toDart;
        audio = mic.getAudioTracks().toDart;
      } on Object catch (e) {
        debugPrint('TabCam: cam: no sound: $e');
      }
    }
    for (final track in audio) {
      stream.addTrack(track);
    }

    _type = _types.firstWhere(
      (type) => web.MediaRecorder.isTypeSupported(type),
      orElse: () => '',
    );
    final recorder = _recorder = web.MediaRecorder(
      stream,
      _type.isEmpty
          ? web.MediaRecorderOptions()
          : web.MediaRecorderOptions(mimeType: _type),
    );
    if (_type.isEmpty) _type = recorder.mimeType;
    _chunks.clear();
    final stopped = _stopped = Completer<void>();
    recorder.ondataavailable = ((web.BlobEvent e) {
      if (e.data.size > 0) _chunks.add(e.data);
    }).toJS;
    recorder.onstop = ((web.Event _) {
      if (!stopped.isCompleted) stopped.complete();
    }).toJS;
    // In pieces, so a long take isn't held in one buffer.
    recorder.start(1000);
  }

  static List<web.MediaStreamTrack> _audioOf(JSObject? source) {
    if (source == null || !source.isA<web.MediaStream>()) return const [];
    return (source as web.MediaStream).getAudioTracks().toDart;
  }

  /// Draws [text]'s band, for the frames after.
  Future<void> _drawBand(String text) async {
    try {
      final png = await renderBand(text);
      final bitmap = await web.window
          .createImageBitmap(web.Blob([png.toJS].toJS))
          .toDart;
      _bands[text] = bitmap;
    } on Object catch (e) {
      debugPrint('TabCam: cam: band not drawn, the text instead: $e');
      _plain.add(text);
    }
  }

  /// [text] along the bottom as the canvas draws text, where its band
  /// couldn't be made: the same look, roughly.
  static void _drawPlain(
    web.CanvasRenderingContext2D context,
    int width,
    int height,
    String text,
  ) {
    final lines = text.split('\n');
    var size = width / 48;
    context.font = '${size}px RobotoMono, monospace';
    var widest = 0.0;
    for (final line in lines) {
      widest = max(widest, context.measureText(line).width);
    }
    final pad = width / 64;
    if (widest > width - 2 * pad) {
      size *= (width - 2 * pad) / widest;
      context.font = '${size}px RobotoMono, monospace';
    }
    final band = lines.length * size * 1.2 + 2 * pad;
    context.fillStyle = 'rgba(0, 0, 0, 0.7)'.toJS;
    context.fillRect(0, height - band, width, band);
    context.fillStyle = 'white'.toJS;
    context.textBaseline = 'top';
    context.textAlign = 'center';
    for (final (i, line) in lines.indexed) {
      context.fillText(line, width / 2, height - band + pad + i * size * 1.2);
    }
  }

  @override
  Future<XFile> stop() async {
    final recorder = _recorder;
    if (recorder == null) throw StateError('not recording');
    if (recorder.state != 'inactive') recorder.stop();
    await _stopped?.future;
    _end();
    final type = _type.split(';').first;
    final blob = web.Blob(_chunks.toJS, web.BlobPropertyBag(type: type));
    _chunks.clear();
    final bytes = (await blob.arrayBuffer().toDart).toDart.asUint8List();
    final extension = type == 'video/mp4' ? 'mp4' : 'webm';
    return XFile.fromData(bytes, name: 'take.$extension', mimeType: type);
  }

  void _end() {
    if (_frame case final frame?) web.window.cancelAnimationFrame(frame);
    _frame = null;
    for (final track in _mic?.getTracks().toDart ?? <web.MediaStreamTrack>[]) {
      track.stop();
    }
    _mic = null;
    _recorder = null;
  }

  @override
  void dispose() {
    if (_recorder case final r? when r.state != 'inactive') r.stop();
    _end();
    for (final band in _bands.values) {
      band?.close();
    }
    _bands.clear();
  }
}
