import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../library/capture_event.dart';
import '../library/library.dart';
import '../screens/video_page.dart';
import 'link_frame.dart';

/// Cam's backing track: one of the capture's recordings, videos or links,
/// played in a frame above the camera while the user plays along (and
/// records). A recording or video plays in the app ([media]); so does a
/// link straight to a sound or video file; any other link shows in a
/// frame ([link]). A recording or video of the capture's own can play
/// just a [section] of itself, over and over.
class BackingTrack extends ChangeNotifier {
  BackingTrack(this.library, {this.open = _open});

  final Library library;

  /// Opens a recording's or video's player; tests pass their own.
  final Future<VideoPlayerController> Function(
    Library library,
    CaptureEvent event,
    EventPage page,
  )
  open;

  static Future<VideoPlayerController> _open(
    Library library,
    CaptureEvent event,
    EventPage page,
  ) => openPlayer(library, event, page, mixWithOthers: true);

  /// Whether [page] can be a backing track.
  static bool plays(EventPage page) =>
      page.isAudio || page.isVideo || page.isLink;

  /// The file or link chosen, and what plays it once it's loaded.
  EventPage? get page => _page;
  EventPage? _page;
  VideoPlayerController? get media => _media;
  VideoPlayerController? _media;
  LinkFrameController? get link => _link;
  LinkFrameController? _link;

  /// Whether it starts over at its end; on by default.
  bool get repeat => _repeat;
  bool _repeat = true;

  /// Turns [repeat] on or off, for what plays now and what's chosen next.
  Future<void> setRepeat(bool on) async {
    _repeat = on;
    _link?.repeat = on;
    notifyListeners();
    await _media?.setLooping(on && section == null);
  }

  /// Whether a [section] can be set: a recording or video of the capture's
  /// own, loaded (not a link, which can't be held to the split second).
  bool get canSection =>
      _media != null && _page?.url == null && _duration > Duration.zero;

  Duration get _duration => _media?.value.duration ?? Duration.zero;

  /// The part that plays, from start to end; null: all of it. Each file
  /// keeps its own while the screen is open. With [repeat] it starts over
  /// at the section's start; without, it stops at its end.
  ({Duration start, Duration end})? get section => _sections[_page?.id];
  final _sections = <String, ({Duration start, Duration end})>{};

  /// The shortest section: anything shorter can't be played or looped.
  static const minSection = Duration(milliseconds: 500);

  /// Plays only from [start] to [end] (kept within the file, and at least
  /// [minSection] long); the whole file again when they cover it.
  Future<void> setSection(Duration start, Duration end) async {
    final id = _page?.id;
    final media = _media;
    if (id == null || media == null || !canSection) return;
    final length = _duration;
    start = _clamp(start, Duration.zero, length);
    end = _clamp(end, Duration.zero, length);
    if (end - start < minSection) {
      if (start + minSection <= length) {
        end = start + minSection;
      } else {
        start = length - minSection;
        end = length;
      }
    }
    final whole = start <= Duration.zero && end >= length;
    if (whole) {
      _sections.remove(id);
    } else {
      _sections[id] = (start: start, end: end);
    }
    notifyListeners();
    await _sectionChanged(media);
  }

  /// Starts (or, with [end], ends) the section where it plays now.
  Future<void> sectionHere({bool end = false}) async {
    final media = _media;
    if (media == null || !canSection) return;
    final at = media.value.position;
    final now = section ?? (start: Duration.zero, end: _duration);
    return end ? setSection(now.start, at) : setSection(at, now.end);
  }

  /// Plays all of it again.
  Future<void> clearSection() async {
    final media = _media;
    if (_sections.remove(_page?.id) == null) return;
    notifyListeners();
    if (media != null) await _sectionChanged(media);
  }

  Timer? _sectionTimer;

  /// The section's end is watched every [_sectionTick] while one is set
  /// (the player's own position updates are coarser); the player's own
  /// looping, back to the file's start, is off meanwhile.
  static const _sectionTick = Duration(milliseconds: 100);

  Future<void> _sectionChanged(VideoPlayerController media) async {
    final range = section;
    _sectionTimer?.cancel();
    _sectionTimer = null;
    await media.setLooping(_repeat && range == null);
    if (range == null) return;
    _sectionTimer = Timer.periodic(_sectionTick, (_) => _keepInSection());
    final at = media.value.position;
    if (at < range.start || at >= range.end) await media.seekTo(range.start);
  }

  bool _checking = false;

