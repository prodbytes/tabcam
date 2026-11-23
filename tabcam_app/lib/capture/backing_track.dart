import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../library/capture_event.dart';
import '../library/library.dart';
import '../library/meta_names.dart';
import '../screens/video_page.dart';
import 'link_frame.dart';
import 'take_priority.dart';

/// Cam's backing track: one of the capture's recordings, videos or links,
/// played in a frame above the camera while the user plays along (and
/// records). A recording or video plays in the app ([media]); so does a
/// link straight to a sound or video file; any other link shows in a
/// frame ([link]). A recording or video of the capture's own can play
/// just a [section] of itself, over and over; what plays in the app can
/// play slower (or faster), at a [speed]. What plays in the app keeps
/// the [phrases] passed while Cam recorded along with it. Play waits a
/// [countIn] first, in silence, for the user to get to the instrument;
/// while a take records it always does ([countsIn]), and each time it
/// starts over too, so the take has room before the song.
class BackingTrack extends ChangeNotifier {
  BackingTrack(
    this.library, {
    this.open = _open,
    ValueListenable<bool>? recording,
  }) : _recording = recording ?? TakePriority.recording {
    _recording.addListener(_recordingChanged);
    unawaited(_loadSettings());
  }

  final Library library;

  /// Whether a take records now ([TakePriority.recording]; tests pass
  /// their own).
  final ValueListenable<bool> _recording;

  /// Whether a take records now: the progress bar's part played is red
  /// then, else the primary colour.
  bool get recording => _recording.value;

  void _recordingChanged() {
    if (_disposed) return;
    if (_media case final media?) unawaited(_loopChanged(media));
    notifyListeners();
  }

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

  /// The capture it's from.
  String? _eventId;
  VideoPlayerController? get media => _media;
  VideoPlayerController? _media;
  LinkFrameController? get link => _link;
  LinkFrameController? _link;

  /// The device's meta file the player's settings are kept in.
  static const metaName = MetaNames.playAlong;

  Future<void> _loadSettings() async {
    try {
      final json = await library.readMeta(metaName);
      if (json == null || _disposed) return;
      final map = jsonDecode(json);
      if (map is Map && map['countIn'] == false && !_countInSet) {
        _countIn = false;
        notifyListeners();
      }
    } on Object catch (e) {
      debugPrint('TabCam: play-along settings unreadable: $e');
    }
  }

  /// How long the count-in waits.
  static const countInLength = Duration(seconds: 2);

  /// Whether play waits [countInLength] first, in silence (the user moves
  /// from the keyboard or the screen to the instrument), and waits again
  /// each time it starts over ([repeat]); on by default, kept on the
  /// device. Only what plays in the app waits: a link in a frame plays at
  /// once. While a take records it waits whatever this says
  /// ([countsIn]).
  bool get countIn => _countIn;
  bool _countIn = true;

  /// Whether play waits [countInLength] now, and each start over too: with
  /// [countIn] on, and always while a take records (the take has the
  /// user's breath before the song, and room to line the song up in).
  bool get countsIn => _countIn || _recording.value;

  /// Whether the user set [countIn] before the device's setting loaded.
  bool _countInSet = false;

  /// Turns [countIn] on or off (off, a count-in under way plays at once),
  /// and keeps it on the device.
  Future<void> setCountIn(bool on) async {
    _countInSet = true;
    if (on == _countIn) return;
    _countIn = on;
    final media = _media;
    if (!countsIn && _cancelCountIn() && media != null) await media.play();
    if (media != null) await _loopChanged(media);
    notifyListeners();
    try {
      await library.writeMeta(metaName, jsonEncode({'countIn': on}));
    } on Object catch (e) {
      debugPrint('TabCam: play-along settings not saved: $e');
    }
  }

  /// Whether it's counting in: play was pressed, and it plays once
  /// [countInLength] has passed.
  bool get countingIn => _countInTimer != null;
  Timer? _countInTimer;

  /// Counts the count-ins, so each one's display starts over.
  int get countInRun => _countInRun;
  int _countInRun = 0;

  /// Plays [media], after the count-in if there's one ([countsIn]).
  Future<void> _play(VideoPlayerController media) async {
    _cancelCountIn();
    if (!countsIn) return media.play();
    _countInRun++;
    _countInTimer = Timer(countInLength, () {
      _countInTimer = null;
      if (_disposed || _media != media) return;
      unawaited(media.play());
      notifyListeners();
    });
    notifyListeners();
  }

  /// Stops the count-in, if one is under way (it doesn't play); whether
  /// one was.
  bool _cancelCountIn() {
    final timer = _countInTimer;
    if (timer == null) return false;
    timer.cancel();
    _countInTimer = null;
    if (!_disposed) notifyListeners();
    return true;
  }

