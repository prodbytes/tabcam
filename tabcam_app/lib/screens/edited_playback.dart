import 'dart:async';

import 'package:video_player/video_player.dart';

import '../capture/render_plan.dart';
import '../library/page_edit.dart';

/// Plays [video] as a [RenderPlan] says (the one Download renders),
/// without making a file of it: the kept part only (from its start, when
/// outside it; at its end, back to its start, playing on when [loop]ing,
/// paused otherwise), with the video's own sound at its volume, or muted,
/// and the song lane's player along it, playing in its clips from where
/// the plan says, paused between them, at its volume. Checked every tenth
/// of a second while it plays. The players stay their owner's to dispose
/// of.
class EditedPlayback {
  EditedPlayback(this.video, {this.loop = false}) {
    video.addListener(_onVideo);
  }

  final VideoPlayerController video;
  final bool loop;

  /// The plan played; null plays the video as it is.
  RenderPlan? get plan => _plan;
  RenderPlan? _plan;

  /// The song lane's player.
  VideoPlayerController? get song => _song;
  VideoPlayerController? _song;

  Timer? _ticker;
  bool _songPlaying = false;
  Duration? _last;

  Duration get start => _plan?.start ?? Duration.zero;
  Duration get end {
    final length = video.value.duration;
    final end = _plan?.end;
    if (end == null) return length;
    return length > Duration.zero && end > length ? length : end;
  }

  /// The preview's plan of [edit] (null: the video as it is), its song
  /// [songLength] long.
  static RenderPlan? planOf(PageEdit? edit, {Duration? songLength}) =>
      edit == null
      ? null
      : RenderPlan.of(edit, songLength: songLength ?? Duration.zero);

  /// Plays [plan] from now on (with [song] as the song lane's player);
  /// where the song plays is found again at the next check, unless only
  /// volumes changed (it plays on, as loud as now asked).
  Future<void> set(RenderPlan? plan, {VideoPlayerController? song}) async {
    final changedSong = !identical(song, _song);
    final moved = changedSong || plan?.timeline != _plan?.timeline;
    if (changedSong) await pauseSong();
    _plan = plan;
    _song = song;
    await video.setVolume(plan == null ? 1 : plan.own?.volume ?? 0);
    await song?.setVolume(plan?.song?.volume ?? 1);
    if (moved && !changedSong) await pauseSong();
  }

  void _onVideo() {
    if (video.value.isPlaying) {
      _ticker ??= Timer.periodic(const Duration(milliseconds: 100), _tick);
    } else if (_ticker != null) {
      _ticker?.cancel();
      _ticker = null;
      _last = null;
      unawaited(pauseSong());
    }
  }

  Future<void> _tick(Timer _) async {
    if (!video.value.isPlaying) return;
    final at = video.value.position;
    final last = _last;
    _last = at;
    if (at >= end || at < start - const Duration(milliseconds: 250)) {
      await pauseSong();
      await video.seekTo(start);
      if (!loop && at >= end) await video.pause();
      return;
    }
    final plan = _plan;
    final song = _song;
    if (plan == null || song == null || plan.song == null) return;
    // Sought: the song finds its place again.
    if (last != null && (at - last).abs() > const Duration(seconds: 1)) {
      await pauseSong();
    }
    final into = plan.songAt(at - start);
    if (into != null && !_songPlaying) {
      _songPlaying = true;
      await song.seekTo(into);
      await song.play();
    } else if (into == null && _songPlaying) {
      await pauseSong();
    }
  }

  Future<void> pauseSong() async {
    if (!_songPlaying) return;
    _songPlaying = false;
    await _song?.pause();
  }

  /// Plays the kept part (from its start, when outside it), or pauses.
  Future<void> playPause() async {
    if (video.value.isPlaying) {
      await video.pause();
      return;
    }
    final at = video.value.position;
    if (at < start || at >= end) await video.seekTo(start);
    await video.play();
  }

  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    video.removeListener(_onVideo);
  }
}
