import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../dictionary/dictionary_sidebar.dart';
import '../l10n/language.dart';
import '../library/capture_event.dart';
import '../cloud/cloud_ocr.dart';
import '../library/library.dart';
import '../library/meta_names.dart';
import '../metronome/metronome.dart';
import '../recognition/necklines.dart';
import '../screens/mono_font.dart';
import '../screens/premium_card.dart';
import '../screens/video_page.dart';
import 'auto_pass.dart';
import 'backing_track.dart';
import 'head_gestures.dart';
import 'link_frame.dart';
import 'play_along_sidebar.dart';
import 'media.dart';
import 'mp4_length.dart';
import 'take_log.dart';
import 'take_overlay.dart';
import 'take_priority.dart';
import 'take_sound.dart';
import '../screens/messages.dart';

/// Whether a take of [mimeType] plays here, for Cam's Play: not a WebM (a
/// take recorded in Chrome or Firefox) on iOS or macOS, whose player
/// (AVPlayer) can't play one.
bool takePlaysHere(String mimeType) =>
    kIsWeb ||
    mimeType != 'video/webm' ||
    switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => false,
      _ => true,
    };

/// Cam: the guitarist records themselves playing along with the capture's
/// tab. The camera (the front one first: it faces the player) fills the
/// screen, with the tab under it one neckline at a time ([necklines]).
/// Any key moves to the next neckline (a page-turner pedal, a keyboard);
/// Backspace, ← , ↑ and Page Up to the one before; a tap on the neckline
/// or its arrows too; on Android, iOS and the web, a strong nod up or turn
/// to the right too, a nod down or turn to the left to the one before
/// ([HeadTracking]). **Rec** (or the 1 key) records (video and sound)
/// until it's tapped again, and adds the take to the capture as a video
/// ("Take 1", "Take 2"…); the . key saves the take and starts the next,
/// the song in the sidebar from its start. Each take keeps a log of what
/// Cam noted while it recorded ([TakeLog]: the tab's turns, the necklines
/// shown, how far the file started before the take's clock). **Play**
/// plays the capture's last take back, the necklines turning where they
/// turned while it was recorded (as its log says).
/// **Tab** hides the tab from the screen, and shows it again.
///
/// **Phrase passes**: while recording along with a song playing in the
/// sidebar's frame, with Auto-pass on, each turn of the tab is noted at
/// the song's position ([BackingTrack.recordPass]), merged with one the
/// same way within two seconds of it, and kept with the capture
/// ([PhraseTimes]); the take keeps its own. **Auto-pass** (beside Tab, on
/// by default, kept on the device) then turns the tab by itself where it
/// turned before, each time through the song ([AutoPass]). Off, no pass
/// is noted, for the song or the take.
///
/// **Play along** (the app bar's, when the capture has recordings, videos,
/// links or PDFs) shows and hides a sidebar of them, open from the first
/// time there's one (when Cam opens, or when one arrives later): the
/// one tapped plays in a compact frame at the sidebar's top, above the
/// list ([BackingTrack]), while the user plays and records; the space bar
/// pauses and plays it. A PDF tapped there shows on the screen's other
/// side, to follow the tab on it ([PlayAlong.followed]).
///
/// **Recording comes first** ([TakePriority]): the take's sound is
/// recorded as a musician wants it (on Android, by the app itself, from
/// the microphone's unprocessed source, and put into the take after
/// ([TakeSound]); on iOS, the audio session set for recording music and
/// mixed with the song; on the web, the microphone without voice-call
/// processing, at a high bitrate), set up when Cam opens rather than as
/// the take starts; while it records, head gestures
/// look less often, the web draws the tab at the camera's rate, and cloud
/// sync starts no pass.
class PlayAlongScreen extends StatefulWidget {
  const PlayAlongScreen({
    super.key,
    required this.library,
    required this.eventId,
    this.cameras = availableCameras,
    this.headTracking = HeadTracking.start,
    this.takeRecorder = TakeRecorder.forPlatform,
    this.burn = TakeOverlay.burn,
    this.linkFrame = linkFrameFor,
    this.pdfView = pdfViewFor,
    this.gate,
  });

  final Library library;
  final String eventId;

  /// Set for a user without Premium: the screen is a preview, greyed out
  /// under the Premium card ([PremiumGate]). No camera opens, no key or
  /// tap does anything, and the tab along the bottom is the capture's, or
  /// a sample where it has none.
  final ({CloudOcr ocr, String? email})? gate;

  /// The cameras there are; tests pass their own.
  final Future<List<CameraDescription>> Function() cameras;

  /// Watches for head gestures; null where it can't. Tests pass their own.
  final HeadTracking? Function(
    CameraController camera,
    void Function(HeadGesture) onGesture,
  )
  headTracking;

  /// Records takes with the tab in them as they go (the web); null where
  /// the tab is burned in after ([TakeOverlay]). Tests pass their own.
  final TakeRecorder? Function() takeRecorder;

  /// Burns the tab into a take ([TakeOverlay.burn]); tests pass their own.
  final Future<XFile?> Function(XFile take, List<(TabBand, Uint8List)> bands)
  burn;

  /// Shows a link in the backing track's frame; tests pass their own.
  final Widget Function(LinkFrameController controller) linkFrame;

  /// Shows the PDF followed beside the camera; tests pass their own.
  final Widget Function(Library library, CaptureEvent event, EventPage page)
  pdfView;

  @override
  State<PlayAlongScreen> createState() => _PlayAlongScreenState();
}

