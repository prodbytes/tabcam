import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'take_recorder.dart' show TakeMic;

/// Recording comes first: while Cam records a take, its sound is what
/// matters most, so the take's recording gets the microphone as a
/// musician wants it (not as a voice call does), and what else runs
/// (sync, head gestures) waits or slows down. See specs/cam.md, "Recording comes first". Pure Dart (but
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
  /// MP4 only). VP8 before VP9: Chrome encodes both in software (libvpx),
  /// VP9 at several times VP8's cost while the take records; VP8 plays
  /// wherever VP9 does. H.264 (which Chrome may encode in hardware) isn't
  /// asked for: in a WebM, Firefox and Safari don't play it, and an MP4
  /// take would change what the app reads from the web's takes.
  static const List<String> webTypes = [
    'video/webm;codecs=vp8,opus',
    'video/webm;codecs=vp9,opus',
    'video/webm',
    'video/mp4',
  ];

  /// The camera's sound's bitrate on iOS (AAC, mono, 44.1 kHz there):
  /// left out, the encoder's default is low for music. (Android's camera
  /// takes none.)
  static const int iosAudioBitrate = 128000;

  /// How often head gestures look for a face: about 10 times a second,
  /// about 7 while a take records (enough for a nod, which takes most of
  /// a second out and back).
  static const Duration headInterval = Duration(milliseconds: 100);
  static const Duration headIntervalRecording = Duration(milliseconds: 150);
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
  /// camera's plugin leaves it so), and its preferred input to none.
  static Future<void> release() => _call('release');

  /// The session's inputs (the iPhone's microphone, wired and USB ones;
  /// not Bluetooth headsets, which the session's category leaves out),
  /// each `{id, name}`: [choose]'s `input`. Empty when it can't tell.
  static Future<List<TakeMic>> inputs() async {
    if (!supported) return const [];
    try {
      return TakeMic.fromChannel(await channel.invokeMethod<Object?>('inputs'));
    } on Object catch (e) {
      debugPrint('TabCam: cam: no list of microphones: $e');
      return const [];
    }
  }

  /// The session's preferred input, [input] (null: the system's choice),
  /// which the camera records the take's sound from. Whether it's set
  /// (false: not connected, or refused).
  static Future<bool> choose(String? input) async {
    if (!supported) return false;
    try {
      return await channel.invokeMethod<bool>('choose', {'input': input}) ??
          false;
    } on Object catch (e) {
      debugPrint('TabCam: cam: microphone $input: $e');
      return false;
    }
  }

  static Future<void> _call(String method) async {
    if (!supported) return;
    try {
      await channel.invokeMethod<void>(method);
    } on Object catch (e) {
      debugPrint('TabCam: cam: audio session ($method): $e');
    }
  }
}
