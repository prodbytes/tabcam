import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android: the take's sound recorded by the app, not by the camera, as a
/// musician wants it (the microphone's unprocessed source where the phone
/// has one; the camera's is the camcorder source, with the maker's gain
/// control and noise suppression), and put into the take, in step with
/// its video, when it stops. Method channel `tabcam/take_sound`
/// (android/…/TakeSound.kt). See specs/cam.md, "Recording comes first".
///
/// Cam [prepare]s it when it opens: where it can't (the microphone
/// refused, or no source works), the camera records the take's sound
/// itself, as before. Refused here, the microphone is asked for again by
/// the camera as it opens; allowed there, Cam prepares this again (without
/// asking) and the app records the sound after all: the camera, opened
/// with sound, records none of its own while the app's records (see
/// `MainActivity.checkPermission`). Then each take: [start] before the camera starts,
/// [videoStarted] as soon as it has, [videoStopping] just before it's
/// stopped, and [stop] with the camera's video (or [cancel] if the camera
/// didn't start).
abstract final class TakeSound {
  static const channel = MethodChannel('tabcam/take_sound');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Asks for the microphone if it isn't allowed (not with [ask] false),
  /// and opens it: whether takes get their sound here (else the camera
  /// should record it), and if not, whether the microphone was refused.
  static Future<TakeSoundReady> prepare({bool ask = true}) async {
    if (!supported) return TakeSoundReady.unavailable;
    try {
      final info = await channel.invokeMapMethod<String, Object?>('prepare', {
        'ask': ask,
      });
      if (info?['ok'] == true) {
        debugPrint(
          'TabCam: cam: the take\'s sound: ${info!['source']}, '
          '${info['sampleRate']} Hz, ${info['channels']} channel(s)',
        );
        return TakeSoundReady.ok;
      }
      debugPrint(
        'TabCam: cam: the camera records the take\'s sound: '
        '${info?['reason']}',
      );
      if (info?['refused'] == true) return TakeSoundReady.refused;
    } on Object catch (e) {
      debugPrint('TabCam: cam: the camera records the take\'s sound: $e');
    }
    return TakeSoundReady.unavailable;
  }

  /// The microphone records the take's sound; throws when it can't.
  static Future<void> start() => channel.invokeMethod<void>('start');

  /// The camera's recording has started (when, to put the sound in step).
  static Future<void> videoStarted() => _quiet('videoStarted');

  /// The camera's recording is about to stop.
  static Future<void> videoStopping() => _quiet('videoStopping');

  /// [video] (the camera's, without sound) with the take's sound in it, in
  /// step: a new MP4 ([take]). Should that fail, [take] is [video] and
  /// [error] says why; [warning] says what went wrong with a sound that's
  /// there (it stopped early, it's all silence).
  static Future<({XFile take, String? error, String? warning})> stop(
    XFile video,
  ) async {
    try {
      final reply = await channel.invokeMapMethod<String, Object?>('stop', {
        'video': video.path,
      });
      final path = reply?['path'] as String?;
      if (path == null) return (take: video, error: '?', warning: null);
      debugPrint(
        'TabCam: cam: the take\'s sound put in, '
        '${reply!['leadMs']} ms before the video dropped',
      );
      return (
        take: XFile(path, mimeType: 'video/mp4'),
        error: null,
        warning: reply['warning'] as String?,
      );
    } on PlatformException catch (e) {
      debugPrint('TabCam: cam: the take has no sound: $e');
      return (take: video, error: e.message ?? e.code, warning: null);
    } on Object catch (e) {
      debugPrint('TabCam: cam: the take has no sound: $e');
      return (take: video, error: '$e', warning: null);
    }
  }

  /// Drops the take's sound (the camera didn't start).
  static Future<void> cancel() => _quiet('cancel');

  /// Closes the microphone (Cam closes).
  static Future<void> release() async {
    if (supported) await _quiet('release');
  }

  static Future<void> _quiet(String method) async {
    try {
      await channel.invokeMethod<void>(method);
    } on Object catch (e) {
      debugPrint('TabCam: cam: the take\'s sound ($method): $e');
    }
  }
}

/// What [TakeSound.prepare] came to.
enum TakeSoundReady {
  /// The app records the takes' sound: the camera opens without it.
  ok,

  /// The microphone isn't allowed: the camera opens with sound (and asks
  /// for it again).
  refused,

  /// The app can't record it (no source works, or not Android): the
  /// camera records the takes' sound.
  unavailable,
}