class _PlayAlongScreenState extends State<PlayAlongScreen> {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _camera = 0;
  String? _error;

  late final List<String> _lines = necklines(switch (widget.library
      .byId(widget.eventId)
      ?.tabText) {
    final text? => text,
    null => widget.gate == null ? '' : premiumSampleTab,
  });
  int _line = 0;

  /// Whether the tab shows along the bottom; hidden, it still turns (and
  /// is still burned into a take), it just isn't on the screen.
  bool _tabShown = true;

  /// While recording: when it started, and when each neckline showed.
  final _clock = Stopwatch();
  List<(Duration, int)> _marks = [];

  /// The take's lag readings ([TakeLog.lagRaw]), on [_span] (started as
  /// the recording is told to start): when it was told to start and when
  /// that returned, when [_clock] started, when it was told to stop and
  /// when that returned.
  final _span = Stopwatch();
  Duration _startCall = Duration.zero;
  Duration _startReturn = Duration.zero;
  Duration _clockZero = Duration.zero;
  Duration _stopCall = Duration.zero;
  Duration _stopReturn = Duration.zero;

  /// The web's take recorder: how long it had recorded when [_clock]
  /// started (ms; null: not known, or not its take).
  double? _recorderLag;

  /// The [_marks] (by index) made with auto-pass off: the tab turned in
  /// the take there, but it's no phrase pass of the take's.
  Set<int> _unpassed = {};
  bool _recording = false;
  bool _saving = false;

  /// Saving a take to start the next at once ([_nextTake], the . key).
  bool _nextTaking = false;

  /// Starting a take ([_rec]): until it records, Rec, 1 and . wait.
  bool _starting = false;

  /// The take Play plays: the capture's last (the user's own last, on a
  /// capture they contribute to), the one just saved after Rec.
  EventPage? _take;
  VideoPlayerController? _player;

  /// Play pressed, the take's player opening (its file may still be
  /// downloading, a take from another device): Rec, 1 and . wait, and
  /// Play (showing Stop) again lets it go, the player let go of as it
  /// opens.
  Object? _opening;

  /// The log of the take playing back ([_play]), its necklines turning as
  /// it says, and for each of its marks the capture's line it is
  /// ([_placesFor]); and the neckline it shows when that isn't one of the
  /// capture's (its tab changed since).
  TakeLog? _playedLog;
  List<int> _playedPlaces = const [];
  String? _playedLine;

  /// The take recorded last here and, for each of its log's marks, the
  /// capture's line it was ([TakeTab.placesOf]): a tab with a line twice
  /// plays it back on the copy that showed.
  (String, List<int>)? _recordedPlaces;

  /// Head gestures: what watches for them (null where it can't), and
  /// whether the user has them on.
  HeadTracking? _heads;
  bool _headsOn = true;

  /// Records takes with the tab in them, where the camera can't.
  late final TakeRecorder? _recorder = widget.takeRecorder();

  /// Burning the tab into the take just recorded.
  bool _burning = false;

  /// Whether this take is [_recorder]'s (else the camera's own).
  bool _recordingTab = false;

  /// Android: whether the takes' sound is recorded by the app
  /// ([TakeSound]), the camera opened without sound; decided when Cam
  /// opens (false: the camera records it, as on iOS).
  bool _ownSound = false;

  /// Android: the microphone was refused when the app asked for it as Cam
  /// opened; the camera asks again, and if allowed there, the app records
  /// the sound after all ([_open]).
  bool _soundRefused = false;

  /// What plays along, and whether the sidebar to choose it shows.
  late final PlayAlong _along = PlayAlong(
    widget.library,
    widget.eventId,
    withPdfs: true,
    withText: true,
  );
  BackingTrack get _track => _along.track;

  /// The keys' focus, taken back after a tap in the sidebar or the frame.
  final _focus = FocusNode();

  /// Auto-pass: whether it's on, and what turns the tab along the song.
  bool _autoPassOn = true;
  final _autoPass = AutoPass();

  /// The song auto-pass follows, and what reads its position meanwhile
  /// (only while it plays).
  String? _autoPassSong;
  Timer? _autoPassTimer;
  bool _autoPassReading = false;

  /// How often auto-pass reads the song's position: the player's own
  /// updates are coarser.
  static const autoPassTick = Duration(milliseconds: 100);

  /// The device's meta file Cam's settings are kept in.
  static const metaName = MetaNames.cam;

  @override
  void initState() {
    super.initState();
    // A preview opens no camera.
    if (widget.gate == null) {
      _take = _lastTake();
      _start();
      _track.addListener(_trackChanged);
      widget.library.addListener(_libraryChanged);
      unawaited(_loadSettings());
    }
  }

  /// The capture's last take (of the user's own files, [Library.addedPages])
  /// that plays here ([takePlaysHere]), if it has one.
  EventPage? _lastTake() {
    final event = widget.library.byId(widget.eventId);
    if (event == null) return null;
    return Library.addedPages(event)
        .where((p) => isTake(p) && takePlaysHere(p.mimeType))
        .lastOrNull;
  }

  /// The take Play plays, deleted (from the sidebar, say): the last of
  /// those left, if any; none yet, one that arrives (a sync).
  void _libraryChanged() {
    if (!mounted) return;
    final take = _take;
    final event = widget.library.byId(widget.eventId);
    final kept =
        take != null &&
        event != null &&
        Library.addedPages(event).any((p) => p.id == take.id);
    if (kept) return;
    final last = _lastTake();
    if (last?.id != take?.id) setState(() => _take = last);
  }

