import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../capture/media.dart';
import '../capture/video_edit.dart';
import '../export/download.dart';
import '../l10n/language.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import 'edited_playback.dart';
import 'file_screen.dart';
import 'media_url.dart';
import 'video_page.dart' show openPlayer;
import 'messages.dart';

/// Basic edits of a video, opened from its file screen: trim its start
/// and end, and keep, remove or replace its sound with a new track (one
/// of the capture's recordings, or a sound file, added to them), shifted
/// to fit the video, at a volume set beside it. The edit is kept with the
/// page as it's made ([PageEdit]), and played as it says
/// ([EditedPlayback]: the kept part, muted, the new track along it); the
/// video's file stays as it is.
/// Download makes a file of it on the device ([VideoEditor]): the video,
/// the video without sound, or the sound alone.
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

/// What Download makes: the video as edited, the video without sound, or
/// its sound alone.
enum _Download { video, silent, sound }

class _VideoEditScreenState extends State<VideoEditScreen> {
  VideoPlayerController? _video;
  EditedPlayback? _playback;
  Object? _error;

  Duration _start = Duration.zero;
  Duration _end = Duration.zero;
  EditSound _sound = EditSound.original;

  /// The new track: its page in the capture, its file, its name, and its
  /// player (for its length, and to play it along the preview).
  String? _trackId;
  XFile? _track;
  String? _trackName;
  VideoPlayerController? _trackPlayer;
  Duration _offset = Duration.zero;

  /// The part of the track used, from [_trackStart] to [_trackEnd]
  /// (trimmed by the track bar's ends).
  Duration _trackStart = Duration.zero;
  Duration _trackEnd = Duration.zero;

  /// How loud the track plays, 0 to 1 (as it is), and how loud it was
  /// before it was muted, for unmuting.
  double _trackVolume = 1;
  double _unmutedVolume = 1;

  /// The shortest part of a track that can be used.
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

  Library get _library => widget.library;

  /// How long the video and the track are: the players' word, unless they
  /// have none (the browser, for a take it recorded), then the editor's.
  Duration _duration = Duration.zero;
  Duration _trackLength = Duration.zero;

  VideoEditing? get _editor => widget.editor ?? VideoEditor.instance;

  /// [file]'s length: [player]'s, or the editor's where the player can't
  /// say.
  Future<Duration> _lengthOf(VideoPlayerController player, XFile file) async {
    final known = player.value.duration;
    if (known > Duration.zero) return known;
    try {
      return await _editor?.length(file) ?? Duration.zero;
    } on Object catch (e) {
      debugPrint('TabCam: video edit: no length: $e');
      return Duration.zero;
    }
  }

  /// [page]'s file: its path, or its bytes on the web.
  Future<XFile> _fileOf(CaptureEvent event, EventPage page) async {
    final path = await _library.path(event, page);
    return path != null
        ? XFile(path, mimeType: page.mimeType)
        : XFile.fromData(
            await _library.original(event, page),
            mimeType: page.mimeType,
            name: page.fileName,
          );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  /// Opens the video, and the edit it has (its track too).
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
          _sound = edit.sound;
          _trackVolume = edit.trackVolume;
          // Saved muted, the level it had isn't known: Unmute gives 100%.
          _unmutedVolume = edit.trackVolume > 0 ? edit.trackVolume : 1;
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
    _playback?.dispose();
    _video?.dispose();
    _trackPlayer?.dispose();
    super.dispose();
  }

  /// Whether the edit changes the video: it's trimmed, or its sound isn't
  /// its own.
  bool get _edited =>
      _start > Duration.zero ||
      _end < _duration ||
      _sound != EditSound.original;

  /// The edit as it is now, as kept with the page: null when it changes
  /// nothing (the video plays as it is) and has no keys a newer app wrote
  /// to keep (nor a length to keep them with).
  PageEdit? get _pageEdit {
    if (!_edited && (_extra.isEmpty || _end <= _start)) return null;
    return PageEdit(
      start: _start,
      end: _end,
      sound: _sound,
      trackId: _trackId,
      trackStart: _trackStart,
      trackEnd: _trackEnd >= _trackLength ? null : _trackEnd,
      offset: _offset,
      trackVolume: _trackVolume,
      extra: _extra,
    );
  }

