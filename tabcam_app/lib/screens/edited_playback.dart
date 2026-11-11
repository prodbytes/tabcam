import 'dart:async';

import 'package:video_player/video_player.dart';

import '../library/page_edit.dart';

/// Plays [video] as an edit says, without making a file of it: the kept
/// part only (from its start, when outside it; at its end, back to its
/// start, playing on when [loop]ing, paused otherwise), with the video's
/// own sound, none, or, muted, the new [track] along it, started where it
/// comes in, at the edit's track volume. Checked every tenth of a second
/// while it plays. The players stay their owner's to dispose of.
class EditedPlayback {
  EditedPlayback(this.video, {this.loop = false}) {
    video.addListener(_onVideo);
  }

  final VideoPlayerController video;
  final bool loop;

  /// The edit played; null plays the video as it is.
  PageEdit? get edit => _edit;
  PageEdit? _edit;

  /// The new track's player, for [EditSound.track].
  VideoPlayerController? get track => _track;
  VideoPlayerController? _track;

  Timer? _ticker;
  bool _trackPlaying = false;
  Duration? _last;

  Duration get start => _edit?.start ?? Duration.zero;
  Duration get end {
    final length = video.value.duration;
    final end = _edit?.end;
    if (end == null) return length;
    return length > Duration.zero && end > length ? length : end;
  }

  /// Plays [edit] from now on (with [track] for its new track, at the
  /// edit's track volume); what the track plays is found again at the next
  /// check, unless only its volume changed (it plays on, as loud as now
  /// asked).
  Future<void> set(PageEdit? edit, {VideoPlayerController? track}) async {
    final changedTrack = !identical(track, _track);
    final moved =
        changedTrack || edit?.withTrackVolume(1) != _edit?.withTrackVolume(1);
    if (changedTrack) await pauseTrack();
    _edit = edit;
    _track = track;
    await video.setVolume(
      edit == null || edit.sound == EditSound.original ? 1 : 0,
    );
    await track?.setVolume(edit?.trackVolume ?? 1);
    if (moved && !changedTrack) await pauseTrack();
  }

  void _onVideo() {
    if (video.value.isPlaying) {
      _ticker ??= Timer.periodic(const Duration(milliseconds: 100), _tick);
    } else if (_ticker != null) {
      _ticker?.cancel();
      _ticker = null;
      _last = null;
      unawaited(pauseTrack());
    }
  }

  Future<void> _tick(Timer _) async {
    if (!video.value.isPlaying) return;
    final at = video.value.position;
    final last = _last;
    _last = at;
    if (at >= end || at < start - const Duration(milliseconds: 250)) {
      await pauseTrack();
      await video.seekTo(start);
      if (!loop && at >= end) await video.pause();
      return;
    }
    final edit = _edit;
    final track = _track;
    if (edit == null || track == null || edit.sound != EditSound.track) {
      return;
    }
    // Sought: the track finds its place again.
    if (last != null && (at - last).abs() > const Duration(seconds: 1)) {
      await pauseTrack();
    }
    // Where in the track the video is: its used part starts [offset]
    // into the kept part.
    final trackEnd = edit.trackEnd ?? track.value.duration;
    final into = edit.trackStart + (at - start - edit.offset);
    final within = into >= edit.trackStart && into < trackEnd;
    if (within && !_trackPlaying) {
      _trackPlaying = true;
      await track.seekTo(into);
      await track.play();
    } else if (!within && _trackPlaying) {
      await pauseTrack();
    }
  }

  Future<void> pauseTrack() async {
    if (!_trackPlaying) return;
    _trackPlaying = false;
    await _track?.pause();
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
