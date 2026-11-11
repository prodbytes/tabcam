import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Recording comes first: while Cam records a take, its sound is what
/// matters most, so the take's recording gets the microphone as a
/// musician wants it (not as a voice call does), and what else runs
/// (sync, head gestures, the tab drawn into the web's take) waits or
/// slows down. See specs/cam.md, "Recording comes first". Pure Dart (but
/// for [TakeAudio]'s channel), tested without a camera
/// (test/take_priority_test.dart).
abstract final class TakePriority {
  /// Whether a take is recording now. Cloud sync starts no pass while it
  /// is ([CloudSync]); one asked for meanwhile runs when the take ends.
  static final ValueNotifier<bool> recording = ValueNotifier(false);

  /// The microphone for a take in the browser (getUserMedia's audio
  /// constraints): no echo cancellation (it takes out the song playing
  /// along), no noise suppression (it takes held notes for noise), no
  /// automatic gain (it pumps the level), no voice isolation; two
  /// channels and 48 kHz where the microphone has them. Asked for, not
  /// required ("ideal", plain booleans): a browser that can't still opens
  /// the microphone.
  static const Map<String, Object> webMicConstraints = {
    'echoCancellation': false,
    'noiseSuppression': false,
    'autoGainControl': false,
    'voiceIsolation': false,
    'channelCount': {'ideal': 2},
    'sampleRate': {'ideal': 48000},
  };

  /// The browser's take: its sound's bitrate (Opus or AAC; left to the
  /// browser, it can be as low as speech wants) and its video's (720p).
  static const int webAudioBitrate = 192000;
  static const int webVideoBitrate = 5000000;

  /// The browser's take's formats, the first it records taken (Safari:
  /// MP4 only). VP8 before VP9: VP9 is encoded in software, and costs the
  /// processor several times more while the take records; VP8, the older,
  /// plays wherever VP9 does.
  static const List<String> webTypes = [
    'video/webm;codecs=vp8,opus',
    'video/webm;codecs=vp9,opus',
    'video/webm',
    'video/mp4',
  ];

  /// How many frames a second the tab is drawn into the browser's take:
  /// the camera's own rate, not the display's (60 to 120).
  static const int webFps = 30;

  /// The camera's sound's bitrate on iOS (AAC, mono, 44.1 kHz there):
  /// left out, the encoder's default is low for music. (Android's camera
  /// takes none.)
  static const int iosAudioBitrate = 128000;

  /// How often head gestures look for a face: about 10 times a second,
  /// about 7 while a take records (enough for a nod, which takes most of
  /// a second out and back).
  static const Duration headInterval = Duration(milliseconds: 100);
  static const Duration headIntervalRecording = Duration(milliseconds: 150);

  /// Whether a frame drawn at [last] (milliseconds, as
  /// requestAnimationFrame gives them; null: none yet) leaves one due at
  /// [now], at [fps] a second: a frame comes from the display a little
  /// early or late, so a few milliseconds early counts.
  static bool frameDue(num? last, num now, {int fps = webFps}) =>
      last == null || now - last >= 1000 / fps - 4;
}

/// iOS: the app's audio session set for a take ([prepare]) when Cam opens
/// and again as a take starts, and set back ([release]) when Cam closes.
/// Method channel `tabcam/audio` (ios/Runner/AppDelegate.swift). Elsewhere
/// it does nothing.
abstract final class TakeAudio {
  static const channel = MethodChannel('tabcam/audio');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Play and record, in the video recording mode (the microphone by the
  /// camera, no voice processing), mixed with others (the song playing
  /// along, in the app or another, goes on and isn't lowered), at 48 kHz.
  static Future<void> prepare() => _call('prepare');

  /// The session's mode back to the default (the category stays: the
  /// camera's plugin leaves it so).
  static Future<void> release() => _call('release');

  static Future<void> _call(String method) async {
    if (!supported) return;
    try {
      await channel.invokeMethod<void>(method);
    } on Object catch (e) {
      debugPrint('TabCam: cam: audio session ($method): $e');
    }
  }
}