  /// Whether it starts over at its end; on by default.
  bool get repeat => _repeat;
  bool _repeat = true;

  /// Turns [repeat] on or off, for what plays now and what's chosen next.
  Future<void> setRepeat(bool on) async {
    _repeat = on;
    _link?.repeat = on;
    notifyListeners();
    if (_media case final media?) await _loopChanged(media);
  }

  /// How fast a recording or video plays, 1 being as recorded: slower
  /// to learn a part (the pitch stays). Kept for what's chosen next.
  double get speed => _speed;
  double _speed = 1;

  /// The slowest and fastest it plays: the browsers mute the sound below
  /// a quarter, and above that few parts are worth learning faster.
  static const minSpeed = 0.25;
  static const maxSpeed = 1.5;

  /// Plays at [speed] (kept between [minSpeed] and [maxSpeed]), for what
  /// plays now and what's chosen next. A link in a frame keeps its own.
  Future<void> setSpeed(double speed) async {
    speed = speed.clamp(minSpeed, maxSpeed);
    if (speed == _speed) return;
    _speed = speed;
    notifyListeners();
    await _media?.setPlaybackSpeed(speed);
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
    await _loopChanged(media);
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
    if (media != null) await _loopChanged(media);
  }

  Timer? _sectionTimer;

  /// The end is watched every [_sectionTick] while a section is set, or
  /// while it starts over counting in ([repeat] with [countsIn]): the
  /// player's own position updates are coarser, and its own looping (back
  /// to the file's start at once) is off meanwhile.
  static const _sectionTick = Duration(milliseconds: 100);

  /// Whether its end is watched, rather than left to the player.
  bool get _watched => section != null || (_repeat && countsIn);

  /// The section (or [repeat], or [countsIn]) changed: who starts it over
  /// at its end, the player or [_keepInSection]; and into a new section,
  /// if it's out of it.
  Future<void> _loopChanged(VideoPlayerController media) async {
    final range = section;
    final watched = _watched;
    _sectionTimer?.cancel();
    _sectionTimer = null;
    await media.setLooping(_repeat && !watched);
    if (!watched || _media != media) return;
    _sectionTimer = Timer.periodic(_sectionTick, (_) => _keepInSection());
    if (range == null) return;
    final at = media.value.position;
    if (at < range.start || at >= range.end) await media.seekTo(range.start);
  }

  bool _checking = false;

  /// At its end (the section's, or the file's): back to its start, playing
  /// on with [repeat] (after a count-in, with [countsIn]), paused without.
  /// The file's own end counts as the section's: a section that ends at
  /// the file's end (or close enough for the player to get there first)
  /// completes the player, which pauses itself at the end, so that's
  /// watched too, not only the position while it plays.
  Future<void> _keepInSection() async {
    final (media, range) = (_media, section);
    if (_checking || media == null || !_watched) return;
    final v = media.value;
    // Completed: the player has paused and seeked to the end (its own
    // doing, video_player's `completed`; the seek landing is waited for,
    // so a seek of ours isn't undone by it).
    final ended =
        !v.isPlaying && v.duration > Duration.zero && v.position >= v.duration;
    if (!v.isPlaying && !ended) return;
    _checking = true;
    try {
      final at = ended
          ? v.position
          : (await media.position ?? media.value.position);
      if (_media != media || section != range) return;
      final start = range?.start ?? Duration.zero;
      final atEnd = ended || (range != null && at >= range.end);
      if (!atEnd) {
        // Skipped back before the section: into it again.
        if (range != null && at < start - const Duration(seconds: 1)) {
          await media.seekTo(start);
        }
        return;
      }
      if (!_repeat) {
        if (!ended) await media.pause();
        await media.seekTo(start);
        return;
      }
      if (countsIn) {
        // A breath before it starts over, as before it first played.
        if (!ended) await media.pause();
        await media.seekTo(start);
        if (_media == media && !_disposed) await _play(media);
        return;
      }
      await media.seekTo(start);
      if (ended) await media.play();
    } finally {
      _checking = false;
    }
  }

  /// Whether [phrases] are kept for it: what plays in the app (a recording
  /// or video, a link straight to a sound or video file), loaded, whose
  /// position is known to the split second.
  bool get canPhrase => _media != null && _duration > Duration.zero;

  /// Where the tab turned while Cam recorded along with it ([PhraseTimes]):
  /// the passes recorded this visit, not saved yet, else the capture's.
  PhraseTimes get phrases {
    final (id, eventId) = (_page?.id, _eventId);
    if (id == null || eventId == null || !canPhrase) return PhraseTimes.none;
    return _unsaved[id] ?? library.phrasesOf(eventId, id);
  }

