import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../capture/media.dart';
import '../capture/video_edit.dart';
import '../l10n/language.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import 'file_screen.dart';
import 'media_url.dart';
import 'video_page.dart' show openPlayer;

/// Basic edits of a video, opened from its file screen: trim its start
/// and end, and keep, remove or replace its sound with a new track (one
/// of the capture's recordings, or a sound file), shifted to fit the
/// video. The preview plays the kept part, with the new track along it.
/// Save applies the edit on the device ([VideoEditor]) and puts the
/// result in the video's place; the screen then pops with the new page's
/// ID.
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

class _VideoEditScreenState extends State<VideoEditScreen> {
  VideoPlayerController? _video;
  Object? _error;

  Duration _start = Duration.zero;
  Duration _end = Duration.zero;
  EditSound _sound = EditSound.original;

  /// The new track: its file, its name, and its player (for its length,
  /// and to play it along the preview).
  XFile? _track;
  String? _trackName;
  VideoPlayerController? _trackPlayer;
  Duration _offset = Duration.zero;

  /// Checks the preview every tenth of a second while it plays: the kept
  /// part's end, and the track's place along it.
  Timer? _ticker;
  bool _trackPlaying = false;

  bool _saving = false;
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
      setState(() {
        _video = controller;
        _duration = length;
        _end = length;
      });
      controller.addListener(_onVideo);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _onVideo() {
    final video = _video;
    if (video == null) return;
    if (video.value.isPlaying) {
      _ticker ??= Timer.periodic(const Duration(milliseconds: 100), _tick);
    } else if (_ticker != null) {
      _ticker?.cancel();
      _ticker = null;
      unawaited(_pauseTrack());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _video?.removeListener(_onVideo);
    _video?.dispose();
    _trackPlayer?.dispose();
    super.dispose();
  }

  /// The kept part's end: back to its start, paused. The track: started
  /// where it comes in, paused where it ends.
  Future<void> _tick(Timer _) async {
    final video = _video;
    if (video == null || !video.value.isPlaying) return;
    final at = video.value.position;
    if (at >= _end) {
      await video.pause();
      await video.seekTo(_start);
      return;
    }
    final track = _trackPlayer;
    if (track == null || _sound != EditSound.track) return;
    final into = at - _start - _offset;
    final within = into >= Duration.zero && into < _trackLength;
    if (within && !_trackPlaying) {
      _trackPlaying = true;
      await track.seekTo(into);
      await track.play();
    } else if (!within && _trackPlaying) {
      await _pauseTrack();
    }
  }

  Future<void> _pauseTrack() async {
    if (!_trackPlaying) return;
    _trackPlaying = false;
    await _trackPlayer?.pause();
  }

  /// Plays the kept part (from its start, when outside it), or pauses.
  Future<void> _playPause() async {
    final video = _video;
    if (video == null) return;
    if (video.value.isPlaying) {
      await video.pause();
      return;
    }
    await video.setVolume(_sound == EditSound.original ? 1 : 0);
    final at = video.value.position;
    if (at < _start || at >= _end) await video.seekTo(_start);
    await video.play();
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
    await _video?.setVolume(sound == EditSound.original ? 1 : 0);
    if (sound != EditSound.track) await _pauseTrack();
    if (sound == EditSound.track && _track == null) await _pickTrack();
  }

  /// A sheet of the capture's recordings, and a sound file to pick.
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
    if (!mounted || picked == null) return;
    XFile? file;
    String? name;
    if (picked is EventPage) {
      final path = await _library.path(event!, picked);
      file = path != null
          ? XFile(path, mimeType: picked.mimeType)
          : XFile.fromData(
              await _library.original(event, picked),
              mimeType: picked.mimeType,
              name: picked.fileName,
            );
      name = fileLabel(l10n, event, picked);
    } else {
      file = await widget.pickFile();
      name = file == null ? null : nameOfFile(file.name) ?? file.name;
    }
    if (!mounted || file == null) return;
    await _loadTrack(file, name!);
  }

