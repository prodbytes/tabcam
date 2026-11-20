import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../capture/waveform.dart';
import '../capture/edit_layers.dart';
import '../capture/media.dart';
import '../capture/out_delays.dart';
import '../capture/play_along_sidebar.dart' show isTake;
import '../capture/song_sync.dart';
import '../capture/sound_reader.dart';
import '../capture/take_log.dart';
import '../capture/take_syncer.dart';
import '../capture/video_edit.dart';
import '../cloud/cloud_ocr.dart';
import '../cloud/cloud_sync.dart';
import '../dictionary/dictionary_sidebar.dart';
import '../export/download.dart';
import '../l10n/language.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import '../metronome/metronome.dart';
import '../recognition/necklines.dart';
import 'download_settings.dart';
import 'edited_playback.dart';
import 'file_screen.dart';
import 'media_url.dart';
import 'premium_card.dart';
import 'share_sheet.dart';
import 'video_page.dart' show mediaLength, openPlayer, pageFile;
import 'keys_help.dart';
import 'messages.dart';
import 'mono_font.dart';
import 'on_picture.dart';

/// Basic edits of a video, opened from its file screen, on one time axis:
/// a ruler (tapped or dragged, the preview goes there) over two lanes,
/// mixed. The **Take** lane (for a video Cam didn't record, "Video
/// sound") is the whole video, the part kept bright: its grips trim it,
/// and both sounds with it. The **Song** lane ("Track") holds one of the
/// capture's recordings, videos or takes, or a sound file (added to
/// them), placed along the video by hand (dragged, trimmed by its ends,
/// nudged by a twentieth of a second); ⋮ changes or removes it. Each lane has
/// its volume and Mute at its left; both go through the **Master**, its
/// volume (up to 200%) and Mute right above the fades' sliders (on a
/// phone, above **On the video**). Under them (beside everything, on a
/// wide screen), **On the video**: what's drawn over it, as chips: a
/// take's tab (its style, the size, background and colours, opened by
/// its palette button or, on a phone, a long press on the band in the
/// preview), the title
/// (its text typed under them on a phone, beside them on a wide screen),
/// the watermark, which only Premium removes, and the **Fades**: the
/// video fades in from black at the kept part's start and out to black
/// at its end, both sounds with it, 3 s each by default (their sliders
/// under the chips, or beside them; drawn on the Take lane as ramps at
/// its ends).
/// The edit is kept with the page as it's made ([PageEdit]), and played
/// as it says ([EditedPlayback]: the kept part, both lanes at their
/// volumes, the layers over it, [EditLayers]; from where the preview is,
/// so a part cut off plays too, as the video is, and it stops at the
/// kept part's end); the video's file stays as it is. A player that
/// fails says so, with Try again. Download renders the same plan
/// ([RenderPlan]) to a file on the device ([VideoEditor]): the video,
/// the video without sound, or the sound alone. The space bar plays or
/// pauses it, as Play / Pause and a tap on the preview do (not while the
/// title is typed).
class VideoEditScreen extends StatefulWidget {
  const VideoEditScreen({
    super.key,
    required this.library,
    required this.eventId,
    required this.page,
    this.editor,
    this.pickFile = _pickFile,
    this.ocr,
    this.sync,
  });

  final Library library;
  final String eventId;
  final EventPage page;

  /// Cloud sync, for Share (the file's edit view's link); null without.
  final CloudSync? sync;

  /// TabCam Premium, where the build has it: the watermark can be turned
  /// off, and is left out of a download, only for a user who has it now
  /// ([watermarkUnlocked]; null, a build without it: always).
  final CloudOcr? ocr;

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

  /// Opens the editor on [page] over the screen, and completes when the
  /// user comes back: from the file screen's Edit, and from a take's Edit
  /// in the play-along sidebar, the same way.
  static Future<void> open(
    BuildContext context, {
    required Library library,
    required String eventId,
    required EventPage page,
    CloudOcr? ocr,
    CloudSync? sync,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => VideoEditScreen(
        library: library,
        eventId: eventId,
        page: page,
        ocr: ocr,
        sync: sync,
      ),
    ),
  );

  @override
  State<VideoEditScreen> createState() => _VideoEditScreenState();
}

/// A lane's level: its [volume] (0 to 1; the master's, 0 to 2), whether
/// it's [muted] (the level kept), the level Unmute puts back after a
/// slide down to 0% ([unmuted]), and a lane's [stereo] (its channels and
/// balance).
class _Level {
  _Level([
    this.volume = 1,
    this.muted = false,
    this.stereo = LaneStereo.standard,
  ]) : unmuted = volume > 0 ? volume : 1,
       master = false;

  /// The master's level, up to [PageEdit.maxMaster].
  _Level.master([this.volume = 1, this.muted = false])
    : unmuted = volume > 0 ? volume : 1,
      master = true,
      stereo = LaneStereo.standard;

  /// Whether it's the master's (up to 200%).
  final bool master;

  double volume;
  bool muted;
  double unmuted;
  LaneStereo stereo;

  /// Whether it's heard.
  bool get silent => muted || volume <= 0;

  /// Keeps the level, when it's not 0, for Unmute: as a slide starts.
  void keep() {
    if (volume > 0) unmuted = volume;
  }

