import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../capture/media.dart';
import '../capture/play_along_sidebar.dart' show isTake;
import '../capture/video_edit.dart';
import '../export/download.dart';
import '../l10n/language.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import 'edited_playback.dart';
import 'file_screen.dart';
import 'media_url.dart';
import 'video_page.dart' show mediaLength, openPlayer, pageFile;
import 'messages.dart';

/// Basic edits of a video, opened from its file screen, on one time axis:
/// a ruler (tapped or dragged, the preview goes there) over two lanes,
/// mixed. The **Take** lane (for a video Cam didn't record, "Video
/// sound") is the whole video, the part kept bright: its grips trim it,
/// and both sounds with it. The **Song** lane ("Track") holds one of the
/// capture's recordings, videos or takes, or a sound file (added to
/// them), placed along the video by hand (dragged, trimmed by its ends,
/// nudged by a tenth of a second); ⋮ changes or removes it. Each lane has
/// its volume and Mute at its left. The edit is kept with the page as
/// it's made ([PageEdit]), and played as it says ([EditedPlayback]: the
/// kept part, both lanes at their volumes); the video's file stays as it
/// is. Download renders the same plan ([RenderPlan]) to a file on the
/// device ([VideoEditor]): the video, the video without sound, or the
/// sound alone.
class VideoEditScreen extends StatefulWidget {
  const VideoEditScreen({
    super.key,
    required this.library,
    required this.eventId,
    required this.page,
    this.editor,
    this.pickFile = _pickFile,
  });

  final Library library;
  final String eventId;
  final EventPage page;

  /// What applies the edit; the platform's by default ([VideoEditor]).
  final VideoEditing? editor;

  /// Picks a sound file from the device; tests pass their own.
  final Future<XFile?> Function() pickFile;

  static Future<XFile?> _pickFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'mp3',
        'm4a',
        'aac',
        'wav',
        'ogg',
        'oga',
        'opus',
        'flac',
        'mp4',
        'webm',
      ],
    );
    return files.firstOrNull?.xFile;
  }

  @override
  State<VideoEditScreen> createState() => _VideoEditScreenState();
}

/// A lane's level: its [volume] (0 to 1), whether it's [muted] (the level
/// kept), and the level Unmute puts back after a slide down to 0%
/// ([unmuted]).
class _Level {
  _Level([this.volume = 1, this.muted = false])
    : unmuted = volume > 0 ? volume : 1;

  double volume;
  bool muted;
  double unmuted;

  /// Whether it's heard.
  bool get silent => muted || volume <= 0;

  /// Keeps the level, when it's not 0, for Unmute: as a slide starts.
  void keep() {
    if (volume > 0) unmuted = volume;
  }

  /// Slid to [to] (which unmutes it); whether that changed anything.
  bool slide(double to) {
    to = PageEdit.volume(to);
    if (to == volume && !muted) return false;
    volume = to;
    muted = false;
    return true;
  }

  /// Mutes it, or makes it heard again: as loud as it was (as before a
  /// slide down to 0%, or 100%).
  void toggleMute() {
    if (silent) {
      muted = false;
      if (volume <= 0) volume = unmuted > 0 ? unmuted : 1;
    } else {
      muted = true;
    }
  }
}

class _VideoEditScreenState extends State<VideoEditScreen> {
  VideoPlayerController? _video;
  EditedPlayback? _playback;
  Object? _error;

  Duration _start = Duration.zero;
  Duration _end = Duration.zero;

  /// The Take lane's level: the video's own sound.
  var _own = _Level();

  /// The Song lane: how it's placed (null: the default, none), its level,
  /// its page in the capture, its file, its name, and its player (for its
  /// length, and to play it along the preview).
  SongMode? _song;
  var _songLevel = _Level();
  String? _trackId;
  XFile? _track;
  String? _trackName;
  VideoPlayerController? _trackPlayer;
  Duration _offset = Duration.zero;

  /// The part of the song used, from [_trackStart] to [_trackEnd]
  /// (trimmed by the song bar's ends).
  Duration _trackStart = Duration.zero;
  Duration _trackEnd = Duration.zero;

  /// The shortest part of a song that can be used.
  static const minTrack = Duration(milliseconds: 500);

  /// The edit as last kept with the page, and the wait before the next
  /// change is kept (a drag makes many).
  PageEdit? _saved;
  Timer? _saveTimer;

  /// The keys of the saved edit a newer app wrote ([PageEdit.extra]):
  /// kept with every change made here.
  Map<String, Object?> _extra = const {};

  /// A download being made, and how far along it is (where that's known).
  bool _busy = false;
  double? _progress;

  /// The formats Download makes here (the menu says them): MP4 and M4A
  /// until the editor says otherwise (a browser that can't make them).
  EditFormats _formats = EditFormats.standard;

  /// A seek of the preview held back while a grip or the ruler is dragged
  /// (one at most every [_seekEvery]), and where the last one asked for
  /// goes when the wait is over.
  Timer? _seekWait;
  Duration? _seekNext;
  static const _seekEvery = Duration(milliseconds: 150);

  Library get _library => widget.library;

  /// How long the video and the song are: the players' word, unless they
  /// have none (the browser, for a take it recorded), then the editor's.
  Duration _duration = Duration.zero;
  Duration _trackLength = Duration.zero;

  VideoEditing? get _editor => widget.editor ?? VideoEditor.instance;

  /// Whether the video is one of Cam's takes: its lanes are then "Take"
  /// and "Song" ("Video sound" and "Track" otherwise).
  bool get _take => isTake(widget.page);

  /// Whether the Song lane has a song in it.
  bool get _hasSong =>
      _song != null && _song != SongMode.off && _trackId != null;

  /// [file]'s length: [player]'s, or the editor's where the player can't
  /// say ([mediaLength], as the file screen finds it).
  Future<Duration> _lengthOf(VideoPlayerController player, XFile file) =>
      mediaLength(player, () async => file, editor: _editor);

  /// [page]'s file: its path, or its bytes on the web.
  Future<XFile> _fileOf(CaptureEvent event, EventPage page) =>
      pageFile(_library, event, page);

