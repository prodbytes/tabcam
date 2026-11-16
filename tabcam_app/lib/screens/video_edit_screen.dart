import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../capture/edit_layers.dart';
import '../capture/media.dart';
import '../capture/play_along_sidebar.dart' show isTake;
import '../capture/take_log.dart';
import '../capture/video_edit.dart';
import '../cloud/cloud_ocr.dart';
import '../export/download.dart';
import '../l10n/language.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import '../recognition/necklines.dart';
import 'edited_playback.dart';
import 'file_screen.dart';
import 'media_url.dart';
import 'premium_card.dart';
import 'video_page.dart' show mediaLength, openPlayer, pageFile;
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
/// nudged by a tenth of a second); ⋮ changes or removes it. Each lane has
/// its volume and Mute at its left. Under them (beside everything, on a
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
/// volumes, the layers over it, [EditLayers]); the video's file stays as
/// it is. Download renders the same plan ([RenderPlan]) to a file on the
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
    this.ocr,
  });

  final Library library;
  final String eventId;
  final EventPage page;

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

  /// The song the take's log lines up by itself (as it played while the
  /// take recorded), when it has one still in the capture: the default
  /// Song lane.
  LoggedSong? _logged;

  /// The shortest part of a song that can be used.
  static const minTrack = Duration(milliseconds: 500);

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
  /// saved before takes kept one).
  TakeLog? get _takeLog => widget.page.takeLog;

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

  /// The watermark's text: a take's, or another video's.
  String _watermarkText(AppLocalizations l10n) =>
      _take ? l10n.videoEditWatermarkTake : l10n.videoEditWatermarkMade;

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
    unawaited(_open());
    unawaited(_loadFormats());
  }

  /// Premium's status arrived, or changed: the Watermark chip unlocks (or
  /// locks) where it is.
  void _onPremium() {
    if (mounted) setState(() {});
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
      final saved = event.pages
          .where((p) => p.id == widget.page.id)
          .firstOrNull
          ?.edit;
      // A take's song, lined up by itself as it played while recording,
      // unless the edit placed one or took it out.
      final logged = LoggedSong.of(_takeLog);
      final lined =
          logged != null && event.pages.any((p) => p.id == logged.page)
          ? logged
          : null;
      final edit = withLoggedSong(saved, lined, duration: length);
      setState(() {
        _video = controller;
        _playback = EditedPlayback(controller);
        _duration = length;
        _end = length;
        _logged = lined;
        _saved = saved;
        _extra = saved?.extra ?? const {};
        if (edit != null) {
          _start = _clamp(edit.start, Duration.zero, length);
          _end = _clamp(edit.end, _start, length);
          _own = _Level(edit.ownVolume, edit.ownMuted);
          _song = edit.song;
          _songLevel = _Level(edit.trackVolume, edit.songMuted);
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
    widget.ocr?.removeListener(_onPremium);
    _title1.dispose();
    _title2.dispose();
    _titleFocus.dispose();
    _title2Focus.dispose();
    _measured.dispose();
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
  /// being edited, it shows as it ends up rather than fading in.
  List<PlanLayer> _previewLayers(AppLocalizations l10n) {
    final editing = _titleBeingEdited;
    final watermark = _watermarkText(l10n);
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
      watermark,
      editing,
    );
    if (of != _layersOf) {
      _layersOf = of;
      _layers = [
        for (final layer in RenderPlan.of(
          _planEdit,
          duration: _duration,
          takeLog: _takeLog,
          title: _captureTitle,
          watermark: watermark,
          premium: _unlocked,
          preview: true,
          frame: frame,
        ).layers)
          if (editing && layer.id == 'title')
            PlanLayer(
              id: layer.id,
              look: layer.look,
              anchor: layer.anchor,
              heightU: layer.heightU,
              marginU: layer.marginU,
            )
          else
            layer,
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
  /// screen, it's under them always).
  void _editTabStyle() {
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
  /// wide screen, they're beside them already, the first one focused.
  void _editTitle() {
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

  /// Whether the screen is wide: **On the video** beside the rest.
  bool get _wide => MediaQuery.sizeOf(context).width >= _wideFrom;
  static const _wideFrom = 840.0;

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
  /// no song (a take's lined up as it played while recording), and the
  /// tab, the capture's name and the watermark over it, fading in and out
  /// over 3 s (the edit is none).
  Future<void> _reset() async {
    final player = _trackPlayer;
    setState(() {
      _start = Duration.zero;
      _end = _duration;
      _own = _Level();
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
  RenderPlan _plan(RenderKind kind, {XFile? input, AppLocalizations? l10n}) =>
      RenderPlan.of(
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
        watermark: _watermarkText(l10n ?? context.l10n),
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
      final label = fileLabel(l10n, event, page);
      final plan = _plan(what, input: input, l10n: l10n);
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
          : AbsorbPointer(absorbing: _busy, child: _body(video, l10n)),
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

  /// The screen's body: the preview, its transport and the lanes; **On
  /// the video** under them on a phone (the title's fields in its place
  /// while they're open), beside them on a wide screen (the fields under
  /// its chips); the song's details.
  Widget _body(VideoPlayerController video, AppLocalizations l10n) {
    final wide = _wide;
    final main = [
      _preview(video, l10n),
      _transport(video, l10n),
      const SizedBox(height: 8),
      _timeline(video, l10n),
      if (!wide) ...[
        const SizedBox(height: 8),
        _editingTitle
            ? _titleFields(l10n)
            : _editingFades
            ? _fadeFields(l10n)
            : _editingTabStyle && _tabStyleOffered
            ? _tabStyleFields(l10n)
            : _onTheVideo(l10n),
      ],
      if (_hasSong) ...[const SizedBox(height: 8), _songDetails(l10n)],
      if (_busy) ...[
        const SizedBox(height: 16),
        Text(
          l10n.videoEditDownloading,
          key: const Key('video-edit-downloading'),
          textAlign: TextAlign.center,
        ),
      ],
    ];
    if (!wide) {
      return ListView(padding: const EdgeInsets.all(16), children: main);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: main),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: _sideWidth,
          child: ListView(
            key: const Key('video-edit-side'),
            padding: const EdgeInsets.all(16),
            children: [_onTheVideo(l10n, wide: true)],
          ),
        ),
      ],
    );
  }

  /// How wide **On the video** is beside the rest, on a wide screen.
  static const _sideWidth = 320.0;

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

  /// The video, at most a third of the screen, with what Download draws
  /// over it, and, while it plays, the fades' black ([EditLayers]);
  /// paused, its on-picture controls over that ([OnPicture]). A tap picks
  /// what's drawn there or plays or pauses it ([_tapPreview]); on a
  /// phone, a long press on the tab's band opens its style.
  Widget _preview(VideoPlayerController video, AppLocalizations l10n) {
    final height = MediaQuery.sizeOf(context).height / 3;
    final layers = _previewLayers(l10n);
    final fades = _fades;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height),
      child: GestureDetector(
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
  /// a phone; beside them, always, on a wide screen).
  void _editFadesHere() => _editFades();

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
                  : l10n.videoEditWatermarkAbout(_watermarkText(l10n)),
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
          _titleFields(l10n),
          const SizedBox(height: 16),
          _fadeFields(l10n),
          if (_tabStyleOffered) ...[
            const SizedBox(height: 16),
            _tabStyleFields(l10n),
          ],
        ],
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
  /// and **Colours** (four swatches, each a bit of band in its colours);
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
        TabColors.light => l10n.videoEditTabColorsLight,
        TabColors.gold => l10n.videoEditTabColorsGold,
        TabColors.brand => l10n.videoEditTabColorsBrand,
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
                  child: _SeekOnTap(
                    length: length,
                    onSeek: _seek,
                    child: _TakeBar(
                      length: length,
                      start: _start,
                      end: _end,
                      fades: _fades,
                      name: ownName,
                      label: l10n.videoEditTakeBar,
                      startLabel: l10n.videoEditKeptStart,
                      endLabel: l10n.videoEditKeptEnd,
                      onTrimStart: _trimStartBy,
                      onTrimEnd: _trimEndBy,
                      onTrimmed: _trimmed,
                    ),
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
                // Empty, it's Add a song; a song's, a tap places the
                // preview as the Take lane's does.
                Expanded(
                  child: hasSong
                      ? _SeekOnTap(
                          length: length,
                          onSeek: _seek,
                          child: songBar,
                        )
                      : songBar,
                ),
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
    final take = _take;
    final shift = _offset == Duration.zero
        ? (take ? l10n.videoEditSongWith : l10n.videoEditTrackWith)
        : _offset > Duration.zero
        ? (take ? l10n.videoEditSongAfter : l10n.videoEditTrackAfter)(
            time(_offset),
          )
        : (take ? l10n.videoEditSongBefore : l10n.videoEditTrackBefore)(
            time(-_offset),
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
        if (_lined)
          Text(
            switch (_logged!.shiftOf(_current)) {
              final d when d > Duration.zero => l10n.videoEditSongLinedLater(
                time(d),
              ),
              final d when d < Duration.zero => l10n.videoEditSongLinedEarlier(
                time(-d),
              ),
              _ => l10n.videoEditSongLined,
            },
            key: const Key('video-edit-song-lined'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        if (trimmed && _trackLength > Duration.zero && _linedClips == null)
          Text(
            (take ? l10n.videoEditSongUsed : l10n.videoEditTrackUsed)(
              time(_trackStart),
              time(_trackEnd),
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
    this.fades = Fades.none,
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
  final Fades fades;
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
