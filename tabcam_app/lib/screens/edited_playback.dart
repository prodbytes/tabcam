import 'dart:async';
import 'dart:math' show min;
import 'dart:ui' show Size;

import 'package:video_player/video_player.dart';

import '../capture/render_plan.dart';
import '../capture/take_log.dart';
import '../library/page_edit.dart';

/// Plays [video] as a [RenderPlan] says (the one Download renders),
/// without making a file of it, the two lanes mixed: the video's own
/// sound at its volume (0: muted), and the song lane's player along it,
/// playing in its clips from where the plan says, paused between them,
/// at its volume. What it plays of the video is one of two:
///
/// - the kept part only (the file screen's player): from its start, when
///   outside it; at its end, back to its start, playing on when
///   [loop]ing, paused otherwise;
/// - the [whole] video (the editor's preview): from where it is, also in
///   a part cut off, which plays as the video is (its own sound at its
///   lane's level, no song, no fades). Playing into the kept part's end
///   it pauses there, and Play then starts at the kept part's start, as
///   it does at the video's end; sought past the kept part's end
///   ([seek]), it plays on to the video's end. A video whose length
///   isn't known has no end to stop at.
///
/// Checked every tenth of a second while it plays (one check at a time,
/// none while a seek is under way). **The song is kept in step with the
/// video** at every check, while both play: both players are asked where
/// they are at once, and the song's error against where the plan has it
/// is corrected. Within [inStep] (a few milliseconds, below what's heard
/// as two sounds) it plays at its speed; up to [seekBeyond] off, its
/// speed is nudged (at most [speedMost] either way, so it's heard as the
/// same song) to catch up over about a second, then put back; further
/// off (a seek, a stall), it's sought again. Its start is sought a
/// little ahead of the video ([_lead]), by as much as it was found late
/// the last times it started (its player's start-up, learnt as it
/// plays), so it starts in step rather than catching up. While it plays, both lanes fade in
/// and out as the plan's fades say, their volumes set again at each
/// check (paused, they're at their levels). The plan's layers (the tab),
/// and its fades' black, are drawn over the video by `EditLayers`. The
/// players stay their owner's to dispose of.
class EditedPlayback {
  EditedPlayback(this.video, {this.loop = false, this.whole = false})
    : assert(!(loop && whole)) {
    video.addListener(_onVideo);
  }

  final VideoPlayerController video;
  final bool loop;

  /// Whether the whole video plays, the parts cut off too (the editor's
  /// preview), not the kept part only.
  final bool whole;

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

  /// How far off the song may be and play at its speed: below what's
  /// heard as two sounds apart.
  static const inStep = Duration(milliseconds: 8);

  /// How far off the song is sought again, rather than nudged.
  static const seekBeyond = Duration(milliseconds: 250);

  /// The most the song's speed is nudged either way to catch up (5%).
  static const speedMost = 0.05;

  /// The most the song's start is sought ahead of the video ([_lead]).
  static const leadMost = Duration(milliseconds: 400);

  /// How far ahead of the video the song's start is sought: its player's
  /// start-up, as found the last times it started.
  Duration _lead = Duration.zero;

  /// Whether the next check learns [_lead] (the song just started).
  bool _learnLead = false;

  /// The song's speed now (1, or nudged to catch up).
  double _songSpeed = 1;

  /// A Play or a Pause being carried out: another pressed meanwhile is
  /// dropped (a pause sent while the browser still starts playing fails
  /// its player).
  bool _toggling = false;

  /// How long a player is waited for to start playing: one that never
  /// does (a browser stuck on a seek) can then be paused, and holds
  /// nothing else back.
  static const _startMost = Duration(seconds: 3);

  /// The song's player being started: it's paused only once that's over
  /// (as [_toggling], for the song).
  Future<void>? _songStarting;

  /// A check being made: the next one is skipped, not made over it (a
  /// player whose seek takes longer than a check).
  bool _ticking = false;

  /// The seeks under way ([seek]), and the last one asked.
  int _seeking = 0;
  Future<void>? _sought;

  /// Whether it stopped by itself at the kept part's end ([whole]): Play
  /// then starts at the kept part's start.
  bool _ended = false;

  /// The most the video moves on between two checks while it plays: a
  /// longer step past the kept part's end is a seek, not its end reached.
  static const _stepMost = Duration(seconds: 2);

  Duration get start => _plan?.start ?? Duration.zero;
  Duration get end {
    final length = video.value.duration;
    final end = _plan?.end;
    if (end == null) return length;
    return length > Duration.zero && end > length ? length : end;
  }

  /// Where the [whole] video stops by itself, the kept part's end; null
  /// while the video's length isn't known (it has none to stop at).
  Duration? get _stop => end > Duration.zero ? end : null;