  /// Something changed: the preview plays it, and it's kept with the page
  /// a moment later.
  void _changed() {
    unawaited(_played());
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _keep);
  }

  /// The preview plays the edit as it is now.
  Future<void> _played() async =>
      _playback?.set(_pageEdit, track: _trackPlayer);

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

  /// Keeps from [start] to [end], at least [VideoEdit.minLength] long.
  void _trim(Duration start, Duration end) {
    final length = _duration;
    start = _clamp(start, Duration.zero, length);
    end = _clamp(end, Duration.zero, length);
    if (end - start < VideoEdit.minLength) {
      if (start + VideoEdit.minLength <= length) {
        end = start + VideoEdit.minLength;
      } else {
        start = length - VideoEdit.minLength;
        end = length;
      }
    }
    // The preview goes to the end moved, while paused.
    final endMoved = end != _end && start == _start;
    setState(() {
      _start = start;
      _end = end;
    });
    _changed();
    final video = _video;
    if (video != null && !video.value.isPlaying) {
      unawaited(video.seekTo(endMoved ? end : start));
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

  Future<void> _setSound(EditSound sound) async {
    setState(() => _sound = sound);
    _changed();
    if (sound == EditSound.track && _track == null) await _pickTrack();
  }

  /// A sheet of the capture's recordings, and a sound file to pick (added
  /// to the capture's files).
  Future<void> _pickTrack() async {
    final event = _library.byId(widget.eventId);
    final l10n = context.l10n;
    final recordings = [
      for (final p in event?.pages ?? const <EventPage>[])
        if (p.isAudio) p,
    ];
    final picked = await showModalBottomSheet<Object>(
      context: context,
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
            for (final p in recordings)
              ListTile(
                key: Key('video-edit-track-${p.id}'),
                leading: const Icon(Icons.music_note),
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

  /// Plays [file], page [id] of the capture, as the new track: as [from]
  /// places it, or from its start, with the video's.
  Future<void> _loadTrack(
    String id,
    XFile file,
    String name, {
    PageEdit? from,
  }) async {
    await _playback?.set(_pageEdit);
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
    });
    _changed();
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

  /// Moves the track's used part [delta] along the video (kept within
  /// touch of the kept part).
  void _moveTrack(Duration delta) {
    final used = _trackEnd - _trackStart;
    final offset = _clamp(_offset + delta, -used, _end - _start);
    if (offset == _offset) return;
    setState(() => _offset = offset);
    _changed();
  }

  /// Trims the track's start by [delta]: what's left stays where it is
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
    });
    _changed();
  }

  /// Trims the track's end by [delta].
  void _trimTrackEnd(Duration delta) {
    final end = _clamp(_trackEnd + delta, _trackStart + minTrack, _trackLength);
    if (end == _trackEnd) return;
    setState(() => _trackEnd = end);
    _changed();
  }

  /// The track at [volume], 0 to 1 (to the hundredth).
  void _setTrackVolume(double volume) {
    volume = PageEdit.volume(volume);
    if (volume == _trackVolume) return;
    setState(() => _trackVolume = volume);
    _changed();
  }

  /// Keeps the track's level, when it's not muted, for Unmute to put
  /// back: before Mute, and as a slide starts (one down to 0% mutes it).
  void _keepTrackVolume() {
    if (_trackVolume > 0) _unmutedVolume = _trackVolume;
  }

  /// Mutes the track, or puts it back as loud as it was.
  void _muteTrack() {
    if (_trackVolume > 0) {
      _keepTrackVolume();
      _setTrackVolume(0);
    } else {
      _setTrackVolume(_unmutedVolume > 0 ? _unmutedVolume : 1);
    }
  }

  /// Back to the video as it is: all of it, with its own sound (the track
  /// stays picked, from its start, at 100%, for New track).
  void _reset() {
    setState(() {
      _start = Duration.zero;
      _end = _duration;
      _sound = EditSound.original;
      _trackStart = Duration.zero;
      _trackEnd = _trackLength;
      _offset = Duration.zero;
      _trackVolume = 1;
      _unmutedVolume = 1;
    });
    _changed();
  }

  VideoEdit get _edit => VideoEdit(
    start: _start,
    end: _end,
    sound: _sound,
    track: _sound == EditSound.track ? _track : null,
    trackLength: _trackLength,
    trackStart: _trackStart,
    trackEnd: _trackEnd,
    offset: _offset,
    trackVolume: _trackVolume,
  );

  /// Whether the edit's track can be fitted (one of unknown length can't).
  bool get _trackReady =>
      _sound != EditSound.track ||
      (_track != null && _trackLength > Duration.zero);

  bool _canDownload(_Download what) {
    if (_video == null || _busy) return false;
    return switch (what) {
      _Download.video => _trackReady,
      _Download.silent => true,
      _Download.sound => switch (_sound) {
        EditSound.none => false,
        EditSound.original => true,
        EditSound.track => _trackReady && _edit.trackPart != null,
      },
    };
  }

  /// Makes a file of the edit, on the device ([VideoEditor]), and
  /// downloads it: the video as edited, without sound, or its sound alone.
  /// A video the edit doesn't change downloads as it is.
  Future<void> _download(_Download what) async {
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
      final edit = what == _Download.silent
          ? VideoEdit(start: _start, end: _end, sound: EditSound.none)
          : _edit;
      if (what != _Download.sound && !edit.changes(_duration)) {
        await Downloads.saveFile(_library, event, page, label);
        return;
      }
      final out = made = await editor.apply(
        input,
        edit,
        soundOnly: what == _Download.sound,
        onProgress: (done) {
          if (mounted) setState(() => _progress = done);
        },
      );
      final extension =
          Media.of(out)?.extension ?? (what == _Download.sound ? 'm4a' : 'mp4');
      await Downloads.saveBytes(
        safeFileName(label, extension),
        await out.readAsBytes(),
        out.mimeType ?? 'video/mp4',
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final event = _library.byId(widget.eventId);
    final video = _video;
    final changed = _edited;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          event == null ? '' : fileLabel(l10n, event, widget.page),
          overflow: TextOverflow.ellipsis,
        ),
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
                  const SizedBox(height: 16),
                  Text(l10n.videoEditTrim, style: theme.textTheme.titleMedium),
                  _trimBar(l10n, theme),
                  const SizedBox(height: 16),
                  Text(l10n.videoEditSound, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SegmentedButton<EditSound>(
                    key: const Key('video-edit-sound'),
                    segments: [
                      ButtonSegment(
                        value: EditSound.original,
                        label: Text(l10n.videoEditSoundOriginal),
                        icon: const Icon(Icons.volume_up_outlined),
                      ),
                      ButtonSegment(
                        value: EditSound.none,
                        label: Text(l10n.videoEditSoundNone),
                        icon: const Icon(Icons.volume_off_outlined),
                      ),
                      ButtonSegment(
                        value: EditSound.track,
                        label: Text(l10n.videoEditSoundTrack),
                        icon: const Icon(Icons.library_music_outlined),
                      ),
                    ],
                    selected: {_sound},
                    onSelectionChanged: (s) => _setSound(s.first),
                  ),
                  if (_sound == EditSound.track) ...[
                    const SizedBox(height: 8),
                    _trackRow(l10n, theme),
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
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.videoEditKept,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const Key('video-edit-reset'),
                onPressed: changed && !_busy ? _reset : null,
                child: Text(l10n.videoEditReset),
              ),
              const SizedBox(width: 8),
              _downloadButton(l10n),
            ],
          ),
        ),
      ),
    );
  }

  /// Download, split: the button downloads the video as edited; its menu
  /// also has it without sound, and its sound alone.
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
          onPressed: _canDownload(_Download.video)
              ? () => _download(_Download.video)
              : null,
        ),
        const SizedBox(width: 2),
        MenuAnchor(
          menuChildren: [
            for (final (what, label, icon) in [
              (
                _Download.video,
                l10n.videoEditDownloadVideo,
                Icons.movie_outlined,
              ),
              (
                _Download.silent,
                l10n.videoEditDownloadSilent,
                Icons.videocam_off_outlined,
              ),
              (_Download.sound, l10n.videoEditDownloadSound, Icons.audiotrack),
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

  /// The video, at most a third of the screen, and its controls under it:
  /// play / pause, its progress and where it is.
  Widget _preview(VideoPlayerController video) {
    final height = MediaQuery.sizeOf(context).height / 3;
    return Column(
      children: [
        ConstrainedBox(
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
        ),
        Row(
          children: [
            // Its own button: the kept part plays, not the whole video.
            ValueListenableBuilder(
              valueListenable: video,
              builder: (context, value, _) => IconButton(
                key: const Key('video-edit-play'),
                tooltip: value.isPlaying
                    ? context.l10n.textViewPause
                    : context.l10n.textViewPlay,
                icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: _playback?.playPause,
              ),
            ),
            Expanded(
              child: VideoProgressIndicator(video, allowScrubbing: true),
            ),
            const SizedBox(width: 12),
            // Where it is, to the tenth of a second: the trims are set by
            // it.
            ValueListenableBuilder(
              valueListenable: video,
              builder: (context, value, _) => Text(
                time(value.position),
                key: const Key('video-edit-time'),
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ],
    );
  }

  /// The part kept: a range over the whole video, its times, and buttons
  /// to start or end it where the preview is.
  Widget _trimBar(AppLocalizations l10n, ThemeData theme) {
    final ms = _duration.inMilliseconds.toDouble();
    final primary = theme.colorScheme.primary;
    final trimmed = _start > Duration.zero || _end < _duration;
    return Column(
      children: [
        RangeSlider(
          key: const Key('video-edit-range'),
          min: 0,
          max: ms <= 0 ? 1 : ms,
          values: RangeValues(
            _start.inMilliseconds.clamp(0, ms).toDouble(),
            _end.inMilliseconds.clamp(0, ms).toDouble(),
          ),
          onChanged: ms <= 0
              ? null
              : (v) => _trim(
                  Duration(milliseconds: v.start.round()),
                  Duration(milliseconds: v.end.round()),
                ),
        ),
        Row(
          children: [
            IconButton(
              key: const Key('video-edit-start-here'),
              tooltip: l10n.videoEditTrimStart,
              icon: const Icon(Icons.first_page),
              onPressed: () => _trimHere(end: false),
            ),
            Expanded(
              child: Text(
                l10n.videoEditKeep(time(_start), time(_end)),
                key: const Key('video-edit-times'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: trimmed ? primary : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            IconButton(
              key: const Key('video-edit-end-here'),
              tooltip: l10n.videoEditTrimEnd,
              icon: const Icon(Icons.last_page),
              onPressed: () => _trimHere(end: true),
            ),
          ],
        ),
      ],
    );
  }

  /// The new track: its name and Change, then, on one row, its volume
  /// ([_TrackVolume]) and its bar along the kept part ([_TrackBar]:
  /// dragged to move it, its ends to trim it), nudges of a tenth of a
  /// second either way, and where it starts in words.
  Widget _trackRow(AppLocalizations l10n, ThemeData theme) {
    final name = _trackName;
    final clip = _end - _start;
    const tenth = Duration(milliseconds: 100);
    final trimmed = _trackStart > Duration.zero || _trackEnd < _trackLength;
    final shift = _offset == Duration.zero
        ? l10n.videoEditTrackWith
        : _offset > Duration.zero
        ? l10n.videoEditTrackAfter(time(_offset))
        : l10n.videoEditTrackBefore(time(-_offset));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const Key('video-edit-track'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.music_note),
          title: Text(name ?? l10n.videoEditNoTrack),
          trailing: TextButton(
            key: const Key('video-edit-change-track'),
            onPressed: _pickTrack,
            child: Text(
              name == null
                  ? l10n.videoEditPickTrack
                  : l10n.videoEditChangeTrack,
            ),
          ),
        ),
        if (name != null &&
            _trackLength > Duration.zero &&
            clip > Duration.zero) ...[
          Row(
            children: [
              _TrackVolume(
                volume: _trackVolume,
                onChanged: _setTrackVolume,
                onChangeStart: _keepTrackVolume,
                onMute: _muteTrack,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _TrackBar(
                  clip: clip,
                  trackStart: _trackStart,
                  trackEnd: _trackEnd,
                  offset: _offset,
                  name: name,
                  label: l10n.videoEditTrackBar,
                  onMove: _moveTrack,
                  onTrimStart: _trimTrackStart,
                  onTrimEnd: _trimTrackEnd,
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                key: const Key('video-edit-track-earlier'),
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
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              IconButton(
                key: const Key('video-edit-track-later'),
                tooltip: l10n.videoEditTrackLater,
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _moveTrack(tenth),
              ),
            ],
          ),
          if (trimmed)
            Text(
              l10n.videoEditTrackUsed(time(_trackStart), time(_trackEnd)),
              key: const Key('video-edit-track-used'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ],
    );
  }
}

/// The track's volume, at the left of its bar: a speaker over the level
/// (`80%`, in the primary colour when it's not as it is). Tapped, it opens
/// a slider, 0% to 100% in steps of 5%, with Mute beside it (Unmute puts
/// back the level it had before Mute or a slide down to 0%). It fits its
/// bar's height at any text size: the level stays on one line, and the
/// two shrink together when the text is too large.
class _TrackVolume extends StatelessWidget {
  const _TrackVolume({
    required this.volume,
    required this.onChanged,
    required this.onChangeStart,
    required this.onMute,
  });

  final double volume;
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
    final icon = Icon(
      volume <= 0
          ? Icons.volume_off_outlined
          : volume < 0.5
          ? Icons.volume_down_outlined
          : Icons.volume_up_outlined,
    );
    final changed = volume != 1;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const Key('video-edit-track-mute'),
                tooltip: volume <= 0
                    ? l10n.videoEditTrackUnmute
                    : l10n.videoEditTrackMute,
                icon: icon,
                onPressed: onMute,
              ),
              SizedBox(
                width: 200,
                child: Slider(
                  key: const Key('video-edit-track-volume-slider'),
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
          message: l10n.videoEditTrackVolume,
          child: InkWell(
            key: const Key('video-edit-track-volume'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
            child: SizedBox(
              width: 48,
              height: _TrackBar.height,
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
                        key: const Key('video-edit-track-volume-level'),
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 11,
                          color: changed ? theme.colorScheme.primary : null,
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

/// The track along the kept part: a bar as long as the kept part, the
/// track's used part drawn over it where it plays (what falls outside is
/// cut off). Dragged, it moves along the video ([onMove]); dragged by
/// either end, it's trimmed ([onTrimStart], [onTrimEnd]): the start moves
/// with what's cut, so the rest stays put.
class _TrackBar extends StatelessWidget {
  const _TrackBar({
    required this.clip,
    required this.trackStart,
    required this.trackEnd,
    required this.offset,
    required this.name,
    required this.label,
    required this.onMove,
    required this.onTrimStart,
    required this.onTrimEnd,
  });

  final Duration clip;
  final Duration trackStart;
  final Duration trackEnd;
  final Duration offset;
  final String name;

  /// What it does, for screen readers and the mouse.
  final String label;

  final void Function(Duration delta) onMove;
  final void Function(Duration delta) onTrimStart;
  final void Function(Duration delta) onTrimEnd;

  static const height = 44.0;
  static const grip = 14.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final perMs = width / clip.inMilliseconds;
        Duration ms(double dx) => Duration(milliseconds: (dx / perMs).round());
        final left = offset.inMilliseconds * perMs;
        final used = (trackEnd - trackStart).inMilliseconds * perMs;
        final right = left + used;
        return Semantics(
          label: label,
          child: Tooltip(
            message: label,
            child: SizedBox(
              key: const Key('video-edit-track-bar'),
              height: height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    // The kept part.
                    Positioned.fill(
                      child: ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    // The track's used part, where it plays.
                    Positioned(
                      left: left,
                      width: used < 2 ? 2 : used,
                      top: 0,
                      bottom: 0,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: GestureDetector(
                          key: const Key('video-edit-track-move'),
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragUpdate: (d) => onMove(ms(d.delta.dx)),
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                              horizontal: grip + 4,
                            ),
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
                                      color:
                                          theme.colorScheme.onPrimaryContainer,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Its ends, to trim it, where they're on the bar.
                    if (left > -grip && left < width)
                      Positioned(
                        left: left,
                        top: 0,
                        bottom: 0,
                        width: grip,
                        child: _Grip(
                          key: const Key('video-edit-track-left'),
                          onDrag: (dx) => onTrimStart(ms(dx)),
                        ),
                      ),
                    if (right > 0 && right < width + grip)
                      Positioned(
                        left: right - grip,
                        top: 0,
                        bottom: 0,
                        width: grip,
                        child: _Grip(
                          key: const Key('video-edit-track-right'),
                          onDrag: (dx) => onTrimEnd(ms(dx)),
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

/// One end of the track bar: a grip to drag.
class _Grip extends StatelessWidget {
  const _Grip({super.key, required this.onDrag});

  final void Function(double dx) onDrag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
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
    );
  }
}
