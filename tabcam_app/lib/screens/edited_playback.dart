import 'dart:async';
import 'dart:ui' show Size;

import 'package:video_player/video_player.dart';

import '../capture/render_plan.dart';
import '../capture/take_log.dart';
import '../library/page_edit.dart';

/// Plays [video] as a [RenderPlan] says (the one Download renders),
/// without making a file of it: the kept part only (from its start, when
/// outside it; at its end, back to its start, playing on when [loop]ing,
/// paused otherwise), the two lanes mixed: the video's own sound at its
/// volume (0: muted), and the song lane's player along it, playing in its
/// clips from where the plan says, paused between them, at its volume.
/// Checked every tenth of a second while it plays; every
/// [driftChecks] checks, while both play, the song's place is compared
/// with where the plan has it, and sought again when it's more than
/// [driftMost] off (a long video's song would otherwise drift on). While
/// it plays, both lanes fade in and out as the plan's fades say, their
/// volumes set again at each check (paused, they're at their levels).
/// The plan's layers (the tab), and its fades' black, are drawn over the
/// video by `EditLayers`. The players stay their owner's to dispose of.
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

  /// How far the lanes are faded in now (1: at their volumes).
  double _level = 1;

  /// The checks since the song's place was last compared.
  int _sinceDrift = 0;

  /// How often the song's drift is checked (every 2 s), and how far off
  /// it may be.
  static const driftChecks = 20;
  static const driftMost = Duration(milliseconds: 150);

  Duration get start => _plan?.start ?? Duration.zero;
  Duration get end {
    final length = video.value.duration;
    final end = _plan?.end;
    if (end == null) return length;
    return length > Duration.zero && end > length ? length : end;
  }

  /// The preview's plan of [edit] (null: the defaults), its song
  /// [songLength] long, of a video [duration] long with [takeLog] (one of
  /// Cam's takes: its tab is drawn over it), [title] being the capture's
  /// name as the title's default text (drawn unless the edit turns it off
  /// or types another), and its fades unless not [fades], over a [frame]
  /// that size (the video's, as shown; null: not known; the tab's bands
  /// go by it); null when that's the video as it is.
  static RenderPlan? planOf(
    PageEdit? edit, {
    Duration? songLength,
    Duration duration = Duration.zero,
    TakeLog? takeLog,
    List<String> title = const [],
    bool fades = true,
    Size? frame,
  }) {
    final plan = RenderPlan.of(
      edit,
      songLength: songLength ?? Duration.zero,
      duration: duration,
      takeLog: takeLog,
      title: title,
      preview: true,
      fades: fades,
      frame: frame,
    );
    return edit == null && plan.layers.isEmpty && !plan.fades.any ? null : plan;
  }

  /// Plays [plan] from now on (with [song] as the song lane's player);
  /// where the song plays is found again at the next check, unless only
  /// volumes changed (it plays on, as loud as now asked).
  Future<void> set(RenderPlan? plan, {VideoPlayerController? song}) async {
    final changedSong = !identical(song, _song);
    final moved = changedSong || plan?.timeline != _plan?.timeline;
    if (changedSong) await pauseSong();
    _plan = plan;
    _song = song;
    await _setLevel(_levelAt(video.value.position));
    if (moved && !changedSong) await pauseSong();
  }

  /// How far the lanes are faded in at [position] in the video, while it
  /// plays (paused: 1, at their levels).
  double _levelAt(Duration position) {
    final plan = _plan;
    if (plan == null || !video.value.isPlaying) return 1;
    return plan.fades.levelAt(position - start);
  }

  /// Both lanes at their volumes, faded to [level] (0 to 1).
  Future<void> _setLevel(double level) async {
    _level = level;
    final plan = _plan;
    await video.setVolume(plan == null ? 1 : (plan.own?.volume ?? 0) * level);
    await _song?.setVolume((plan?.song?.volume ?? 1) * level);
  }

  /// The lanes faded as they are at [position] in the video, if that's
  /// heard to have changed (a step of 1% or more, or to silence or to
  /// their levels).
  Future<void> _fade(Duration position) async {
    final level = _levelAt(position);
    if (level == _level) return;
    if ((level - _level).abs() >= 0.01 || level == 0 || level == 1) {
      await _setLevel(level);
    }
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
    await _fade(at);
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
      _sinceDrift = 0;
      await song.seekTo(into);
      await song.play();
    } else if (into == null && _songPlaying) {
      await pauseSong();
    } else if (into != null && ++_sinceDrift >= driftChecks) {
      _sinceDrift = 0;
      await _correctDrift(plan, song);
    }
  }

  /// Seeks the song to where the plan has it, if it's more than
  /// [driftMost] off: both players asked where they are now.
  Future<void> _correctDrift(
    RenderPlan plan,
    VideoPlayerController song,
  ) async {
    final videoAt = await video.position;
    final songAt = await song.position;
    if (videoAt == null || songAt == null || !_songPlaying) return;
    final want = plan.songAt(videoAt - start);
    if (want == null) return;
    if ((songAt - want).abs() > driftMost) await song.seekTo(want);
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
    var at = video.value.position;
    if (at < start || at >= end) {
      await video.seekTo(start);
      at = start;
    }
    // Faded in from where it starts, not loud until the first check.
    if (_plan?.fades.any ?? false) {
      await _setLevel(_plan!.fades.levelAt(at - start));
    }
    await video.play();
  }

  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    video.removeListener(_onVideo);
  }
}
