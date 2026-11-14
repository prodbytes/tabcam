import 'dart:async';
import 'dart:js_interop';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'take_recorder.dart';
import 'take_priority.dart';
import 'web_head_tracker.dart' show cameraVideo;

/// In the browser, takes are recorded by the app's own recorder.
TakeRecorder? webTakeRecorder() => WebTakeRecorder();

/// Records a take in the browser: the browser's MediaRecorder records the
/// camera preview's video track ([cameraVideo]'s stream) with the
/// microphone's sound, as they come. Nothing is drawn while it records
/// (no canvas, no per-frame work, and nothing to freeze while the
/// browser's tab is hidden): the tab isn't in the take's picture, it's
/// kept with the take (`TakeLog`) and the editor draws it. All in the
/// browser: nothing is uploaded to make it.
///
/// The microphone is its own, not the camera's (Cam opens the camera
/// without sound on the web): opened when Cam opens ([prepare]) and kept
/// open until it closes, without the processing meant for voice calls
/// ([TakePriority.webMicConstraints]), so the instrument and the song
/// playing along are recorded as they sound.
class WebTakeRecorder implements TakeRecorder {
  WebTakeRecorder({
    this.getUserMedia = _getUserMedia,
    this.enumerateDevices = _enumerateDevices,
  });

  /// Opens a microphone with these constraints (the browser's
  /// getUserMedia); tests pass their own.
  final Future<web.MediaStream> Function(web.MediaStreamConstraints)
  getUserMedia;

  /// The devices the browser has (enumerateDevices); tests pass their own.
  final Future<List<web.MediaDeviceInfo>> Function() enumerateDevices;

  static Future<web.MediaStream> _getUserMedia(
    web.MediaStreamConstraints constraints,
  ) => web.window.navigator.mediaDevices.getUserMedia(constraints).toDart;

  static Future<List<web.MediaDeviceInfo>> _enumerateDevices() async =>
      (await web.window.navigator.mediaDevices.enumerateDevices().toDart)
          .toDart;

  /// The microphone takes record from ([useMicrophone]); null: the
  /// browser's default.
  String? _micId;

  /// What the open microphone was opened from: [_micId], or null (the
  /// default, also when the one chosen couldn't be opened).
  String? _openedFrom;

  web.MediaRecorder? _recorder;
  web.MediaStream? _mic;
  Future<web.MediaStream?>? _opening;
  bool _disposed = false;
  final List<web.Blob> _chunks = [];
  Completer<void>? _stopped;
  String _type = 'video/webm';

  /// When the recording started (its `start` event), on the page's clock
  /// (`performance.now()`, ms).
  double? _startedAt;

  /// How long [start] waits for the recording's `start` event at most.
  static const startWait = Duration(seconds: 1);

  @override
  Future<void> prepare() async {
    await _openMic();
  }