  Future<void> _loadTrack(XFile file, String name) async {
    await _pauseTrack();
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
      _track = file;
      _trackName = name;
      _trackPlayer = player;
      _trackLength = length;
      _offset = Duration.zero;
    });
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

  Future<void> _setOffset(Duration offset) async {
    setState(() => _offset = offset);
    // The track finds its new place at the next tick.
    await _pauseTrack();
  }

  VideoEdit get _edit => VideoEdit(
    start: _start,
    end: _end,
    sound: _sound,
    track: _sound == EditSound.track ? _track : null,
    offset: _offset,
  );

  bool get _canSave {
    if (_video == null || _saving) return false;
    if (_sound == EditSound.track && _track == null) return false;
    return _edit.changes(_duration);
  }

  Future<void> _save() async {
    final editor = _editor;
    final event = _library.byId(widget.eventId);
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (editor == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.videoEditNotHere)));
      return;
    }
    if (event == null) return;
    await _video?.pause();
    setState(() {
      _saving = true;
      _progress = null;
    });
    try {
      final page = widget.page;
      final input = await _fileOf(event, page);
      final output = await editor.apply(
        input,
        _edit,
        onProgress: (done) {
          if (mounted) setState(() => _progress = done);
        },
      );
      final media = Media.of(output) ?? Media(output, PageKind.video, 'mp4');
      final now = _library.byId(widget.eventId) ?? event;
      final updated = await _library.replacePage(now, page, media);
      final index = now.pages.indexWhere((p) => p.id == page.id);
      navigator.pop(index < 0 ? null : updated.pages[index].id);
    } on Object catch (e, stack) {
      debugPrint(
        'TabCam: video edit: ${l10n.videoEditCouldntSave}: $e\n$stack',
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.videoEditCouldntSave}: $e')),
      );
      setState(() => _saving = false);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          event == null ? '' : fileLabel(l10n, event, widget.page),
          overflow: TextOverflow.ellipsis,
        ),
        bottom: _saving
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
              absorbing: _saving,
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
                  if (_saving) ...[
                    const SizedBox(height: 16),
                    Text(
                      l10n.videoEditSaving,
                      key: const Key('video-edit-saving'),
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
                  l10n.videoEditReplaces,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                key: const Key('video-edit-cancel'),
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: Text(l10n.eventCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('video-edit-save'),
                onPressed: _canSave ? _save : null,
                child: Text(l10n.eventSave),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The video, at most a third of the screen, the play / pause button
  /// over it and its progress under.
  Widget _preview(VideoPlayerController video) {
    final height = MediaQuery.sizeOf(context).height / 3;
    return Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: height),
          child: GestureDetector(
            onTap: _playPause,
            child: Center(
              child: AspectRatio(
                aspectRatio: video.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(video),
                    ValueListenableBuilder(
                      valueListenable: video,
                      builder: (context, value, _) => value.isPlaying
                          ? const SizedBox.shrink()
                          : const Icon(
                              Icons.play_circle_fill,
                              size: 64,
                              color: Colors.white70,
                            ),
                    ),
                  ],
                ),
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
                onPressed: _playPause,
              ),
            ),
            Expanded(
              child: VideoProgressIndicator(video, allowScrubbing: true),
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

  /// The new track: its name and Change, then where it starts along the
  /// video, as a slider from its own length before the video's start to
  /// the kept part's end.
  Widget _trackRow(AppLocalizations l10n, ThemeData theme) {
    final name = _trackName;
    final clip = _end - _start;
    final low = -_trackLength.inMilliseconds.toDouble();
    final high = clip.inMilliseconds.toDouble();
    final offset = _offset.inMilliseconds.toDouble().clamp(low, high);
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
        if (name != null && high > low) ...[
          Slider(
            key: const Key('video-edit-offset'),
            min: low,
            max: high,
            value: offset,
            label: shift,
            onChanged: (v) => _setOffset(Duration(milliseconds: v.round())),
          ),
          Text(
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
        ],
      ],
    );
  }
}