  Future<void> _loadSettings() async {
    try {
      final json = await widget.library.readMeta(metaName);
      if (json == null) return;
      final map = jsonDecode(json);
      if (map is Map && map['autoPass'] == false && mounted) {
        setState(() => _autoPassOn = false);
        _trackChanged();
      }
    } on Object catch (e) {
      debugPrint('TabCam: cam settings unreadable: $e');
    }
  }

  Future<void> _toggleAutoPass() async {
    setState(() => _autoPassOn = !_autoPassOn);
    _focus.requestFocus();
    // On again: the tab goes where the passes show at the song's position.
    _autoPass.reset();
    _trackChanged();
    try {
      await widget.library.writeMeta(
        metaName,
        jsonEncode({'autoPass': _autoPassOn}),
      );
    } on Object catch (e) {
      debugPrint('TabCam: cam settings not saved: $e');
    }
  }

  /// The song changed, played or paused: auto-pass follows it while it
  /// plays (another song starts it over).
  void _trackChanged() {
    final song = _track.page?.id;
    if (song != _autoPassSong) {
      _autoPassSong = song;
      _autoPass.reset();
    }
    final follow = _autoPassOn && _track.canPhrase && _track.playing;
    if (!follow) {
      _autoPassTimer?.cancel();
      _autoPassTimer = null;
    } else {
      _autoPassTimer ??= Timer.periodic(autoPassTick, (_) => _autoPassNow());
    }
  }

  /// Reads where the song is, and turns the tab where a pass says to.
  Future<void> _autoPassNow() async {
    final media = _track.media;
    if (_autoPassReading || media == null || !_autoPassOn || _player != null) {
      return;
    }
    final times = _track.phrases;
    if (times.isEmpty || !media.value.isPlaying) return;
    _autoPassReading = true;
    try {
      final at = await media.position ?? media.value.position;
      if (!mounted || _track.media != media || !_autoPassOn) return;
      if (_autoPass.tick(times, at) case final line?) _show(line);
    } on Object catch (e) {
      debugPrint('TabCam: auto-pass: $e');
    } finally {
      _autoPassReading = false;
    }
  }

