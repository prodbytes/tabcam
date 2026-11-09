/// The metronome's sound: [MetronomeSound], played with Web Audio on the
/// web ([metronome_sound_web.dart]) and as a looping WAV through the
/// platform's media player elsewhere ([metronome_sound_io.dart]).
library;

import 'click_track.dart';

export 'metronome_sound_io.dart'
    if (dart.library.js_interop) 'metronome_sound_web.dart';

/// Plays the clicks, or a fake in tests.
abstract interface class MetronomeSound {
  /// Plays [signature]'s clicks at [bpm], from its bar's first beat, until
  /// [stop] (a playing one starts over with these). Completes when the
  /// first click sounds; throws when it can't play.
  Future<void> start(int bpm, TimeSignature signature);

  Future<void> stop();
}