  /// Whether [at] in the video is in the kept part.
  bool _kept(Duration at) {
    final stop = _stop;
    return at >= start && (stop == null || at < stop);
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
  /// plays (paused: 1, at their levels; so is a part cut off, of the
  /// [whole] video).
  double _levelAt(Duration position) {
    final plan = _plan;
    if (plan == null || !video.value.isPlaying) return 1;
    if (whole && !_kept(position)) return 1;
    return plan.fades.levelAt(position - start);
  }

  /// Both lanes at their volumes, faded to [level] (0 to 1). The players
  /// play nothing louder than it is: a lane the master lifts past 100%
  /// plays at 100% here, and only Download's file is louder.
  Future<void> _setLevel(double level) async {
    _level = level;
    final plan = _plan;
    double heard(double volume) => min(1, volume * level);
    await video.setVolume(plan == null ? 1 : heard(plan.own?.volume ?? 0));
    await _song?.setVolume(heard(plan?.song?.volume ?? 1));
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
    if (_ticking || _seeking > 0 || !video.value.isPlaying) return;
    _ticking = true;
    try {
      await _check();
    } finally {
      _ticking = false;
    }
  }

  /// One check while it plays: the kept part's end, the fades, and where
  /// the song is.
  Future<void> _check() async {
    final at = video.value.position;
    final last = _last;
    _last = at;
    final sought = _sought;
    if (whole) {
      // The kept part's end passed while playing on (not sought over):
      // paused there.
      final stop = _stop;
      if (stop != null &&
          last != null &&
          last < stop &&
          at >= stop &&
          at - last < _stepMost) {
        _ended = true;
        await pauseSong();
        // Sought meanwhile: it plays on from there.
        if (!identical(sought, _sought)) return;
        await video.pause();
        if (identical(sought, _sought)) await video.seekTo(stop);
        return;
      }
    } else if (at >= end || at < start - const Duration(milliseconds: 250)) {
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
    // Paused or sought meanwhile: the song isn't put where the video was.
    if (!video.value.isPlaying || !identical(sought, _sought)) return;
    final into = plan.songAt(at - start);
    if (into != null && !_songPlaying) {
      _songPlaying = true;
      _learnLead = true;
      await _setSongSpeed(song, 1);
      await song.seekTo(into + _lead);
      // Unless paused meanwhile.
      if (_songPlaying) await _startSong(song);
    } else if (into == null && _songPlaying) {
      await pauseSong();
    } else if (into != null && _songStarting == null) {
      await _keepInStep(plan, song);
    }
  }

  /// Keeps the song in step with the video: both players asked where
  /// they are at once, the song nudged or sought to where the plan has
  /// it (see the class's doc).
  Future<void> _keepInStep(RenderPlan plan, VideoPlayerController song) async {
    final (videoAt, songAt) = await (video.position, song.position).wait;
    if (videoAt == null || songAt == null || !_songPlaying) return;
    final want = plan.songAt(videoAt - start);
    if (want == null) return;
    final error = songAt - want;
    // Just started: how late it was is how far ahead the next start goes.
    if (_learnLead) {
      _learnLead = false;
      if (error.abs() <= seekBeyond * 2) {
        final lead = _lead - error;
        _lead = lead < Duration.zero
            ? Duration.zero
            : lead > leadMost
            ? leadMost
            : lead;
      }
    }
    if (error.abs() > seekBeyond) {
      await _setSongSpeed(song, 1);
      await song.seekTo(want + _lead);
      _learnLead = true;
      return;
    }
    if (error.abs() <= inStep) {
      await _setSongSpeed(song, 1);
      return;
    }
    // Caught up over about a second: ahead, a little slower; behind, a
    // little faster.
    final speed = (1 - error.inMicroseconds / 1e6).clamp(
      1 - speedMost,
      1 + speedMost,
    );
    await _setSongSpeed(song, speed);
  }

  /// The song at [speed], unless it's that (or within 0.2% of it) already.
  Future<void> _setSongSpeed(VideoPlayerController song, double speed) async {
    if ((speed - _songSpeed).abs() < 0.002) return;
    _songSpeed = speed;
    await song.setPlaybackSpeed(speed);
  }

  /// Starts [song], waited for [_startMost] at most.
  Future<void> _startSong(VideoPlayerController song) async {
    final starting = song.play().timeout(_startMost, onTimeout: () {});
    _songStarting = starting;
    try {
      await starting;
    } finally {
      if (identical(_songStarting, starting)) _songStarting = null;
    }
  }

  Future<void> pauseSong() async {
    if (!_songPlaying) return;
    _songPlaying = false;
    final song = _song;
    final starting = _songStarting;
    if (starting != null) {
      try {
        await starting;
      } on Object {
        // Its check's to hear of.
      }
      // Started again meanwhile: it plays on.
      if (_songPlaying) return;
    }
    await song?.pause();
  }

  /// Goes to [at] in the video: playing on from there when it plays,
  /// paused there when it doesn't. The song finds its place again at the
  /// next check. Seeks reach the player in the order they're asked.
  Future<void> seek(Duration at) => _sought = _seek(at);

  Future<void> _seek(Duration at) async {
    _seeking++;
    _ended = false;
    try {
      await Future.wait([video.seekTo(at), pauseSong()]);
      _last = null;
      await _fade(at);
    } finally {
      _seeking--;
    }
  }

  /// Plays, or pauses. The kept part only: from its start, when outside
  /// it. The [whole] video: from where it is (where the last [seek] goes,
  /// once it got there); from the kept part's start where it stopped by
  /// itself at its end, or at the video's end.
  Future<void> playPause() async {
    if (_toggling) return;
    _toggling = true;
    try {
      if (video.value.isPlaying) {
        await video.pause();
        return;
      }
      // A seek still under way (a player that says where it is only once
      // it got there): played from where it goes.
      final sought = _sought;
      if (sought != null) {
        try {
          await sought;
        } on Object {
          // Its asker's to hear of.
        }
      }
      var at = video.value.position;
      final length = video.value.duration;
      final restart = whole
          ? (_ended && !_kept(at)) || (length > Duration.zero && at >= length)
          : at < start || at >= end;
      if (restart) {
        await video.seekTo(start);
        at = start;
      }
      _ended = false;
      // Faded in from where it starts, not loud until the first check.
      if (_plan?.fades.any ?? false) {
        await _setLevel(
          whole && !_kept(at) ? 1 : _plan!.fades.levelAt(at - start),
        );
      }
      // Where it starts from: the kept part's end is seen passed from the
      // first check on.
      if (whole) _last = at;
      await video.play().timeout(_startMost, onTimeout: () {});
    } finally {
      _toggling = false;
    }
  }

  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    video.removeListener(_onVideo);
  }
}