  Future<void> _start() async {
    try {
      final cameras = await widget.cameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _error = appL10n.eventNoCamera);
        return;
      }
      final front = cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      _cameras = cameras;
      // Before the camera opens: it opens with sound or without by this.
      if (TakeSound.supported) {
        final ready = await TakeSound.prepare();
        if (!mounted) return;
        _ownSound = ready == TakeSoundReady.ok;
        _soundRefused = ready == TakeSoundReady.refused;
      }
      await _open(front < 0 ? 0 : front);
    } on Object catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    }
  }

  Future<void> _open(int index) async {
    final old = _controller;
    setState(() {
      _controller = null;
      _camera = index;
      _error = null;
    });
    await old?.dispose();
    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      // The web's takes have the microphone's sound, opened by the take
      // recorder without the processing for voice calls (the camera's
      // would have it); so do Android's where the app records it
      // ([TakeSound]).
      enableAudio: !kIsWeb && !_ownSound,
      // iOS (Android's camera takes none): music wants more than the
      // encoder's default.
      audioBitrate: TakePriority.iosAudioBitrate,
      // As the face detector reads them.
      imageFormatGroup: HeadTracking.imageFormat,
    );
    try {
      await controller.initialize();
    } on Object catch (e) {
      await controller.dispose();
      if (mounted) setState(() => _error = _describe(e));
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    // Refused when the app asked, the microphone was allowed at the
    // camera's own prompt (else the camera wouldn't have opened): the app
    // records the takes' sound after all. This camera, opened with sound,
    // records none of its own then (its plugin checks the permission as
    // each recording starts, and the app's side hides it).
    if (_soundRefused) {
      _soundRefused = false;
      _ownSound = await TakeSound.prepare(ask: false) == TakeSoundReady.ok;
      if (!mounted) {
        await controller.dispose();
        return;
      }
    }
    await _prepareSound(controller);
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
    _heads ??= widget.headTracking(controller, _gesture);
    _heads
      ?..camera = controller
      ..active = _headsOn;
    await _stream();
  }

  /// Gets the take's sound ready before any take, so starting one changes
  /// nothing the song playing along hears: on iOS, the microphone joins
  /// the camera now (else it would as the take starts, and its first
  /// moments are lost) and the audio session is set for it ([TakeAudio]);
  /// on the web, the take recorder opens the microphone (not waited
  /// for: the preview shows while the browser asks for it).
  Future<void> _prepareSound(CameraController controller) async {
    if (TakeAudio.supported) {
      try {
        await controller.prepareForVideoRecording();
      } on Object catch (e) {
        debugPrint('TabCam: cam: not prepared for recording: $e');
      }
      await TakeAudio.prepare();
    }
    if (_recorder case final recorder?) {
      unawaited(
        recorder.prepare().catchError(
          (Object e) => debugPrint('TabCam: cam: take recorder: $e'),
        ),
      );
    }
  }

  /// Whether a take records: what else runs makes way for it
  /// ([TakePriority]).
  void _takeRecording(bool recording) {
    TakePriority.recording.value = recording;
    _heads?.recording = recording;
  }

  /// With head gestures on, the camera's frames go to [_heads].
  Future<void> _stream() async {
    final controller = _controller;
    if (_heads == null || !_headsOn || controller == null) return;
    final v = controller.value;
    if (!controller.supportsImageStreaming() ||
        v.isStreamingImages ||
        v.isRecordingVideo) {
      return;
    }
    try {
      await controller.startImageStream(_frame);
    } on Object catch (e) {
      debugPrint('TabCam: head gestures: $e');
    }
  }

  void _frame(CameraImage image) {
    if (_headsOn) _heads?.onImage(image);
  }

  /// A nod or turn: the next neckline or the one before (not while a take
  /// plays: it turns them itself).
  void _gesture(HeadGesture gesture) {
    if (!mounted || !_headsOn || _player != null) return;
    unawaited(_pass(gesture == HeadGesture.next ? 1 : -1));
  }

  Future<void> _toggleHeads() async {
    setState(() => _headsOn = !_headsOn);
    _heads?.active = _headsOn;
    final controller = _controller;
    if (_headsOn) return _stream();
    if (controller != null &&
        controller.value.isStreamingImages &&
        !controller.value.isRecordingVideo) {
      await controller.stopImageStream();
    }
  }

  static String _describe(Object e) => switch (e) {
    CameraException(:final code)
        when code.contains('ermission') || code.contains('ccess') =>
      appL10n.camNotAllowed,
    CameraException(:final description?) => appL10n.eventCameraFailed(
      description,
    ),
    _ => appL10n.eventCameraFailed('$e'),
  };

  void _snack(String message) => showMessage(context, message);

  /// Shows neckline [index] (kept in range); while recording, notes when.
  /// False when it was showing already.
  bool _show(int index) {
    if (_lines.isEmpty) return false;
    final line = index.clamp(0, _lines.length - 1);
    if (line == _line) return false;
    setState(() => _line = line);
    if (_recording) {
      if (!_autoPassOn) _unpassed.add(_marks.length);
      _marks.add((_clock.elapsed, line));
    }
    return true;
  }

  /// The user passes a phrase: the next neckline ([delta] 1) or the one
  /// before (-1). With auto-pass on and a song playing along, the same
  /// pass auto-pass just made doesn't turn the tab again, and, recording,
  /// it's noted at the song's position ([BackingTrack.recordPass]). With
  /// auto-pass off, it only turns the tab: no pass is noted.
  Future<void> _pass(int delta) async {
    final direction = delta > 0 ? PassDirection.next : PassDirection.previous;
    final media = _track.media;
    final along =
        media != null &&
        _track.canPhrase &&
        media.value.isPlaying &&
        _player == null &&
        _autoPassOn;
    if (!along) {
      _show(_line + delta);
      return;
    }
    Duration at;
    try {
      at = await media.position ?? media.value.position;
    } on Object {
      at = media.value.position;
    }
    if (!mounted) return;
    final absorbed = _autoPassOn && _autoPass.absorbs(at, direction);
    if (!absorbed && !_show(_line + delta)) return;
    // (Auto-pass switched off while the position was read: not noted.)
    if (_recording && _autoPassOn && _track.media == media) {
      _track.recordPass(at, direction, _line);
    }
  }

  static final _back = {
    LogicalKeyboardKey.backspace,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.pageUp,
  };

  /// Keys that only change what other keys do: pressed alone, nothing.
  static final _modifiers = {
    ...LogicalKeyboardKey.expandSynonyms({
      LogicalKeyboardKey.shift,
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.alt,
      LogicalKeyboardKey.meta,
    }),
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.fn,
    LogicalKeyboardKey.escape,
  };

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent || widget.gate != null) {
      return KeyEventResult.ignored;
    }
    // Typing in a field (the dictionary's search) isn't moving the tab.
    if (FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>() !=
        null) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (_modifiers.contains(key)) return KeyEventResult.ignored;
    // 1: Rec / Stop, as the button (when it can be pressed), sidebar or
    // not. A key down: held, it doesn't start and stop again.
    if (_alone(event, _recKeys)) {
      if (event is KeyDownEvent && _canRec) unawaited(_rec());
      return KeyEventResult.handled;
    }
    // .: Stop and Rec again, a new take (not recording, Rec); a key down,
    // and nothing while one is saved for the next.
    if (_alone(event, _nextTakeKeys, _nextTakePhysical)) {
      if (event is KeyDownEvent && _canRec) unawaited(_nextTake());
      return KeyEventResult.handled;
    }
    // Space: the backing track's play / pause, while its sidebar shows.
    if (key == LogicalKeyboardKey.space && _along.open && _track.page != null) {
      if (event is KeyDownEvent) unawaited(_track.toggle());
      return KeyEventResult.handled;
    }
    // 0: back to its start (its section's).
    if (PlayAlongKeys.isRestart(event) && _along.open && _track.page != null) {
      if (event is KeyDownEvent) unawaited(_track.restart());
      return KeyEventResult.handled;
    }
    // ← and →: the backing track [skipBy] back and on, as « and » (held,
    // again and again); with no track showing, they turn the tab.
    if (_skips[key] case final by? when _along.open && _track.page != null) {
      unawaited(_track.skip(by));
      return KeyEventResult.handled;
    }
    unawaited(_pass(_back.contains(key) ? -1 : 1));
    return KeyEventResult.handled;
  }

  /// The keys that press Rec / Stop: 1, on the top row or the keypad.
  static final _recKeys = {
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.numpad1,
  };

  /// The keys that save the take and start a new one: ., on the main
  /// keyboard or the keypad.
  static final _nextTakeKeys = {
    LogicalKeyboardKey.period,
    LogicalKeyboardKey.numpadDecimal,
  };

  /// The keypad's decimal key, whatever it types: on the web, where it
  /// types "," (Brazilian, German and most European layouts), its logical
  /// key is the comma, not [LogicalKeyboardKey.numpadDecimal].
  static final _nextTakePhysical = {PhysicalKeyboardKey.numpadDecimal};

  /// Whether [event] is one of [keys] (or of the [physical] keys) pressed
  /// alone (with Ctrl, ⌘ or Alt it's another shortcut's, such as the
  /// browser's first tab, and turns the tab as any key).
  static bool _alone(
    KeyEvent event,
    Set<LogicalKeyboardKey> keys, [
    Set<PhysicalKeyboardKey> physical = const {},
  ]) {
    final keyboard = HardwareKeyboard.instance;
    return (keys.contains(event.logicalKey) ||
            physical.contains(event.physicalKey)) &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed;
  }

  /// Whether Rec / Stop can be pressed: a camera, no take being saved
  /// (nor saved for the next), none playing back (nor opening to).
  bool get _canRec =>
      _controller != null &&
      !_saving &&
      !_nextTaking &&
      _player == null &&
      _opening == null;

  /// How far ← and → move the backing track.
  static final _skips = {
    LogicalKeyboardKey.arrowLeft: -skipBy,
    LogicalKeyboardKey.arrowRight: skipBy,
  };

  Future<void> _rec() async {
    if (_recording) return _stopRecording();
    final controller = _controller;
    // A second press while the first starts would start another recording
    // alongside it (the camera records one at a time).
    if (controller == null || _saving || _starting) return;
    _starting = true;
    try {
      await _startRecording(controller);
    } finally {
      _starting = false;
    }
  }

  /// Starts recording a take with [controller], and the sidebar's song with
  /// it.
  Future<void> _startRecording(CameraController controller) async {
    await _stopPlaying();
    var soundStarted = false;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      // Again, in case something changed it since Cam opened (cheap when
      // nothing did).
      await TakeAudio.prepare();
      _recordingTab = false;
      if (_recorder case final recorder?) {
        // No take without its sound (a microphone refused or missing):
        // the sound matters most.
        if (!await recorder.hasSound()) {
          debugPrint('TabCam: cam: no microphone, no take');
          if (mounted) _snack(context.l10n.camNoSound);
          unawaited(_stream());
          return;
        }
        // The tab recorded in as it goes; failing that, the camera alone,
        // with the microphone's sound (the web's camera has none).
        try {
          _startTiming();
          await recorder.start(() => _lines.isEmpty ? null : _lines[_line]);
          _startReturn = _span.elapsed;
          _recordingTab = true;
        } on Object catch (e) {
          debugPrint('TabCam: cam: recording without the tab: $e');
          if (!await recorder.lendSoundToCamera()) {
            if (mounted) _snack(context.l10n.camNoSound);
            unawaited(_stream());
            return;
          }
          if (mounted) _snack(context.l10n.camRecordingNoTab('$e'));
        }
      }
      if (!_recordingTab) {
        // Android: the take's sound first, so it has the video's first
        // moment; what came before is dropped when it's put in.
        if (_ownSound) {
          await TakeSound.start();
          soundStarted = true;
        }
        // Its frames go to the head gestures while it records, with them
        // on (not on the web: it streams none, and the tracker reads the
        // preview). Off, none are streamed: on iOS each would be copied on
        // the queue that writes the take's sound.
        _startTiming();
        await controller.startVideoRecording(
          onAvailable:
              _heads == null ||
                  !_headsOn ||
                  !controller.supportsImageStreaming()
              ? null
              : _frame,
        );
        _startReturn = _span.elapsed;
        if (soundStarted) await TakeSound.videoStarted();
      }
    } on Object catch (e) {
      debugPrint('TabCam: cam: $e');
      if (soundStarted) unawaited(TakeSound.cancel());
      if (mounted) _snack(context.l10n.camCouldntRecord('$e'));
      unawaited(_stream());
      return;
    }
    _clockZero = _span.elapsed;
    _recorderLag = _recordingTab ? _recorder?.msSinceStart() : null;
    _clock
      ..reset()
      ..start();
    _marks = [(Duration.zero, _line)];
    _unpassed = {};
    _takeRecording(true);
    if (mounted) setState(() => _recording = true);
    // The song in the sidebar's player starts with the take (counting in
    // first, from where it is), unless it plays already.
    if (mounted &&
        _along.open &&
        _track.page != null &&
        !_track.loading &&
        !_track.playing &&
        !_track.countingIn) {
      unawaited(_track.toggle());
    }
  }

  /// Notes that the recording is told to start now ([_span] from 0).
  void _startTiming() {
    _span
      ..reset()
      ..start();
    _startCall = _span.elapsed;
  }

  /// [stop]s the recording, noting when it was told to and when it
  /// returned.
  Future<XFile> _timedStop(Future<XFile> Function() stop) async {
    _stopCall = _span.elapsed;
    try {
      return await stop();
    } finally {
      _stopReturn = _span.elapsed;
      _span.stop();
    }
  }

  /// The take's lag ([TakeLog.lagMs]), from the readings noted while it
  /// started and stopped: the web's recorder's own, else the bounds the
  /// calls put on it, with the file's length ([fileMs]) where known.
  ({int lagMs, LagFrom from, Map<String, int> raw}) _lag(int? fileMs) {
    int ms(Duration at) => (at - _clockZero).inMilliseconds;
    if (_recorderLag case final since?) {
      return lagFromRecorder(
        since,
        startCallMs: ms(_startCall),
        startReturnMs: ms(_startReturn),
      );
    }
    return lagFromBounds(
      startCallMs: ms(_startCall),
      startReturnMs: ms(_startReturn),
      stopCallMs: ms(_stopCall),
      stopReturnMs: ms(_stopReturn),
      fileMs: fileMs,
    );
  }

  /// The . key: while recording, a new take. The song in the sidebar
  /// stops at once, back at its start (its section's); the take is saved
  /// as Stop saves it; then Rec starts the next, and the song with it
  /// from there (counting in, if that's on). Not recording, Rec.
  Future<void> _nextTake() async {
    if (!_recording) return _rec();
    setState(() => _nextTaking = true);
    try {
      if (_along.open && _track.page != null) {
        try {
          await _track.stop();
        } on Object catch (e) {
          debugPrint('TabCam: cam: the song didn\'t stop: $e');
        }
      }
      await _stopRecording();
      // The take is kept whether or not the next one starts.
      if (!mounted || _controller == null) return;
      await _rec();
    } finally {
      if (mounted) setState(() => _nextTaking = false);
    }
  }

  /// Stops recording and adds the take to the capture.
  Future<void> _stopRecording() async {
    final controller = _controller;
    if (!_recording || controller == null) return;
    final l10n = context.l10n;
    setState(() {
      _recording = false;
      _saving = true;
    });
    _clock.stop();
    final marks = _marks;
    final unpassed = _unpassed;
    try {
      XFile file;
      try {
        file = await (_recordingTab
            ? _timedStop(_recorder!.stop)
            : _ownSound
            ? _stopWithSound(controller)
            : _timedStop(controller.stopVideoRecording));
      } finally {
        _takeRecording(false);
      }
      unawaited(_stream());
      // The log: the tab's turns as they came, and the lag (on the phones,
      // with the file's length as recorded).
      final tab = _lines.isEmpty ? null : TakeTab.of(_lines, marks);
      final fileMs = _recordingTab || kIsWeb ? null : await mp4VideoMs(file);
      final lag = _lag(fileMs);
      // Whether the tab is in the picture: drawn in as the web recorded,
      // or burned in here.
      var burned = _recordingTab && tab != null;
      if (!_recordingTab && tab != null && TakeOverlay.supported) {
        if (await _burn(file, tab, lag.lagMs) case final withTab?) {
          file = withTab;
          burned = true;
        }
      }
      final log = TakeLog(
        burned: burned,
        lagMs: lag.lagMs,
        lagFrom: lag.from,
        lagRaw: lag.raw,
        tab: tab,
      );
      final known = Media.of(file);
      final media = known?.kind == PageKind.video
          ? known!
          : Media(file, PageKind.video, kIsWeb ? 'webm' : 'mp4');
      final library = widget.library;
      final event = library.byId(widget.eventId);
      if (event == null) return;
      // A reader's take is theirs: in their contribution, named among it.
      final names = {for (final p in Library.addedPages(event)) p.title};
      var n = 1;
      while (names.contains(l10n.camTake(n))) {
        n++;
      }
      final updated = await library.addMedia(
        event,
        [media],
        take: true,
        takeLog: log,
      );
      final page = Library.addedPages(updated).last;
      final name = l10n.camTake(n);
      await library.renamePage(event.id, page.id, name);
      // Played along later, the take turns the tab as it turned in it
      // while auto-pass was on (off all along: it has no passes).
      await library.setPhrases(
        event.id,
        page.id,
        takePhrases(marks, skip: unpassed),
      );
      _take = page;
      if (tab != null) {
        _recordedPlaces = (page.id, TakeTab.placesOf(_lines, marks));
      }
      if (mounted) _snack(l10n.camSaved(name));
    } on Object catch (e, stack) {
      debugPrint('TabCam: cam: $e\n$stack');
      if (mounted) _snack(l10n.camCouldntRecord('$e'));
    } finally {
      await _track.savePhrases();
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Android, the take's sound recorded by the app: the camera stopped,
  /// then the sound, which goes into the camera's video in step with it
  /// ([TakeSound.stop]). Should that fail, the video is kept without
  /// sound, and a message says so: never a silent take unsaid.
  Future<XFile> _stopWithSound(CameraController controller) async {
    final l10n = context.l10n;
    await TakeSound.videoStopping();
    final XFile video;
    try {
      video = await _timedStop(controller.stopVideoRecording);
    } on Object {
      unawaited(TakeSound.cancel());
      rethrow;
    }
    final (:take, :error, :warning) = await TakeSound.stop(video);
    if (mounted && error != null) _snack(l10n.camTakeNoSound(error));
    if (mounted && warning != null) _snack(l10n.camTakeSoundWarning(warning));
    return take;
  }

  /// [take] with [tab] burned in where it showed, at its times in the
  /// file ([lagMs] after the take's clock, [TakeTab.fileMarks]); null when
  /// it couldn't be (the take is kept as it is, and a message says so).
  Future<XFile?> _burn(XFile take, TakeTab tab, int lagMs) async {
    final l10n = context.l10n;
    setState(() => _burning = true);
    try {
      final pngs = <int, Uint8List>{};
      final bands = <(TabBand, Uint8List)>[];
      for (final band in bandsOf(tab.fileMarks(lagMs))) {
        final png = pngs[band.line] ??= await renderBand(tab.lines[band.line]);
        bands.add((band, png));
      }
      final burned = await widget.burn(take, bands);
      if (burned == null && mounted) {
        _snack(l10n.camNoOverlay(TakeOverlay.lastError ?? '?'));
      }
      return burned;
    } finally {
      if (mounted) setState(() => _burning = false);
    }
  }

  /// Plays the take back ([_take]), or stops it; while it opens, lets it
  /// go ([_opening]).
  Future<void> _play() async {
    if (_player != null) return _stopPlaying();
    if (_opening != null) {
      setState(() => _opening = null);
      return;
    }
    final take = _take;
    final event = widget.library.byId(widget.eventId);
    if (take == null || event == null) return;
    final opening = Object();
    setState(() => _opening = opening);
    try {
      await _track.pause();
      // Mixed with others: else (iOS) it takes that from the app's audio
      // session, and the next take would stop a song playing in another
      // app (Android: it would take the audio focus from it).
      final player = await openPlayer(
        widget.library,
        event,
        take,
        mixWithOthers: true,
      );
      // Left, or let go of (Play again) while it opened.
      if (!mounted || _opening != opening) {
        await player.dispose();
        return;
      }
      player.addListener(_follow);
      setState(() {
        _opening = null;
        _player = player;
        _playedLog = take.takeLog;
        _playedPlaces = _placesFor(take);
      });
      await player.play();
    } on Object catch (e) {
      debugPrint('TabCam: cam: $e');
      if (mounted && _opening == opening) {
        _snack(context.l10n.textViewCantPlay);
      }
    } finally {
      if (mounted && _opening == opening) setState(() => _opening = null);
    }
  }

  /// For each mark of [take]'s log, the capture's line it is: exact for
  /// the take recorded here last while the tab is as it was, else from
  /// the texts ([TakeTab.placesIn]).
  List<int> _placesFor(EventPage take) {
    final tab = take.takeLog?.tab;
    if (tab == null) return const [];
    if (_recordedPlaces case (final id, final places)
        when id == take.id && places.length == tab.marks.length) {
      var same = true;
      for (final (i, (_, line)) in tab.marks.indexed) {
        final place = places[i];
        if (place >= _lines.length || _lines[place] != tab.lines[line]) {
          same = false;
          break;
        }
      }
      if (same) return places;
    }
    return tab.placesIn(_lines);
  }

  /// While a take plays: the neckline that showed then, as its log says
  /// (one no longer in the capture's tab shows as it was; a take without
  /// a log turns none); at its end, the camera again.
  void _follow() {
    final player = _player;
    if (player == null) return;
    final v = player.value;
    final at = v.position;
    if (_playedLog case TakeLog(:final tab?, :final lagMs)) {
      if (tab.markAt(at, lagMs) case final mark?) {
        final text = tab.lines[tab.marks[mark].$2];
        final line = mark < _playedPlaces.length ? _playedPlaces[mark] : -1;
        if (line >= 0 && (line != _line || _playedLine != null)) {
          setState(() {
            _line = line;
            _playedLine = null;
          });
        } else if (line < 0 && text != _playedLine) {
          setState(() => _playedLine = text);
        }
      }
    }
    if (v.isCompleted ||
        (v.duration > Duration.zero && at >= v.duration && !v.isPlaying)) {
      _stopPlaying();
    }
  }

  Future<void> _stopPlaying() async {
    if (_opening != null) {
      _opening = null;
      if (mounted) setState(() {});
    }
    final player = _player;
    if (player == null) return;
    player.removeListener(_follow);
    _playedLog = null;
    _playedPlaces = const [];
    if (mounted) {
      setState(() {
        _player = null;
        _playedLine = null;
      });
    }
    await player.dispose();
  }

  /// Back while recording: the take is saved, then the screen closes.
  Future<void> _leave() async {
    await _stopRecording();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    TakePriority.recording.value = false;
    if (widget.gate == null) {
      unawaited(TakeAudio.release());
      unawaited(TakeSound.release());
    }
    _autoPassTimer?.cancel();
    _track.removeListener(_trackChanged);
    widget.library.removeListener(_libraryChanged);
    unawaited(_track.savePhrases());
    _along.dispose();
    _focus.dispose();
    _recorder?.dispose();
    _controller?.dispose();
    _heads?.dispose();
    _player?.removeListener(_follow);
    _player?.dispose();
    super.dispose();
  }

  Widget _view() {
    final player = _player;
    if (player != null) {
      return AspectRatio(
        aspectRatio: player.value.aspectRatio,
        child: VideoPlayer(player),
      );
    }
    return switch ((_error, _controller)) {
      (final error?, _) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: Colors.white70,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
      (_, final controller?) => CameraPreview(controller),
      _ when widget.gate != null => const Icon(
        key: Key('cam-preview'),
        Icons.videocam_outlined,
        color: Colors.white24,
        size: 96,
      ),
      _ => const CircularProgressIndicator(),
    };
  }

  /// The tab, one neckline, along the bottom.
  Widget _neckline() {
    final l10n = context.l10n;
    const color = Colors.white;
    // A take playing back shows its own neckline where the capture's tab
    // no longer has it.
    final played = _playedLine;
    if (_lines.isEmpty && played == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          l10n.camNoTab,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    return Row(
      children: [
        IconButton(
          tooltip: l10n.camPrevious,
          color: color,
          disabledColor: Colors.white24,
          icon: const Icon(Icons.chevron_left),
          onPressed: _line > 0 ? () => unawaited(_pass(-1)) : null,
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_pass(1)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // As wide as the screen: a long staff shrinks to fit.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      played ?? _lines[_line],
                      key: const Key('neckline'),
                      softWrap: false,
                      style: const TextStyle(
                        fontFamily: monoFont,
                        color: color,
                        fontSize: 18,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (played == null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_line + 1} / ${_lines.length}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: l10n.camNext,
          color: color,
          disabledColor: Colors.white24,
          icon: const Icon(Icons.chevron_right),
          onPressed: _line < _lines.length - 1
              ? () => unawaited(_pass(1))
              : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = _controller;
    final event = widget.library.byId(widget.eventId);
    final playing = _player != null;
    // Play pressed, its take opening: Play shows Stop, deletes wait.
    final opening = _opening != null;
    final gate = widget.gate;
    final body = PlayAlongBeside(
      along: _along,
      linkFrame: widget.linkFrame,
      pdfView: widget.pdfView,
      onUse: _focus.requestFocus,
      // Not in a preview, nor while a take records, saves (or is saved
      // for the next, until it starts) or plays back.
      deletes: gate == null,
      canDelete:
          !_recording && !_saving && !_nextTaking && !playing && !opening,
      child: _main(controller, playing),
    );
    return PopScope(
      // Leaving while recording keeps the take.
      // (Not while one is saved for the next: it would start after.)
      canPop: !_recording && !_saving && !_nextTaking,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving && !_nextTaking) _leave();
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _key,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(
              event?.title ?? l10n.eventCam,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              DictionaryButton(onClosed: _focus.requestFocus),
              MetronomeButton(onClosed: _focus.requestFocus),
              if (gate == null)
                PlayAlongButton(along: _along, onPressed: _focus.requestFocus),
              if (_heads case final heads?)
                ValueListenableBuilder(
                  valueListenable: heads.face,
                  builder: (context, face, _) => IconButton(
                    key: const Key('cam-heads'),
                    tooltip: _headsOn ? l10n.camHeadsOn : l10n.camHeadsOff,
                    // On, the theme's primary colour while it sees the
                    // user's face.
                    color: _headsOn && face
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    icon: Icon(
                      _headsOn ? Icons.face : Icons.face_retouching_off,
                    ),
                    onPressed: _toggleHeads,
                  ),
                ),
              if (_cameras.length > 1 && controller != null)
                IconButton(
                  tooltip: l10n.eventFlipCamera,
                  icon: const Icon(Icons.cameraswitch),
                  onPressed: _recording || _saving || _nextTaking
                      ? null
                      : () => _open((_camera + 1) % _cameras.length),
                ),
            ],
            bottom: _saving
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(4),
                    child: LinearProgressIndicator(),
                  )
                : null,
          ),
          body: MetronomeBeside(
            onClosed: _focus.requestFocus,
            child: DictionaryBeside(
              onClosed: _focus.requestFocus,
              child: gate == null
                  ? body
                  : PremiumGate(
                      ocr: gate.ocr,
                      email: gate.email,
                      lead: l10n.premiumCamFeature,
                      onClose: () => Navigator.of(context).pop(),
                      child: body,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// The camera, the neckline and Rec, Play and Tab.
  Widget _main(CameraController? controller, bool playing) {
    final l10n = context.l10n;
    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(child: _view()),
              if (_burning)
                Card(
                  color: Colors.black87,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        // Wraps where the camera is narrow (the sidebar
                        // beside it).
                        Flexible(
                          child: Text(
                            l10n.camAddingTab,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_tabShown) ColoredBox(color: Colors.black87, child: _neckline()),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Control(
                  key: const Key('cam-rec'),
                  icon: _recording ? Icons.stop : Icons.fiber_manual_record,
                  color: Colors.red,
                  label: _recording ? l10n.camStop : l10n.camRec,
                  tooltip: _recording ? l10n.camStopKey : l10n.camRecKey,
                  onPressed: _canRec ? _rec : null,
                ),
                _Control(
                  key: const Key('cam-play'),
                  // Opening: Stop lets it go.
                  icon: playing || _opening != null
                      ? Icons.stop
                      : Icons.play_arrow,
                  color: Colors.white,
                  label: playing || _opening != null
                      ? l10n.camStop
                      : l10n.camPlay,
                  onPressed:
                      _take == null || _recording || _saving || _nextTaking
                      ? null
                      : _play,
                ),
                _Control(
                  key: const Key('cam-tab'),
                  icon: _tabShown ? Icons.subtitles : Icons.subtitles_off,
                  color: Colors.white,
                  label: _tabShown ? l10n.camHideTab : l10n.camShowTab,
                  onPressed: () {
                    setState(() => _tabShown = !_tabShown);
                    _focus.requestFocus();
                  },
                ),
                _Control(
                  key: const Key('cam-auto-pass'),
                  icon: _autoPassOn ? Icons.auto_mode : Icons.motion_photos_off,
                  color: _autoPassOn
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white,
                  label: l10n.camAutoPass,
                  tooltip: _autoPassOn
                      ? l10n.camAutoPassOn
                      : l10n.camAutoPassOff,
                  onPressed: widget.gate == null ? _toggleAutoPass : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Rec, Play, Tab or Auto-pass: an icon over its label, on black.
class _Control extends StatelessWidget {
  const _Control({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String label;

  /// What its tooltip says; null: its [label].
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null;
    // Narrow (a PDF beside the camera), the labels shorten, not overflow.
    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: tooltip ?? label,
            iconSize: 36,
            color: color,
            disabledColor: Colors.white24,
            icon: Icon(icon),
            onPressed: onPressed,
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: on ? Colors.white : Colors.white38),
          ),
        ],
      ),
    );
  }
}
