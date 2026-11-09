import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'click_track.dart';
import 'metronome_sound.dart';

/// Android, iOS and macOS: whole bars of clicks made here as a WAV
/// ([clickTrackWav], at least 20 seconds), kept in the cache folder and
/// looped by the platform's media player, mixed with whatever else plays
/// (the play-along track). The clicks keep time within the file; the loop
/// starts over between bars.
class PlatformMetronomeSound implements MetronomeSound {
  VideoPlayerController? _player;

  @override
  Future<void> start(int bpm, TimeSignature signature) async {
    await stop();
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/metronome-$bpm-${signature.beats}-${signature.unit}.wav',
    );
    if (!await file.exists()) {
      await file.writeAsBytes(
        clickTrackWav(bpm: bpm, signature: signature),
        flush: true,
      );
    }
    final player = VideoPlayerController.file(
      file,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _player = player;
    await player.initialize();
    await player.setLooping(true);
    if (_player != player) {
      await player.dispose(); // stopped meanwhile
      return;
    }
    await player.play();
  }

  @override
  Future<void> stop() async {
    final player = _player;
    _player = null;
    if (player == null) return;
    await player.pause();
    await player.dispose();
  }
}
