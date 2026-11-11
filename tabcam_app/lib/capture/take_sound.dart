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
/// itself, as before. Then each take: [start] before the camera starts,
/// [videoStarted] as soon as it has, [videoStopping] just before it's
/// stopped, and [stop] with the camera's video (or [cancel] if the camera
/// didn't start).
abstract final class TakeSound {
  static const channel = MethodChannel('tabcam/take_sound');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Asks for the microphone if it isn't allowed, and opens it: whether
  /// takes get their sound here (else the camera should record it).
  static Future<bool> prepare() async {
    if (!supported) return false;
    try {
      final info = await channel.invokeMapMethod<String, Object?>('prepare');
      if (info?['ok'] == true) {
        debugPrint(
          'TabCam: cam: the take\'s sound: ${info!['source']}, '
          '${info['sampleRate']} Hz, ${info['channels']} channel(s)',
        );
        return true;
      }
      debugPrint(
        'TabCam: cam: the camera records the take\'s sound: '
        '${info?['reason']}',
      );
    } on Object catch (e) {
      debugPrint('TabCam: cam: the camera records the take\'s sound: $e');
    }
    return false;
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