  /// The microphone, open (opened now if it isn't); null if it can't be.
  Future<web.MediaStream?> _openMic() {
    if (_mic case final mic? when _live(mic)) return Future.value(mic);
    return _opening ??= () async {
      try {
        var from = _micId;
        web.MediaStream mic;
        try {
          mic = await getUserMedia(_constraints(from));
        } on Object catch (e) {
          // The one chosen is gone (unplugged, say): the default, so the
          // take still has its sound.
          if (from == null) rethrow;
          debugPrint('TabCam: cam: microphone $from: $e; the default instead');
          from = null;
          mic = await getUserMedia(_constraints(null));
        }
        _openedFrom = from;
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

  /// The microphone as [TakePriority.webMicConstraints], from [id] (null:
  /// the browser's default).
  static web.MediaStreamConstraints _constraints(String? id) =>
      web.MediaStreamConstraints(
        audio: {
          ...TakePriority.webMicConstraints,
          if (id != null) 'deviceId': {'exact': id},
        }.jsify()!,
      );

  /// The browser's own entries for its default (Chrome's "default" and
  /// "communications"), which Cam's menu has as its "Default".
  static const _defaults = {'', 'default', 'communications'};

  @override
  Future<List<TakeMic>> microphones() async {
    try {
      return [
        for (final d in await enumerateDevices())
          if (d.kind == 'audioinput' && !_defaults.contains(d.deviceId))
            TakeMic(d.deviceId, d.label),
      ];
    } on Object catch (e) {
      debugPrint('TabCam: cam: no list of microphones: $e');
      return const [];
    }
  }

  @override
  Future<bool> useMicrophone(String? id) async {
    if (_recorder != null) throw StateError('recording');
    // One opening finishes first, so it isn't left open beside the next.
    await _opening;
    _micId = id;
    final was = _mic;
    // Not open: it opens from [id] when Cam needs it.
    if (was == null) return true;
    if (_live(was) && _openedFrom == id) return true;
    _stopTracks(was);
    _mic = null;
    await _openMic();
    return _mic != null && _openedFrom == id;
  }

  static bool _live(web.MediaStream stream) =>
      stream.getAudioTracks().toDart.any((t) => t.readyState == 'live');

  /// The camera preview's stream, if it shows.
  static web.MediaStream? _cameraStream() {
    final source = cameraVideo(null)?.srcObject;
    if (source == null || !source.isA<web.MediaStream>()) return null;
    return source as web.MediaStream;
  }

  @override
  Future<bool> hasSound() async {
    if (await _openMic() case final mic? when _live(mic)) return true;
    final camera = _cameraStream();
    return camera != null && _live(camera);
  }

  @override
  Future<bool> lendSoundToCamera() async {
    final camera = _cameraStream();
    if (camera == null) return false;
    if (_live(camera)) return true;
    final mic = await _openMic();
    if (mic == null) return false;
    // A track of a microphone closed since is no use.
    for (final track in camera.getAudioTracks().toDart) {
      camera.removeTrack(track);
    }
    for (final track in mic.getAudioTracks().toDart) {
      // The preview is muted: it isn't heard, only recorded.
      camera.addTrack(track);
    }
    return _live(camera);
  }

  static void _stopTracks(web.MediaStream stream) {
    for (final track in stream.getTracks().toDart) {
      track.stop();
    }
  }

  @override
  Future<void> start() async {
    final camera = _cameraStream();
    final video = [
      ...?camera?.getVideoTracks().toDart.where((t) => t.readyState == 'live'),
    ];
    if (camera == null || video.isEmpty) {
      throw StateError('the camera isn\'t showing yet');
    }
    // The camera's picture as it comes, with the microphone's sound (open
    // since Cam opened); without it, the camera's, if it has any. Nothing
    // is drawn: the tab isn't in the take, it's kept with it.
    var audio = (await _openMic())?.getAudioTracks().toDart ?? const [];
    if (audio.isEmpty) audio = camera.getAudioTracks().toDart;
    if (audio.isEmpty) debugPrint('TabCam: cam: a take without sound');
    final stream = web.MediaStream(
      <web.MediaStreamTrack>[...video, ...audio].toJS,
    );

    _type = TakePriority.webTypes.firstWhere(
      (type) => web.MediaRecorder.isTypeSupported(type),
      orElse: () => '',
    );
    final options = web.MediaRecorderOptions(
      audioBitsPerSecond: TakePriority.webAudioBitrate,
      videoBitsPerSecond: TakePriority.webVideoBitrate,
    );
    if (_type.isNotEmpty) options.mimeType = _type;
    final recorder = _recorder = web.MediaRecorder(stream, options);
    if (_type.isEmpty) _type = recorder.mimeType;
    _chunks.clear();
    _startedAt = null;
    final stopped = _stopped = Completer<void>();
    final started = Completer<void>();
    recorder.onstart = ((web.Event e) {
      // When it happened, not when this ran: the same clock as
      // `performance.now()` (else, a browser of old, when this ran).
      final now = web.window.performance.now();
      final at = e.timeStamp.toDouble();
      _startedAt = at > 0 && at <= now ? at : now;
      if (!started.isCompleted) started.complete();
    }).toJS;
    recorder.ondataavailable = ((web.BlobEvent e) {
      if (e.data.size > 0) _chunks.add(e.data);
    }).toJS;
    recorder.onstop = ((web.Event _) {
      if (!stopped.isCompleted) stopped.complete();
    }).toJS;
    // In pieces, so a long take isn't held in one buffer.
    recorder.start(1000);
    // Returns once it records, so the take's clock starts after it does
    // (its lag, [msSinceStart], is then how far ahead the file is).
    await started.future.timeout(startWait, onTimeout: () {});
  }

  @override
  double? msSinceStart() => switch (_startedAt) {
    final at? => web.window.performance.now() - at,
    null => null,
  };

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

  /// The take ended: the microphone stays open for the next (and the
  /// camera's tracks, the preview's, are left as they are).
  void _end() => _recorder = null;

  @override
  void dispose() {
    _disposed = true;
    if (_recorder case final r? when r.state != 'inactive') r.stop();
    _end();
    if (_mic case final mic?) _stopTracks(mic);
    _mic = null;
  }
}
