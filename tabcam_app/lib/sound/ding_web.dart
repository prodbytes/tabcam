import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'ding_sound.dart';

/// The page's sound, made or woken by [primeDing] in a tap: a browser
/// plays sound only once the user has done something on the page, and
/// Safari only when it was started from a tap's own handler. Put to sleep
/// after each ding.
web.AudioContext? _audio;

/// Wakes the page's sound, from a tap (the one that starts the wait), so
/// the ding can play when the wait ends.
void primeDing() {
  try {
    final audio = _audio ??= web.AudioContext();
    if (audio.state != 'running') audio.resume();
  } catch (e) {
    debugPrint('TabCam: ding: $e');
  }
}

/// Plays the ding through Web Audio; whether it started. When the browser
/// won't wake the sound (no tap woke it), nothing plays, rather than the
/// ding coming late at the next tap.
Future<bool> playDing() async {
  try {
    final audio = _audio ??= web.AudioContext();
    if (audio.state != 'running') {
      await audio.resume().toDart.timeout(const Duration(milliseconds: 500));
    }
    final samples = dingSamples(audio.sampleRate.round());
    final buffer = audio.createBuffer(1, samples.length, audio.sampleRate);
    buffer.copyToChannel(samples.toJS, 0);
    final source = audio.createBufferSource()..buffer = buffer;
    source.connect(audio.destination);
    source.onended = ((web.Event _) {
      audio.suspend();
    }).toJS;
    source.start();
    return true;
  } catch (e) {
    debugPrint('TabCam: ding: $e');
    return false;
  }
}
