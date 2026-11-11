import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'take_overlay.dart';
import 'take_priority.dart';
import 'web_head_tracker.dart' show cameraVideo;

/// In the browser, takes are recorded with the tab in them.
TakeRecorder? webTakeRecorder() => WebTakeRecorder();

/// Records a take in the browser with the tab drawn in: each frame, the
/// camera preview's `<video>` ([cameraVideo]) and the band for the
/// neckline showing ([renderBand]) along its bottom go onto a canvas,
/// at most [TakePriority.webFps] times a second, and the browser's
/// MediaRecorder records the canvas with the microphone's sound. All in
/// the browser: nothing is uploaded to make it.
///
/// The microphone is its own, not the camera's (Cam opens the camera
/// without sound on the web): opened when Cam opens ([prepare]) and kept
/// open until it closes, without the processing meant for voice calls
/// ([TakePriority.webMicConstraints]), so the instrument and the song
/// playing along are recorded as they sound.
class WebTakeRecorder implements TakeRecorder {
  WebTakeRecorder({this.getUserMedia = _getUserMedia});

  /// Opens a microphone with these constraints (the browser's
  /// getUserMedia); tests pass their own.
  final Future<web.MediaStream> Function(web.MediaStreamConstraints)
  getUserMedia;

  static Future<web.MediaStream> _getUserMedia(
    web.MediaStreamConstraints constraints,
  ) => web.window.navigator.mediaDevices.getUserMedia(constraints).toDart;

  web.MediaRecorder? _recorder;
  web.MediaStream? _mic;
  Future<web.MediaStream?>? _opening;
  bool _disposed = false;
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

  @override
  Future<void> prepare() async {
    await _openMic();
  }

  /// The microphone, open (opened now if it isn't); null if it can't be.
  Future<web.MediaStream?> _openMic() {
    if (_mic case final mic? when _live(mic)) return Future.value(mic);
    return _opening ??= () async {
      try {
        final mic = await getUserMedia(
          web.MediaStreamConstraints(
            audio: TakePriority.webMicConstraints.jsify()!,
          ),
        );
        if (_disposed) {
          _stopTracks(mic);
          return null;
        }
        for (final track in mic.getAudioTracks().toDart) {
          // Whether the browser did as asked (Safari on iOS may not).
          debugPrint(
            'TabCam: cam: microphone: '
            '${track.getSettings().dartify()}',
          );
        }
        return _mic = mic;
      } on Object catch (e) {
        debugPrint('TabCam: cam: no microphone: $e');
        return null;
      } finally {
        _opening = null;
      }
    }();
  }

  static bool _live(web.MediaStream stream) =>
      stream.getAudioTracks().toDart.any((t) => t.readyState == 'live');

  static void _stopTracks(web.MediaStream stream) {
    for (final track in stream.getTracks().toDart) {
      track.stop();
    }
  }

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

    // Drawn at the camera's rate, not the display's: what the canvas
    // doesn't need to draw, the take's encoding has.
    num? last;
    void draw(num now) {
      _frame = web.window.requestAnimationFrame(draw.toJS);
      if (!TakePriority.frameDue(last, now)) return;
      last = now;
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
    }

    if (neckline() case final text?) await _drawBand(text);
    final stream = canvas.captureStream(TakePriority.webFps);
    // The microphone's sound (open since Cam opened); without it, the
    // camera's, if it has any.
    var audio = (await _openMic())?.getAudioTracks().toDart ?? const [];
    if (audio.isEmpty) audio = _audioOf(video.srcObject);
    if (audio.isEmpty) debugPrint('TabCam: cam: a take without sound');
    for (final track in audio) {
      stream.addTrack(track);
    }
    draw(web.window.performance.now());

    _type = TakePriority.webTypes.firstWhere(
      (type) => web.MediaRecorder.isTypeSupported(type),
      orElse: () => '',
    );
    final options = web.MediaRecorderOptions(
      audioBitsPerSecond: TakePriority.webAudioBitrate,
      videoBitsPerSecond: TakePriority.webVideoBitrate,
    );
    if (_type.isNotEmpty) options.mimeType = _type;
    final web.MediaRecorder recorder;
    try {
      recorder = _recorder = web.MediaRecorder(stream, options);
    } on Object {
      _end(); // no take: no drawing either
      rethrow;
    }
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

  /// The take ended: the microphone stays open for the next.
  void _end() {
    if (_frame case final frame?) web.window.cancelAnimationFrame(frame);
    _frame = null;
    _recorder = null;
  }

  @override
  void dispose() {
    _disposed = true;
    if (_recorder case final r? when r.state != 'inactive') r.stop();
    _end();
    if (_mic case final mic?) _stopTracks(mic);
    _mic = null;
    for (final band in _bands.values) {
      band?.close();
    }
    _bands.clear();
  }
}
