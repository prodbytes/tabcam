import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ding_sound.dart';

/// The phones' player: channel `tabcam/sound`, method `ding`, the WAV's
/// bytes as its argument (Android's `Sound.kt`, iOS's `Sound` in
/// `AppDelegate.swift`).
const dingChannel = MethodChannel('tabcam/sound');

/// The phones need no tap to play a sound.
void primeDing() {}

Uint8List? _wav;

/// Plays the ding: Android as a notification sound, iOS as a system
/// sound, so it follows that volume and stays quiet on silent. Whether it
/// started: where there's no player (a computer, tests) nothing plays; a
/// failure is only logged.
Future<bool> playDing() async {
  try {
    await dingChannel.invokeMethod<void>('ding', _wav ??= dingWav());
    return true;
  } on MissingPluginException {
    return false; // no player here
  } on PlatformException catch (e) {
    debugPrint('TabCam: ding: $e');
    return false;
  }
}
