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
/// frame ([link]).
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
      if (play) await media.play();
    } on Object catch (e) {
      debugPrint('TabCam: cam: ${page.fileName} can\'t play here: $e');
      if (_page?.id == page.id) _error = e;
    } finally {
      if (_page?.id == page.id) _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Plays or pauses it; at its end, plays it from the start.
  Future<void> toggle() async {
    if (_media case final media?) {
      final v = media.value;
      if (v.isPlaying) return media.pause();
      if (v.duration > Duration.zero && v.position >= v.duration) {
        await media.seekTo(Duration.zero);
      }
      return media.play();
    }
    await _link?.toggle();
  }

  /// Goes [by] forward (back, negative), within its start and end.
  Future<void> skip(Duration by) async {
    if (_media case final media?) {
      final v = media.value;
      var to = v.position + by;
      if (to < Duration.zero) to = Duration.zero;
      if (v.duration > Duration.zero && to > v.duration) to = v.duration;
      return media.seekTo(to);
    }
    await _link?.skip(by);
  }

  /// Pauses it (a take plays back).
  Future<void> pause() async {
    await _media?.pause();
    await _link?.pause();
  }

  /// Pauses it, back at its start.
  Future<void> stop() async {
    if (_media case final media?) {
      await media.pause();
      return media.seekTo(Duration.zero);
    }
    await _link?.stop();
  }

  /// Stops it, and lets go of it.
  Future<void> close() async {
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