  /// Slid to [to] (which unmutes it); whether that changed anything.
  bool slide(double to) {
    to = master ? PageEdit.master(to) : PageEdit.volume(to);
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

  /// The master's level: both lanes through it, up to 200%.
  var _master = _Level.master();

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

  /// The song the take's log lines up by itself (as it played while the
  /// take recorded), when it has one still in the capture: the default
  /// Song lane.
  LoggedSong? _logged;

  /// The song's delays kept on this device per audio output
  /// ([OutDelays]), and the one this take opened with, kept for the output
  /// its song played through (null: none): a lane at it hasn't been moved
  /// by hand, so it follows where the song is found in the take's sound.
  Map<String, int> _outDelays = const {};
  int? _seededMs;

  /// The shortest part of a song that can be used.
  static const minTrack = Duration(milliseconds: 500);

  /// Auto-align ([_align]): whether the sounds can be read here (a
  /// [SoundReader]; none on the desktop, where it isn't offered), whether
  /// it's listening, and what it said last (null: nothing).
  late final bool _listens = _canListen();
  bool _aligning = false;
  String? _alignSaid;

  static bool _canListen() {
    final reader = SoundReader.open();
    reader?.close();
    return reader != null;
  }

  /// Whether the take's tab is drawn over it (where it can be,
  /// [tabOffered]), how it looks, and whether its style's controls are
  /// open in place of the chips (on a phone).
  bool _tab = true;
  EditTabStyle _tabStyle = EditTabStyle.standard;
  bool _editingTabStyle = false;

  /// The title: whether it's on, and the text typed for it (null: the
  /// capture's name, [_captureTitle]); its fields, and whether they're
  /// open in place of the chips (on a phone).
  bool _titleOn = true;
  List<String>? _titleLines;
  final _title1 = TextEditingController();
  final _title2 = TextEditingController();
  final _titleFocus = FocusNode();
  final _title2Focus = FocusNode();
  bool _editingTitle = false;

  /// Whether the watermark is drawn (only Premium turns it off).
  bool _watermark = true;

  /// The layer picked on the preview ([OnPicture]): outlined in the
  /// primary colour, with its toolbar; and the tab's size when its
  /// handle's drag began.
  PictureLayer? _picked;
  double _resizeFrom = EditTabStyle.standard.size;

  /// How long the video fades in from black, and out to black (both
  /// sounds with it); the fades the Fades chip puts back when turned on
  /// again; and whether their sliders are open in place of the chips (on
  /// a phone).
  Duration _fadeIn = PageEdit.defaultFade;
  Duration _fadeOut = PageEdit.defaultFade;
  (Duration, Duration)? _fadesBack;
  bool _editingFades = false;

  /// The layers the preview draws, and what they were worked out from;
  /// the title's picture, for a tap on it.
  List<PlanLayer> _layers = const [];
  Object? _layersOf;
  final _measured = LayerPictures();

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

  /// Where the preview was last asked to go, until its player got there
  /// (null: where the player says): the playhead and the time show it at
  /// once, and follow a drag held back.
  final _headAt = ValueNotifier<Duration?>(null);

  /// Where the preview is: where it's going, or where its player says.
  Duration get _at => _headAt.value ?? _video?.value.position ?? Duration.zero;

  /// The editor's keys: the space bar plays or pauses ([_key]).
  final _keys = FocusNode(debugLabel: 'video edit keys');

  /// The room the editor's content had when last laid out (the body,
  /// beside the dictionary's and the metronome's sidebars): whether it's
  /// [_wide] is measured on it.
  Size? _box;

  /// The title's fields, the fades' sliders and the tab's style in the
  /// Download settings, brought into view as a tap on the picture shows
  /// them hidden ([_showSettings]).
  final _titleAt = GlobalKey(debugLabel: 'title fields');
  final _fadesAt = GlobalKey(debugLabel: 'fade fields');
  final _tabStyleAt = GlobalKey(debugLabel: 'tab style');

  Library get _library => widget.library;

  /// How long the video and the song are: the players' word, unless they
  /// have none (the browser, for a take it recorded), then the editor's.
  Duration _duration = Duration.zero;
  Duration _trackLength = Duration.zero;

  VideoEditing? get _editor => widget.editor ?? VideoEditor.instance;

  /// Whether the video is one of Cam's takes: its lanes are then "Take"
  /// and "Song" ("Video sound" and "Track" otherwise).
  bool get _take => isTake(widget.page);

  /// What Cam noted while the take recorded (none: not a take, or one
  /// saved before takes kept one): the page's, as it is in the library
  /// now ([_log]: with where its song was found in its sound, once
  /// that's measured).
  TakeLog? get _takeLog => _log ?? widget.page.takeLog;
  TakeLog? _log;

  /// Where the Take lane's grips are without their snap to the song's
  /// marks, while one is dragged ([_snapped]).
  Duration? _dragStart;
  Duration? _dragEnd;

  /// Whether the Song lane has a song in it (as [PageEdit.hasSong]: a
  /// song picked, its lane not `off`; none said, a newer app's default).
  bool get _hasSong => _song != SongMode.off && _trackId != null;

  /// Whether the song in the Song lane is lined up by itself, as it
  /// played while the take recorded ([_logged]; `song` not said).
  bool get _lined =>
      _hasSong &&
      (_song == null || _song == SongMode.auto) &&
      _trackId == _logged?.page;

  /// A lined-up song's clips, more than one (it was paused, skipped or
  /// started over while recording), at their times in the video (`at`),
  /// as the Song lane shows them; null otherwise.
  List<SongClip>? get _linedClips {
    final logged = _logged;
    if (logged == null || !_lined || logged.clips.length < 2) return null;
    final shift = logged.shiftOf(_current);
    return [
      for (final c in logged.clips)
        SongClip(
          at: c.at + shift,
          from: c.from,
          to: _trackLength > Duration.zero && c.to > _trackLength
              ? _trackLength
              : c.to,
        ),
    ];
  }

  /// [file]'s length: [player]'s, or the editor's where the player can't
  /// say ([mediaLength], as the file screen finds it).
  Future<Duration> _lengthOf(VideoPlayerController player, XFile file) =>
      mediaLength(player, () async => file, editor: _editor);

  /// [page]'s file: its path, or its bytes on the web.
  Future<XFile> _fileOf(CaptureEvent event, EventPage page) =>
      pageFile(_library, event, page);

  /// The capture's name, as the title's default text.
  List<String> get _captureTitle {
    final event = _library.byId(widget.eventId);
    return event == null
        ? const []
        : captureTitleLines(event.title, event.artist);
  }

  /// The title's text as it is now: what's typed, or the capture's name.
  List<String> get _titleText => titleText(_titleLines ?? _captureTitle);

  /// Whether this user can leave the watermark off ([watermarkUnlocked]).
  bool get _unlocked => watermarkUnlocked(widget.ocr);

  /// Whether the title's text is being edited: its fields open (a phone),
  /// or one of them focused (a wide screen). The preview then shows it
  /// as it ends up, not fading in.
  bool get _titleBeingEdited =>
      _editingTitle || _titleFocus.hasFocus || _title2Focus.hasFocus;

  /// The fades as the kept part plays them (none longer than half of it).
  Fades get _fades {
    final length = _end - _start;
    return Fades(
      fadeIn: PageEdit.fadeWithin(_fadeIn, length),
      fadeOut: PageEdit.fadeWithin(_fadeOut, length),
      length: length,
    );
  }

  /// The longest a fade can be over the kept part: [PageEdit.maxFade], or
  /// half the kept part, to the tenth of a second.
  Duration get _fadeMost {
    final most = PageEdit.fadeWithin(PageEdit.maxFade, _end - _start);
    return Duration(milliseconds: most.inMilliseconds ~/ 100 * 100);
  }

  @override
  void initState() {
    super.initState();
    widget.ocr?.addListener(_onPremium);
    _titleFocus.addListener(_onTitleFocus);
    _title2Focus.addListener(_onTitleFocus);
    DownloadSettingsState.instance.addListener(_onSettings);
    unawaited(_open());
    unawaited(_loadFormats());
  }

  /// Premium's status arrived, or changed: the Watermark chip unlocks (or
  /// locks) where it is.
  void _onPremium() {
    if (mounted) setState(() {});
  }

  /// The Download settings shown or hidden: hidden, the fields one of
  /// their chips opened in their place (on a phone) close, as Done closes
  /// them, so the preview stops showing the title as it's edited.
  void _onSettings() {
    if (!mounted || DownloadSettingsState.instance.open) return;
    if (!_editingTitle && !_editingFades && !_editingTabStyle) return;
    setState(() {
      _editingTitle = false;
      _editingFades = false;
      _editingTabStyle = false;
    });
  }

  /// Shows the Download settings where they're hidden, then brings [at]
  /// (the part a tap on the picture opened) into view in them.
  void _showSettings(GlobalKey at) {
    final settings = DownloadSettingsState.instance;
    if (settings.open) return;
    settings.show();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shown = at.currentContext;
      if (mounted && shown != null && shown.mounted) {
        unawaited(Scrollable.ensureVisible(shown));
      }
    });
  }

  void _onTitleFocus() {
    if (mounted) setState(() {});
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
    VideoPlayerController? opened;
    try {
      final controller = opened = await openPlayer(
        _library,
        event,
        widget.page,
      );
      final videoFile = await _fileOf(event, widget.page);
      final length = await _lengthOf(controller, videoFile);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      unawaited(_readTakeWave(videoFile, length));
      await controller.setLooping(false);
      final page = event.pages.where((p) => p.id == widget.page.id).firstOrNull;
      final saved = page?.edit;
      final log = page?.takeLog ?? widget.page.takeLog;
      // A take's song, lined up by itself as it played while recording,
      // unless the edit placed one or took it out.
      final logged = LoggedSong.of(log);
      final lined =
          logged != null && event.pages.any((p) => p.id == logged.page)
          ? logged
          : null;
      var edit = withLoggedSong(saved, lined, duration: length);
      // Kept where the log alone had it, before the song was found in
      // the take's sound: it follows what was found.
      if (edit != null && lined != null && _follows(edit, lined)) {
        edit = lined.placed(edit);
      }
      // Through headphones, the song not found in the take's sound, and
      // a delay kept for that output: a lane still where the log has it
      // opens moved by it (once the song is in it, below).
      final outDelays = await OutDelays.read(_library);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      final kept = log != null && _seedsDelay(log)
          ? outDelays[log.out!.key]
          : null;
      int? seed;
      int? seeded;
      if (kept != null &&
          edit != null &&
          lined != null &&
          !lined.measured &&
          edit.songMode == SongMode.auto &&
          edit.trackId == lined.page) {
        final shift = lined.shiftOf(edit).inMilliseconds;
        if (shift == 0) seed = kept;
        if (shift == 0 || shift == kept) seeded = kept;
      }
      setState(() {
        _log = log;
        _video = controller;
        _playback = EditedPlayback(controller, whole: true);
        _duration = length;
        _end = length;
        _logged = lined;
        _outDelays = outDelays;
        _seededMs = seeded;
        _saved = saved;
        _extra = saved?.extra ?? const {};
        if (edit != null) {
          _start = _clamp(edit.start, Duration.zero, length);
          _end = _clamp(edit.end, _start, length);
          _own = _Level(edit.ownVolume, edit.ownMuted, edit.ownStereo);
          _song = edit.song;
          _songLevel = _Level(
            edit.trackVolume,
            edit.songMuted,
            edit.songStereo,
          );
          _master = _Level.master(edit.masterVolume, edit.masterMuted);
          _tab = edit.tab;
          _tabStyle = edit.tabStyle;
          _titleOn = edit.title?.on ?? true;
          _titleLines = edit.title?.lines;
          _watermark = edit.watermark;
          _fadeIn = edit.fadeIn;
          _fadeOut = edit.fadeOut;
        }
        _fillTitle();
      });
      controller.addListener(_onPlayer);
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
        // Moved as the delay control moves it, and kept so.
        if (seed != null && mounted && _lined && _trackLength > Duration.zero) {
          _moveTrack(Duration(milliseconds: seed));
        }
      }
      await _played();
      // Not measured yet (a take from before, or from a device that
      // couldn't): the song is looked for in the take's sound now.
      if (lined != null && log?.sync == null) unawaited(_measureSong());
    } on Object catch (e) {
      // A player opened but not the screen's yet has no one else to let
      // go of it.
      if (opened != null && !identical(opened, _video)) {
        unawaited(opened.dispose());
      }
      if (mounted) setState(() => _error = e);
    }
  }

  /// The video's player said something: when it failed after it opened
  /// (a play the browser refused, a file it can't read on), the screen
  /// says the video can't be played, with Try again ([_retry]).
  void _onPlayer() {
    final video = _video;
    if (video == null || _error != null || !video.value.hasError) return;
    final error = video.value.errorDescription ?? 'the player failed';
    debugPrint('TabCam: video edit: the player failed: $error');
    if (mounted) setState(() => _error = error);
  }

  /// Try again, where the video couldn't be opened or its player failed:
  /// the edit as it is kept with the page, the players let go of, and the
  /// video opened again, with that edit.
  Future<void> _retry() async {
    if (_error == null) return;
    final video = _video;
    final song = _trackPlayer;
    final unkept = _saveTimer?.isActive ?? false;
    _saveTimer?.cancel();
    _seekWait?.cancel();
    _seekWait = null;
    _seekNext = null;
    _headAt.value = null;
    video?.removeListener(_onPlayer);
    _playback?.dispose();
    setState(() {
      _error = null;
      _video = null;
      _playback = null;
      _trackPlayer = null;
      _picked = null;
    });
    if (unkept) await _keep();
    await video?.dispose();
    await song?.dispose();
    if (mounted) await _open();
  }

  /// Whether [edit] has [logged]'s song lined up by itself and not moved
  /// from it ([LoggedSong.shiftOf] none).
  static bool _follows(PageEdit edit, LoggedSong logged) =>
      edit.songMode == SongMode.auto &&
      edit.trackId == logged.page &&
      logged.shiftOf(edit) == Duration.zero;

  /// Whether a take's log says its song played through headphones
  /// (wired, Bluetooth, USB) for the whole take and wasn't found in its
  /// sound: it then opens with the delay kept for that output
  /// ([OutDelays]).
  static bool _seedsDelay(TakeLog log) => switch (log.out) {
    final out? => out.headphones && !out.changed && !(log.sync?.found ?? false),
    null => false,
  };

  /// Has the take's song found in its sound ([TakeSyncer]), and, found,
  /// lines it up there: the Song lane follows, unless it was moved by
  /// hand, or holds another song (it stays where it was put).
  Future<void> _measureSong() async {
    final log = await TakeSyncer.sync(_library, widget.eventId, widget.page.id);
    if (!mounted || log == null || log.sync == null || log == _log) return;
    final logged = LoggedSong.of(log);
    final was = _logged;
    final follows =
        logged != null &&
        was != null &&
        logged.page == was.page &&
        _lined &&
        (_follows(_current, was) ||
            (_seededMs != null &&
                was.shiftOf(_current).inMilliseconds == _seededMs));
    setState(() {
      _log = log;
      // Found, the song's sound has the output's delay in it already.
      if (logged?.measured ?? false) _seededMs = null;
      if (logged == null || was == null || logged.page != was.page) return;
      _logged = logged;
      if (!follows) return;
      final placed = logged.placed(_current);
      _offset = placed.offset;
      _trackStart = _clamp(placed.trackStart, Duration.zero, _trackLength);
      _trackEnd = placed.trackEnd == null
          ? _trackLength
          : _clamp(placed.trackEnd!, _trackStart, _trackLength);
    });
    _changed();
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      unawaited(_keep());
    }
    _timelineScroll.dispose();
    _seekWait?.cancel();
    _video?.removeListener(_onPlayer);
    _playback?.dispose();
    _video?.dispose();
    _trackPlayer?.dispose();
    _headAt.dispose();
    widget.ocr?.removeListener(_onPremium);
    DownloadSettingsState.instance.removeListener(_onSettings);
    _title1.dispose();
    _title2.dispose();
    _titleFocus.dispose();
    _title2Focus.dispose();
    _keys.dispose();
    _measured.dispose();
    super.dispose();
  }

  /// The edit as it is now, with the keys a newer app wrote.
  PageEdit get _current => PageEdit(
    start: _start,
    end: _end,
    ownVolume: _own.volume,
    ownMuted: _own.muted,
    ownStereo: _own.stereo,
    song: _song,
    songMuted: _songLevel.muted,
    trackId: _trackId,
    trackStart: _trackStart,
    trackEnd: _trackEnd >= _trackLength ? null : _trackEnd,
    offset: _offset,
    trackVolume: _songLevel.volume,
    songStereo: _songLevel.stereo,
    masterVolume: _master.volume,
    masterMuted: _master.muted,
    tab: _tab,
    tabStyle: _tabStyle,
    title: EditTitle.of(on: _titleOn, lines: _titleLines),
    watermark: _watermark,
    fadeIn: _fadeIn,
    fadeOut: _fadeOut,
    extra: _extra,
  );

  /// Whether the edit is anything but the defaults: the whole video with
  /// its own sound as it is (and a take's tab, the capture's name and the
  /// watermark over it, fading in and out over 3 s), and a take's song
  /// lined up as it played while recording ([_logged]).
  bool get _edited => _comparable(_current) != _comparable(_defaults);

  /// The defaults ([_edited]).
  PageEdit get _defaults {
    final whole = PageEdit(start: Duration.zero, end: _duration);
    return withLoggedSong(whole, _logged, duration: _duration) ?? whole;
  }

  /// [edit] as it's compared with the defaults: without the keys a newer
  /// app wrote, and, for a song lined up by itself, its track keys left
  /// out but for how far it's been moved (they follow from the log).
  PageEdit _comparable(PageEdit edit) {
    edit = edit.copyWith(extra: const {});
    final logged = _logged;
    if (logged == null ||
        edit.songMode != SongMode.auto ||
        edit.trackId != logged.page) {
      return edit;
    }
    return edit.copyWith(
      trackStart: Duration.zero,
      trackEnd: null,
      offset: logged.shiftOf(edit),
    );
  }

  /// The edit the preview plays and Download renders: as kept
  /// ([_pageEdit]), or, kept as none, the defaults, a take's song lined
  /// up by itself among them.
  PageEdit? get _planEdit => _pageEdit ?? (_hasSong ? _current : null);

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
    EditedPlayback.planOf(
      _planEdit,
      songLength: _trackLength,
      duration: _duration,
      takeLog: _takeLog,
      frame: _frame,
    ),
    song: _trackPlayer,
  );

  /// The video's frame as it shows, in pixels (null: not known yet): the
  /// tab's bands are drawn for it.
  Size? get _frame => _video == null ? null : frameOf(_video!);

  /// The layers the preview draws over the video, as Download's plan has
  /// them (for this user: the watermark as [_unlocked] says): worked out
  /// again only when what they're made of changes. While the title is
  /// being edited, it shows throughout, as it ends up, rather than as its
  /// cards fade in and out.
  List<PlanLayer> _previewLayers(AppLocalizations l10n) {
    final editing = _titleBeingEdited;
    final frame = _frame;
    final of = (
      _start,
      _end,
      _tab,
      _tabStyle,
      frame,
      _duration,
      _titleOn,
      _titleLines?.join('\n'),
      _captureTitle.join('\n'),
      _watermark,
      _unlocked,
      editing,
    );
    if (of != _layersOf) {
      _layersOf = of;
      final planned = RenderPlan.of(
        _planEdit,
        duration: _duration,
        takeLog: _takeLog,
        title: _captureTitle,
        watermark: watermarkText,
        premium: _unlocked,
        preview: true,
        frame: frame,
      ).layers;
      final title = editing
          ? planned.where((l) => l.id == 'title').firstOrNull
          : null;
      _layers = [
        for (final layer in planned)
          if (title == null || layer.id != 'title') layer,
        // Its cards as one, the whole kept part through, unfaded.
        if (title != null)
          PlanLayer(
            id: title.id,
            look: title.look,
            anchor: title.anchor,
            heightU: title.heightU,
            marginU: title.marginU,
          ),
      ];
      _measured.keepOnly(_layers.map((l) => l.look));
    }
    return _layers;
  }

  /// The Tab chip: the take's tab drawn over it, or not.
  void _setTab(bool on) {
    if (on == _tab) return;
    setState(() => _tab = on);
    _changed();
  }

  /// Whether the take's tab can be drawn over it, so styled.
  bool get _tabStyleOffered => _take && tabOffered(_takeLog);

  /// Opens the tab's style in place of the chips (on a phone: on a wide
  /// screen, it's under them always), the Download settings shown.
  void _editTabStyle() {
    _showSettings(_tabStyleAt);
    if (_wide) return;
    setState(() {
      _editingTabStyle = true;
      _editingTitle = false;
      _editingFades = false;
    });
  }

  /// The sizes the Size slider offers over the video's frame: from the
  /// smallest it can be read at ([TabLayout.minSizeOf]) to the largest
  /// any of the take's bands still grows at ([tabSizeMost]); worked out
  /// again only when the frame changes.
  (double, double) _tabSizes() {
    final frame = _frame;
    final known = _tabSizesOf;
    if (known != null && known.$1 == frame) return (known.$2, known.$3);
    final least = TabLayout.minSizeOf(frame);
    final most = tabSizeMost(_takeLog?.tab?.lines ?? const [], frame);
    _tabSizesOf = (frame, least, most);
    return (least, most);
  }

  (Size?, double, double)? _tabSizesOf;

  /// The tab's style changed to [style]: the preview draws it at once
  /// (nothing is sought again), the tab on, as typing a title turns it on.
  void _setTabStyle(EditTabStyle style) {
    if (style == _tabStyle && _tab) return;
    setState(() {
      _tabStyle = style;
      _tab = true;
    });
    _changed();
  }

  /// **Done**: the tab's style closes.
  void _tabStyleDone() => setState(() => _editingTabStyle = false);

  /// The title's fields show its text as it is now (setState's).
  void _fillTitle() {
    final lines = _titleLines ?? _captureTitle;
    _title1.text = lines.firstOrNull ?? '';
    _title2.text = lines.length > 1 ? lines[1] : '';
  }

  /// The Title chip: the title on or off (its text kept). With no text to
  /// show, it opens its fields instead.
  void _setTitle(bool on) {
    if (on && _titleText.isEmpty) {
      _editTitle();
      return;
    }
    if (on == _titleOn) return;
    setState(() => _titleOn = on);
    _changed();
  }

  /// Opens the title's fields: in place of the chips on a phone; on a
  /// wide screen, they're beside them already, the first one focused. The
  /// Download settings show, where they were hidden.
  void _editTitle() {
    _showSettings(_titleAt);
    setState(() {
      _editingTitle = !_wide;
      _editingFades = false;
      _editingTabStyle = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocus.requestFocus();
    });
  }

  /// The title's text typed: it's the title's from now on (and on), the
  /// preview showing it at once, kept a moment later; the song isn't
  /// sought again (nothing it plays by changed).
  void _typed(String _) {
    setState(() {
      _titleLines = [_title1.text, _title2.text];
      _titleOn = true;
    });
    _changed();
  }

  /// **Use the capture's name**: the text typed goes, the title is the
  /// capture's name (and follows it), on.
  void _titleFromCapture() {
    setState(() {
      _titleLines = null;
      _titleOn = true;
      _fillTitle();
    });
    _changed();
  }

  /// **No title**: off, its text kept; the fields close.
  void _noTitle() {
    setState(() {
      _titleOn = false;
      _editingTitle = false;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    _changed();
  }

  /// **Done**: the fields close.
  void _titleDone() {
    setState(() => _editingTitle = false);
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// The Fades chip: off, both fades are none (kept, to put back); on,
  /// they're as they were before (3 s each, if they never were).
  void _setFades(bool on) {
    final fading = _fadeIn > Duration.zero || _fadeOut > Duration.zero;
    if (on == fading) return;
    setState(() {
      if (on) {
        final (fadeIn, fadeOut) =
            _fadesBack ?? (PageEdit.defaultFade, PageEdit.defaultFade);
        _fadeIn = fadeIn;
        _fadeOut = fadeOut;
      } else {
        _fadesBack = (_fadeIn, _fadeOut);
        _fadeIn = Duration.zero;
        _fadeOut = Duration.zero;
      }
    });
    _changed();
  }

  /// Opens the fades' sliders: in place of the chips on a phone (a wide
  /// screen has them beside the chips already).
  void _editFades() {
    if (_wide) return;
    setState(() {
      _editingFades = true;
      _editingTitle = false;
      _editingTabStyle = false;
    });
  }

  /// A fade's slider moved: the fade in ([end] false) or out, to [seconds]
  /// (to the tenth of a second); the preview plays it at once, nothing
  /// sought again.
  void _setFade(double seconds, {required bool end}) {
    final fade = Duration(milliseconds: (seconds * 10).round() * 100);
    if (fade == (end ? _fadeOut : _fadeIn)) return;
    setState(() {
      if (end) {
        _fadeOut = fade;
      } else {
        _fadeIn = fade;
      }
    });
    _changed();
  }

  /// **No fades**: both none; the sliders stay open.
  void _noFades() => _setFades(false);

  /// **Done**: the fades' sliders close.
  void _fadesDone() => setState(() => _editingFades = false);

  /// The Watermark chip: for a user with Premium, it on or off; for
  /// anyone else, it stays on and the Premium card says how to remove it.
  void _setWatermark(bool on) {
    if (!_unlocked) {
      unawaited(_premiumSheet());
      return;
    }
    if (on == _watermark) return;
    setState(() => _watermark = on);
    _changed();
  }

  /// TabCam Premium's card, in a sheet: Premium removes the watermark.
  Future<void> _premiumSheet() async {
    final ocr = widget.ocr;
    if (ocr == null) return;
    final l10n = context.l10n;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          key: const Key('video-edit-premium'),
          padding: const EdgeInsets.all(16),
          child: PremiumCard(
            ocr: ocr,
            email: ocr.auth.user?.email,
            lead: l10n.videoEditWatermarkLocked,
            onClose: () => Navigator.pop(context),
          ),
        ),
      ),
    );
  }

  /// Whether the editor is wide: the Download settings beside the viewer.
  /// So is a short landscape room (a phone on its side), where there's no
  /// room for them under the viewer. Measured on the editor's own room
  /// ([_box]: narrower than the screen with the dictionary's or the
  /// metronome's sidebar beside it), else the screen.
  bool get _wide {
    final size = _box ?? MediaQuery.sizeOf(context);
    return size.width >= _wideFrom ||
        (size.width >= _wideShortFrom && size.height < _shortBelow);
  }

  static const _wideFrom = 840.0;
  static const _wideShortFrom = 560.0;
  static const _shortBelow = 480.0;

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

  /// The Take lane's start grip, dragged by [delta]: near one of the
  /// song's marks, it's on it ([_snapped]).
  void _trimStartBy(Duration delta) {
    final at = _dragStart = (_dragStart ?? _start) + delta;
    _keepPart(
      _clamp(_snapped(at), Duration.zero, _end - PageEdit.minLength),
      _end,
      endMoved: false,
      exact: false,
    );
  }

  /// The Take lane's end grip, dragged by [delta], as the start's.
  void _trimEndBy(Duration delta) {
    final at = _dragEnd = (_dragEnd ?? _end) + delta;
    _keepPart(
      _start,
      _clamp(_snapped(at), _start + PageEdit.minLength, _duration),
      endMoved: true,
      exact: false,
    );
  }

  /// The kept part's start moved [by] (a press of its ‹ or ›), within the
  /// video and no nearer its end than the shortest part kept; the
  /// preview, while paused, shows the frame it cuts at.
  void _stepStart(Duration by) => _keepPart(
    _clamp(_start + by, Duration.zero, _end - PageEdit.minLength),
    _end,
    endMoved: false,
  );

  /// The kept part's end moved [by], as the start's.
  void _stepEnd(Duration by) => _keepPart(
    _start,
    _clamp(_end + by, _start + PageEdit.minLength, _duration),
    endMoved: true,
  );

  /// Where a lined-up song starts and stops in the video, clip by clip
  /// ([LoggedSong.marksIn]): drawn on the ruler and the Take lane, and
  /// where a grip dragged near snaps to; none without one.
  List<Duration> get _songMarks {
    final logged = _logged;
    if (logged == null || !_lined || _duration <= Duration.zero) {
      return const [];
    }
    return logged.marksIn(_current, _duration, songLength: _trackLength);
  }

  /// How near one of the song's marks a grip dragged snaps to it: a
  /// hundredth of the video in view (a few points of the lane, whatever
  /// the [_zoom]), and no less than a twentieth of a second at the whole
  /// video, a millisecond zoomed in all the way.
  Duration get _snapWithin => Duration(
    milliseconds: max(
      max(1, 50 ~/ _zoom),
      _duration.inMilliseconds ~/ (100 * _zoom),
    ),
  );

  /// How far the timeline is zoomed in: 1, the whole video in the lanes'
  /// width; 2, half of it, and so on ([zooms]), scrolled sideways.
  double _zoom = 1;

  /// The lanes' sound, drawn over their bars once read ([Waveform.read]):
  /// the video's own, and the song's (with its page ID); none where it
  /// can't be read.
  Waveform? _takeWave;
  Waveform? _songWave;
  String? _songWaveId;

  /// Reads the video's own sound for the Take lane's waveform.
  Future<void> _readTakeWave(XFile file, Duration length) async {
    final wave = await Waveform.read(file, length);
    if (mounted && wave != null) setState(() => _takeWave = wave);
  }

  /// Reads song [id]'s sound for the Song lane's waveform, unless it's
  /// read already.
  Future<void> _readSongWave(String id, XFile file, Duration length) async {
    if (_songWaveId == id && _songWave != null) return;
    _songWaveId = id;
    _songWave = null;
    final wave = await Waveform.read(file, length);
    if (mounted && wave != null && _songWaveId == id && _trackId == id) {
      setState(() => _songWave = wave);
    }
  }

  /// Where the song's sound is along the video, for its waveform: each of
  /// its clips lined up by itself, else its one placed part.
  List<WaveSpan> get _songSpans {
    if (_linedClips case final clips?) {
      return [for (final c in clips) (at: c.at, end: c.end, from: c.from)];
    }
    final at = _start + _offset;
    return [(at: at, end: at + (_trackEnd - _trackStart), from: _trackStart)];
  }

  /// [wave] over a lane's bar ([key]'s), where [spans] put it.
  Widget _waveOver(String key, Waveform? wave, List<WaveSpan> spans) =>
      wave == null
      ? const SizedBox.shrink()
      : Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              key: Key(key),
              painter: WavePainter(
                wave: wave,
                length: _duration,
                spans: spans,
                start: _start,
                end: _end,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        );

  /// The timeline's zooms ([_zoom]).
  static const zooms = [1.0, 2.0, 4.0, 8.0, 16.0, 32.0];

  /// The zoomed timeline's sideways scroll.
  final _timelineScroll = ScrollController();

  /// Zooms the timeline one step in ([by] 1) or out (−1), keeping the
  /// playhead where it is on screen (in view: zoomed, it's put in it).
  void _zoomBy(int by) {
    final i = zooms.indexOf(_zoom);
    final next = zooms[(i + by).clamp(0, zooms.length - 1)];
    if (next == _zoom) return;
    _setZoom(next);
  }

  /// The timeline at [zoom], the playhead kept where it was on screen.
  void _setZoom(double zoom) {
    zoom = zoom.clamp(zooms.first, zooms.last);
    final c = _timelineScroll;
    final length = _duration.inMilliseconds;
    final head = length <= 0 ? 0.0 : _at.inMilliseconds / length;
    double? keep;
    if (c.hasClients) {
      final view = c.position.viewportDimension;
      final onScreen = (head * view * _zoom - c.offset).clamp(0.0, view);
      keep = head * view * zoom - onScreen;
    }
    setState(() => _zoom = zoom);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!c.hasClients || keep == null) return;
      c.jumpTo(keep.clamp(0.0, c.position.maxScrollExtent));
    });
  }

  /// While it plays zoomed in, the timeline scrolls to keep the playhead
  /// in view ([fraction] of the video), a quarter in from the left.
  void _keepHeadInView(double fraction) {
    final c = _timelineScroll;
    if (_zoom <= 1 || !c.hasClients || !(_video?.value.isPlaying ?? false)) {
      return;
    }
    final view = c.position.viewportDimension;
    final x = fraction * view * _zoom;
    if (x >= c.offset && x <= c.offset + view - 8) return;
    c.jumpTo((x - view / 4).clamp(0.0, c.position.maxScrollExtent));
  }

  /// [at], or the song's mark it's near ([_snapWithin]): the nearest.
  Duration _snapped(Duration at) {
    Duration? best;
    for (final mark in _songMarks) {
      final off = (mark - at).abs();
      if (off <= _snapWithin && (best == null || off < (best - at).abs())) {
        best = mark;
      }
    }
    return best ?? at;
  }

  /// Keeps the take from where its song starts to where it stops (its
  /// first clip's start to its last's end, within the video): cut to the
  /// song, to the millisecond.
  void _cutToSong() {
    final marks = _songMarks;
    if (marks.length < 2) return;
    _trim(marks.first, marks.last);
  }

  /// Whether the kept part is the song's already ([_cutToSong]).
  bool get _cutIsSong {
    final marks = _songMarks;
    return marks.length < 2 || (_start == marks.first && _end == marks.last);
  }

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
  /// last. Playing, it plays on from there; paused, it stays paused
  /// ([EditedPlayback.seek]). The playhead and the time are there at
  /// once ([_headAt]). Nowhere in a video whose length isn't known.
  void _seek(Duration at, {bool exact = true}) {
    final playback = _playback;
    if (playback == null || _duration <= Duration.zero) return;
    at = _clamp(at, Duration.zero, _duration);
    _headAt.value = at;
    if (exact) {
      _seekWait?.cancel();
      _seekWait = null;
      _seekNext = null;
      _seekNow(playback, at);
      return;
    }
    if (_seekWait != null) {
      _seekNext = at;
      return;
    }
    _seekNow(playback, at);
    _seekWait = Timer(_seekEvery, () {
      _seekWait = null;
      final next = _seekNext;
      _seekNext = null;
      if (next != null && mounted) _seek(next, exact: false);
    });
  }

  /// Asks [playback] to go to [at] now. Once it got there, the playhead
  /// and the time follow the player again (unless asked elsewhere since).
  void _seekNow(EditedPlayback playback, Duration at) {
    unawaited(
      playback.seek(at).whenComplete(() {
        if (mounted && _headAt.value == at) _headAt.value = null;
      }),
    );
  }

  /// A Take grip let go: the preview, while paused, goes exactly to the
  /// end it moved.
  void _trimmed({required bool end}) {
    _dragStart = _dragEnd = null;
    final video = _video;
    if (video != null && !video.value.isPlaying) {
      _seek(end ? _end : _start);
    }
  }

  static Duration _clamp(Duration d, Duration low, Duration high) =>
      d < low ? low : (d > high ? high : d);

  /// Keeps from, or until, where the preview is: where it's going, or
  /// where its player is (asked of it: a paused one isn't polled).
  Future<void> _trimHere({required bool end}) async {
    final at = _headAt.value ?? await _video?.position ?? Duration.zero;
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
                _take ? l10n.videoEditPickSong : l10n.videoEditPickTrack,
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
  /// places it, or, picked, placed by hand at the timeline's end (its
  /// end where the kept part ends; one as long or longer, from the kept
  /// part's start, so none of its start is cut), at the lane's level,
  /// heard.
  Future<void> _loadTrack(
    String id,
    XFile file,
    String name, {
    PageEdit? from,
  }) async {
    await _playback?.set(
      EditedPlayback.planOf(_planEdit, duration: _duration, takeLog: _takeLog),
    );
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
      _alignSaid = null;
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
      _offset = from?.offset ?? _atEnd(length);
      if (from == null) {
        _song = SongMode.manual;
        _songLevel.muted = false;
      }
    });
    _changed();
    unawaited(_readSongWave(id, file, length));
  }

  /// Where a song [length] long, just picked, starts after the kept
  /// part's start: at the timeline's end, its end where the kept part
  /// ends; one as long as the kept part or longer (or whose length can't
  /// be told), with the kept part.
  Duration _atEnd(Duration length) {
    final room = _end - _start - length;
    return length <= Duration.zero || room <= Duration.zero
        ? Duration.zero
        : room;
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
    _alignSaid = null;
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
    if (_song == null || _song == SongMode.auto) _song = SongMode.manual;
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
      // Lined up by itself, it all moves, and stays lined up.
      if (!_lined) _placedByHand();
    });
    _changed();
  }

  /// How far the song is from where it was put, in the delay control
  /// ([_delayControl]): for a song lined up by itself, how far it's been
  /// moved from that line-up; else where it starts against the kept part
  /// ([_offset]). Later is positive.
  Duration get _delay => _lined ? _logged!.shiftOf(_current) : _offset;

  /// The furthest the delay control's typed value goes either way.
  static const maxDelay = Duration(seconds: 10);

  /// The delay control's steps: a millisecond (about the smallest
  /// difference heard between two sounds) and ten.
  static const delaySteps = [1, 10];

  /// Asks for the song's delay in milliseconds ([_delay]) and moves it
  /// there, as ‹ and › do.
  Future<void> _typeDelay() async {
    final typed = await showDialog<int>(
      context: context,
      builder: (_) => _DelayDialog(ms: _delay.inMilliseconds),
    );
    if (typed == null || !mounted) return;
    final to = Duration(
      milliseconds: typed.clamp(
        -maxDelay.inMilliseconds,
        maxDelay.inMilliseconds,
      ),
    );
    _moveTrack(to - _delay);
  }

  /// Keeps [ms] as the song's delay for the output [key] on this device
  /// ([OutDelays]; 0: forgets it): takes through it whose song wasn't
  /// found in their sound open with it.
  Future<void> _keepDelay(String key, int ms) async {
    final delays = {..._outDelays}..remove(key);
    if (ms != 0) delays[key] = ms;
    setState(() => _outDelays = Map.unmodifiable(delays));
    await OutDelays.write(_library, delays);
  }

  /// Where the Song lane has the song now, clip by clip, in the video's
  /// file (a song lined up by itself, each of its clips as the edit
  /// moved them; else its one placed part), cut to the file.
  List<LaneClip> get _laneClips {
    final clips = _lined
        ? [
            for (final c in _logged!.clipsIn(_current, _trackLength))
              SongClip(at: c.at + _start, from: c.from, to: c.to),
          ]
        : [SongClip(at: _start + _offset, from: _trackStart, to: _trackEnd)];
    return [
      for (final c in clampClips(clips, _duration))
        (
          fileMs: c.at.inMilliseconds,
          songMs: c.from.inMilliseconds,
          lengthMs: (c.to - c.from).inMilliseconds,
        ),
    ];
  }

  /// Auto-align, the magic button: lines the song up with the take by
  /// their sounds, around where the Song lane has it now, or, where the
  /// song isn't in the take's sound (headphones), by the rhythm
  /// ([SongSync.align]); a take not measured yet is measured first, as
  /// it is when the editor opens it ([_measureSong]). What's found moves
  /// the song as the delay control does ([_moveTrack]: a song lined up by
  /// itself stays lined up, and the move is kept with the edit); the
  /// take's log ([TakeLog.sync]) is never written. What happened is said
  /// under it ([_alignSaid]).
  Future<void> _align() async {
    final song = _track;
    if (song == null || _aligning || !_listens) return;
    final l10n = context.l10n;
    setState(() {
      _aligning = true;
      _alignSaid = null;
    });
    try {
      // Not measured yet: the standard measure first; found, the Song
      // lane is where it was found.
      if (_lined && _takeLog?.sync == null) {
        await _measureSong();
        if (!mounted || _track != song) return;
        if (_lined && _logged!.measured) {
          final moved = _logged!.shiftOf(_current);
          if (moved != Duration.zero) _moveTrack(-moved);
          setState(() => _alignSaid = l10n.videoEditAlignedSync);
          return;
        }
      }
      final event = _library.byId(widget.eventId);
      final reader = SoundReader.open();
      if (event == null || reader == null) {
        setState(() => _alignSaid = l10n.videoEditAlignUnread);
        return;
      }
      // Moved from where it was as the listening began (the song may be
      // nudged meanwhile).
      final from = _offset;
      final SongAlign? found;
      try {
        found = await SongSync.align(
          take: await _fileOf(event, widget.page),
          song: song,
          reader: reader,
          clips: _laneClips,
          progress: (done, of) {
            if (mounted) {
              setState(
                () => _alignSaid = l10n.videoEditAlignListening(done, of),
              );
            }
          },
        );
      } finally {
        reader.close();
      }
      debugPrint('TabCam: video edit: Auto-align: $found');
      if (!mounted || _track != song) return;
      final String said;
      if (found == null) {
        said = l10n.videoEditAlignUnread;
      } else if (!found.found) {
        said = _take
            ? l10n.videoEditAlignNotFound
            : l10n.videoEditAlignNotFoundTrack;
      } else {
        final ms = found.ms;
        _moveTrack(from + Duration(milliseconds: ms) - _offset);
        final by = ms.abs();
        final later = ms > 0;
        said = switch (found) {
          SongAlign(from: AlignFrom.rhythm) when ms == 0 =>
            l10n.videoEditAlignedRhythmSame,
          SongAlign(from: AlignFrom.rhythm) =>
            later
                ? l10n.videoEditAlignedRhythmLater(by)
                : l10n.videoEditAlignedRhythmEarlier(by),
          _ when ms == 0 => l10n.videoEditAlignedSame,
          SongAlign(rough: true, :final spreadMs) =>
            later
                ? l10n.videoEditAlignedRoughLater(by, spreadMs)
                : l10n.videoEditAlignedRoughEarlier(by, spreadMs),
          _ =>
            later
                ? l10n.videoEditAlignedLater(by)
                : l10n.videoEditAlignedEarlier(by),
        };
      }
      setState(() => _alignSaid = said);
    } on Object catch (e) {
      debugPrint('TabCam: video edit: Auto-align failed: $e');
      if (mounted) setState(() => _alignSaid = l10n.videoEditAlignUnread);
    } finally {
      if (mounted) setState(() => _aligning = false);
    }
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

  /// [level]'s channels and balance changed to [stereo].
  void _setStereo(_Level level, LaneStereo stereo) {
    if (stereo == level.stereo) return;
    setState(() => level.stereo = stereo);
    _changed();
  }

  /// [level] muted, or heard again as loud as it was.
  void _mute(_Level level) {
    setState(level.toggleMute);
    _changed();
  }

  /// Back to the defaults: the whole video, with its own sound as it is
  /// (the master at 100%), no song (a take's lined up as it played while
  /// recording), and the tab, the capture's name and the watermark over
  /// it, fading in and out over 3 s (the edit is none).
  Future<void> _reset() async {
    final player = _trackPlayer;
    setState(() {
      _start = Duration.zero;
      _end = _duration;
      _own = _Level();
      _master = _Level.master();
      _song = null;
      _tab = true;
      _tabStyle = EditTabStyle.standard;
      _editingTabStyle = false;
      _titleOn = true;
      _titleLines = null;
      _editingTitle = false;
      _watermark = true;
      _fadeIn = PageEdit.defaultFade;
      _fadeOut = PageEdit.defaultFade;
      _fadesBack = null;
      _editingFades = false;
      _fillTitle();
      _clearSong();
    });
    _changed();
    await _played();
    await player?.dispose();
    await _lineUpSong();
  }

  /// Puts the take's song in the Song lane, lined up by itself as it
  /// played while recording ([_logged]), when it has one.
  Future<void> _lineUpSong() async {
    final logged = _logged;
    final event = _library.byId(widget.eventId);
    final page = event?.pages.where((p) => p.id == logged?.page).firstOrNull;
    if (logged == null || event == null || page == null) return;
    final file = await _fileOf(event, page);
    if (!mounted) return;
    await _loadTrack(
      page.id,
      file,
      fileLabel(context.l10n, event, page),
      from: logged.placed(_current.copyWith(song: null, trackId: null)),
    );
  }

  /// The plan of the edit as it is now, for [kind]: of [input], the
  /// video's file, for Download (the preview's has no files). Whether the
  /// watermark is left out is this user's Premium as it is now, as they
  /// download ([_unlocked]).
  RenderPlan _plan(RenderKind kind, {XFile? input}) => RenderPlan.of(
    _planEdit,
    input: input,
    duration: _duration,
    inputExtension: input == null ? null : Media.of(input)?.extension,
    songFile: _track,
    songLength: _trackLength,
    kind: kind,
    formats: _formats,
    takeLog: _takeLog,
    title: _captureTitle,
    watermark: watermarkText,
    premium: _unlocked,
    frame: _frame,
  );

  /// Whether the song lane can be rendered: it isn't heard (a muted song
  /// is left out of the download), or its song can be fitted (one of
  /// unknown length can't).
  bool get _trackReady =>
      !_hasSong ||
      _songLevel.silent ||
      (_track != null && _trackLength > Duration.zero);

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
      // Each download is named for when it's made, so renders don't clash.
      final label = timestamped(fileLabel(l10n, event, page));
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

  /// A cut's or the song's time, which moves by [step]: as [time] on a
  /// tenth of a second, else to the hundredth (m:ss.hh), so every step
  /// shows.
  static String fine(Duration d) {
    final hundredths = d.inMilliseconds ~/ 10;
    if (hundredths % 10 == 0) return time(d);
    final s = (hundredths ~/ 100) % 60;
    return '${hundredths ~/ 6000}:${s.toString().padLeft(2, '0')}'
        '.${(hundredths % 100).toString().padLeft(2, '0')}';
  }

  /// How far a press of ‹ or › moves a cut's end, or the song: a
  /// twentieth of a second.
  static const step = Duration(milliseconds: 50);

  /// m:ss, for the ruler.
  static String _rulerTime(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// How wide a lane's name is in its header: room for "Take" or a short
  /// name on a phone (two lines at most), more beside a wide screen's.
  double get _nameWidth => _wide ? 120 : 56;

  /// The lanes' headers at the left (the name, then the volume): the ruler
  /// and the bars line up after them, as wide as the rest.
  double get _lead => _nameWidth + _LaneVolume.width + 4;

  /// The gap between the two lanes.
  static const _laneGap = 2.0;

  /// The lanes' panel: the ruler and the two lanes, and its padding; the
  /// cut's steps under them where there's room ([_cutStepsHeight]).
  static const _dockPad = EdgeInsets.fromLTRB(8, 0, 8, 6);
  static const _cutStepsHeight = 40.0;
  static const _dockHeight =
      _Ruler.height + _SongBar.height + _laneGap + _SongBar.height + 6;

  /// The transport's row, over the lanes.
  static const _transportHeight = 48.0;

  /// The least the viewer keeps before the lanes, then the transport, give
  /// way (a tiny window), and the least the Download settings keep under
  /// the viewer on a phone, their title included (a tall video takes the
  /// rest).
  static const _viewerLeast = 96.0;
  static const _inspectorLeast = 160.0;

  /// To the start / To the end: this close to the kept part's end counts
  /// as there (the next press goes on to the video's end).
  static const _near = Duration(milliseconds: 50);

  /// The keys that move the preview ([_key]).
  static final _moveKeys = {
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };

  /// A key pressed in the editor: the space bar plays or pauses the
  /// preview, as Play / Pause does; Home and End are To the start and To
  /// the end; ← and → step a tenth of a second (with Shift, a second).
  /// Not while a field is typed in (the title's), nor with Ctrl, Alt or ⌘
  /// held; Home, End and the arrows only while nothing in the editor has
  /// the keyboard (a slider's arrows are its own).
  KeyEventResult _key(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;
    final space = key == LogicalKeyboardKey.space;
    if (!space && !_moveKeys.contains(key) ||
        _video == null ||
        _error != null ||
        _busy) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isAltPressed || keys.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>() !=
        null) {
      return KeyEventResult.ignored;
    }
    if (space) {
      if (event is KeyDownEvent) unawaited(_playback?.playPause());
      return KeyEventResult.handled;
    }
    if (!_keys.hasPrimaryFocus || _duration <= Duration.zero) {
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) return KeyEventResult.handled;
    if (key == LogicalKeyboardKey.home) {
      if (event is KeyDownEvent) _toStart();
    } else if (key == LogicalKeyboardKey.end) {
      if (event is KeyDownEvent) unawaited(_toEnd());
    } else {
      final by = keys.isShiftPressed
          ? const Duration(seconds: 1)
          : const Duration(milliseconds: 100);
      _step(
        key == LogicalKeyboardKey.arrowLeft ? -by : by,
        exact: event is KeyDownEvent,
      );
    }
    return KeyEventResult.handled;
  }

  /// To the start: the kept part's start, or, there already, the video's.
  /// Playing, it plays on from there.
  void _toStart() => _seek(_at > _start + _near ? _start : Duration.zero);

  /// To the end: paused, at the kept part's end, or, there already, the
  /// video's.
  Future<void> _toEnd() async {
    final at = _at;
    if (_video?.value.isPlaying ?? false) await _playback?.playPause();
    if (!mounted) return;
    _seek(at < _end - _near ? _end : _duration);
  }

  /// The preview moved [by] (← and →): at once, or, a key held down, at
  /// most every [_seekEvery].
  void _step(Duration by, {required bool exact}) =>
      _seek(_clamp(_at + by, Duration.zero, _duration), exact: exact);

  @override
  Widget build(BuildContext context) {
    // A click anywhere gives the editor the keyboard back (a field's tap
    // outside lets it go), unless something in it already has it.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerUp: (_) {
        if (!_keys.hasFocus) _keys.requestFocus();
      },
      child: Focus(
        focusNode: _keys,
        autofocus: true,
        onKeyEvent: _key,
        child: _scaffold(context),
      ),
    );
  }

  Widget _scaffold(BuildContext context) {
    final l10n = context.l10n;
    final event = _library.byId(widget.eventId);
    final video = _video;
    final ready = video != null && _error == null;
    // On a phone, Dictionary, Metronome, Share and About go in a menu, so
    // the file's name keeps some room.
    final menu = MediaQuery.sizeOf(context).width < _menuBelow;
    // Share: the link to this file's edit view.
    final share = event == null || _busy
        ? null
        : () => shareCapture(
            context,
            event,
            sync: widget.sync,
            file: widget.page,
            edit: true,
          );
    void about() => Messenger.maybeOf(context)?.show(l10n.videoEditKept);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          event == null ? '' : fileLabel(l10n, event, widget.page),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (ready) ...[
            _appBarActions(l10n),
            DownloadSettingsButton(onClosed: _keys.requestFocus),
          ],
          if (!menu) ...[
            DictionaryButton(onClosed: _keys.requestFocus),
            MetronomeButton(onClosed: _keys.requestFocus),
            IconButton(
              key: const Key('video-edit-share'),
              tooltip: l10n.eventShare,
              icon: const Icon(Icons.link),
              onPressed: share,
            ),
          ],
          const KeysHelpButton(screen: KeysScreen.videoEdit),
          if (menu)
            _moreMenu(l10n, share: share, about: about)
          else
            IconButton(
              key: const Key('video-edit-about'),
              tooltip: l10n.videoEditAbout,
              icon: const Icon(Icons.info_outline),
              onPressed: about,
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
      // The dictionary and the metronome at the right, usable during a
      // download too.
      body: MetronomeBeside(
        onClosed: _keys.requestFocus,
        child: DictionaryBeside(
          title: event?.title,
          onClosed: _keys.requestFocus,
          child: _error != null
              ? _cantPlay(l10n)
              : video == null
              ? const Center(child: CircularProgressIndicator())
              : AbsorbPointer(absorbing: _busy, child: _body(video, l10n)),
        ),
      ),
    );
  }

  /// How wide the screen is before Dictionary, Metronome, Share and
  /// About leave the app bar's menu ([_moreMenu]) for buttons of their
  /// own.
  static const _menuBelow = 600.0;

  /// On a phone, at the app bar's end (⋮): Dictionary and Metronome
  /// (their sidebars shown or hidden), Share ([share]; off without the
  /// capture, or during a download) and About the edit ([about]).
  Widget _moreMenu(
    AppLocalizations l10n, {
    required VoidCallback? share,
    required VoidCallback about,
  }) {
    final dictionary = DictionaryState.instance;
    final metronome = MetronomeState.instance;
    PopupMenuItem<VoidCallback> item(
      String key,
      IconData icon,
      String label,
      VoidCallback? action,
    ) => PopupMenuItem(
      key: Key(key),
      value: action,
      enabled: action != null,
      child: ListTile(leading: Icon(icon), title: Text(label)),
    );
    return PopupMenuButton<VoidCallback>(
      key: const Key('video-edit-more'),
      tooltip: l10n.videoEditMore,
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        item(
          'dictionary',
          Icons.menu_book_outlined,
          dictionary.open ? l10n.dictionaryHide : l10n.dictionary,
          () {
            dictionary.toggle();
            if (!dictionary.open) _keys.requestFocus();
          },
        ),
        item(
          'metronome',
          Icons.av_timer,
          metronome.open ? l10n.metronomeHide : l10n.metronome,
          () {
            metronome.toggle();
            if (!metronome.open) _keys.requestFocus();
          },
        ),
        item('video-edit-share', Icons.link, l10n.eventShare, share),
        item(
          'video-edit-about',
          Icons.info_outline,
          l10n.videoEditAbout,
          about,
        ),
      ],
    );
  }

  /// Reset and Download, in the app bar: named from [_labelsFrom] wide,
  /// icons with their names as tooltips under it; at the largest text
  /// sizes, both shrink to fit rather than crowd out the name.
  Widget _appBarActions(AppLocalizations l10n) {
    final width = MediaQuery.sizeOf(context).width;
    final labels = width >= _labelsFrom;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width * 0.55),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              key: const Key('video-edit-reset'),
              onPressed: _edited && !_busy ? _reset : null,
              child: labels
                  ? Text(l10n.videoEditReset)
                  : Tooltip(
                      message: l10n.videoEditReset,
                      child: const Icon(Icons.restart_alt),
                    ),
            ),
            const SizedBox(width: 4),
            _downloadButton(l10n, labels: labels),
          ],
        ),
      ),
    );
  }

  /// How wide the screen is before Reset and Download are named in the
  /// app bar.
  static const _labelsFrom = 840.0;

  /// In the body's place where the video couldn't be opened, or its
  /// player failed: it says so, with Try again ([_retry]).
  Widget _cantPlay(AppLocalizations l10n) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.textViewCantPlay, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('video-edit-retry'),
            onPressed: _retry,
            child: Text(l10n.homeLibraryTryAgain),
          ),
        ],
      ),
    ),
  );

  /// The screen's body, a frame that doesn't scroll: the viewer on top,
  /// with the Download settings ([DownloadSettingsBeside]) beside it where
  /// the editor's room is [_wide], else under it (the master, **On the
  /// video** or the fields one of its chips opened, the song's details),
  /// scrolling; and at the bottom edge the transport and the lanes.
  /// Hidden, the settings leave the viewer all the room. While the
  /// on-screen keyboard is open (the title typed in), the transport and
  /// the lanes give their room to the viewer and the field; in a tiny
  /// window the lanes go first, then the transport.
  Widget _body(VideoPlayerController video, AppLocalizations l10n) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return LayoutBuilder(
      builder: (context, box) {
        _box = box.biggest;
        final wide = _wide;
        final height = box.maxHeight;
        final width = box.maxWidth;
        final inset = MediaQuery.paddingOf(context).bottom;
        bool fits(double dock) =>
            height >= dock + inset + _transportHeight + 1 + _viewerLeast;
        final showTransport =
            !keyboard && height >= _transportHeight + _viewerLeast;
        final showDock = showTransport && fits(_dockHeight);
        final showSteps = showDock && fits(_dockHeight + _cutStepsHeight);
        final dockHeight =
            (showDock ? _dockHeight + inset : 0) +
            (showSteps ? _cutStepsHeight : 0);
        final panel = showTransport
            ? _panel(video, l10n, dock: showDock, steps: showSteps)
            : null;
        // Under the viewer, it's as high as the picture needs, leaving the
        // settings their least (a tall video takes the rest).
        final free =
            height - (showTransport ? _transportHeight + 1 : 0) - dockHeight;
        final aspect = video.value.aspectRatio > 0
            ? video.value.aspectRatio
            : 16 / 9;
        final viewer = max(
          0.0,
          min(width / aspect, free - min(_inspectorLeast, free * 0.45)),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: DownloadSettingsBeside(
                beside: wide,
                viewerHeight: viewer,
                viewer: _preview(video, l10n),
                onClosed: _keys.requestFocus,
                panel: (context) => wide
                    ? ListView(
                        key: const Key('video-edit-side'),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        children: [
                          _onTheVideo(l10n, wide: true),
                          if (_hasSong) ...[
                            const SizedBox(height: 16),
                            _songDetails(l10n),
                          ],
                        ],
                      )
                    : ListView(
                        key: const Key('video-edit-inspector'),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        children: [
                          _masterFields(l10n),
                          const SizedBox(height: 8),
                          _editingTitle
                              ? KeyedSubtree(
                                  key: _titleAt,
                                  child: _titleFields(l10n),
                                )
                              : _editingFades
                              ? KeyedSubtree(
                                  key: _fadesAt,
                                  child: _fadeFields(l10n),
                                )
                              : _editingTabStyle && _tabStyleOffered
                              ? KeyedSubtree(
                                  key: _tabStyleAt,
                                  child: _tabStyleFields(l10n),
                                )
                              : _onTheVideo(l10n),
                          if (_hasSong) ...[
                            const SizedBox(height: 8),
                            _songDetails(l10n),
                          ],
                        ],
                      ),
              ),
            ),
            ?panel,
          ],
        );
      },
    );
  }

  /// The bottom panel, the whole width: the transport, and under it, when
  /// [dock], the lanes, flush with the bottom edge (over the safe area),
  /// with the cut's steps under them when [steps].
  Widget _panel(
    VideoPlayerController video,
    AppLocalizations l10n, {
    required bool dock,
    required bool steps,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(height: 1),
            SizedBox(
              height: _transportHeight,
              child: _busy
                  ? Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          l10n.videoEditDownloading,
                          key: const Key('video-edit-downloading'),
                          maxLines: 1,
                        ),
                      ),
                    )
                  : _transport(video, l10n),
            ),
            if (dock)
              Padding(
                padding: _dockPad,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _timeline(video, l10n),
                    if (steps)
                      SizedBox(
                        height: _cutStepsHeight,
                        child: Padding(
                          padding: EdgeInsets.only(left: _lead),
                          child: _cutSteps(l10n),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Download, split: the button downloads the video as edited; its menu
  /// also has it without sound, and its sound alone, each saying its
  /// format. Without [labels], the button is its icon, named by its
  /// tooltip.
  Widget _downloadButton(AppLocalizations l10n, {bool labels = true}) {
    const radius = Radius.circular(20);
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.horizontal(left: radius),
    );
    final onPressed = _canDownload(RenderKind.video)
        ? () => _download(RenderKind.video)
        : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (labels)
          FilledButton.icon(
            key: const Key('video-edit-download'),
            style: FilledButton.styleFrom(shape: shape),
            icon: const Icon(Icons.download_outlined),
            label: Text(l10n.videoEditDownload),
            onPressed: onPressed,
          )
        else
          FilledButton(
            key: const Key('video-edit-download'),
            style: FilledButton.styleFrom(
              shape: shape,
              minimumSize: const Size(48, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: onPressed,
            child: Tooltip(
              message: l10n.videoEditDownload,
              child: const Icon(Icons.download_outlined),
            ),
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

  /// The viewer: the video as large as its box allows, on black, with
  /// what Download draws over it, and, while the kept part plays, the
  /// fades' black ([EditLayers]); paused, its on-picture controls over
  /// that ([OnPicture]). A tap picks what's drawn there or plays or pauses
  /// it ([_tapPreview]), and on the black around it plays or pauses; on a
  /// phone, a long press on the tab's band opens its style.
  Widget _preview(VideoPlayerController video, AppLocalizations l10n) {
    final layers = _previewLayers(l10n);
    final fades = _fades;
    return ColoredBox(
      color: Colors.black,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _playback?.playPause,
        child: Center(
          child: AspectRatio(
            aspectRatio: video.value.aspectRatio,
            child: LayoutBuilder(
              builder: (context, box) => GestureDetector(
                key: const Key('video-edit-preview'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (tap) =>
                    _tapPreview(tap.localPosition, box.biggest, layers),
                onLongPressStart: _wide
                    ? null
                    : (press) => _pressPreview(
                        press.localPosition,
                        box.biggest,
                        layers,
                      ),
                child: layers.isEmpty && !fades.any
                    ? VideoPlayer(video)
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoPlayer(video),
                          EditLayers(
                            video: video,
                            layers: layers,
                            start: _start,
                            fades: fades,
                            kept: _end - _start,
                          ),
                          OnPicture(
                            video: video,
                            layers: layers,
                            start: _start,
                            size: box.biggest,
                            sizeOf: (look) => _measured.of(look).size,
                            selected: _picked,
                            toolbar: (kind) => _pictureToolbar(l10n, kind),
                            resizeLabel: l10n.videoEditPictureResize,
                            onResizeStart: _resizeStart,
                            onResize: _resizeTab,
                            onResizeEnd: () {},
                            fadeBadge: (at) => _fadeBadge(l10n, at),
                            onFades: _editFadesHere,
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

  /// Whether [layer], at [at] on the preview, [size] big, is under it.
  bool _hit(PlanLayer layer, Offset at, Size size) =>
      layer.rectIn(size, _measured.of(layer.look).size).contains(at);

  /// A tap at [at] on the preview, [size] big, showing [layers]: on the
  /// title (a corner of it), it's picked and edited, playing or not.
  /// Paused, a tap on another layer drawn at that frame (the tab's band
  /// showing, the watermark) picks it ([OnPicture]: its outline in the
  /// primary colour, its toolbar beside it); on the one picked, it plays,
  /// still picked; anywhere else, it plays and nothing is picked. Playing,
  /// a tap anywhere else pauses it.
  void _tapPreview(Offset at, Size size, List<PlanLayer> layers) {
    final title = layers.where((l) => l.id == 'title').firstOrNull;
    if (title != null && _hit(title, at, size)) {
      setState(() => _picked = PictureLayer.title);
      _editTitle();
      return;
    }
    final video = _video;
    if (video != null && !video.value.isPlaying) {
      final now = video.value.position - _start;
      final hit = OnPicture.shown(
        layers,
        now,
        size,
        (look) => _measured.of(look).size,
      ).where((d) => d.$2.contains(at)).map((d) => d.$1).lastOrNull;
      if (hit != null && hit != _picked) {
        setState(() => _picked = hit);
        // On a wide screen the band's style is in the Download settings,
        // always: they show.
        if (hit == PictureLayer.tab && _wide) _showSettings(_tabStyleAt);
        return;
      }
      if (hit == null && _picked != null) setState(() => _picked = null);
    }
    unawaited(_playback?.playPause());
  }

  /// A long press at [at] on the preview, [size] big, showing [layers]
  /// (on a phone): on the tab's band showing, its style opens in place of
  /// the chips, as its chip's palette button opens it.
  void _pressPreview(Offset at, Size size, List<PlanLayer> layers) {
    final now = (_video?.value.position ?? Duration.zero) - _start;
    final band = layers
        .where((l) => l.id == 'tab' && l.alphaAt(now) > 0)
        .firstOrNull;
    if (band != null && _hit(band, at, size)) {
      unawaited(Feedback.forLongPress(context));
      setState(() => _picked = PictureLayer.tab);
      _editTabStyle();
    }
  }

  /// The toolbar beside [kind] picked on the preview ([OnPicture]): for
  /// the tab's band, **smaller** and **larger** (a step of the Size
  /// slider), its four colours, on a phone its whole style, and **hide**
  /// (the Tab chip off); for the title, **edit** and **hide**; for the
  /// watermark, **hide** with Premium, or Premium's card without.
  Widget _pictureToolbar(AppLocalizations l10n, PictureLayer kind) {
    Widget button(
      String key,
      IconData icon,
      String tooltip,
      VoidCallback? onPressed,
    ) => IconButton(
      key: Key('video-edit-picture-$key'),
      tooltip: tooltip,
      color: Colors.white,
      disabledColor: Colors.white38,
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon),
      onPressed: onPressed,
    );
    final children = switch (kind) {
      PictureLayer.tab => () {
        final style = _tabStyle;
        final (least, most) = _tabSizes();
        final size = style.size.clamp(least, most);
        return [
          button(
            'tab-smaller',
            Icons.text_decrease,
            l10n.videoEditPictureSmaller,
            size > least + 0.001 ? () => _stepTabSize(-1) : null,
          ),
          button(
            'tab-larger',
            Icons.text_increase,
            l10n.videoEditPictureLarger,
            size < most - 0.001 ? () => _stepTabSize(1) : null,
          ),
          for (final colors in TabColors.values)
            _PictureSwatch(
              colors: colors,
              selected: style.colors == colors,
              label: _colorsName(l10n, colors),
              onTap: () => _setTabStyle(style.copyWith(colors: colors)),
            ),
          if (!_wide)
            button(
              'tab-style',
              Icons.palette_outlined,
              l10n.videoEditTabStyleEdit,
              _editTabStyle,
            ),
          button(
            'tab-hide',
            Icons.visibility_off_outlined,
            l10n.videoEditPictureHideTab,
            () {
              setState(() => _picked = null);
              _setTab(false);
            },
          ),
        ];
      }(),
      PictureLayer.title => [
        button('title-edit', Icons.edit, l10n.videoEditTitleEdit, _editTitle),
        button(
          'title-hide',
          Icons.visibility_off_outlined,
          l10n.videoEditPictureHideTitle,
          () {
            setState(() => _picked = null);
            _setTitle(false);
          },
        ),
      ],
      PictureLayer.watermark => [
        if (_unlocked)
          button(
            'watermark-hide',
            Icons.visibility_off_outlined,
            l10n.videoEditPictureHideWatermark,
            () {
              setState(() => _picked = null);
              _setWatermark(false);
            },
          )
        else
          button(
            'watermark-premium',
            Icons.workspace_premium_outlined,
            l10n.videoEditWatermarkLocked,
            widget.ocr == null ? null : () => _setWatermark(false),
          ),
      ],
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  /// The tab's size on the Size slider's steps (by 5% from the smallest
  /// it offers), within what it offers ([_tabSizes]).
  double _onSizeStep(double size) {
    final (least, most) = _tabSizes();
    final steps = ((most - least) * 20).round();
    if (steps <= 0) return least;
    final k = ((size - least) * 20).round().clamp(0, steps);
    return least + k / 20;
  }

  /// **Smaller** or **larger** on the tab's toolbar: a step of the Size
  /// slider, [by] steps.
  void _stepTabSize(int by) {
    final (least, most) = _tabSizes();
    final now = _tabStyle.size.clamp(least, most);
    _setTabStyle(_tabStyle.copyWith(size: _onSizeStep(now + by / 20)));
  }

  /// The tab's handle grabbed: its size now, to scale from.
  void _resizeStart() {
    final (least, most) = _tabSizes();
    _resizeFrom = _tabStyle.size.clamp(least, most);
  }

  /// The tab's handle dragged: the band [ratio] times as high as when it
  /// was grabbed, on the Size slider's steps; drawn at once, kept a moment
  /// later, as the slider's.
  void _resizeTab(double ratio) {
    final size = _onSizeStep(_resizeFrom * ratio);
    if (size == _tabStyle.size) return;
    _setTabStyle(_tabStyle.copyWith(size: size));
  }

  /// The badge on the picture at [at] in the output, while a fade covers
  /// it: "Fade in · 3.0 s", "Fade out · 3.0 s"; else none.
  String? _fadeBadge(AppLocalizations l10n, Duration at) {
    final fades = _fades;
    String seconds(Duration d) =>
        l10n.videoEditFadeSeconds((d.inMilliseconds / 1000).toStringAsFixed(1));
    if (fades.fadeIn > Duration.zero &&
        at >= Duration.zero &&
        at < fades.fadeIn) {
      return '${l10n.videoEditFadeIn} · ${seconds(fades.fadeIn)}';
    }
    if (fades.fadeOut > Duration.zero &&
        at > fades.length - fades.fadeOut &&
        at <= fades.length) {
      return '${l10n.videoEditFadeOut} · ${seconds(fades.fadeOut)}';
    }
    return null;
  }

  /// The fade badge tapped: the fades' sliders (in place of the chips on
  /// a phone; beside them, always, on a wide screen), the Download
  /// settings shown.
  void _editFadesHere() {
    _showSettings(_fadesAt);
    _editFades();
  }

  /// **On the video**: what's drawn over it, as chips (and, on a [wide]
  /// screen, the title's fields under them). A take's **Tab** ([_tabChip]).
  /// **Title** ✎: on by default, with the capture's name (none when it's
  /// the name the app gave it: the chip then adds one); tapped, it's on
  /// or off, its text kept; ✎ (or a tap on the title in the preview)
  /// edits its text. **Watermark**: for a user with Premium, on or off;
  /// for anyone else, locked on, and a tap shows the Premium card.
  /// **Fades** (on by default): tapped, on or off; its button opens their
  /// sliders on a phone (on a wide screen, they're under the title's
  /// fields).
  Widget _onTheVideo(AppLocalizations l10n, {bool wide = false}) {
    final theme = Theme.of(context);
    final text = _titleText;
    final locked = !_unlocked;
    final fading = _fadeIn > Duration.zero || _fadeOut > Duration.zero;
    return Column(
      key: const Key('video-edit-on-video'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.videoEditOnTheVideo, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ?_tabChip(l10n, wide: wide),
            InputChip(
              key: const Key('video-edit-title'),
              avatar: text.isEmpty ? const Icon(Icons.add, size: 18) : null,
              label: Text(l10n.videoEditLayerTitle),
              selected: _titleOn && text.isNotEmpty,
              onSelected: _setTitle,
              deleteIcon: const Icon(
                Icons.edit_outlined,
                key: Key('video-edit-title-edit'),
                size: 18,
              ),
              onDeleted: _editTitle,
              deleteButtonTooltipMessage: l10n.videoEditTitleEdit,
            ),
            FilterChip(
              key: const Key('video-edit-watermark'),
              avatar: locked ? const Icon(Icons.lock_outline, size: 18) : null,
              showCheckmark: !locked,
              label: Text(l10n.videoEditLayerWatermark),
              tooltip: locked
                  ? l10n.videoEditWatermarkLocked
                  : l10n.videoEditWatermarkAbout(watermarkText),
              selected: locked || _watermark,
              onSelected: _setWatermark,
            ),
            InputChip(
              key: const Key('video-edit-fades'),
              label: Text(l10n.videoEditFades),
              tooltip: l10n.videoEditFadesAbout,
              selected: fading,
              onSelected: _setFades,
              deleteIcon: wide
                  ? null
                  : const Icon(
                      Icons.tune,
                      key: Key('video-edit-fades-edit'),
                      size: 18,
                    ),
              onDeleted: wide ? null : _editFades,
              deleteButtonTooltipMessage: l10n.videoEditFadesEdit,
            ),
          ],
        ),
        if (wide) ...[
          const SizedBox(height: 12),
          KeyedSubtree(key: _titleAt, child: _titleFields(l10n)),
          const SizedBox(height: 16),
          _masterFields(l10n),
          const SizedBox(height: 8),
          KeyedSubtree(key: _fadesAt, child: _fadeFields(l10n)),
          if (_tabStyleOffered) ...[
            const SizedBox(height: 16),
            KeyedSubtree(key: _tabStyleAt, child: _tabStyleFields(l10n)),
          ],
        ],
      ],
    );
  }

  /// **Master**: where both lanes go, after their own levels: Mute (the
  /// level kept; Unmute puts it back, or, after a slide down to 0%, the
  /// level before it) and its volume, 0% to 200% in steps of 5% (sliding
  /// unmutes it), its level beside it, in the primary colour when it's
  /// not 100%, or muted. Right above the fades' sliders (on a phone, above
  /// **On the video**, where the Fades chip opens them). The preview plays
  /// nothing louder than the lanes are; Download's file is.
  Widget _masterFields(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final master = _master;
    final name = l10n.videoEditMaster;
    final percent = (master.volume * 100).round();
    final level = l10n.videoEditTrackVolumeLevel(percent);
    final silent = master.silent;
    final changed = master.volume != 1 || master.muted;
    final color = changed ? theme.colorScheme.primary : null;
    const most = PageEdit.maxMaster * 100;
    return Column(
      key: const Key('video-edit-master'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            text: name,
            style: theme.textTheme.titleSmall,
            children: [
              TextSpan(
                text: ' · ${l10n.videoEditMasterAbout}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Row(
          children: [
            IconButton(
              key: const Key('video-edit-master-mute'),
              tooltip: silent
                  ? l10n.videoEditLaneUnmute(name)
                  : l10n.videoEditLaneMute(name),
              color: color,
              icon: Icon(
                silent
                    ? Icons.volume_off_outlined
                    : master.volume < 0.5
                    ? Icons.volume_down_outlined
                    : Icons.volume_up_outlined,
              ),
              onPressed: () => _mute(master),
            ),
            Expanded(
              child: Slider(
                key: const Key('video-edit-master-slider'),
                max: most,
                divisions: most ~/ 5,
                value: percent.clamp(0, most).toDouble(),
                label: level,
                semanticFormatterCallback: (v) =>
                    '$name ${l10n.videoEditTrackVolumeLevel(v.round())}',
                onChangeStart: (_) => master.keep(),
                onChanged: (v) => _slide(master, v / 100),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48),
              child: Text(
                level,
                key: const Key('video-edit-master-level'),
                textAlign: TextAlign.end,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  decoration: master.muted ? TextDecoration.lineThrough : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The fades' sliders: how long the start fades in from black and the
  /// end out to black (both sounds with it), 0 to 10 s by tenths of a
  /// second, never more than half the kept part (a longer one kept plays
  /// that long, and is back when the kept part is long enough again); **No
  /// fades**; on a phone, in place of the chips, with **Done** to close
  /// them.
  Widget _fadeFields(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final inline = _wide;
    final most = _fadeMost;
    final tenths = most.inMilliseconds ~/ 100;
    final fades = _fades;
    Widget slider(String name, Duration fade, {required bool end}) {
      final shown = fade > most ? most : fade;
      return _sliderRow(
        name: name,
        key: 'video-edit-fade-${end ? 'out' : 'in'}',
        value: shown.inMilliseconds / 1000,
        min: 0,
        max: max(0.1, most.inMilliseconds / 1000),
        divisions: max(1, tenths),
        shown: l10n.videoEditFadeSeconds(
          (shown.inMilliseconds / 1000).toStringAsFixed(1),
        ),
        onChanged: tenths <= 0 ? null : (v) => _setFade(v, end: end),
      );
    }

    return Column(
      key: const Key('video-edit-fade-fields'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          inline
              ? l10n.videoEditFadesAbout
              : '${l10n.videoEditFades} · ${l10n.videoEditFadesAbout}',
          style: inline
              ? theme.textTheme.bodySmall
              : theme.textTheme.titleSmall,
        ),
        slider(l10n.videoEditFadeIn, _fadeIn, end: false),
        slider(l10n.videoEditFadeOut, _fadeOut, end: true),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              key: const Key('video-edit-fades-off'),
              onPressed: fades.any ? _noFades : null,
              child: Text(l10n.videoEditFadesOff),
            ),
            if (!inline)
              FilledButton.tonal(
                key: const Key('video-edit-fades-done'),
                onPressed: _fadesDone,
                child: Text(l10n.videoEditTitleDone),
              ),
          ],
        ),
      ],
    );
  }

  /// One of the panels' sliders: its [name], the slider ([key], at
  /// [value] from [min] to [max] in [divisions] steps) and its value as
  /// [shown] (`[key]-value`), which a screen reader also says. On one
  /// row (the name in two lines at most, the value shrinking to fit), or,
  /// [stacked], the name and the value over a slider as wide as the panel
  /// (so neither is ever cut, at any text size).
  Widget _sliderRow({
    required String name,
    required String key,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String shown,
    required ValueChanged<double>? onChanged,
    bool stacked = false,
  }) {
    final slider = Slider(
      key: Key(key),
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      label: shown,
      semanticFormatterCallback: (_) => '$name $shown',
      onChanged: onChanged,
    );
    final said = Text(
      shown,
      key: Key('$key-value'),
      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(name)),
              const SizedBox(width: 8),
              said,
            ],
          ),
          slider,
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        Expanded(flex: 5, child: slider),
        SizedBox(
          width: 48,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: said,
          ),
        ),
      ],
    );
  }

  /// The tab's style: **Size** (by 5%, of its default: from 50%, or
  /// what can still be read on a portrait frame, to 200%, or as far as
  /// the take's bands still grow over this frame, [_tabSizes]), **Background**
  /// (its opacity, 0% to 100% by 5%: the text stays opaque, outlined as
  /// the background fades out), each its name and value over its slider,
  /// **Colours** (two swatches, each a bit of band in its colours) and
  /// **Alignment** (the text to the left, the default, centre or right);
  /// **Default style**; on a phone, in place of the chips, with **Done**
  /// to close it. The preview draws each change at once.
  Widget _tabStyleFields(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final inline = _wide;
    final style = _tabStyle;
    String percent(double v) => l10n.videoEditTabPercent((v * 100).round());
    // Only the sizes that change the band over this video: shown as drawn
    // (a size kept past either end is drawn at that end).
    final (least, most) = _tabSizes();
    final sizes = ((most - least) * 20).round();
    final size = style.size.clamp(least, most);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          inline
              ? l10n.videoEditTabStyleAbout
              : '${l10n.videoEditTabStyle} · ${l10n.videoEditTabStyleAbout}',
          key: const Key('video-edit-tab-style'),
          style: inline
              ? theme.textTheme.bodySmall
              : theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        _sliderRow(
          name: l10n.videoEditTabSize,
          key: 'video-edit-tab-size',
          value: size,
          min: least,
          max: sizes > 0 ? most : least + 0.05,
          divisions: max(1, sizes),
          shown: percent(size),
          onChanged: sizes > 0
              ? (v) => _setTabStyle(style.copyWith(size: v))
              : null,
          stacked: true,
        ),
        _sliderRow(
          name: l10n.videoEditTabBackground,
          key: 'video-edit-tab-opacity',
          value: style.opacity,
          min: 0,
          max: 1,
          divisions: 20,
          shown: percent(style.opacity),
          onChanged: (v) => _setTabStyle(style.copyWith(opacity: v)),
          stacked: true,
        ),
        Text(l10n.videoEditTabColors),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final colors in TabColors.values)
              _TabSwatch(
                colors: colors,
                selected: style.colors == colors,
                label: _colorsName(l10n, colors),
                onTap: () => _setTabStyle(style.copyWith(colors: colors)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(l10n.videoEditTabAlign),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SegmentedButton<TabAlign>(
            key: const Key('video-edit-tab-align'),
            showSelectedIcon: false,
            segments: [
              for (final (align, icon, name) in [
                (
                  TabAlign.left,
                  Icons.format_align_left,
                  l10n.videoEditTabAlignLeft,
                ),
                (
                  TabAlign.center,
                  Icons.format_align_center,
                  l10n.videoEditTabAlignCenter,
                ),
                (
                  TabAlign.right,
                  Icons.format_align_right,
                  l10n.videoEditTabAlignRight,
                ),
              ])
                ButtonSegment(
                  value: align,
                  icon: Icon(
                    icon,
                    key: Key('video-edit-tab-align-${align.name}'),
                  ),
                  tooltip: name,
                ),
            ],
            selected: {style.align},
            onSelectionChanged: (picked) =>
                _setTabStyle(style.copyWith(align: picked.single)),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              key: const Key('video-edit-tab-style-reset'),
              onPressed: style.isStandard
                  ? null
                  : () => _setTabStyle(EditTabStyle.standard),
              child: Text(l10n.videoEditTabStyleReset),
            ),
            if (!inline)
              FilledButton.tonal(
                key: const Key('video-edit-tab-style-done'),
                onPressed: _tabStyleDone,
                child: Text(l10n.videoEditTitleDone),
              ),
          ],
        ),
      ],
    );
  }

  /// [colors]' name, as its swatch says it.
  static String _colorsName(AppLocalizations l10n, TabColors colors) =>
      switch (colors) {
        TabColors.dark => l10n.videoEditTabColorsDark,
        TabColors.gold => l10n.videoEditTabColorsGold,
        TabColors.primary => l10n.videoEditTabColorsPrimary,
        TabColors.secondary => l10n.videoEditTabColorsSecondary,
      };

  /// The title's text: two fields (typing shows it in the preview at
  /// once), **Use the capture's name** and **No title**; on a phone, in
  /// place of the chips, with **Done** to close them.
  Widget _titleFields(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final inline = _wide;
    InputDecoration field(String label) =>
        InputDecoration(labelText: label, isDense: true, counterText: '');
    return Column(
      key: const Key('video-edit-title-fields'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          inline
              ? l10n.videoEditTitleAbout
              : '${l10n.videoEditLayerTitle} · ${l10n.videoEditTitleAbout}',
          style: inline
              ? theme.textTheme.bodySmall
              : theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('video-edit-title-1'),
          controller: _title1,
          focusNode: _titleFocus,
          maxLength: EditTitle.maxChars,
          decoration: field(l10n.videoEditTitleLine1),
          textInputAction: TextInputAction.next,
          onChanged: _typed,
          onSubmitted: (_) => _title2Focus.requestFocus(),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('video-edit-title-2'),
          controller: _title2,
          focusNode: _title2Focus,
          maxLength: EditTitle.maxChars,
          decoration: field(l10n.videoEditTitleLine2),
          textInputAction: TextInputAction.done,
          onChanged: _typed,
          onSubmitted: (_) => _titleDone(),
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              key: const Key('video-edit-title-capture'),
              onPressed: _titleLines != null || !_titleOn
                  ? _titleFromCapture
                  : null,
              child: Text(l10n.videoEditTitleCapture),
            ),
            TextButton(
              key: const Key('video-edit-title-off'),
              onPressed: _titleOn ? _noTitle : null,
              child: Text(l10n.videoEditTitleOff),
            ),
            if (!inline)
              FilledButton.tonal(
                key: const Key('video-edit-title-done'),
                onPressed: _titleDone,
                child: Text(l10n.videoEditTitleDone),
              ),
          ],
        ),
      ],
    );
  }

  /// The **Tab** chip (on by default): where the take's log has its tab,
  /// not in its picture already, with its style's button (on a phone; on
  /// a wide screen the style is under the chips already); off and
  /// disabled, its tooltip saying why, on a take whose tab is burned in
  /// as it was saved, or one saved before takes kept their tab apart. (A
  /// disabled chip shows no tooltip of its own, so it's in one.) None on
  /// a video that isn't a take, nor on a take without a tab: its log has
  /// none, or, with no log, its capture has none to show.
  Widget? _tabChip(AppLocalizations l10n, {bool wide = false}) {
    if (!_take) return null;
    final log = _takeLog;
    final offered = tabOffered(log);
    // A take that kept its log, with no tab to draw.
    if (log != null && log.tab == null) return null;
    // One from before the log, in a capture with no tab: it never had one.
    if (log == null &&
        necklines(_library.byId(widget.eventId)?.tabText ?? '').isEmpty) {
      return null;
    }
    final styled = offered && !wide;
    final chip = InputChip(
      key: const Key('video-edit-tab'),
      label: Text(l10n.videoEditLayerTab),
      tooltip: offered ? l10n.videoEditLayerTabAbout : null,
      selected: offered && _tab,
      onSelected: offered ? _setTab : null,
      deleteIcon: styled
          ? const Icon(
              Icons.palette_outlined,
              key: Key('video-edit-tab-style-edit'),
              size: 18,
            )
          : null,
      onDeleted: styled ? _editTabStyle : null,
      deleteButtonTooltipMessage: l10n.videoEditTabStyleEdit,
    );
    if (offered) return chip;
    return Tooltip(
      key: const Key('video-edit-tab-why'),
      // No log: from before takes kept one, with or without a tab.
      message: log == null
          ? l10n.videoEditTabNotKept
          : l10n.videoEditTabInPicture,
      triggerMode: TooltipTriggerMode.tap,
      child: chip,
    );
  }

  /// Over the lanes, on one row: at the left where the preview is (to the
  /// tenth of a second: the trims are set by it) over the part kept; in
  /// the middle To the start, Play / Pause and To the end; at the right
  /// Start here and End here, which trim to where it is (named on a wide
  /// row).
  Widget _transport(VideoPlayerController video, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final trimmed = _start > Duration.zero || _end < _duration;
    final known = _duration > Duration.zero;
    const tabular = [FontFeature.tabularFigures()];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: LayoutBuilder(
        builder: (context, box) {
          final named = box.maxWidth >= 720;
          Widget trim(String key, String label, IconData icon, bool end) {
            void onPressed() => _trimHere(end: end);
            return named
                ? TextButton.icon(
                    key: Key(key),
                    onPressed: onPressed,
                    icon: Icon(icon),
                    label: Text(label),
                  )
                : IconButton(
                    key: Key(key),
                    tooltip: label,
                    icon: Icon(icon),
                    onPressed: onPressed,
                  );
          }

          return Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: ListenableBuilder(
                          listenable: Listenable.merge([video, _headAt]),
                          builder: (context, _) => Text(
                            time(_at),
                            key: const Key('video-edit-time'),
                            maxLines: 1,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontFeatures: tabular,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l10n.videoEditKeep(fine(_start), fine(_end)),
                          key: const Key('video-edit-times'),
                          maxLines: 1,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: trimmed ? theme.colorScheme.primary : null,
                            fontFeatures: tabular,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('video-edit-to-start'),
                tooltip: l10n.videoEditToStart,
                icon: const Icon(Icons.skip_previous),
                onPressed: known ? _toStart : null,
              ),
              // Its own button: it plays as edited, from where the preview
              // is.
              ValueListenableBuilder(
                valueListenable: video,
                builder: (context, value, _) => IconButton.filled(
                  key: const Key('video-edit-play'),
                  tooltip:
                      '${value.isPlaying ? l10n.textViewPause : l10n.textViewPlay}'
                      ' (${l10n.videoEditSpaceKey})',
                  iconSize: 28,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(56, 40),
                    padding: EdgeInsets.zero,
                  ),
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: _playback?.playPause,
                ),
              ),
              IconButton(
                key: const Key('video-edit-to-end'),
                tooltip: l10n.videoEditToEnd,
                icon: const Icon(Icons.skip_next),
                onPressed: known ? () => unawaited(_toEnd()) : null,
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        trim(
                          'video-edit-start-here',
                          l10n.videoEditTrimStart,
                          Icons.first_page,
                          false,
                        ),
                        trim(
                          'video-edit-end-here',
                          l10n.videoEditTrimEnd,
                          Icons.last_page,
                          true,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Under the lanes, the cut's two ends, each with where it is (to the
  /// hundredth of a second when it isn't on a tenth) between ‹ and ›,
  /// which move it a [step] earlier or later: the start at the left, the
  /// end at the right, under the Take lane's grips.
  Widget _cutSteps(AppLocalizations l10n) {
    final most = _end - PageEdit.minLength;
    final least = _start + PageEdit.minLength;
    Widget end(
      String name,
      String at,
      String earlier,
      String later,
      VoidCallback? onEarlier,
      VoidCallback? onLater,
    ) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: Key('video-edit-$name-earlier'),
          tooltip: earlier,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left),
          onPressed: onEarlier,
        ),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              at,
              key: Key('video-edit-$name-at'),
              maxLines: 1,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        IconButton(
          key: Key('video-edit-$name-later'),
          tooltip: later,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right),
          onPressed: onLater,
        ),
      ],
    );
    return Row(
      key: const Key('video-edit-cut-steps'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: end(
            'start',
            l10n.videoEditCutStartAt(fine(_start)),
            l10n.videoEditStartEarlier,
            l10n.videoEditStartLater,
            _start > Duration.zero ? () => _stepStart(-step) : null,
            _start < most ? () => _stepStart(step) : null,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: end(
            'end',
            l10n.videoEditCutEndAt(fine(_end)),
            l10n.videoEditEndEarlier,
            l10n.videoEditEndLater,
            _end > least ? () => _stepEnd(-step) : null,
            _end < _duration ? () => _stepEnd(step) : null,
          ),
        ),
      ],
    );
  }

  /// The time axis: the ruler right over the Take lane and the Song
  /// lane, each lane's header at its left (its name, then its volume; the
  /// Song lane's name opens its menu), and where the preview is drawn
  /// across them, with a handle on the ruler.
  Widget _timeline(VideoPlayerController video, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final ownName = _take ? l10n.videoEditLaneTake : l10n.videoEditLaneVideo;
    final songName = _take ? l10n.videoEditLaneSong : l10n.videoEditLaneTrack;
    final length = _duration;
    final hasSong = _hasSong;
    final marks = _songMarks;
    final Widget songBar;
    if (!hasSong) {
      songBar = _AddSong(
        label: _take ? l10n.videoEditAddSong : l10n.videoEditAddTrack,
        onTap: _pickTrack,
      );
    } else if (_trackLength <= Duration.zero || length <= Duration.zero) {
      // Its length unknown: it can't be placed.
      songBar = _SongBar.unplaced(name: _trackName ?? songName);
    } else if (_linedClips case final clips?) {
      // Lined up in several clips: moved as one, silent between them; not
      // trimmed (one clip can't say it).
      songBar = _SongBar(
        length: length,
        start: _start,
        end: _end,
        at: clips.first.at,
        used: clips.last.end - clips.first.at,
        gaps: [
          for (final (i, c) in clips.indexed.skip(1)) (clips[i - 1].end, c.at),
        ],
        name: _trackName ?? songName,
        label: l10n.videoEditTrackBar,
        onMove: _moveTrack,
      );
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
    final lead = _lead;
    final takeHeader = _LaneHeader(
      width: _nameWidth,
      wide: _wide,
      name: ownName,
      volume: _LaneVolume(
        lane: 'take',
        name: ownName,
        volume: _own.volume,
        muted: _own.muted,
        stereo: _own.stereo,
        onStereo: (v) => _setStereo(_own, v),
        onChanged: (v) => _slide(_own, v),
        onChangeStart: _own.keep,
        onMute: () => _mute(_own),
      ),
    );
    final songHeader = _LaneHeader(
      width: _nameWidth,
      wide: _wide,
      name: hasSong ? null : songName,
      menu: hasSong ? _songMenu(l10n, songName) : null,
      volume: hasSong
          ? _LaneVolume(
              lane: 'song',
              name: songName,
              volume: _songLevel.volume,
              muted: _songLevel.muted,
              stereo: _songLevel.stereo,
              onStereo: (v) => _setStereo(_songLevel, v),
              onChanged: (v) => _slide(_songLevel, v),
              onChangeStart: _songLevel.keep,
              onMute: () => _mute(_songLevel),
            )
          : null,
    );
    // The ruler, the lanes' bars and the playhead, on one time axis, as
    // wide as the zoom makes them; the headers stay put at their left.
    Widget bars(double width) => SizedBox(
      width: width,
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Ruler(
                length: length,
                marks: marks,
                label: l10n.videoEditRuler,
                timeOf: _rulerTime,
                onSeek: (at, {required exact}) => _seek(at, exact: exact),
              ),
              SizedBox(
                width: width,
                height: _SongBar.height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _SeekOnTap(
                        length: length,
                        onSeek: _seek,
                        child: _TakeBar(
                          length: length,
                          start: _start,
                          end: _end,
                          marks: marks,
                          fades: _fades,
                          label: l10n.videoEditTakeBar,
                          startLabel: l10n.videoEditKeptStart,
                          endLabel: l10n.videoEditKeptEnd,
                          onTrimStart: _trimStartBy,
                          onTrimEnd: _trimEndBy,
                          onTrimmed: _trimmed,
                        ),
                      ),
                    ),
                    _waveOver('video-edit-take-wave', _takeWave, [
                      (at: Duration.zero, end: length, from: Duration.zero),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: _laneGap),
              // Empty, it's Add a song; a song's, a tap places the
              // preview as the Take lane's does.
              SizedBox(
                width: width,
                height: _SongBar.height,
                // Empty and zoomed in, its Add a song stays in view, over
                // the scrolled lanes (below).
                child: hasSong
                    ? Stack(
                        children: [
                          Positioned.fill(
                            child: _SeekOnTap(
                              length: length,
                              onSeek: _seek,
                              child: songBar,
                            ),
                          ),
                          if (_trackLength > Duration.zero &&
                              _songWaveId == _trackId)
                            _waveOver(
                              'video-edit-song-wave',
                              _songWave,
                              _songSpans,
                            ),
                        ],
                      )
                    : _zoom > 1
                    ? const SizedBox.shrink()
                    : songBar,
              ),
            ],
          ),
          // Where the preview is, across the ruler and the lanes.
          Positioned.fill(
            child: IgnorePointer(
              child: ListenableBuilder(
                listenable: Listenable.merge([video, _headAt]),
                builder: (context, _) {
                  final at = length <= Duration.zero
                      ? 0.0
                      : _at.inMilliseconds / length.inMilliseconds;
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _keepHeadInView(at),
                  );
                  return CustomPaint(
                    key: const Key('video-edit-playhead'),
                    painter: _Playhead(
                      at: at,
                      lead: 0,
                      color: theme.colorScheme.primary,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: lead,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: _Ruler.height, child: _zoomControls(l10n)),
              SizedBox(height: _SongBar.height, child: takeHeader),
              const SizedBox(height: _laneGap),
              SizedBox(height: _SongBar.height, child: songHeader),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final view = box.maxWidth;
              if (_zoom <= 1) return bars(view);
              // Ctrl / ⌘ + the wheel, or a trackpad's pinch, zoom it too.
              return Listener(
                onPointerSignal: (event) {
                  final keyboard = HardwareKeyboard.instance;
                  if (event is PointerScrollEvent &&
                      (keyboard.isControlPressed || keyboard.isMetaPressed)) {
                    _zoomBy(event.scrollDelta.dy < 0 ? 1 : -1);
                  } else if (event is PointerScaleEvent) {
                    _setZoom(_zoom * event.scale);
                  }
                },
                child: Stack(
                  children: [
                    Scrollbar(
                      controller: _timelineScroll,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        key: const Key('video-edit-timeline-scroll'),
                        controller: _timelineScroll,
                        scrollDirection: Axis.horizontal,
                        child: bars(view * _zoom),
                      ),
                    ),
                    // No song: Add a song as wide as the view, not the
                    // zoomed lane (its middle would be off screen).
                    if (!hasSong)
                      Positioned(
                        left: 0,
                        width: view,
                        top: _Ruler.height + _SongBar.height + _laneGap,
                        height: _SongBar.height,
                        child: songBar,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Zoom out and Zoom in, in the corner left of the ruler, with the zoom
  /// between them once it isn't the whole video ("4×").
  Widget _zoomControls(AppLocalizations l10n) {
    final theme = Theme.of(context);
    Widget button(String key, String tip, IconData icon, VoidCallback? on) =>
        IconButton(
          key: Key(key),
          tooltip: tip,
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          onPressed: on,
          icon: Icon(icon),
        );
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            'video-edit-zoom-out',
            l10n.pdfZoomOut,
            Icons.zoom_out,
            _zoom > zooms.first ? () => _zoomBy(-1) : null,
          ),
          if (_zoom > 1)
            Text(
              '${_zoom.round()}×',
              key: const Key('video-edit-zoom'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          button(
            'video-edit-zoom-in',
            l10n.pdfZoomIn,
            Icons.zoom_in,
            _zoom < zooms.last ? () => _zoomBy(1) : null,
          ),
        ],
      ),
    );
  }

  /// The Song lane's name, in its header, with a ⋮: it opens Change… and
  /// Remove.
  Widget _songMenu(AppLocalizations l10n, String name) => MenuAnchor(
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
    builder: (context, menu, _) => Tooltip(
      message: MaterialLocalizations.of(context).showMenuTooltip,
      child: InkWell(
        key: const Key('video-edit-song-menu'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
        child: Row(
          children: [
            Expanded(child: _LaneHeader.nameText(context, name, wide: _wide)),
            const Icon(Icons.more_vert, size: 16),
          ],
        ),
      ),
    ),
  );

  /// Under the lanes, the song's details: its lane and name, nudges of a
  /// twentieth of a second either way with where it starts in words between
  /// them, and the part of it used, once trimmed.
  Widget _songDetails(AppLocalizations l10n) {
    final theme = Theme.of(context);
    const tabular = [FontFeature.tabularFigures()];
    final trimmed = _trackStart > Duration.zero || _trackEnd < _trackLength;
    final take = _take;
    // Auto-align, where the sounds can be read.
    final aligns = _listens && _track != null && _trackLength > Duration.zero;
    final shift = _offset == Duration.zero
        ? (take ? l10n.videoEditSongWith : l10n.videoEditTrackWith)
        : _offset > Duration.zero
        ? (take ? l10n.videoEditSongAfter : l10n.videoEditTrackAfter)(
            fine(_offset),
          )
        : (take ? l10n.videoEditSongBefore : l10n.videoEditTrackBefore)(
            fine(-_offset),
          );
    return Column(
      key: const Key('video-edit-song-details'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '${take ? l10n.videoEditLaneSong : l10n.videoEditLaneTrack} · ',
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
                onPressed: () => _moveTrack(-step),
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
                onPressed: () => _moveTrack(step),
              ),
            ],
          ),
        if (_trackLength > Duration.zero) ...[
          _delayControl(l10n),
          ..._outputLines(l10n),
        ],
        if (_lined)
          Text(
            switch (_logged!.shiftOf(_current)) {
              final d when d > Duration.zero => l10n.videoEditSongLinedLater(
                fine(d),
              ),
              final d when d < Duration.zero => l10n.videoEditSongLinedEarlier(
                fine(-d),
              ),
              // Found in the take's own sound, or as Cam noted it.
              _ =>
                _logged!.measured
                    ? l10n.videoEditSongLinedSound
                    : l10n.videoEditSongLined,
            },
            key: const Key('video-edit-song-lined'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        // The take cut to its song: from where it starts to where it
        // stops, as the marks on the ruler show; and Auto-align.
        if ((_lined && _songMarks.length >= 2) || aligns)
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              if (_lined && _songMarks.length >= 2)
                Tooltip(
                  message: l10n.videoEditCutToSongTip,
                  child: TextButton.icon(
                    key: const Key('video-edit-cut-to-song'),
                    icon: const Icon(Icons.content_cut, size: 18),
                    label: Text(l10n.videoEditCutToSong),
                    onPressed: _cutIsSong ? null : _cutToSong,
                  ),
                ),
              if (aligns)
                Tooltip(
                  message: take
                      ? l10n.videoEditAutoAlignTip
                      : l10n.videoEditAutoAlignTrackTip,
                  child: TextButton.icon(
                    key: const Key('video-edit-song-align'),
                    icon: _aligning
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high, size: 18),
                    label: Text(l10n.videoEditAutoAlign),
                    onPressed: _aligning || _duration <= Duration.zero
                        ? null
                        : _align,
                  ),
                ),
            ],
          ),
        if (_alignSaid case final said?)
          Text(
            said,
            key: const Key('video-edit-song-align-said'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        if (trimmed && _trackLength > Duration.zero && _linedClips == null)
          Text(
            (take ? l10n.videoEditSongUsed : l10n.videoEditTrackUsed)(
              fine(_trackStart),
              fine(_trackEnd),
            ),
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

/// Asks for the song's delay in milliseconds, from [ms]: + later, −
/// earlier; pops it, or nothing when cancelled.
class _DelayDialog extends StatefulWidget {
  const _DelayDialog({required this.ms});

  final int ms;

  @override
  State<_DelayDialog> createState() => _DelayDialogState();
}

class _DelayDialogState extends State<_DelayDialog> {
  late final _field = TextEditingController(text: '${widget.ms}');

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _field.text.trim().replaceAll('+', '').replaceAll('−', '-');
    final ms = int.tryParse(text);
    if (ms != null) Navigator.of(context).pop(ms);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.videoEditDelayTitle),
      content: TextField(
        key: const Key('video-edit-delay-field'),
        controller: _field,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^[+\-−]?\d{0,5}')),
        ],
        decoration: InputDecoration(
          suffixText: 'ms',
          helperText: l10n.videoEditDelayHelp,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.eventCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.videoEditDelaySet)),
      ],
    );
  }
}

/// The song's delay, to the millisecond (`+120 ms`: later; `−35 ms`:
/// earlier), between steps of 10 and 1 ms either way; tapped, a value is
/// typed. For a Bluetooth speaker's or headphones' delay, which the
/// line-up can't see.
extension on _VideoEditScreenState {
  Widget _delayControl(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final ms = _delay.inMilliseconds;
    final shown = _msText(ms);
    Widget stepButton(int by) => IconButton(
      key: Key('video-edit-delay-${by < 0 ? 'minus' : 'plus'}${by.abs()}'),
      tooltip: by < 0
          ? l10n.videoEditDelayEarlier(by.abs())
          : l10n.videoEditDelayLater(by),
      visualDensity: VisualDensity.compact,
      onPressed: () => _moveTrack(Duration(milliseconds: by)),
      icon: Text(
        by < 0 ? '−${by.abs()}' : '+$by',
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      ),
    );
    return Column(
      key: const Key('video-edit-delay'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${l10n.videoEditDelay} · ',
                style: theme.textTheme.bodyMedium,
              ),
              TextSpan(
                text: l10n.videoEditDelayHint,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        // Shrunk to fit a narrow panel rather than overflow it.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final by in _VideoEditScreenState.delaySteps.reversed)
                stepButton(-by),
              Tooltip(
                message: l10n.videoEditDelayType,
                child: TextButton(
                  key: const Key('video-edit-delay-value'),
                  onPressed: _typeDelay,
                  child: Text(
                    shown,
                    style: TextStyle(
                      color: ms == 0 ? null : theme.colorScheme.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              for (final by in _VideoEditScreenState.delaySteps) stepButton(by),
            ],
          ),
        ),
      ],
    );
  }

  /// A delay as the control shows it: `+120 ms`, `−35 ms`, `0 ms`.
  static String _msText(int ms) =>
      ms > 0 ? '+$ms ms' : (ms < 0 ? '−${-ms} ms' : '0 ms');

  /// Under the delay control, for a take whose log says what its song
  /// played through ([TakeLog.out]): what it was, the latency its device
  /// reported, and whether it changed during the take; and, for a song
  /// lined up by itself, not found in the take's sound, through
  /// headphones: **Remember** the delay for that output (its takes open
  /// with it, [OutDelays]), that it's the one kept, or **Forget** it.
  List<Widget> _outputLines(AppLocalizations l10n) {
    final out = _take ? _takeLog?.out : null;
    if (out == null || out.route == OutRoute.unknown) return const [];
    final theme = Theme.of(context);
    final route = out.route.name;
    final lines = <Widget>[
      Text(
        [
          l10n.videoEditSongOut(route),
          if (out.latencyMs case final ms?) l10n.videoEditSongOutLatency(ms),
          if (out.changed) l10n.videoEditSongOutChanged,
        ].join(),
        key: const Key('video-edit-song-out'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall,
      ),
    ];
    final logged = _logged;
    if (!_lined || logged == null || logged.measured) return lines;
    if (!out.headphones || out.changed) return lines;
    final ms = _delay.inMilliseconds;
    final kept = _outDelays[out.key];
    final output = l10n.videoEditOutName(route);
    if (kept != null && kept == ms) {
      lines.add(
        Text(
          l10n.videoEditSongDelayKept(output),
          key: const Key('video-edit-song-delay-kept'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      );
    } else if (ms == 0 && kept != null) {
      lines.add(
        Align(
          child: TextButton.icon(
            key: const Key('video-edit-song-delay-forget'),
            icon: const Icon(Icons.bookmark_remove_outlined, size: 18),
            label: Text(l10n.videoEditSongDelayForget(output)),
            onPressed: () => _keepDelay(out.key, 0),
          ),
        ),
      );
    } else if (ms != 0 && ms >= OutDelays.least && ms <= OutDelays.most) {
      lines.add(
        Align(
          child: TextButton.icon(
            key: const Key('video-edit-song-delay-remember'),
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: Text(l10n.videoEditSongDelayRemember(_msText(ms), output)),
            onPressed: () => _keepDelay(out.key, ms),
          ),
        ),
      );
    }
    return lines;
  }
}

/// A swatch of the tab's [colors]: a little piece of band in them (a
/// staff's bit, in the text's colour on the background's), ringed in the
/// primary colour, with a check, when it's [selected] (else in the
/// outline's, so a white or black one shows on any theme); named [label]
/// (its tooltip, and what a screen reader says, with whether it's
/// picked). Its sample doesn't grow with the text size.
/// A colour of the tab's on the picture's toolbar ([OnPicture]): a small
/// bit of band, "3" in its text's colour on its background's, ringed in
/// the primary colour when it's the one in use.
class _PictureSwatch extends StatelessWidget {
  const _PictureSwatch({
    required this.colors,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final TabColors colors;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, text) = TabLayout.colorsOf(colors);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        child: InkWell(
          key: Key('video-edit-picture-colors-${colors.name}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: selected ? scheme.primary : Colors.white38,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Text(
                '3',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontFamily: monoFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabSwatch extends StatelessWidget {
  const _TabSwatch({
    required this.colors,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final TabColors colors;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, text) = TabLayout.colorsOf(colors);
    final radius = BorderRadius.circular(10);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        child: InkWell(
          key: Key('video-edit-tab-colors-${colors.name}'),
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            width: 52,
            height: 48,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: ColoredBox(
                color: background,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: Text(
                        '3-5',
                        maxLines: 1,
                        softWrap: false,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontFamily: monoFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: text,
                        ),
                      ),
                    ),
                    if (selected)
                      Align(
                        alignment: Alignment.topRight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(6),
                            ),
                          ),
                          child: Icon(
                            Icons.check,
                            size: 12,
                            color: scheme.onPrimary,
                          ),
                        ),
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

/// A lane's header, at its left: its [name] (or, for the Song lane with
/// a song, the [menu] its name opens), [width] wide, then its [volume]
/// (room for one when there's none), as high as a lane.
class _LaneHeader extends StatelessWidget {
  const _LaneHeader({
    required this.width,
    required this.wide,
    this.name,
    this.menu,
    this.volume,
  });

  final double width;

  /// Whether the editor is wide ([_VideoEditScreenState._wide]).
  final bool wide;
  final String? name;
  final Widget? menu;
  final Widget? volume;

  /// A lane's [name] as headers show it: small, on two lines at most on a
  /// phone (one when [wide]), its size kept to 1.3 times.
  static Widget nameText(
    BuildContext context,
    String name, {
    required bool wide,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Text(
          name,
          maxLines: wide ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style:
              (wide ? theme.textTheme.labelMedium : theme.textTheme.labelSmall)
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: width,
        height: _SongBar.height,
        child:
            menu ??
            Align(
              alignment: Alignment.centerLeft,
              child: nameText(context, name ?? '', wide: wide),
            ),
      ),
      volume ?? const SizedBox(width: _LaneVolume.width),
      const SizedBox(width: 4),
    ],
  );
}

/// A lane's volume, at the left of its bar: a speaker over the level
/// (`80%`, in the primary colour when it's not as it is, or muted; the
/// speaker crossed out when it isn't heard). Tapped, it opens a slider,
/// 0% to 100% in steps of 5% (sliding unmutes it), with Mute beside it
/// (muted, the level stays; Unmute puts it back, or, after a slide down
/// to 0%, the level before it), and under them its [stereo]: **Channels**
/// (Stereo, Left, Right, Mono: which of its sound's channels play on both
/// sides) and **Balance** (left 100% to right 100%, in steps of 5%), with a
/// note, once either is changed, that only Download has them (the players
/// can't pan). Its keys name its [lane]
/// (`video-edit-take-…`, `video-edit-song-…`), so there can be two. It
/// fits its bar's height at any text size: the level stays on one line,
/// and the two shrink together when the text is too large.
class _LaneVolume extends StatelessWidget {
  const _LaneVolume({
    required this.lane,
    required this.name,
    required this.volume,
    required this.muted,
    required this.stereo,
    required this.onStereo,
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
  final LaneStereo stereo;
  final void Function(LaneStereo stereo) onStereo;
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
    final changed = volume != 1 || muted || !stereo.isStandard;
    final balance = (stereo.balance * 100).round();
    String balanceOf(int balance) => balance == 0
        ? l10n.videoEditBalanceCentre
        : balance < 0
        ? l10n.videoEditBalanceLeft(-balance)
        : l10n.videoEditBalanceRight(balance);
    final balanceText = balanceOf(balance);
    final channelNames = {
      LaneChannels.stereo: (
        l10n.videoEditChannelsStereo,
        l10n.videoEditChannelsStereoTip,
      ),
      LaneChannels.left: (
        l10n.videoEditChannelsLeft,
        l10n.videoEditChannelsLeftTip,
      ),
      LaneChannels.right: (
        l10n.videoEditChannelsRight,
        l10n.videoEditChannelsRightTip,
      ),
      LaneChannels.mono: (
        l10n.videoEditChannelsMono,
        l10n.videoEditChannelsMonoTip,
      ),
    };
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
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Text(
            l10n.videoEditLaneChannels,
            style: theme.textTheme.labelMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: SizedBox(
            width: 296,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SegmentedButton<LaneChannels>(
                key: Key('video-edit-$lane-channels'),
                showSelectedIcon: false,
                segments: [
                  for (final MapEntry(key: c, value: (name, tip))
                      in channelNames.entries)
                    ButtonSegment(
                      value: c,
                      label: Text(name, key: Key('video-edit-$lane-${c.name}')),
                      tooltip: tip,
                    ),
                ],
                selected: {stereo.channels},
                onSelectionChanged: (s) =>
                    onStereo(stereo.copyWith(channels: s.first)),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  l10n.videoEditLaneBalance,
                  style: theme.textTheme.labelMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 180,
                child: Slider(
                  key: Key('video-edit-$lane-balance'),
                  min: -100,
                  max: 100,
                  divisions: 40,
                  value: balance.clamp(-100, 100).toDouble(),
                  label: balanceText,
                  semanticFormatterCallback: (v) => balanceOf(v.round()),
                  onChanged: (v) => onStereo(stereo.copyWith(balance: v / 100)),
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  balanceText,
                  key: Key('video-edit-$lane-balance-level'),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        if (!stereo.isStandard)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SizedBox(
              width: 296,
              child: Text(
                l10n.videoEditStereoPreviewNote,
                key: Key('video-edit-$lane-stereo-note'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          )
        else
          const SizedBox(height: 8),
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
    this.marks = const [],
    required this.label,
    required this.timeOf,
    required this.onSeek,
  });

  /// How high it is: room for its times (at most 1.3 times their size)
  /// over the ticks, and a finger.
  static const height = 32.0;

  final Duration length;

  /// Where the take's song starts and stops (the Take lane's grips snap
  /// to them): a small flag each, in the primary colour.
  final List<Duration> marks;
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
    const height = _Ruler.height;
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
                marks: widget.marks,
                timeOf: widget.timeOf,
                style: style,
                scaler: scaler,
                tick: theme.colorScheme.outline,
                mark: theme.colorScheme.primary,
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
    this.marks = const [],
    required this.timeOf,
    required this.style,
    required this.scaler,
    required this.tick,
    required this.mark,
  });

  final Duration length;
  final List<Duration> marks;
  final String Function(Duration at) timeOf;
  final TextStyle style;
  final TextScaler scaler;
  final Color tick;
  final Color mark;

  /// The steps between ticks, in milliseconds: the first with room for a
  /// time (under a second once zoomed in far enough).
  static const _steps = [
    100, 200, 500, 1000, 2000, 5000, 10000, 15000, 30000, 60000, //
    120000, 300000, 600000, 1200000, 1800000,
  ];

  /// [ms] as the ruler says it: m:ss, with tenths when it isn't on a
  /// second ("0:01.5").
  String _say(int ms) {
    final whole = timeOf(Duration(milliseconds: ms));
    final tenths = (ms % 1000) ~/ 100;
    return ms % 1000 == 0 ? whole : '$whole.$tenths';
  }

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
    final widest = label('${timeOf(length)}.0').width + 12;
    final step = _steps.firstWhere(
      (s) => s / 1000 * perSecond >= widest,
      orElse: () => _steps.last,
    );
    final paint = Paint()
      ..color = tick
      ..strokeWidth = 1;
    final total = length.inMilliseconds;
    for (var ms = 0; ms <= total; ms += step) {
      final x = ms / 1000 * perSecond;
      canvas.drawLine(
        Offset(x, size.height - 6),
        Offset(x, size.height),
        paint,
      );
      final text = label(_say(ms));
      if (x + text.width <= size.width) text.paint(canvas, Offset(x + 2, 0));
    }
    // The song's marks: a small flag pointing down at each, over the
    // ticks.
    final flag = Paint()..color = mark;
    for (final at in marks) {
      final x = at.inMilliseconds / 1000 * perSecond;
      canvas.drawPath(
        Path()
          ..moveTo(x - 4, size.height - 7)
          ..lineTo(x + 4, size.height - 7)
          ..lineTo(x, size.height)
          ..close(),
        flag,
      );
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.length != length ||
      !listEquals(old.marks, marks) ||
      old.mark != mark ||
      old.style != style ||
      old.scaler != scaler ||
      old.tick != tick;
}

/// Where the preview is ([at], 0 to 1 of the video), a line across the
/// ruler and the lanes, after [lead], with a small handle pointing down
/// at the top of the ruler (dragging it is dragging the ruler).
class _Playhead extends CustomPainter {
  _Playhead({required this.at, required this.lead, required this.color});

  final double at;
  final double lead;
  final Color color;

  /// The handle's size.
  static const handle = Size(12, 10);

  @override
  void paint(Canvas canvas, Size size) {
    final x = lead + at.clamp(0, 1) * (size.width - lead);
    final paint = Paint()..color = color;
    canvas.drawRect(Rect.fromLTWH(x - 1, 0, 2, size.height), paint);
    canvas.drawPath(
      Path()
        ..moveTo(x - handle.width / 2, 0)
        ..lineTo(x + handle.width / 2, 0)
        ..lineTo(x, handle.height)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(_Playhead old) =>
      old.at != at || old.color != color || old.lead != lead;
}

/// The Take lane: the whole video ([length]), the part kept, from
/// [start] to [end], bright (the lane's [name] on it), the rest dimmed.
/// Its two grips trim it ([onTrimStart], [onTrimEnd], by how far they're
/// dragged; [onTrimmed] as one is let go), and both sounds with it. The
/// [fades] are drawn on the part kept as ramps at its ends.
/// A lane's bar that, clicked or tapped (not dragged), takes the preview
/// where it's clicked along the video, as the ruler does: [length] across
/// its width. Its drags (the grips, the song moved) stay its own.
class _SeekOnTap extends StatelessWidget {
  const _SeekOnTap({
    required this.length,
    required this.onSeek,
    required this.child,
  });

  final Duration length;
  final void Function(Duration at) onSeek;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        final width = box.maxWidth;
        final ms = length.inMilliseconds;
        if (width <= 0 || ms <= 0) return;
        final x = d.localPosition.dx.clamp(0.0, width);
        onSeek(Duration(milliseconds: (x / width * ms).round()));
      },
      child: child,
    ),
  );
}

class _TakeBar extends StatelessWidget {
  const _TakeBar({
    required this.length,
    required this.start,
    required this.end,
    this.marks = const [],
    this.fades = Fades.none,
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

  /// Where the take's song starts and stops: a thin line down the bar at
  /// each, where a grip dragged near snaps to.
  final List<Duration> marks;
  final Fades fades;

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
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    if (fades.any)
                      Positioned(
                        left: left,
                        width: max(2, right - left),
                        top: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: CustomPaint(
                            key: const Key('video-edit-take-fades'),
                            painter: _FadeRamps(
                              fadeIn: fades.length <= Duration.zero
                                  ? 0
                                  : fades.fadeIn.inMicroseconds /
                                        fades.length.inMicroseconds,
                              fadeOut: fades.length <= Duration.zero
                                  ? 0
                                  : fades.fadeOut.inMicroseconds /
                                        fades.length.inMicroseconds,
                              color: theme.colorScheme.onPrimaryContainer
                                  .withValues(alpha: 0.25),
                            ),
                          ),
                        ),
                      ),
                    for (final (i, at) in marks.indexed)
                      Positioned(
                        key: Key('video-edit-take-mark-$i'),
                        left: at.inMilliseconds * perMs - 1,
                        top: 0,
                        bottom: 0,
                        width: 2,
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.7,
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

/// The fades on the Take lane's part kept: the fade in as a ramp over its
/// first [fadeIn] (a fraction of its width), shaded above, the fade out
/// over its last [fadeOut].
class _FadeRamps extends CustomPainter {
  _FadeRamps({
    required this.fadeIn,
    required this.fadeOut,
    required this.color,
  });

  final double fadeIn;
  final double fadeOut;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final w = size.width;
    final h = size.height;
    if (fadeIn > 0) {
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(fadeIn * w, 0)
          ..lineTo(0, h)
          ..close(),
        paint,
      );
    }
    if (fadeOut > 0) {
      canvas.drawPath(
        Path()
          ..moveTo(w - fadeOut * w, 0)
          ..lineTo(w, 0)
          ..lineTo(w, h)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FadeRamps old) =>
      old.fadeIn != fadeIn || old.fadeOut != fadeOut || old.color != color;
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
    this.onTrimStart,
    this.onTrimEnd,
    this.gaps = const [],
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
      onTrimEnd = null,
      gaps = const [];

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

  /// Where it's silent along the video, between its clips (from, to);
  /// none for one clip.
  final List<(Duration, Duration)> gaps;

  /// The lanes' height: a touch target's.
  static const height = 44.0;

  /// The song's block: its name between the grips, after an icon where
  /// there's room for both.
  Widget _block(ThemeData theme) => LayoutBuilder(
    builder: (context, box) {
      const inset = _Grip.width + 4;
      final icon = box.maxWidth - 2 * inset >= 36;
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: inset),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon) ...[
              Icon(
                Icons.graphic_eq,
                size: 16,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 4),
            ],
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
    },
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
                    // Silent between its clips.
                    for (final (from, to) in gaps)
                      Positioned(
                        left: from.inMilliseconds * perMs,
                        width: max(0.0, (to - from).inMilliseconds * perMs),
                        top: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
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
                    if (onTrimStart != null &&
                        left > -_Grip.width &&
                        left < width)
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
                    if (onTrimEnd != null &&
                        right > 0 &&
                        right < width + _Grip.width)
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
          onHorizontalDragCancel: onDone,
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