  /// Passes recorded, by song, until [savePhrases].
  final _unsaved = <String, PhraseTimes>{};

  /// Notes a phrase pass at [at] (its position): the tab turned
  /// [direction] to [line]; merged into one within two seconds of it
  /// ([PhraseTimes.add]). Kept on [savePhrases].
  void recordPass(Duration at, PassDirection direction, int line) {
    final id = _page?.id;
    if (id == null || !canPhrase) return;
    _unsaved[id] = phrases.add(at, direction, line);
    notifyListeners();
  }

  /// Keeps the passes recorded with the capture.
  Future<void> savePhrases() async {
    final eventId = _eventId;
    if (eventId == null || _unsaved.isEmpty) return;
    final unsaved = Map.of(_unsaved);
    _unsaved.clear();
    for (final MapEntry(:key, :value) in unsaved.entries) {
      await library.setPhrases(eventId, key, value);
    }
  }

  /// Forgets its phrase passes: the tab isn't turned by itself along it
  /// until some are recorded again. Cleared on purpose
  /// ([Library.clearPhrases]): a take of it deleted later doesn't bring
  /// the take's back.
  Future<void> clearPhrases() async {
    final (id, eventId) = (_page?.id, _eventId);
    if (id == null || eventId == null) return;
    _unsaved.remove(id);
    notifyListeners();
    await library.clearPhrases(eventId, id);
    if (!_disposed) notifyListeners();
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
    _eventId = event.id;
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
      if (_speed != 1) await media.setPlaybackSpeed(_speed);
      await _loopChanged(media);
      if (play) await _play(media);
    } on Object catch (e) {
      debugPrint('TabCam: cam: ${page.fileName} can\'t play here: $e');
      if (_page?.id == page.id) _error = e;
    } finally {
      if (_page?.id == page.id) _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Plays or pauses it; at its end (its section's), plays it from the
  /// start (the section's). Play counts in first ([countIn]); pressed
  /// while it counts in, it doesn't play.
  Future<void> toggle() async {
    if (_media case final media?) {
      if (_cancelCountIn()) return;
      final v = media.value;
      if (v.isPlaying) return media.pause();
      if (section case final range?) {
        if (v.position < range.start || v.position >= range.end) {
          await media.seekTo(range.start);
        }
      } else if (v.duration > Duration.zero && v.position >= v.duration) {
        await media.seekTo(Duration.zero);
      }
      return _play(media);
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

  /// Goes to [at] (the main row of Cam's view tapped or dragged there),
  /// kept within its start and end, or its section's when one is set (out
  /// of it, the section would only pull it back). A link in a frame can't
  /// be taken to a time: it stays where it is.
  Future<void> seek(Duration at) async {
    final media = _media;
    if (media == null) return;
    final length = media.value.duration;
    final range = section ?? (start: Duration.zero, end: length);
    if (at < range.start) at = range.start;
    if (length > Duration.zero && at > range.end) at = range.end;
    await media.seekTo(at);
  }

  /// Back to its start (its section's): the **0** key. Paused, it stays
  /// paused there; playing, or counting in, it starts over as Play starts
  /// it, so with [countsIn] it counts in again before it plays.
  Future<void> restart() async {
    if (_media case final media?) {
      final going = _cancelCountIn() || media.value.isPlaying;
      final counts = going && countsIn;
      if (counts) await media.pause();
      await media.seekTo(section?.start ?? Duration.zero);
      if (counts && _media == media) await _play(media);
      return;
    }
    final link = _link;
    if (link == null) return;
    // A frame's page goes back only through Stop, which pauses it.
    final wasPlaying = link.playing;
    await link.stop();
    if (wasPlaying) await link.toggle();
  }

  /// A take starts: it plays along from where it is (from its start, at
  /// its end), after a count-in of its own ([countsIn]: the take's
  /// first [countInLength] are the song's breath), one under way
  /// counting from now again; playing already, it plays on.
  Future<void> playWithTake() async {
    if (_media case final media?) {
      if (media.value.isPlaying) return;
      _cancelCountIn();
      return toggle();
    }
    if (!(_link?.playing ?? true)) await _link?.toggle();
  }

  /// Pauses it (a take plays back), or stops its count-in.
  Future<void> pause() async {
    _cancelCountIn();
    await _media?.pause();
    await _link?.pause();
  }

  /// Pauses it, back at its start (its section's).
  Future<void> stop() async {
    _cancelCountIn();
    if (_media case final media?) {
      await media.pause();
      return media.seekTo(section?.start ?? Duration.zero);
    }
    await _link?.stop();
  }

  /// Stops it, and lets go of it.
  Future<void> close() async {
    _cancelCountIn();
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
    _recording.removeListener(_recordingChanged);
    _countInTimer?.cancel();
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