  /// At the section's end: back to its start, playing on with [repeat],
  /// paused without.
  Future<void> _keepInSection() async {
    final (media, range) = (_media, section);
    if (_checking || media == null || range == null) return;
    if (!media.value.isPlaying) return;
    _checking = true;
    try {
      final at = await media.position ?? media.value.position;
      if (_media != media || section != range) return;
      if (at >= range.end || at < range.start - const Duration(seconds: 1)) {
        if (!_repeat && at >= range.end) await media.pause();
        await media.seekTo(range.start);
      }
    } finally {
      _checking = false;
    }
  }

  static Duration _clamp(Duration d, Duration min, Duration max) =>
      d < min ? min : (d > max ? max : d);

  bool get loading => _loading;
  bool _loading = false;

  /// What failed, for the one that couldn't play.
  Object? get error => _error;
  Object? _error;

  bool _disposed = false;

  /// Whether play / pause reaches it ([toggle]).
  bool get canToggle => _media != null || (_link?.canToggle ?? false);

  /// Whether it plays, as far as the app knows.
  bool get playing => _media?.value.isPlaying ?? _link?.playing ?? false;

  /// Plays [page] in place of what played (or, without [play], loads it
  /// paused); [page] again plays or pauses it.
  Future<void> choose(
    CaptureEvent event,
    EventPage page, {
    bool play = true,
  }) async {
    if (_page?.id == page.id) return toggle();
    await close();
    _page = page;
    _loading = true;
    notifyListeners();
    try {
      final url = page.url;
      if (url != null && !isMediaUrl(url)) {
        _link = LinkFrameController(url, autoplay: play)
          ..repeat = _repeat
          ..addListener(notifyListeners);
        return;
      }
      final media = url != null
          ? VideoPlayerController.networkUrl(
              url,
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            )
          : await open(library, event, page);
      if (url != null) {
        try {
          await media.initialize();
        } on Object {
          await media.dispose();
          rethrow;
        }
      }
      if (_disposed || _page?.id != page.id) {
        await media.dispose();
        return;
      }
      _media = media..addListener(notifyListeners);
      if (section != null) {
        await _sectionChanged(media);
      } else {
        await media.setLooping(_repeat);
      }
      if (play) await media.play();
    } on Object catch (e) {
      debugPrint('TabCam: cam: ${page.fileName} can\'t play here: $e');
      if (_page?.id == page.id) _error = e;
    } finally {
      if (_page?.id == page.id) _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Plays or pauses it; at its end (its section's), plays it from the
  /// start (the section's).
  Future<void> toggle() async {
    if (_media case final media?) {
      final v = media.value;
      if (v.isPlaying) return media.pause();
      if (section case final range?) {
        if (v.position < range.start || v.position >= range.end) {
          await media.seekTo(range.start);
        }
      } else if (v.duration > Duration.zero && v.position >= v.duration) {
        await media.seekTo(Duration.zero);
      }
      return media.play();
    }
    await _link?.toggle();
  }

  /// Goes [by] forward (back, negative), within its start and end (its
  /// section's).
  Future<void> skip(Duration by) async {
    if (_media case final media?) {
      final v = media.value;
      final range = section ?? (start: Duration.zero, end: v.duration);
      var to = v.position + by;
      if (to < range.start) to = range.start;
      if (v.duration > Duration.zero && to > range.end) to = range.end;
      return media.seekTo(to);
    }
    await _link?.skip(by);
  }

  /// Pauses it (a take plays back).
  Future<void> pause() async {
    await _media?.pause();
    await _link?.pause();
  }

  /// Pauses it, back at its start (its section's).
  Future<void> stop() async {
    if (_media case final media?) {
      await media.pause();
      return media.seekTo(section?.start ?? Duration.zero);
    }
    await _link?.stop();
  }

  /// Stops it, and lets go of it.
  Future<void> close() async {
    _sectionTimer?.cancel();
    _sectionTimer = null;
    final (media, link) = (_media, _link);
    _media = null;
    _link = null;
    _page = null;
    _loading = false;
    _error = null;
    if (!_disposed) notifyListeners();
    media?.removeListener(notifyListeners);
    link?.removeListener(notifyListeners);
    await media?.dispose();
    link?.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    _sectionTimer?.cancel();
    _media?.removeListener(notifyListeners);
    _media?.dispose();
    _link?.removeListener(notifyListeners);
    _link?.dispose();
    super.dispose();
  }
}

const _mediaExtensions = {
  'mp3', 'm4a', 'aac', 'wav', 'ogg', 'oga', 'opus', 'flac', //
  'mp4', 'm4v', 'mov', 'webm',
};

/// Whether [url] is straight to a sound or video file (its path ends in
/// one's extension), which the app plays itself.
bool isMediaUrl(Uri url) {
  final path = url.path.toLowerCase();
  final dot = path.lastIndexOf('.');
  return dot >= 0 && _mediaExtensions.contains(path.substring(dot + 1));
}