  @override
  void initState() {
    super.initState();
    unawaited(_open());
    unawaited(_loadFormats());
  }

  Future<void> _loadFormats() async {
    try {
      final formats = await _editor?.formats();
      if (formats != null && mounted) setState(() => _formats = formats);
    } on Object catch (e) {
      debugPrint('TabCam: video edit: formats unknown: $e');
    }
  }

  /// Opens the video, and the edit it has (its song too).
  Future<void> _open() async {
    final event = _library.byId(widget.eventId);
    if (event == null) return;
    try {
      final controller = await openPlayer(_library, event, widget.page);
      final length = await _lengthOf(
        controller,
        await _fileOf(event, widget.page),
      );
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(false);
      final edit = event.pages
          .where((p) => p.id == widget.page.id)
          .firstOrNull
          ?.edit;
      setState(() {
        _video = controller;
        _playback = EditedPlayback(controller);
        _duration = length;
        _end = length;
        _saved = edit;
        _extra = edit?.extra ?? const {};
        if (edit != null) {
          _start = _clamp(edit.start, Duration.zero, length);
          _end = _clamp(edit.end, _start, length);
          _own = _Level(edit.ownVolume, edit.ownMuted);
          _song = edit.song;
          _songLevel = _Level(edit.trackVolume, edit.songMuted);
        }
      });
      final track = edit?.trackId == null
          ? null
          : event.pages.where((p) => p.id == edit!.trackId).firstOrNull;
      if (edit != null && track != null) {
        final file = await _fileOf(event, track);
        if (!mounted) return;
        await _loadTrack(
          track.id,
          file,
          fileLabel(context.l10n, event, track),
          from: edit,
        );
      }
      await _played();
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      unawaited(_keep());
    }
    _seekWait?.cancel();
    _playback?.dispose();
    _video?.dispose();
    _trackPlayer?.dispose();
    super.dispose();
  }

  /// The edit as it is now, with the keys a newer app wrote.
  PageEdit get _current => PageEdit(
    start: _start,
    end: _end,
    ownVolume: _own.volume,
    ownMuted: _own.muted,
    song: _song,
    songMuted: _songLevel.muted,
    trackId: _trackId,
    trackStart: _trackStart,
    trackEnd: _trackEnd >= _trackLength ? null : _trackEnd,
    offset: _offset,
    trackVolume: _songLevel.volume,
    extra: _extra,
  );

  /// Whether the edit changes the video: anything but the whole video
  /// with its own sound as it is (the defaults).
  bool get _edited =>
      _current.copyWith(extra: const {}) !=
      PageEdit(start: Duration.zero, end: _duration);

  /// The edit as it is now, as kept with the page: null when it's the
  /// defaults (the video plays as it is) and has no keys a newer app
  /// wrote to keep (nor a length to keep them with).
  PageEdit? get _pageEdit {
    if (!_edited && (_extra.isEmpty || _end <= _start)) return null;
    return _current;
  }

