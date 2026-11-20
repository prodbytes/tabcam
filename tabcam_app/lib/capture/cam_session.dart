import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../l10n/language.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import '../library/meta_names.dart';
import '../recognition/necklines.dart';
import '../screens/premium_card.dart';
import '../screens/video_page.dart';
import 'auto_pass.dart';
import 'backing_track.dart';
import 'camera_list.dart';
import 'head_gestures.dart';
import 'media.dart';
import 'mp4_length.dart';
import 'play_along_sidebar.dart';
import 'take_file.dart';
import 'take_h264.dart';
import 'take_log.dart';
import 'take_priority.dart';
import 'take_recorder.dart';
import 'take_sound.dart';
import 'take_syncer.dart';

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

/// What Cam has to tell the user ([CamSession.onNote]); the screen
/// showing Cam says it in the app's language (`camNoteText`).
enum CamNote {
  /// No take: the microphone is refused or missing.
  noSound,

  /// The take didn't record (the detail: why).
  couldntRecord,

  /// The microphone chosen didn't open (the detail: its name).
  micFailed,

  /// The take was thrown away (the . key).
  discarded,

  /// The take was saved (the detail: its name).
  saved,

  /// Android: the take was kept without its sound (the detail: why).
  takeNoSound,

  /// Android: the take's sound was put in with a warning (the detail).
  soundWarning,

  /// iOS: the take wasn't made H.264 (the detail: why).
  notH264,

  /// The take didn't play back.
  cantPlay,
}

/// What Cam does, apart from how it shows (Cam's view, `StudioView`,
/// shows it, with the widgets in `cam_controls.dart`): the camera, the head
/// gestures, the tab (one phrase at a time) and auto-pass, the
/// microphone and its input volume (Cam's settings, [metaName]), the
/// takes (Rec, the / and . keys, saving a take with its log) and playing
/// the last one back. It tells its listeners whenever what shows
/// changes, and the screen what to say ([onNote]).
///
/// [start] opens the camera, as Cam opens (not in a preview, [gated]).
/// [dispose] lets go of it all, [along] with it.
class CamSession extends ChangeNotifier {
  CamSession({
    required this.library,
    required this.eventId,
    required Future<List<CameraDescription>> Function() cameras,
    required this._headTracking,
    required this._takeRecorder,
    required this._now,
    required this._takeName,
    required this.onNote,
    this.gated = false,
    this.startId,
    this.opensByItself = true,
  }) : _findCameras = cameras;

  final Library library;
  final String eventId;

  /// The file [along] loads first when its sidebar opens by itself
  /// ([PlayAlong.startId]); null, the first to play.
  final String? startId;

  /// Whether [along]'s sidebar opens by itself once the capture has
  /// something to list ([PlayAlong.opensByItself]).
  final bool opensByItself;

  /// A preview, for a user without Premium (`PlayAlongScreen.gate`): no
  /// camera opens ([start] isn't called), no key does anything, and the
  /// tab is the capture's, or a sample where it has none.
  final bool gated;

  /// The cameras there are.
  final Future<List<CameraDescription>> Function() _findCameras;

  /// Watches for head gestures; null where it can't.
  final HeadTracking? Function(
    CameraController camera,
    void Function(HeadGesture) onGesture,
  )
  _headTracking;

  /// Records takes where the camera plugin doesn't (the web); null where
  /// it does.
  final TakeRecorder? Function() _takeRecorder;

  /// The time now, which names the takes.
  final DateTime Function() _now;

  /// A take's name, from when it started ("Take 14:32").
  final String Function(DateTime started) _takeName;

  /// Says [CamNote] to the user (with its detail, where it has one); only
  /// while the session isn't disposed.
  final void Function(CamNote note, [String? detail]) onNote;

  bool _disposed = false;

  /// Whether [dispose] has been called (what the screen's `mounted` was).
  bool get disposed => _disposed;

  /// Tells the listeners what shows changed (not once disposed).
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _note(CamNote note, [String? detail]) => onNote(note, detail);

  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _camera = 0;
  String? _error;

  /// The cameras found as Cam opened (Flip camera moves along them).
  List<CameraDescription> get cameras => _cameras;

  /// The camera open, if one is.
  CameraController? get controller => _controller;

  /// Why the camera didn't open, if it didn't.
  String? get error => _error;

  late final List<String> _lines = necklines(switch (library
      .byId(eventId)
      ?.tabText) {
    final text? => text,
    null => gated ? premiumSampleTab : '',
  });
  int _line = 0;

  /// The tab's phrases ([necklines]).
  List<String> get lines => _lines;

  /// The phrase showing, of [lines].
  int get line => _line;

  /// Whether the tab shows along the bottom; hidden, it still turns (and
  /// its turns are still in a take's log), it just isn't on the screen.
  bool _tabShown = true;
  bool get tabShown => _tabShown;

  /// While recording: when it started (the take's clock), and when each
  /// neckline showed.
  late final Stopwatch _clock = takeClock();
  List<(Duration, int)> _marks = [];

  /// Makes the take's clock; tests pass one on their own clock.
  @visibleForTesting
  static Stopwatch Function() takeClock = Stopwatch.new;

  /// How long the take recording has recorded, on its clock: told every
  /// [elapsedTick] while it records, and only then (its last reading
  /// stays once it stops). Only what shows it listens: it tells Cam's
  /// listeners nothing, so the camera isn't built again for it.
  ValueListenable<Duration> get elapsed => _elapsed;
  final _elapsed = ValueNotifier(Duration.zero);
  Timer? _elapsedTimer;

