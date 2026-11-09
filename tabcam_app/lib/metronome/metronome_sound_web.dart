import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'click_track.dart';
import 'metronome_sound.dart';

/// Web Audio: each click an oscillator scheduled on the audio clock a
/// little ahead (a 25 ms timer schedules the next 100 ms), so they keep
/// time even when the page is busy.
class PlatformMetronomeSound implements MetronomeSound {
  web.AudioContext? _audio;
  Timer? _timer;
  double _next = 0;
  int _beat = 0;

  static const _ahead = 0.1;

  @override
  Future<void> start(int bpm, TimeSignature signature) async {
    await stop();
    final audio = _audio ??= web.AudioContext();
    // Browsers start it suspended until the user does something: Start is.
    await audio.resume().toDart;
    final accents = signature.accents;
    final interval = 60 / bpm;
    _beat = 0;
    _next = audio.currentTime + 0.05;
    void schedule() {
      while (_next < audio.currentTime + _ahead) {
        _click(audio, accents[_beat], _next);
        _next += interval;
        _beat = (_beat + 1) % accents.length;
      }
    }

    schedule();
    _timer = Timer.periodic(
      const Duration(milliseconds: 25),
      (_) => schedule(),
    );
  }

  void _click(web.AudioContext audio, Accent accent, double at) {
    final tone = audio.createOscillator()..frequency.value = accent.hertz;
    final level = audio.createGain();
    level.gain
      ..setValueAtTime(0.0001, at)
      ..exponentialRampToValueAtTime(accent.volume, at + 0.001)
      ..exponentialRampToValueAtTime(
        0.0001,
        at + clickLength.inMilliseconds / 1000,
      );
    tone.connect(level);
    level.connect(audio.destination);
    tone
      ..start(at)
      ..stop(at + clickLength.inMilliseconds / 1000 + 0.01);
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }
}