  /// Something changed: the preview plays it, and it's kept with the page
  /// a moment later.
  void _changed() {
    unawaited(_played());
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _keep);
  }

  /// The preview plays the edit as it is now: the plan Download renders.
  Future<void> _played() async => _playback?.set(
    EditedPlayback.planOf(_pageEdit, songLength: _trackLength),
    song: _trackPlayer,
  );

  /// Keeps the edit with the page, when it changed.
  Future<void> _keep() async {
    final edit = _pageEdit;
    // Unchanged, or with a newer app's keys but no length known yet: the
    // edit saved stays.
    if (edit == _saved || (edit == null && _extra.isNotEmpty)) return;
    _saved = edit;
    try {
      await _library.setPageEdit(widget.eventId, widget.page.id, edit);
    } on Object catch (e) {
      debugPrint('TabCam: video edit: not kept: $e');
    }
  }

  /// Keeps from [start] to [end], at least [PageEdit.minLength] long
  /// (the end moved when the start leaves it too little).
  void _trim(Duration start, Duration end) {
    final length = _duration;
    start = _clamp(start, Duration.zero, length);
    end = _clamp(end, Duration.zero, length);
    if (end - start < PageEdit.minLength) {
      if (start + PageEdit.minLength <= length) {
        end = start + PageEdit.minLength;
      } else {
        start = length - PageEdit.minLength;
        end = length;
      }
    }
    _keepPart(start, end, endMoved: end != _end && start == _start);
  }

  /// The Take lane's start grip, dragged by [delta].
  void _trimStartBy(Duration delta) => _keepPart(
    _clamp(_start + delta, Duration.zero, _end - PageEdit.minLength),
    _end,
    endMoved: false,
    exact: false,
  );

  /// The Take lane's end grip, dragged by [delta].
  void _trimEndBy(Duration delta) => _keepPart(
    _start,
    _clamp(_end + delta, _start + PageEdit.minLength, _duration),
    endMoved: true,
    exact: false,
  );

  /// Keeps from [start] to [end]. The song stays where it is along the
  /// video (what falls outside is cut off, in both lanes). The preview,
  /// while paused, goes to the end moved ([endMoved]): at once, or, while
  /// a grip is dragged (not [exact]), at most every 150 ms.
  void _keepPart(
    Duration start,
    Duration end, {
    required bool endMoved,
    bool exact = true,
  }) {
    if (start == _start && end == _end) return;
    setState(() {
      if (_trackId != null) _offset -= start - _start;
      _start = start;
      _end = end;
    });
    _changed();
    final video = _video;
    if (video != null && !video.value.isPlaying) {
      _seek(endMoved ? end : start, exact: exact);
    }
  }

  /// The preview goes to [at]: at once when [exact] (a grip let go, a
  /// tap), else at most every [_seekEvery] (a drag), the last asked for
  /// last.
  void _seek(Duration at, {bool exact = true}) {
    final video = _video;
    if (video == null) return;
    at = _clamp(at, Duration.zero, _duration);
    if (exact) {
      _seekWait?.cancel();
      _seekWait = null;
      _seekNext = null;
      unawaited(video.seekTo(at));
      return;
    }
    if (_seekWait != null) {
      _seekNext = at;
      return;
    }
    unawaited(video.seekTo(at));
    _seekWait = Timer(_seekEvery, () {
      _seekWait = null;
      final next = _seekNext;
      _seekNext = null;
      if (next != null && mounted) _seek(next, exact: false);
    });
  }

  /// A Take grip let go: the preview, while paused, goes exactly to the
  /// end it moved.
  void _trimmed({required bool end}) {
    final video = _video;
    if (video != null && !video.value.isPlaying) {
      _seek(end ? _end : _start);
    }
  }

  static Duration _clamp(Duration d, Duration low, Duration high) =>
      d < low ? low : (d > high ? high : d);

  /// Keeps from, or until, where the preview is (asked of the player: a
  /// paused one isn't polled).
  Future<void> _trimHere({required bool end}) async {
    final at = await _video?.position ?? Duration.zero;
    if (!mounted) return;
    end ? _trim(_start, at) : _trim(at, _end);
  }

  /// A sheet of what can go in the Song lane: the capture's recordings,
  /// videos and takes (not the video edited), and a sound file to pick
  /// (added to the capture's files).
  Future<void> _pickTrack() async {
    final event = _library.byId(widget.eventId);
    final l10n = context.l10n;
    final candidates = [
      for (final p in event?.pages ?? const <EventPage>[])
        if ((p.isAudio || p.isVideo) && p.id != widget.page.id) p,
    ];
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          key: const Key('video-edit-tracks'),
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                l10n.videoEditPickTrack,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final p in candidates)
              ListTile(
                key: Key('video-edit-track-${p.id}'),
                leading: Icon(
                  p.isAudio
                      ? Icons.music_note
                      : isTake(p)
                      ? Icons.videocam_outlined
                      : Icons.movie_outlined,
                ),
                title: Text(fileLabel(l10n, event!, p)),
                onTap: () => Navigator.pop(context, p),
              ),
            ListTile(
              key: const Key('video-edit-track-file'),
              leading: const Icon(Icons.audio_file_outlined),
              title: Text(l10n.videoEditTrackFile),
              onTap: () => Navigator.pop(context, 'file'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null || event == null) return;
    final EventPage page;
    final XFile file;
    var now = event;
    if (picked is EventPage) {
      page = picked;
      file = await _fileOf(event, page);
    } else {
      final chosen = await widget.pickFile();
      if (chosen == null || !mounted) return;
      file = chosen;
      // A recording of the capture's from now on: the edit names it, and
      // it syncs with the rest.
      final name = file.name.toLowerCase();
      final dot = name.lastIndexOf('.');
      final extension =
          Media.of(file)?.extension ??
          (dot < 0 ? 'mp3' : name.substring(dot + 1));
      final before = {for (final p in event.pages) p.id};
      try {
        now = await _library.addMedia(event, [
          Media(file, PageKind.audio, extension),
        ]);
      } on Object catch (e) {
        debugPrint('TabCam: video edit: the track wasn\'t added: $e');
        return;
      }
      final added = now.pages.where((p) => !before.contains(p.id));
      if (added.isEmpty) return;
      page = added.first;
    }
    if (!mounted) return;
    await _loadTrack(page.id, file, fileLabel(l10n, now, page));
  }

  /// Puts [file], page [id] of the capture, in the Song lane: as [from]
  /// places it, or, picked, placed by hand from the kept part's start, at
  /// the lane's level, heard.
  Future<void> _loadTrack(
    String id,
    XFile file,
    String name, {
    PageEdit? from,
  }) async {
    await _playback?.set(EditedPlayback.planOf(_pageEdit));
    await _trackPlayer?.dispose();
    _trackPlayer = null;
    VideoPlayerController? player;
    var length = Duration.zero;
    try {
      player = await _openFile(file);
      length = await _lengthOf(player, file);
    } on Object catch (e) {
      debugPrint('TabCam: video edit: the track can\'t be played: $e');
    }
    if (!mounted) {
      await player?.dispose();
      return;
    }
    setState(() {
      _trackId = id;
      _track = file;
      _trackName = name;
      _trackPlayer = player;
      _trackLength = length;
      _trackStart = from == null
          ? Duration.zero
          : _clamp(from.trackStart, Duration.zero, length);
      _trackEnd = from?.trackEnd == null
          ? length
          : _clamp(from!.trackEnd!, _trackStart, length);
      _offset = from?.offset ?? Duration.zero;
      if (from == null) {
        _song = SongMode.manual;
        _songLevel.muted = false;
      }
    });
    _changed();
  }

  /// Takes the song out of its lane (`song: off`): the lane is empty
  /// again, as loud as it is.
  Future<void> _removeSong() async {
    final player = _trackPlayer;
    setState(() {
      _song = SongMode.off;
      _clearSong();
    });
    _changed();
    await _played();
    await player?.dispose();
  }

  /// The Song lane without a song (setState's).
  void _clearSong() {
    _songLevel = _Level();
    _trackId = null;
    _track = null;
    _trackName = null;
    _trackPlayer = null;
    _trackLength = Duration.zero;
    _trackStart = Duration.zero;
    _trackEnd = Duration.zero;
    _offset = Duration.zero;
  }

  /// A player for [file]: from its path, or its bytes on the web.
  static Future<VideoPlayerController> _openFile(XFile file) async {
    if (file.path.isEmpty || kIsWeb) {
      return openBytesPlayer(
        await file.readAsBytes(),
        file.mimeType ?? 'audio/mpeg',
      );
    }
    final controller = VideoPlayerController.file(File(file.path));
    try {
      await controller.initialize();
    } on Object {
      await controller.dispose();
      rethrow;
    }
    return controller;
  }

  /// The song, changed by hand here: placed by hand from now on.
  void _placedByHand() {
    if (_song == SongMode.auto) _song = SongMode.manual;
  }

  /// Moves the song's used part [delta] along the video (kept within
  /// touch of it).
  void _moveTrack(Duration delta) {
    final used = _trackEnd - _trackStart;
    final offset = _clamp(
      _offset + delta,
      -_start - used + minTrack,
      _duration - _start - minTrack,
    );
    if (offset == _offset) return;
    setState(() {
      _offset = offset;
      _placedByHand();
    });
    _changed();
  }

  /// Trims the song's start by [delta]: what's left stays where it is
  /// along the video.
  void _trimTrackStart(Duration delta) {
    final start = _clamp(
      _trackStart + delta,
      Duration.zero,
      _trackEnd - minTrack,
    );
    if (start == _trackStart) return;
    setState(() {
      _offset += start - _trackStart;
      _trackStart = start;
      _placedByHand();
    });
    _changed();
  }

  /// Trims the song's end by [delta].
  void _trimTrackEnd(Duration delta) {
    final end = _clamp(_trackEnd + delta, _trackStart + minTrack, _trackLength);
    if (end == _trackEnd) return;
    setState(() {
      _trackEnd = end;
      _placedByHand();
    });
    _changed();
  }

  /// [level] slid to [volume], 0 to 1 (to the hundredth): heard at it.
  void _slide(_Level level, double volume) {
    if (!level.slide(volume)) return;
    setState(() {});
    _changed();
  }

  /// [level] muted, or heard again as loud as it was.
  void _mute(_Level level) {
    setState(level.toggleMute);
    _changed();
  }

  /// Back to the defaults: the whole video, with its own sound as it is,
  /// and no song (the edit is none).
  Future<void> _reset() async {
    final player = _trackPlayer;
    setState(() {
      _start = Duration.zero;
      _end = _duration;
      _own = _Level();
      _song = null;
      _clearSong();
    });
    _changed();
    await _played();
    await player?.dispose();
  }

  /// The plan of the edit as it is now, for [kind]: of [input], the
  /// video's file, for Download (the preview's has no files).
  RenderPlan _plan(RenderKind kind, {XFile? input}) => RenderPlan.of(
    _pageEdit,
    input: input,
    duration: _duration,
    inputExtension: input == null ? null : Media.of(input)?.extension,
    songFile: _track,
    songLength: _trackLength,
    kind: kind,
    formats: _formats,
  );

  /// Whether the song can be fitted (one of unknown length can't).
  bool get _trackReady =>
      !_hasSong || (_track != null && _trackLength > Duration.zero);

  bool _canDownload(RenderKind what) {
    if (_video == null || _busy) return false;
    return switch (what) {
      RenderKind.video => _trackReady,
      RenderKind.silent => true,
      RenderKind.sound => _trackReady && _plan(RenderKind.sound).hasSound,
    };
  }

  /// Renders the edit's plan to a file, on the device ([VideoEditor]),
  /// and downloads it: the video as edited, without sound, or its sound
  /// alone, in [_formats]. A plan that's a passthrough (the video as it
  /// is, already an MP4 or M4V, or in the format made here: a WebM where
  /// the browser records WebM) downloads the file as it is; anything else
  /// is made (a WebM, or a MOV, as an MP4).
  Future<void> _download(RenderKind what) async {
    final editor = _editor;
    final event = _library.byId(widget.eventId);
    final l10n = context.l10n;
    final messenger = Messenger.maybeOf(context);
    if (editor == null) {
      messenger?.show(l10n.videoEditNotHere);
      return;
    }
    if (event == null) return;
    await _video?.pause();
    setState(() {
      _busy = true;
      _progress = null;
    });
    XFile? made;
    try {
      final page = widget.page;
      final input = await _fileOf(event, page);
      final label = fileLabel(l10n, event, page);
      final plan = _plan(what, input: input);
      if (plan.passthrough) {
        await Downloads.saveFile(_library, event, page, label);
        return;
      }
      final out = made = await editor.render(
        plan,
        onProgress: (done) {
          if (mounted) setState(() => _progress = done);
        },
      );
      final format = plan.format;
      await Downloads.saveBytes(
        safeFileName(label, Media.of(out)?.extension ?? format.extension),
        await out.readAsBytes(),
        out.mimeType ?? format.mimeType,
      );
    } on Object catch (e, stack) {
      debugPrint(
        'TabCam: video edit: ${l10n.videoEditCouldntDownload}: $e\n$stack',
      );
      messenger?.show('${l10n.videoEditCouldntDownload}: $e');
    } finally {
      // The phones' editors write it to a temporary file.
      if (made != null && !kIsWeb && made.path.isNotEmpty) {
        unawaited(
          File(made.path).delete().then((_) {}, onError: (Object _) {}),
        );
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  /// m:ss.t, to the tenth of a second.
  static String time(Duration d) {
    final tenths = d.inMilliseconds ~/ 100;
    final s = (tenths ~/ 10) % 60;
    return '${tenths ~/ 600}:${s.toString().padLeft(2, '0')}.${tenths % 10}';
  }

  /// m:ss, for the ruler.
  static String _rulerTime(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// The lanes' room at the left (the volume) and at the right (the Song
  /// lane's menu): the ruler and the bars line up between them.
  static const _lead = _LaneVolume.width + 4;
  static const _trail = 48.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final event = _library.byId(widget.eventId);
    final video = _video;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          event == null ? '' : fileLabel(l10n, event, widget.page),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            key: const Key('video-edit-about'),
            tooltip: l10n.videoEditAbout,
            icon: const Icon(Icons.info_outline),
            onPressed: () =>
                Messenger.maybeOf(context)?.show(l10n.videoEditKept),
          ),
        ],
        bottom: _busy
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  key: const Key('video-edit-progress'),
                  value: _progress,
                ),
              )
            : null,
      ),
      body: _error != null
          ? Center(child: Text(l10n.textViewCantPlay))
          : video == null
          ? const Center(child: CircularProgressIndicator())
          : AbsorbPointer(
              absorbing: _busy,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _preview(video),
                  _transport(video, l10n),
                  const SizedBox(height: 8),
                  _timeline(video, l10n),
                  if (_hasSong) ...[
                    const SizedBox(height: 8),
                    _songDetails(l10n),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    Text(
                      l10n.videoEditDownloading,
                      key: const Key('video-edit-downloading'),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          // At the largest text sizes, both shrink to fit rather than
          // overflow.
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('video-edit-reset'),
                    onPressed: _edited && !_busy ? _reset : null,
                    child: Text(l10n.videoEditReset),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 3,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: _downloadButton(l10n),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Download, split: the button downloads the video as edited; its menu
  /// also has it without sound, and its sound alone, each saying its
  /// format.
  Widget _downloadButton(AppLocalizations l10n) {
    const radius = Radius.circular(20);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          key: const Key('video-edit-download'),
          style: FilledButton.styleFrom(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.horizontal(left: radius),
            ),
          ),
          icon: const Icon(Icons.download_outlined),
          label: Text(l10n.videoEditDownload),
          onPressed: _canDownload(RenderKind.video)
              ? () => _download(RenderKind.video)
              : null,
        ),
        const SizedBox(width: 2),
        MenuAnchor(
          menuChildren: [
            for (final (what, label, icon) in [
              (
                RenderKind.video,
                l10n.videoEditDownloadVideo(_formats.video.label),
                Icons.movie_outlined,
              ),
              (
                RenderKind.silent,
                l10n.videoEditDownloadSilent(_formats.video.label),
                Icons.videocam_off_outlined,
              ),
              (
                RenderKind.sound,
                l10n.videoEditDownloadSound(_formats.sound.label),
                Icons.audiotrack,
              ),
            ])
              MenuItemButton(
                key: Key('video-edit-download-${what.name}'),
                leadingIcon: Icon(icon),
                onPressed: _canDownload(what) ? () => _download(what) : null,
                child: Text(label),
              ),
          ],
          builder: (context, menu, _) => FilledButton(
            key: const Key('video-edit-download-more'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(40, 40),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(right: radius),
              ),
            ),
            onPressed: _video == null || _busy
                ? null
                : () => menu.isOpen ? menu.close() : menu.open(),
            child: Tooltip(
              message: l10n.videoEditDownloadMore,
              child: const Icon(Icons.arrow_drop_down),
            ),
          ),
        ),
      ],
    );
  }

  /// The video, at most a third of the screen (a tap plays or pauses it).
  Widget _preview(VideoPlayerController video) {
    final height = MediaQuery.sizeOf(context).height / 3;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height),
      child: GestureDetector(
        onTap: _playback?.playPause,
        child: Center(
          child: AspectRatio(
            aspectRatio: video.value.aspectRatio,
            child: VideoPlayer(video),
          ),
        ),
      ),
    );
  }

  /// Under the preview, on one row: Play / Pause, where it is (to the
  /// tenth of a second: the trims are set by it), the part kept, and
  /// Start here and End here, which trim to where it is.
  Widget _transport(VideoPlayerController video, AppLocalizations l10n) {
    final trimmed = _start > Duration.zero || _end < _duration;
    const tabular = [FontFeature.tabularFigures()];
    return Row(
      children: [
        // Its own button: the kept part plays, not the whole video.
        ValueListenableBuilder(
          valueListenable: video,
          builder: (context, value, _) => IconButton(
            key: const Key('video-edit-play'),
            tooltip: value.isPlaying ? l10n.textViewPause : l10n.textViewPlay,
            icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: _playback?.playPause,
          ),
        ),
        ValueListenableBuilder(
          valueListenable: video,
          builder: (context, value, _) => Text(
            time(value.position),
            key: const Key('video-edit-time'),
            style: const TextStyle(fontFeatures: tabular),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              l10n.videoEditKeep(time(_start), time(_end)),
              key: const Key('video-edit-times'),
              maxLines: 1,
              style: TextStyle(
                color: trimmed ? Theme.of(context).colorScheme.primary : null,
                fontFeatures: tabular,
              ),
            ),
          ),
        ),
        IconButton(
          key: const Key('video-edit-start-here'),
          tooltip: l10n.videoEditTrimStart,
          icon: const Icon(Icons.first_page),
          onPressed: () => _trimHere(end: false),
        ),
        IconButton(
          key: const Key('video-edit-end-here'),
          tooltip: l10n.videoEditTrimEnd,
          icon: const Icon(Icons.last_page),
          onPressed: () => _trimHere(end: true),
        ),
      ],
    );
  }

  /// The time axis: the ruler over the Take lane and the Song lane, each
  /// lane's volume at its left, the Song lane's menu at its right, and
  /// where the preview is drawn across them.
  Widget _timeline(VideoPlayerController video, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final ownName = _take ? l10n.videoEditLaneTake : l10n.videoEditLaneVideo;
    final songName = _take ? l10n.videoEditLaneSong : l10n.videoEditLaneTrack;
    final length = _duration;
    final hasSong = _hasSong;
    final Widget songBar;
    if (!hasSong) {
      songBar = _AddSong(
        label: _take ? l10n.videoEditAddSong : l10n.videoEditAddTrack,
        onTap: _pickTrack,
      );
    } else if (_trackLength <= Duration.zero || length <= Duration.zero) {
      // Its length unknown: it can't be placed.
      songBar = _SongBar.unplaced(name: _trackName ?? songName);
    } else {
      songBar = _SongBar(
        length: length,
        start: _start,
        end: _end,
        at: _start + _offset,
        used: _trackEnd - _trackStart,
        name: _trackName ?? songName,
        label: l10n.videoEditTrackBar,
        onMove: _moveTrack,
        onTrimStart: _trimTrackStart,
        onTrimEnd: _trimTrackEnd,
      );
    }
    return Stack(
      children: [
        Column(
          children: [
            Row(
              children: [
                const SizedBox(width: _lead),
                Expanded(
                  child: _Ruler(
                    length: length,
                    label: l10n.videoEditRuler,
                    timeOf: _rulerTime,
                    onSeek: (at, {required exact}) => _seek(at, exact: exact),
                  ),
                ),
                const SizedBox(width: _trail),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _LaneVolume(
                  lane: 'take',
                  name: ownName,
                  volume: _own.volume,
                  muted: _own.muted,
                  onChanged: (v) => _slide(_own, v),
                  onChangeStart: _own.keep,
                  onMute: () => _mute(_own),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _TakeBar(
                    length: length,
                    start: _start,
                    end: _end,
                    name: ownName,
                    label: l10n.videoEditTakeBar,
                    startLabel: l10n.videoEditKeptStart,
                    endLabel: l10n.videoEditKeptEnd,
                    onTrimStart: _trimStartBy,
                    onTrimEnd: _trimEndBy,
                    onTrimmed: _trimmed,
                  ),
                ),
                const SizedBox(width: _trail),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (hasSong)
                  _LaneVolume(
                    lane: 'song',
                    name: songName,
                    volume: _songLevel.volume,
                    muted: _songLevel.muted,
                    onChanged: (v) => _slide(_songLevel, v),
                    onChangeStart: _songLevel.keep,
                    onMute: () => _mute(_songLevel),
                  )
                else
                  const SizedBox(width: _LaneVolume.width),
                const SizedBox(width: 4),
                Expanded(child: songBar),
                SizedBox(
                  width: _trail,
                  child: hasSong ? _songMenu(l10n) : null,
                ),
              ],
            ),
          ],
        ),
        // Where the preview is, across the ruler and the lanes.
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder(
              valueListenable: video,
              builder: (context, value, _) => CustomPaint(
                painter: _Playhead(
                  at: length <= Duration.zero
                      ? 0
                      : value.position.inMilliseconds / length.inMilliseconds,
                  lead: _lead,
                  trail: _trail,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The Song lane's ⋮: Change… and Remove.
  Widget _songMenu(AppLocalizations l10n) => MenuAnchor(
    menuChildren: [
      MenuItemButton(
        key: const Key('video-edit-song-change'),
        leadingIcon: const Icon(Icons.swap_horiz),
        onPressed: _pickTrack,
        child: Text(l10n.videoEditChangeTrack),
      ),
      MenuItemButton(
        key: const Key('video-edit-song-remove'),
        leadingIcon: const Icon(Icons.delete_outline),
        onPressed: _removeSong,
        child: Text(l10n.videoEditRemoveSong),
      ),
    ],
    builder: (context, menu, _) => IconButton(
      key: const Key('video-edit-song-menu'),
      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
      icon: const Icon(Icons.more_vert),
      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
    ),
  );

  /// Under the lanes, the song's details: its lane and name, nudges of a
  /// tenth of a second either way with where it starts in words between
  /// them, and the part of it used, once trimmed.
  Widget _songDetails(AppLocalizations l10n) {
    final theme = Theme.of(context);
    const tenth = Duration(milliseconds: 100);
    const tabular = [FontFeature.tabularFigures()];
    final trimmed = _trackStart > Duration.zero || _trackEnd < _trackLength;
    final shift = _offset == Duration.zero
        ? l10n.videoEditTrackWith
        : _offset > Duration.zero
        ? l10n.videoEditTrackAfter(time(_offset))
        : l10n.videoEditTrackBefore(time(-_offset));
    return Column(
      key: const Key('video-edit-song-details'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '${_take ? l10n.videoEditLaneSong : l10n.videoEditLaneTrack} · ',
              style: theme.textTheme.titleSmall,
            ),
            Expanded(
              child: Text(
                _trackName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
          ],
        ),
        if (_trackLength > Duration.zero)
          Row(
            children: [
              IconButton(
                key: const Key('video-edit-song-earlier'),
                tooltip: l10n.videoEditTrackEarlier,
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _moveTrack(-tenth),
              ),
              Expanded(
                child: Text(
                  shift,
                  key: const Key('video-edit-shift'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _offset == Duration.zero
                        ? null
                        : theme.colorScheme.primary,
                    fontFeatures: tabular,
                  ),
                ),
              ),
              IconButton(
                key: const Key('video-edit-song-later'),
                tooltip: l10n.videoEditTrackLater,
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _moveTrack(tenth),
              ),
            ],
          ),
        if (trimmed && _trackLength > Duration.zero)
          Text(
            l10n.videoEditTrackUsed(time(_trackStart), time(_trackEnd)),
            key: const Key('video-edit-song-used'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontFeatures: tabular,
            ),
          ),
      ],
    );
  }
}

/// A lane's volume, at the left of its bar: a speaker over the level
/// (`80%`, in the primary colour when it's not as it is, or muted; the
/// speaker crossed out when it isn't heard). Tapped, it opens a slider,
/// 0% to 100% in steps of 5% (sliding unmutes it), with Mute beside it
/// (muted, the level stays; Unmute puts it back, or, after a slide down
/// to 0%, the level before it). Its keys name its [lane]
/// (`video-edit-take-…`, `video-edit-song-…`), so there can be two. It
/// fits its bar's height at any text size: the level stays on one line,
/// and the two shrink together when the text is too large.
class _LaneVolume extends StatelessWidget {
  const _LaneVolume({
    required this.lane,
    required this.name,
    required this.volume,
    required this.muted,
    required this.onChanged,
    required this.onChangeStart,
    required this.onMute,
  });

  static const width = 48.0;

  /// The lane, for its keys: `take` or `song`.
  final String lane;

  /// The lane, as the user sees it ("Take", "Song", …).
  final String name;
  final double volume;
  final bool muted;
  final void Function(double volume) onChanged;

  /// A slide starts, before [onChanged].
  final VoidCallback onChangeStart;
  final VoidCallback onMute;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final percent = (volume * 100).round();
    final level = l10n.videoEditTrackVolumeLevel(percent);
    final silent = muted || volume <= 0;
    final icon = Icon(
      silent
          ? Icons.volume_off_outlined
          : volume < 0.5
          ? Icons.volume_down_outlined
          : Icons.volume_up_outlined,
    );
    final changed = volume != 1 || muted;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: Key('video-edit-$lane-mute'),
                tooltip: silent
                    ? l10n.videoEditLaneUnmute(name)
                    : l10n.videoEditLaneMute(name),
                icon: icon,
                onPressed: onMute,
              ),
              SizedBox(
                width: 200,
                child: Slider(
                  key: Key('video-edit-$lane-volume-slider'),
                  max: 100,
                  divisions: 20,
                  value: percent.clamp(0, 100).toDouble(),
                  label: level,
                  semanticFormatterCallback: (v) =>
                      l10n.videoEditTrackVolumeLevel(v.round()),
                  onChangeStart: (_) => onChangeStart(),
                  onChanged: (v) => onChanged(v / 100),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  level,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ],
      builder: (context, menu, _) => Semantics(
        button: true,
        child: Tooltip(
          message: l10n.videoEditLaneVolume(name),
          child: InkWell(
            key: Key('video-edit-$lane-volume'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
            child: SizedBox(
              width: width,
              height: _SongBar.height,
              child: IconTheme.merge(
                data: IconThemeData(
                  size: 20,
                  color: changed ? theme.colorScheme.primary : null,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      icon,
                      Text(
                        level,
                        key: Key('video-edit-$lane-volume-level'),
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 11,
                          color: changed ? theme.colorScheme.primary : null,
                          decoration: muted ? TextDecoration.lineThrough : null,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The time axis over the lanes, as long as the video: a tick and its
/// time (m:ss) as often as there's room for one. Tapped or dragged, the
/// preview goes there ([onSeek]: at once for a tap or as a drag ends, not
/// [exact] while it drags).
class _Ruler extends StatefulWidget {
  const _Ruler({
    required this.length,
    required this.label,
    required this.timeOf,
    required this.onSeek,
  });

  final Duration length;
  final String label;
  final String Function(Duration at) timeOf;
  final void Function(Duration at, {required bool exact}) onSeek;

  @override
  State<_Ruler> createState() => _RulerState();
}

class _RulerState extends State<_Ruler> {
  /// Where a drag is, along the ruler.
  double _dragX = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Its times stay small: the ruler is a guide, the time beside Play
    // says where the preview is at any text size.
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    final style = theme.textTheme.labelSmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final height = 10 + scaler.scale(style.fontSize ?? 11) * 1.4;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        Duration at(double x) {
          final ms = widget.length.inMilliseconds;
          if (width <= 0 || ms <= 0) return Duration.zero;
          return Duration(
            milliseconds: (x.clamp(0, width) / width * ms).round(),
          );
        }

        return Semantics(
          label: widget.label,
          child: GestureDetector(
            key: const Key('video-edit-ruler'),
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) =>
                widget.onSeek(at(d.localPosition.dx), exact: true),
            onHorizontalDragStart: (d) => _dragX = d.localPosition.dx,
            onHorizontalDragUpdate: (d) {
              _dragX = d.localPosition.dx;
              widget.onSeek(at(_dragX), exact: false);
            },
            onHorizontalDragEnd: (_) => widget.onSeek(at(_dragX), exact: true),
            child: CustomPaint(
              size: Size(width, height),
              painter: _RulerPainter(
                length: widget.length,
                timeOf: widget.timeOf,
                style: style,
                scaler: scaler,
                tick: theme.colorScheme.outline,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.length,
    required this.timeOf,
    required this.style,
    required this.scaler,
    required this.tick,
  });

  final Duration length;
  final String Function(Duration at) timeOf;
  final TextStyle style;
  final TextScaler scaler;
  final Color tick;

  /// The steps between ticks, in seconds: the first with room for a time.
  static const _steps = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1200, 1800];

  @override
  void paint(Canvas canvas, Size size) {
    final seconds = length.inMilliseconds / 1000;
    if (seconds <= 0 || size.width <= 0) return;
    final perSecond = size.width / seconds;
    TextPainter label(String text) => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final widest = label(timeOf(length)).width + 12;
    final step = _steps.firstWhere(
      (s) => s * perSecond >= widest,
      orElse: () => _steps.last,
    );
    final paint = Paint()
      ..color = tick
      ..strokeWidth = 1;
    for (var s = 0; s <= seconds; s += step) {
      final x = s * perSecond;
      canvas.drawLine(
        Offset(x, size.height - 6),
        Offset(x, size.height),
        paint,
      );
      final text = label(timeOf(Duration(seconds: s)));
      if (x + text.width <= size.width) text.paint(canvas, Offset(x + 2, 0));
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.length != length ||
      old.style != style ||
      old.scaler != scaler ||
      old.tick != tick;
}

/// Where the preview is ([at], 0 to 1 of the video), a line across the
/// ruler and the lanes, between [lead] and [trail].
class _Playhead extends CustomPainter {
  _Playhead({
    required this.at,
    required this.lead,
    required this.trail,
    required this.color,
  });

  final double at;
  final double lead;
  final double trail;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = lead + at.clamp(0, 1) * (size.width - lead - trail);
    canvas.drawRect(
      Rect.fromLTWH(x - 1, 0, 2, size.height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_Playhead old) =>
      old.at != at || old.color != color || old.lead != lead;
}

/// The Take lane: the whole video ([length]), the part kept, from
/// [start] to [end], bright (the lane's [name] on it), the rest dimmed.
/// Its two grips trim it ([onTrimStart], [onTrimEnd], by how far they're
/// dragged; [onTrimmed] as one is let go), and both sounds with it.
class _TakeBar extends StatelessWidget {
  const _TakeBar({
    required this.length,
    required this.start,
    required this.end,
    required this.name,
    required this.label,
    required this.startLabel,
    required this.endLabel,
    required this.onTrimStart,
    required this.onTrimEnd,
    required this.onTrimmed,
  });

  final Duration length;
  final Duration start;
  final Duration end;
  final String name;

  /// What it does, for screen readers and the mouse; and its grips'.
  final String label;
  final String startLabel;
  final String endLabel;

  final void Function(Duration delta) onTrimStart;
  final void Function(Duration delta) onTrimEnd;
  final void Function({required bool end}) onTrimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final ms = length.inMilliseconds;
        final perMs = ms <= 0 ? 0.0 : width / ms;
        Duration delta(double dx) =>
            Duration(milliseconds: perMs <= 0 ? 0 : (dx / perMs).round());
        final left = start.inMilliseconds * perMs;
        final right = ms <= 0 ? width : end.inMilliseconds * perMs;
        // Where a grip can be, within the bar (however narrow).
        final gripMost = max(0.0, width - _Grip.width);
        return Semantics(
          label: label,
          child: Tooltip(
            message: label,
            child: SizedBox(
              key: const Key('video-edit-take-bar'),
              height: _SongBar.height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    // The whole video, dimmed.
                    Positioned.fill(
                      child: ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    // The part kept.
                    Positioned(
                      left: left,
                      width: max(2, right - left),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                          horizontal: _Grip.width + 4,
                        ),
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: left.clamp(0, gripMost),
                      top: 0,
                      bottom: 0,
                      width: _Grip.width,
                      child: _Grip(
                        key: const Key('video-edit-take-start'),
                        label: startLabel,
                        onDrag: (dx) => onTrimStart(delta(dx)),
                        onDone: () => onTrimmed(end: false),
                      ),
                    ),
                    Positioned(
                      left: (right - _Grip.width).clamp(0, gripMost),
                      top: 0,
                      bottom: 0,
                      width: _Grip.width,
                      child: _Grip(
                        key: const Key('video-edit-take-end'),
                        label: endLabel,
                        onDrag: (dx) => onTrimEnd(delta(dx)),
                        onDone: () => onTrimmed(end: true),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The Song lane's song along the video ([length]): its used part, [used]
/// long, drawn from [at] in the video (its name on it); what falls outside
/// the part kept ([start] to [end]) dimmed, as it's cut off. Dragged, it
/// moves along the video ([onMove]); dragged by either end, it's trimmed
/// ([onTrimStart], [onTrimEnd]): the start moves with what's cut, so the
/// rest stays put.
class _SongBar extends StatelessWidget {
  const _SongBar({
    required this.length,
    required this.start,
    required this.end,
    required this.at,
    required this.used,
    required this.name,
    required this.label,
    required this.onMove,
    required this.onTrimStart,
    required this.onTrimEnd,
  });

  /// A song whose length isn't known, so it can't be placed: its name
  /// alone.
  const _SongBar.unplaced({required this.name})
    : length = Duration.zero,
      start = Duration.zero,
      end = Duration.zero,
      at = Duration.zero,
      used = Duration.zero,
      label = null,
      onMove = null,
      onTrimStart = null,
      onTrimEnd = null;

  final Duration length;
  final Duration start;
  final Duration end;
  final Duration at;
  final Duration used;
  final String name;

  /// What it does, for screen readers and the mouse.
  final String? label;

  final void Function(Duration delta)? onMove;
  final void Function(Duration delta)? onTrimStart;
  final void Function(Duration delta)? onTrimEnd;

  /// The lanes' height: a touch target's.
  static const height = 44.0;

  Widget _block(ThemeData theme) => Container(
    decoration: BoxDecoration(
      color: theme.colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(6),
    ),
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: _Grip.width + 4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.graphic_eq,
          size: 16,
          color: theme.colorScheme.onPrimaryContainer,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.colorScheme.onPrimaryContainer,
              fontSize: 12,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onMove = this.onMove;
    if (onMove == null || length <= Duration.zero) {
      return SizedBox(
        key: const Key('video-edit-song-bar'),
        height: height,
        child: _block(theme),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final perMs = width / length.inMilliseconds;
        Duration ms(double dx) => Duration(milliseconds: (dx / perMs).round());
        final left = at.inMilliseconds * perMs;
        final usedWidth = used.inMilliseconds * perMs;
        final right = left + usedWidth;
        final keptLeft = start.inMilliseconds * perMs;
        final keptRight = end.inMilliseconds * perMs;
        final dim = theme.colorScheme.surface.withValues(alpha: 0.6);
        return Semantics(
          label: label,
          child: Tooltip(
            message: label ?? '',
            child: SizedBox(
              key: const Key('video-edit-song-bar'),
              height: height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    // The song's used part, where it plays.
                    Positioned(
                      left: left,
                      width: usedWidth < 2 ? 2 : usedWidth,
                      top: 0,
                      bottom: 0,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: GestureDetector(
                          key: const Key('video-edit-song-move'),
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragUpdate: (d) => onMove(ms(d.delta.dx)),
                          child: _block(theme),
                        ),
                      ),
                    ),
                    // Outside the part kept: cut off, as in the Take lane.
                    Positioned(
                      left: 0,
                      width: keptLeft.clamp(0, max(0.0, width)),
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(child: ColoredBox(color: dim)),
                    ),
                    Positioned(
                      left: keptRight.clamp(0, max(0.0, width)),
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(child: ColoredBox(color: dim)),
                    ),
                    // Its ends, to trim it, where they're on the bar.
                    if (left > -_Grip.width && left < width)
                      Positioned(
                        left: left,
                        top: 0,
                        bottom: 0,
                        width: _Grip.width,
                        child: _Grip(
                          key: const Key('video-edit-song-left'),
                          onDrag: (dx) => onTrimStart?.call(ms(dx)),
                        ),
                      ),
                    if (right > 0 && right < width + _Grip.width)
                      Positioned(
                        left: right - _Grip.width,
                        top: 0,
                        bottom: 0,
                        width: _Grip.width,
                        child: _Grip(
                          key: const Key('video-edit-song-right'),
                          onDrag: (dx) => onTrimEnd?.call(ms(dx)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The empty Song lane: a dashed row to add a song.
class _AddSong extends StatelessWidget {
  const _AddSong({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      painter: _Dashed(theme.colorScheme.outline),
      child: InkWell(
        key: const Key('video-edit-song-add'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          height: _SongBar.height,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dashed rounded outline.
class _Dashed extends CustomPainter {
  _Dashed(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          const Radius.circular(8),
        ),
      );
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Dashed old) => old.color != color;
}

/// One end of a bar: a grip to drag ([onDrag], by how far; [onDone] as
/// it's let go), named for screen readers by [label].
class _Grip extends StatelessWidget {
  const _Grip({super.key, required this.onDrag, this.onDone, this.label});

  static const width = 16.0;

  final void Function(double dx) onDrag;
  final VoidCallback? onDone;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
          onHorizontalDragEnd: onDone == null ? null : (_) => onDone!(),
          child: Center(
            child: Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