  /// How often [elapsed] is told.
  static const elapsedTick = Duration(milliseconds: 250);

  /// [elapsed] told from the take's clock every [elapsedTick], from now
  /// (from 0: a take starts).
  void _startTicking() {
    _elapsedTimer?.cancel();
    _elapsed.value = Duration.zero;
    _elapsedTimer = Timer.periodic(elapsedTick, (_) {
      if (!_disposed) _elapsed.value = _clock.elapsed;
    });
  }

  /// [elapsed] no longer told: the take stopped (its length its last
  /// reading).
  void _stopTicking() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    if (!_disposed) _elapsed.value = _clock.elapsed;
  }

  /// The take's lag readings ([TakeLog.lagRaw]), on [_span] (started as
  /// the recording is told to start): when it was told to start and when
  /// that returned, when [_clock] started, when it was told to stop and
  /// when that returned.
  final _span = Stopwatch();
  Duration _startCall = Duration.zero;
  Duration _startReturn = Duration.zero;
  Duration _clockZero = Duration.zero;

  /// When the take recording now started (Rec pressed): its name's time.
  DateTime _takeStarted = DateTime.now();
  Duration _stopCall = Duration.zero;
  Duration _stopReturn = Duration.zero;

  /// The web's take recorder: how long it had recorded when [_clock]
  /// started (ms; null: not known, or not its take).
  double? _recorderLag;

  /// What the song plays through, read as the take's clock starts
  /// ([_readOutput]; the take's log keeps it, [TakeLog.out]); and, on
  /// Android with the app's own sound, how long before the video's first
  /// frame that sound began (the stop's reply; kept in [TakeLog.lagRaw]).
  Future<TakeOutput?>? _outRead;
  int? _soundLeadMs;

  /// The [_marks] (by index) made with auto-pass off: the tab turned in
  /// the take there, but it's no phrase pass of the take's.
  Set<int> _unpassed = {};

  /// While recording: the song played along, as it played (the take's
  /// log keeps it, so the editor lines the song up with the take).
  SongNotes? _songNotes;

  /// The take just stopped's song, as noted to its end, while it's saved.
  List<SongSegment> _stoppedSong = const [];

  /// The song played along in the take recording, as noted so far (the
  /// segment playing as if it ended now, [SongNotes.soFar]); once it
  /// stops, as noted to its end (while it's saved, and after).
  List<SongSegment> get songSoFar =>
      _songNotes?.soFar(_clock.elapsed.inMilliseconds) ?? _stoppedSong;
  bool _recording = false;
  bool _saving = false;

  /// Whether a take records.
  bool get recording => _recording;

  /// Whether a take is being saved.
  bool get saving => _saving;

  /// Saving a take (the / key) or throwing it away (the . key) to start
  /// the next at once ([nextTake]).
  bool _nextTaking = false;
  bool get nextTaking => _nextTaking;

  /// Starting a take ([rec]): until it records, Rec, 1, / and . wait.
  bool _starting = false;

  /// The take Play plays: the capture's last (the user's own last, on a
  /// capture they contribute to), the one just saved after Rec.
  EventPage? _take;
  VideoPlayerController? _player;

  /// The take Play plays, if there's one.
  EventPage? get take => _take;

  /// The capture [take] is in (the copy it went to, for a take added to a
  /// copy, `Library.copyToAdd`), and how long it recorded, on its clock,
  /// when it was recorded here (null: one that was there as Cam opened).
  String? _takeEvent;
  Duration? _takeLength;

  /// The take recorded last ([take]: the one just saved after Rec; as Cam
  /// opens, the capture's last), its capture, and how long it recorded on
  /// its clock (null: not recorded since Cam opened). None: no take.
  ({EventPage page, String eventId, Duration? length})? get lastTake {
    final take = _take;
    if (take == null) return null;
    final event = _takeEvent ?? eventId;
    return (page: take, eventId: event, length: _takeLength);
  }

  /// [take] is [page] of capture [event] from now on, [length] long when
  /// it was recorded here.
  void _setTake(EventPage? page, {String? event, Duration? length}) {
    _take = page;
    _takeEvent = event;
    _takeLength = length;
  }

  /// The take playing back, if one is.
  VideoPlayerController? get player => _player;

  /// Play pressed, the take's player opening (its file may still be
  /// downloading, a take from another device): Rec, 1, / and . wait, and
  /// Play (showing Stop) again lets it go, the player let go of as it
  /// opens.
  Object? _opening;

  /// Whether Play's take is opening ([_opening]).
  bool get opening => _opening != null;

  /// The log of the take playing back ([play]), its necklines turning as
  /// it says, and for each of its marks the capture's line it is
  /// ([_placesFor]); and the neckline it shows when that isn't one of the
  /// capture's (its tab changed since).
  TakeLog? _playedLog;
  List<int> _playedPlaces = const [];
  String? _playedLine;

  /// While a take plays back, the phrase it shows when that isn't one
  /// of the capture's (its tab changed since).
  String? get playedLine => _playedLine;

  /// The take recorded last here and, for each of its log's marks, the
  /// capture's line it was ([TakeTab.placesOf]): a tab with a line twice
  /// plays it back on the copy that showed.
  (String, List<int>)? _recordedPlaces;

  /// Head gestures: what watches for them (null where it can't), and
  /// whether the user has them on (off when Cam opens: the face icon
  /// switches them on).
  HeadTracking? _heads;
  bool _headsOn = false;

  /// What watches for head gestures, once the camera is open (null where
  /// it can't).
  HeadTracking? get heads => _heads;

  /// Whether the user has head gestures on.
  bool get headsOn => _headsOn;

  /// Records takes, where the camera plugin doesn't (the web).
  late final TakeRecorder? _recorder = _takeRecorder();

  /// iOS: making the take just recorded H.264 ([TakeH264]).
  bool _converting = false;
  bool get converting => _converting;

  /// Whether this take is [_recorder]'s (else the camera's own).
  bool _byRecorder = false;

  /// Android: whether the takes' sound is recorded by the app
  /// ([TakeSound]), the camera opened without sound; decided when Cam
  /// opens (false: the camera records it, as on iOS).
  bool _ownSound = false;

  /// Android: the microphone was refused when the app asked for it as Cam
  /// opened; the camera asks again, and if allowed there, the app records
  /// the sound after all ([_open]).
  bool _soundRefused = false;

  /// The microphone takes record from, chosen in Rec's menu: its id
  /// ([TakeMic.id]), kept in Cam's settings; null, the system's default.
  /// One not connected records from the default.
  String? _mic;
  String? get mic => _mic;

  /// The input volume, set by tapping the level meter, in dB (0: as the
  /// microphone gives it), from -[maxGainDb] to +[maxGainDb]; kept in
  /// Cam's settings.
  int _gainDb = 0;
  int get gainDb => _gainDb;

  static const maxGainDb = 24;

  /// [_gainDb] as a factor (1: as it comes).
  double get _gain => math.pow(10, _gainDb / 20).toDouble();

  /// A microphone being opened from Rec's menu: Rec's menu waits.
  bool _micBusy = false;

  /// Cam's settings, read as it opens: the camera waits for them (the
  /// microphone opens from the one chosen).
  Future<void>? _settingsRead;

  /// What plays along, and whether the sidebar to choose it shows; made
  /// as first used, opening on [startId] or by itself as
  /// [opensByItself] says.
  late final PlayAlong along = PlayAlong(
    library,
    eventId,
    withPdfs: true,
    withText: true,
    startId: startId,
    opensByItself: opensByItself,
  );
  BackingTrack get _track => along.track;

  /// Auto-pass: whether it's on, and what turns the tab along the song.
  bool _autoPassOn = true;
  final _autoPass = AutoPass();

  /// Whether auto-pass is on.
  bool get autoPassOn => _autoPassOn;

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

  /// As Cam opens (not in a preview: it opens no camera): the take Play
  /// plays, the camera, following the song and the capture, and Cam's
  /// settings.
  void start() {
    _setTake(_lastTake());
    _start();
    _track.addListener(_trackChanged);
    library.addListener(_libraryChanged);
    _settingsRead = _loadSettings();
  }

  /// The capture's last take that plays here ([takePlaysHere]), if it has
  /// one.
  EventPage? _lastTake() {
    final event = library.byId(eventId);
    if (event == null) return null;
    return event.pages
        .where((p) => isTake(p) && takePlaysHere(p.mimeType))
        .lastOrNull;
  }

  /// The take Play plays, deleted (from the sidebar, say): the last of
  /// those left, if any; none yet, one that arrives (a sync).
  void _libraryChanged() {
    if (_disposed) return;
    final take = _take;
    final event = library.byId(eventId);
    final kept =
        take != null &&
        event != null &&
        event.pages.any((p) => p.id == take.id);
    if (kept) return;
    final last = _lastTake();
    if (last?.id != take?.id) {
      _setTake(last);
      _changed();
    }
  }

  Future<void> _loadSettings() async {
    try {
      final json = await library.readMeta(metaName);
      if (json == null) return;
      final map = jsonDecode(json);
      if (map is! Map) return;
      if (map['mic'] case final String mic when mic.isNotEmpty) _mic = mic;
      if (map['gainDb'] case final num db when db.isFinite) {
        _gainDb = db.round().clamp(-maxGainDb, maxGainDb);
      }
      if (map['autoPass'] == false && !_disposed) {
        _autoPassOn = false;
        _changed();
        _trackChanged();
      }
    } on Object catch (e) {
      debugPrint('TabCam: cam settings unreadable: $e');
    }
  }

  /// Auto-pass on or off, kept in Cam's settings.
  Future<void> toggleAutoPass() async {
    _autoPassOn = !_autoPassOn;
    _changed();
    // On again: the tab goes where the passes show at the song's position.
    _autoPass.reset();
    _trackChanged();
    await saveSettings();
  }

  /// Keeps Cam's settings: Auto-pass, the microphone chosen and the input
  /// volume.
  Future<void> saveSettings() async {
    try {
      await library.writeMeta(
        metaName,
        jsonEncode({
          'autoPass': _autoPassOn,
          'mic': ?_mic,
          if (_gainDb != 0) 'gainDb': _gainDb,
        }),
      );
    } on Object catch (e) {
      debugPrint('TabCam: cam settings not saved: $e');
    }
  }

  /// The song changed, played or paused: auto-pass follows it while it
  /// plays (another song starts it over).
  void _trackChanged() {
    _noteSong();
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
      if (_disposed || _track.media != media || !_autoPassOn) return;
      if (_autoPass.tick(times, at) case final line?) _show(line);
    } on Object catch (e) {
      debugPrint('TabCam: auto-pass: $e');
    } finally {
      _autoPassReading = false;
    }
  }

  Future<void> _start() async {
    try {
      final cameras = await _findCameras();
      if (_disposed) return;
      if (cameras.isEmpty) {
        _error = appL10n.eventNoCamera;
        _changed();
        return;
      }
      final front = cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      _cameras = cameras;
      // The microphone chosen, to open it from.
      await _settingsRead;
      if (_disposed) return;
      // Before the camera opens: it opens with sound or without by this.
      if (TakeSound.supported) {
        final ready = await TakeSound.prepare(device: _mic);
        if (_disposed) return;
        _ownSound = ready == TakeSoundReady.ok;
        _soundRefused = ready == TakeSoundReady.refused;
        // The input volume set (the app's microphone keeps the last one).
        if (_ownSound) await TakeSound.setGain(_gain);
        if (_disposed) return;
      }
      // The front camera, else the first; one that won't open (another
      // app holds it, an infrared one) gives way to the next, and if none
      // does, the first one's error shows.
      final first = front < 0 ? 0 : front;
      String? error;
      for (var i = 0; i < cameras.length; i++) {
        final index = (first + i) % cameras.length;
        if (await _open(index)) return;
        if (_disposed) return;
        error ??= _error;
        // Not allowed: no other camera is either.
        if (_error == appL10n.camNotAllowed) break;
      }
      if (error != null) {
        _error = error;
        _changed();
      }
    } on Object catch (e) {
      if (!_disposed) {
        _error = _describe(e);
        _changed();
      }
    }
  }

  /// Try again, the camera having failed (once the other app lets go of
  /// it, say): from the start.
  void tryAgain() {
    _error = null;
    _changed();
    _start();
  }

  /// Flip camera: the next one of [cameras].
  Future<bool> flip() => _open((_camera + 1) % _cameras.length);

  /// Opens camera [index] of [_cameras]: false when it didn't (its error
  /// shows, with Try again and, with others, Flip camera).
  Future<bool> _open(int index) async {
    final old = _controller;
    _controller = null;
    _camera = index;
    _error = null;
    _changed();
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
      debugPrint('TabCam: cam: camera ${_cameras[index].name} failed: $e');
      await controller.dispose();
      if (!_disposed) {
        _error = _describe(e);
        _changed();
      }
      return false;
    }
    if (_disposed) {
      await controller.dispose();
      return false;
    }
    // Refused when the app asked, the microphone was allowed at the
    // camera's own prompt (else the camera wouldn't have opened): the app
    // records the takes' sound after all. This camera, opened with sound,
    // records none of its own then (its plugin checks the permission as
    // each recording starts, and the app's side hides it).
    if (_soundRefused) {
      _soundRefused = false;
      _ownSound =
          await TakeSound.prepare(ask: false, device: _mic) ==
          TakeSoundReady.ok;
      if (_disposed) {
        await controller.dispose();
        return false;
      }
    }
    await _prepareSound(controller);
    if (_disposed) {
      await controller.dispose();
      return false;
    }
    _controller = controller;
    _changed();
    _heads ??= _headTracking(controller, _gesture);
    _heads
      ?..camera = controller
      ..active = _headsOn && !_away;
    await _stream();
    return true;
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
      // The camera's sound follows the session's input.
      if (_mic case final mic?) await TakeAudio.choose(mic);
    }
    if (_recorder case final recorder?) {
      _applyGain();
      unawaited(
        () async {
          await recorder.useMicrophone(_mic);
          await recorder.prepare();
        }().catchError(
          (Object e) => debugPrint('TabCam: cam: take recorder: $e'),
        ),
      );
    }
  }

  /// Whether takes' microphone can be chosen here: by the web's recorder,
  /// by the app on Android ([TakeSound]), by the audio session on iOS
  /// ([TakeAudio]); not where the camera plugin records the sound on
  /// Android, nor in the preview.
  bool get micChoosable =>
      !gated &&
      _controller != null &&
      (_recorder != null || _ownSound || TakeAudio.supported);

  /// Where the level meter beside Rec reads the microphone: the web's
  /// recorder, or the app on Android ([TakeSound.peak]); null where the
  /// camera records the sound (iOS, and Android's fallback): no meter.
  Future<double?> Function()? get level {
    if (gated || _controller == null) return null;
    if (_recorder case final recorder?) return recorder.peak;
    if (_ownSound) return TakeSound.peak;
    return null;
  }

  /// The input volume can be set (the level meter tapped): where the meter
  /// shows, between takes (a take keeps the volume it started with).
  bool get canSetGain => level != null && canRec && !_recording && !_starting;

  /// Takes record at the input volume set ([_gainDb]) from now on, and
  /// the level meter shows it.
  void _applyGain() {
    if (_recorder case final recorder?) {
      try {
        recorder.setGain(_gain);
      } on Object catch (e) {
        debugPrint('TabCam: cam: input volume: $e');
      }
    }
    if (_ownSound) unawaited(TakeSound.setGain(_gain));
  }

  /// The input volume is [db] dB from now on.
  void setGainDb(int db) {
    if (_disposed || db == _gainDb || !canSetGain) return;
    _gainDb = db;
    _changed();
    _applyGain();
  }

  /// Rec's menu can open: not while a take starts, records, is saved or
  /// plays, nor while a microphone opens.
  bool get canChooseMic =>
      micChoosable && canRec && !_recording && !_starting && !_micBusy;

  /// The microphones takes can record from here.
  Future<List<TakeMic>> microphones() async {
    if (_recorder case final recorder?) return recorder.microphones();
    if (_ownSound) return TakeSound.inputs();
    return TakeAudio.inputs();
  }

  /// Takes record from [id] from now on (null: the default): whether it
  /// opened.
  Future<bool> _useMic(String? id) async {
    if (_recorder case final recorder?) return recorder.useMicrophone(id);
    if (_ownSound) return TakeSound.choose(id);
    return TakeAudio.choose(id);
  }

  /// Takes record from microphone [id] (null: the default), named [name],
  /// from now on, kept in Cam's settings. One that won't open leaves the
  /// default open, and the default chosen.
  Future<void> chooseMic(String? id, String name) async {
    _micBusy = true;
    _changed();
    var opened = false;
    try {
      opened = await _useMic(id);
    } on Object catch (e) {
      debugPrint('TabCam: cam: microphone $id: $e');
    }
    if (_disposed) return;
    final failed = !opened && id != null;
    // The default open instead: told so, should it not be already.
    if (failed) unawaited(_useMic(null).catchError((Object _) => false));
    _micBusy = false;
    _mic = failed ? null : id;
    _changed();
    unawaited(saveSettings());
    if (failed) _note(CamNote.micFailed, name);
  }

  /// Whether a take records: what else runs makes way for it
  /// ([TakePriority]).
  void _takeRecording(bool recording) {
    TakePriority.recording.value = recording;
    _heads?.recording = recording;
  }

  /// Whether Cam is away: its view edits a take in the camera's place
  /// (`StudioView`). The camera stays open, but no frame goes to the head
  /// gestures meanwhile, and none turns the tab.
  bool get away => _away;
  bool _away = false;

  /// Cam goes away ([away]), its camera's frames no longer streamed, or
  /// comes back, streamed again for the head gestures (where they're on).
  Future<void> setAway(bool away) async {
    if (away == _away || _disposed) return;
    _away = away;
    _heads?.active = _headsOn && !away;
    if (!away) return _stream();
    final controller = _controller;
    if (controller != null &&
        controller.value.isStreamingImages &&
        !controller.value.isRecordingVideo) {
      try {
        await controller.stopImageStream();
      } on Object catch (e) {
        debugPrint('TabCam: head gestures: $e');
      }
      // Back meanwhile: streamed again.
      if (!_away && !_disposed) await _stream();
    }
  }

  /// With head gestures on, the camera's frames go to [_heads] (not while
  /// Cam is [away]).
  Future<void> _stream() async {
    final controller = _controller;
    if (_heads == null || !_headsOn || _away || controller == null) return;
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
    if (_headsOn && !_away) _heads?.onImage(image);
  }

  /// A nod or turn: the next neckline or the one before (not while a take
  /// plays: it turns them itself).
  void _gesture(HeadGesture gesture) {
    if (_disposed || !_headsOn || _away || _player != null) return;
    unawaited(pass(gesture == HeadGesture.next ? 1 : -1));
  }

  /// Head gestures on or off.
  Future<void> toggleHeads() async {
    _headsOn = !_headsOn;
    _changed();
    _heads?.active = _headsOn && !_away;
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
    _ when cameraNotReadable(e) => appL10n.camNotReadable,
    CameraException(:final description?) => appL10n.eventCameraFailed(
      description,
    ),
    _ => appL10n.eventCameraFailed('$e'),
  };

  /// Tab: hides the tab from the screen, or shows it again.
  void toggleTab() {
    _tabShown = !_tabShown;
    _changed();
  }

  /// Shows neckline [index] (kept in range); while recording, notes when.
  /// False when it was showing already.
  bool _show(int index) {
    if (_lines.isEmpty) return false;
    final line = index.clamp(0, _lines.length - 1);
    if (line == _line) return false;
    _line = line;
    _changed();
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
  Future<void> pass(int delta) async {
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
    if (_disposed) return;
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

  /// Cam's keys, for the screen's [Focus.onKeyEvent].
  KeyEventResult key(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent || gated) {
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
    // .: the song back at its start, the take thrown away and Rec again
    // (only the last is kept); /: Stop and Rec again here, both kept. Not
    // recording, Rec (. from the song's start). A key down (held, they
    // don't repeat), and nothing while a take is saved (or thrown away)
    // for the next, or can't be recorded.
    if (_alone(event, _retakeKeys, _retakePhysical)) {
      if (event is KeyDownEvent && canRec) {
        unawaited(nextTake(keep: false));
      }
      return KeyEventResult.handled;
    }
    if (_alone(event, _nextTakeKeys)) {
      if (event is KeyDownEvent && canRec) unawaited(nextTake());
      return KeyEventResult.handled;
    }
    // Space, 1, 0, ← and →, while the sidebar shows, are the backing
    // track's (play / pause, back to its start, « and »): [PlayAlongKeys]
    // gets them first. With no track showing, ← turns the tab back.
    unawaited(pass(_back.contains(key) ? -1 : 1));
    return KeyEventResult.handled;
  }

  /// The keys that throw the take away and start a new one from the
  /// song's start: ., on the main keyboard or the keypad.
  static final _retakeKeys = {
    LogicalKeyboardKey.period,
    LogicalKeyboardKey.numpadDecimal,
  };

  /// The keypad's decimal key, whatever it types: on the web, where it
  /// types "," (Brazilian, German and most European layouts), its logical
  /// key is the comma, not [LogicalKeyboardKey.numpadDecimal].
  static final _retakePhysical = {PhysicalKeyboardKey.numpadDecimal};

  /// The keys that save the take and start a new one: /, on the main
  /// keyboard or the keypad.
  static final _nextTakeKeys = {
    LogicalKeyboardKey.slash,
    LogicalKeyboardKey.numpadDivide,
  };

  /// Whether [event] is one of [keys] (or of the [physical] keys) pressed
  /// alone (with Ctrl, ⌘ or Alt it's another shortcut's, the browser's,
  /// and turns the tab as any key).
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
  bool get canRec =>
      _controller != null &&
      !_saving &&
      !_nextTaking &&
      _player == null &&
      _opening == null;

  /// Whether the sidebar's Delete (and a take's Edit) works: not while a
  /// take records, saves (or is saved for the next, until it starts) or
  /// plays back (or opens to).
  bool get canDelete =>
      !_recording &&
      !_saving &&
      !_nextTaking &&
      _player == null &&
      _opening == null;

  /// Rec: records a take, or, recording, stops and saves it.
  Future<void> rec() async {
    if (_recording) return stopRecording();
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
    await stopPlaying();
    var soundStarted = false;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      // Again, in case something changed it since Cam opened (cheap when
      // nothing did).
      await TakeAudio.prepare();
      _byRecorder = false;
      if (_recorder case final recorder?) {
        // No take without its sound (a microphone refused or missing):
        // the sound matters most.
        if (!await recorder.hasSound()) {
          debugPrint('TabCam: cam: no microphone, no take');
          if (!_disposed) _note(CamNote.noSound);
          unawaited(_stream());
          return;
        }
        // The recorder's take; failing that, the camera plugin's own, with
        // the microphone's sound (the web's camera has none).
        try {
          _startTiming();
          await recorder.start();
          _startReturn = _span.elapsed;
          _byRecorder = true;
        } on Object catch (e) {
          debugPrint('TabCam: cam: the camera records the take: $e');
          if (!await recorder.lendSoundToCamera()) {
            if (!_disposed) _note(CamNote.noSound);
            unawaited(_stream());
            return;
          }
        }
      }
      if (!_byRecorder) {
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
      if (!_disposed) _note(CamNote.couldntRecord, '$e');
      unawaited(_stream());
      return;
    }
    _clockZero = _span.elapsed;
    _takeStarted = _now();
    _recorderLag = _byRecorder ? _recorder?.msSinceStart() : null;
    // Not waited for: the clock starts now.
    _outRead = _readOutput();
    _soundLeadMs = null;
    _clock
      ..reset()
      ..start();
    _marks = [(Duration.zero, _line)];
    _unpassed = {};
    _takeRecording(true);
    if (!_disposed) {
      _recording = true;
      _startTicking();
      _changed();
    }
    // A song playing already plays on in the take from here.
    _songNotes = SongNotes();
    _noteSong();
    // The song in the sidebar's player starts with the take, from where
    // it is, after a count-in from the take's start (one under way counts
    // again from now), so every take opens with its breath before the
    // song; playing already, it plays on.
    if (!_disposed &&
        along.open &&
        _track.page != null &&
        !_track.loading &&
        !_track.playing) {
      unawaited(_track.playWithTake());
    }
  }

  /// The takes saved with a song noted, not measured yet: each one's song
  /// is found in its sound and kept with its log ([TakeSyncer]).
  final _unsynced = <(String, String)>[];

  void _syncTakes() {
    for (final (event, page) in _unsynced) {
      unawaited(TakeSyncer.sync(library, event, page));
    }
    _unsynced.clear();
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

  /// After a segment of the song starts, when it's read again
  /// ([_anchorSong]): at once, then once it surely sounds (a player says
  /// it plays a little before its sound starts, and its position stays
  /// at the start meanwhile), the last reading telling it best.
  static const _anchorAfter = [
    Duration.zero,
    Duration(milliseconds: 300),
    Duration(milliseconds: 1000),
  ];

  /// The readings [_anchorAfter] still to come.
  final _anchorTimers = <Timer>[];

  void _cancelAnchors() {
    for (final t in _anchorTimers) {
      t.cancel();
    }
    _anchorTimers.clear();
  }

  /// While recording, notes where the song playing along is now (the
  /// sidebar's player changed); a segment just started is told again from
  /// fresh readings of its player ([SongNotes.anchor]).
  void _noteSong() {
    final notes = _songNotes;
    if (notes == null || !_recording) return;
    final t = _clock.elapsed.inMilliseconds;
    if (_track.link?.playing ?? false) notes.noteLink();
    final media = _track.media;
    final page = media == null ? null : _track.page?.id;
    final v = media?.value;
    final started = notes.note(
      t,
      page: page,
      playing: v?.isPlaying ?? false,
      position: v?.position.inMilliseconds ?? 0,
      speed: v?.playbackSpeed ?? 1,
    );
    if (started && media != null && page != null) {
      final segment = notes.segment;
      _anchorTimers.removeWhere((t) => !t.isActive);
      for (final after in _anchorAfter) {
        if (after == Duration.zero) {
          unawaited(_anchorSong(notes, media, page, segment));
          continue;
        }
        _anchorTimers.add(
          Timer(after, () => _anchorSong(notes, media, page, segment)),
        );
      }
    }
  }

  /// Tells segment [segment] (of [page]) where it started, from where
  /// [media] says it is now: read halfway between asking and the answer.
  Future<void> _anchorSong(
    SongNotes notes,
    VideoPlayerController media,
    String page,
    int segment,
  ) async {
    try {
      if (!identical(notes, _songNotes) || _track.media != media) return;
      final asked = _clock.elapsed.inMicroseconds;
      final at = await media.position;
      final answered = _clock.elapsed.inMicroseconds;
      if (at == null || !identical(notes, _songNotes)) return;
      if (_track.media != media) return;
      notes.anchor(
        ((asked + answered) / 2000).round(),
        page: page,
        position: at.inMilliseconds,
        segment: segment,
      );
    } on Object catch (e) {
      debugPrint('TabCam: cam: where the song is isn\'t known: $e');
    }
  }

  /// The output the song plays through now (the web's recorder's word,
  /// iOS's audio session's, Android's); null when none can say. Never
  /// throws: a take is saved whatever this comes to.
  Future<TakeOutput?> _readOutput() async {
    try {
      if (_recorder case final recorder?) return await recorder.output();
      if (TakeAudio.supported) {
        return TakeOutput.fromReading(await TakeAudio.output());
      }
      if (TakeSound.supported) {
        return TakeOutput.fromReading(await TakeSound.output());
      }
    } on Object catch (e) {
      debugPrint('TabCam: cam: the audio output isn\'t known: $e');
    }
    return null;
  }

  /// The output read as the take started ([_outRead]), marked [changed]
  /// when it's another as it stopped (read again now).
  Future<TakeOutput?> _outputNoted() async {
    final read = _outRead;
    _outRead = null;
    var out = await (read ?? Future<TakeOutput?>.value());
    if (out == null) return null;
    final again = await _readOutput();
    if (again != null && !again.sameAs(out)) out = out.copyWith(changed: true);
    return out;
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

  /// The / key: while recording, a new take, cut here: the take so far is
  /// saved as Stop saves it, then Rec starts the next, the song in the
  /// sidebar playing on through both. The . key ([keep] false): the song
  /// stops at once, back at its start (its section's), the take is thrown
  /// away (only the next is kept), then Rec starts the next, and the song
  /// with it from its start (counting in, if that's on). Not recording, /
  /// is Rec, and . is Rec with the song back at its start.
  Future<void> nextTake({bool keep = true}) async {
    if (!_recording) {
      if (!keep) await _songBack();
      return rec();
    }
    _nextTaking = true;
    _changed();
    try {
      await (keep ? _songHeld() : _songBack());
      await stopRecording(keep: keep);
      // The take is kept (or gone) whether or not the next one starts.
      if (_disposed || _controller == null) return;
      await rec();
    } finally {
      if (!_disposed) {
        _nextTaking = false;
        _changed();
      }
    }
  }

  /// The song in the sidebar (when it shows) paused where it is, at a cut
  /// (the / key): the next take plays it on from there, after its own
  /// count-in, rather than it playing on while the take is saved (and
  /// the next one missing what played meanwhile).
  Future<void> _songHeld() async {
    if (!along.open || _track.page == null) return;
    try {
      await _track.pause();
    } on Object catch (e) {
      debugPrint('TabCam: cam: the song didn\'t pause: $e');
    }
  }

  /// The song in the sidebar (when it shows) stopped, back at its start
  /// (its section's): silent until the next take starts it again.
  Future<void> _songBack() async {
    if (!along.open || _track.page == null) return;
    try {
      await _track.stop();
    } on Object catch (e) {
      debugPrint('TabCam: cam: the song didn\'t stop: $e');
    }
  }

  /// Stops recording and adds the take to the capture; with [keep] false
  /// (the . key), throws it away instead: nothing is added, and its file
  /// is deleted from the device.
  Future<void> stopRecording({bool keep = true}) async {
    final controller = _controller;
    if (!_recording || controller == null) return;
    _recording = false;
    _saving = true;
    _clock.stop();
    _stopTicking();
    final length = _clock.elapsed;
    _cancelAnchors();
    final marks = _marks;
    final unpassed = _unpassed;
    final notes = _songNotes;
    _songNotes = null;
    final song = notes?.finish(length.inMilliseconds) ?? const [];
    _stoppedSong = song;
    _changed();
    try {
      XFile file;
      try {
        file = await (_byRecorder
            ? _timedStop(_recorder!.stop)
            : _ownSound
            ? (keep ? _stopWithSound(controller) : _stopNoSound(controller))
            : _timedStop(controller.stopVideoRecording));
      } finally {
        _takeRecording(false);
      }
      unawaited(_stream());
      if (!keep) {
        await discardTakeFile(file);
        if (!_disposed) _note(CamNote.discarded);
        return;
      }
      // The log: the tab's turns as they came, and the lag (on the phones,
      // with the file's length as recorded).
      final tab = _lines.isEmpty ? null : TakeTab.of(_lines, marks);
      final fileMs = _byRecorder || kIsWeb ? null : await mp4VideoMs(file);
      final lag = _lag(fileMs);
      final out = await _outputNoted();
      // iOS: an HEVC take made H.264, so every browser plays it.
      if (await TakeH264.needed(file)) file = await _toH264(file);
      // The tab isn't in the take's picture: the log keeps it, and the
      // editor draws it over the take.
      final log = TakeLog(
        burned: false,
        lagMs: lag.lagMs,
        lagFrom: lag.from,
        lagRaw: {...lag.raw, 'soundLeadMs': ?_soundLeadMs},
        out: out,
        tab: tab,
        song: song,
        songLink: notes?.link ?? false,
      );
      final known = Media.of(file);
      final media = known?.kind == PageKind.video
          ? known!
          : Media(file, PageKind.video, kIsWeb ? 'webm' : 'mp4');
      final event = library.byId(eventId);
      if (event == null) return;
      // Cam opens on the user's own copy of a capture shared with them
      // (the event screen makes it), so takes are always theirs; added to a
      // shared one, the take would go to their copy ([Library.copyToAdd]).
      final name = _takeName(_takeStarted);
      final updated = await library.addMedia(
        event,
        [media],
        take: true,
        takeLog: log,
      );
      final page = updated.pages.last;
      await library.renamePage(updated.id, page.id, name);
      // Played along later, the take turns the tab as it turned in it
      // while auto-pass was on (off all along: it has no passes).
      await library.setPhrases(
        updated.id,
        page.id,
        takePhrases(marks, skip: unpassed),
      );
      // Its row shows it, named, from the capture it went to.
      _setTake(
        library
                .byId(updated.id)
                ?.pages
                .where((p) => p.id == page.id)
                .firstOrNull ??
            page,
        event: updated.id,
        length: length,
      );
      if (tab != null) {
        _recordedPlaces = (page.id, TakeTab.placesOf(_lines, marks));
      }
      // Where its song really is, from its own sound: measured once no
      // take records (not between takes the / key runs on).
      if (log.linedSong.isNotEmpty) _unsynced.add((updated.id, page.id));
      if (!_nextTaking) _syncTakes();
      if (!_disposed) _note(CamNote.saved, name);
    } on Object catch (e, stack) {
      debugPrint('TabCam: cam: $e\n$stack');
      if (!_disposed) _note(CamNote.couldntRecord, '$e');
    } finally {
      await _track.savePhrases();
      if (!_disposed) {
        _saving = false;
        _changed();
      }
    }
  }

  /// Android, the take's sound recorded by the app: the camera stopped,
  /// then the sound, which goes into the camera's video in step with it
  /// ([TakeSound.stop]). Should that fail, the video is kept without
  /// sound, and a message says so: never a silent take unsaid.
  Future<XFile> _stopWithSound(CameraController controller) async {
    await TakeSound.videoStopping();
    final XFile video;
    try {
      video = await _timedStop(controller.stopVideoRecording);
    } on Object {
      unawaited(TakeSound.cancel());
      rethrow;
    }
    final (:take, :error, :warning, :leadMs) = await TakeSound.stop(video);
    _soundLeadMs = leadMs;
    if (!_disposed && error != null) _note(CamNote.takeNoSound, error);
    if (!_disposed && warning != null) _note(CamNote.soundWarning, warning);
    return take;
  }

  /// Android, the take's sound recorded by the app, the take thrown away:
  /// the camera stopped and the sound dropped ([TakeSound.cancel]), its
  /// file deleted, not put into the video.
  Future<XFile> _stopNoSound(CameraController controller) async {
    await TakeSound.videoStopping();
    try {
      return await _timedStop(controller.stopVideoRecording);
    } finally {
      await TakeSound.cancel();
    }
  }

  /// iOS: [take] made H.264 ([TakeH264.convert]); should that fail, the
  /// take as recorded, and a message says so (it may not play in every
  /// browser).
  Future<XFile> _toH264(XFile take) async {
    if (!_disposed) {
      _converting = true;
      _changed();
    }
    try {
      return await TakeH264.convert(take);
    } on Object catch (e) {
      debugPrint('TabCam: cam: the take wasn\'t made H.264: $e');
      final reason = e is PlatformException ? e.message ?? e.code : '$e';
      if (!_disposed) _note(CamNote.notH264, reason);
      return take;
    } finally {
      if (!_disposed) {
        _converting = false;
        _changed();
      }
    }
  }

  /// Plays the take back ([take]), or stops it; while it opens, lets it
  /// go ([_opening]).
  Future<void> play() async {
    if (_player != null) return stopPlaying();
    if (_opening != null) {
      _opening = null;
      _changed();
      return;
    }
    final take = _take;
    final event = library.byId(eventId);
    if (take == null || event == null) return;
    final opening = Object();
    _opening = opening;
    _changed();
    try {
      await _track.pause();
      // Mixed with others: else (iOS) it takes that from the app's audio
      // session, and the next take would stop a song playing in another
      // app (Android: it would take the audio focus from it).
      final player = await openPlayer(
        library,
        event,
        take,
        mixWithOthers: true,
      );
      // Left, or let go of (Play again) while it opened.
      if (_disposed || _opening != opening) {
        await player.dispose();
        return;
      }
      player.addListener(_follow);
      _opening = null;
      _player = player;
      _playedLog = take.takeLog;
      _playedPlaces = _placesFor(take);
      _changed();
      await player.play();
    } on Object catch (e) {
      debugPrint('TabCam: cam: $e');
      if (!_disposed && _opening == opening) {
        _note(CamNote.cantPlay);
      }
    } finally {
      if (!_disposed && _opening == opening) {
        _opening = null;
        _changed();
      }
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
          _line = line;
          _playedLine = null;
          _changed();
        } else if (line < 0 && text != _playedLine) {
          _playedLine = text;
          _changed();
        }
      }
    }
    if (v.isCompleted ||
        (v.duration > Duration.zero && at >= v.duration && !v.isPlaying)) {
      stopPlaying();
    }
  }

  /// Stops the take playing back (or lets go of the one opening): the
  /// camera again.
  Future<void> stopPlaying() async {
    if (_opening != null) {
      _opening = null;
      _changed();
    }
    final player = _player;
    if (player == null) return;
    player.removeListener(_follow);
    _playedLog = null;
    _playedPlaces = const [];
    if (!_disposed) {
      _player = null;
      _playedLine = null;
      _changed();
    }
    await player.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    TakePriority.recording.value = false;
    _syncTakes();
    if (!gated) {
      unawaited(TakeAudio.release());
      unawaited(TakeSound.release());
    }
    _autoPassTimer?.cancel();
    _elapsedTimer?.cancel();
    _elapsed.dispose();
    _cancelAnchors();
    _track.removeListener(_trackChanged);
    library.removeListener(_libraryChanged);
    unawaited(_track.savePhrases());
    along.dispose();
    _recorder?.dispose();
    _controller?.dispose();
    _heads?.dispose();
    _player?.removeListener(_follow);
    _player?.dispose();
    super.dispose();
  }
}
