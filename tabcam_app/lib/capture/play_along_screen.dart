import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../l10n/language.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import '../recognition/necklines.dart';
import '../screens/file_screen.dart';
import '../screens/mono_font.dart';
import '../screens/video_page.dart';
import '../screens/youtube_link.dart';
import 'backing_track.dart';
import 'head_gestures.dart';
import 'link_frame.dart';
import 'media.dart';
import 'take_overlay.dart';

/// Cam: the guitarist records themselves playing along with the capture's
/// tab. The camera (the front one first: it faces the player) fills the
/// screen, with the tab under it one neckline at a time ([necklines]).
/// Any key moves to the next neckline (a page-turner pedal, a keyboard);
/// Backspace, ← , ↑ and Page Up to the one before; a tap on the neckline
/// or its arrows too; on Android, iOS and the web, a strong nod up or turn
/// to the right too, a nod down or turn to the left to the one before
/// ([HeadTracking]). **Rec** records (video and sound) until it's
/// tapped again, and adds the take to the capture as a video ("Take 1",
/// "Take 2"…). **Play** plays the last take back, the necklines turning
/// where they turned while it was recorded.
///
/// **Play along** (the app bar's, when the capture has recordings, videos
/// or links) shows and hides a sidebar of them, open from the first time
/// there's one (when Cam opens, or when one arrives later): the
/// one tapped plays in a compact frame at the sidebar's top, above the
/// list ([BackingTrack]), while the user plays and records; the space bar
/// pauses and plays it.
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
  });

  final Library library;
  final String eventId;

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

  @override
  State<PlayAlongScreen> createState() => _PlayAlongScreenState();
}

class _PlayAlongScreenState extends State<PlayAlongScreen> {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _camera = 0;
  String? _error;

  late final List<String> _lines = necklines(
    widget.library.byId(widget.eventId)?.tabText ?? '',
  );
  int _line = 0;

  /// While recording: when it started, and when each neckline showed.
  final _clock = Stopwatch();
  List<(Duration, int)> _marks = [];
  bool _recording = false;
  bool _saving = false;

  /// The last take, and when its necklines showed.
  EventPage? _take;
  List<(Duration, int)> _takeMarks = const [];
  VideoPlayerController? _player;

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

  /// What plays along, and whether the sidebar to choose it shows.
  late final BackingTrack _track = BackingTrack(widget.library);
  bool _sidebar = false;

  /// Whether the sidebar has opened by itself yet: it does once, the
  /// first time the capture has something to play along with.
  bool _alongOpened = false;

  /// The keys' focus, taken back after a tap in the sidebar or the frame.
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _start();
    _openAlong();
    widget.library.addListener(_libraryChanged);
  }

  /// Opens the sidebar with the capture's first recording, video or link
  /// loaded, paused, the first time there is one: when Cam opens, or when
  /// one arrives later (a sync, a take). With none, it stays hidden; hidden
  /// by the user, it isn't opened again.
  void _openAlong() {
    if (_alongOpened) return;
    final event = widget.library.byId(widget.eventId);
    final first = event?.pages.where(BackingTrack.plays).firstOrNull;
    if (event == null || first == null) return;
    _alongOpened = true;
    _sidebar = true;
    if (_track.page == null) {
      unawaited(_track.choose(event, first, play: false));
    }
  }

  void _libraryChanged() {
    if (_alongOpened || !mounted) return;
    setState(_openAlong);
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
    setState(() => _controller = controller);
    _heads ??= widget.headTracking(controller, _gesture);
    _heads
      ?..camera = controller
      ..active = _headsOn;
    await _stream();
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
    _show(_line + (gesture == HeadGesture.next ? 1 : -1));
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

  void _snack(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  /// Shows neckline [index] (kept in range); while recording, notes when.
  void _show(int index) {
    if (_lines.isEmpty) return;
    final line = index.clamp(0, _lines.length - 1);
    if (line == _line) return;
    setState(() => _line = line);
    if (_recording) _marks.add((_clock.elapsed, line));
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
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_modifiers.contains(key)) return KeyEventResult.ignored;
    // Space: the backing track's play / pause, while its sidebar shows.
    if (key == LogicalKeyboardKey.space && _sidebar && _track.page != null) {
      if (event is KeyDownEvent) unawaited(_track.toggle());
      return KeyEventResult.handled;
    }
    _show(_line + (_back.contains(key) ? -1 : 1));
    return KeyEventResult.handled;
  }

  Future<void> _rec() async {
    if (_recording) return _stopRecording();
    final controller = _controller;
    if (controller == null || _saving) return;
    await _stopPlaying();
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      _recordingTab = false;
      if (_recorder case final recorder?) {
        // The tab recorded in as it goes; failing that, the camera alone.
        try {
          await recorder.start(() => _lines.isEmpty ? null : _lines[_line]);
          _recordingTab = true;
        } on Object catch (e) {
          debugPrint('TabCam: cam: recording without the tab: $e');
          if (mounted) _snack(context.l10n.camRecordingNoTab('$e'));
        }
      }
      if (!_recordingTab) {
        // Its frames still go to the head gestures while it records (not
        // on the web: it streams none, and the tracker reads the preview).
        await controller.startVideoRecording(
          onAvailable: _heads == null || !controller.supportsImageStreaming()
              ? null
              : _frame,
        );
      }
    } on Object catch (e) {
      debugPrint('TabCam: cam: $e');
      if (mounted) _snack(context.l10n.camCouldntRecord('$e'));
      return;
    }
    _clock
      ..reset()
      ..start();
    _marks = [(Duration.zero, _line)];
    if (mounted) setState(() => _recording = true);
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
    try {
      var file = await (_recordingTab
          ? _recorder!.stop()
          : controller.stopVideoRecording());
      unawaited(_stream());
      if (!_recordingTab && _lines.isNotEmpty && TakeOverlay.supported) {
        file = await _burn(file, marks) ?? file;
      }
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
      final updated = await library.addMedia(event, [media]);
      final page = Library.addedPages(updated).last;
      final name = l10n.camTake(n);
      await library.renamePage(event.id, page.id, name);
      _take = page;
      _takeMarks = marks;
      if (mounted) _snack(l10n.camSaved(name));
    } on Object catch (e, stack) {
      debugPrint('TabCam: cam: $e\n$stack');
      if (mounted) _snack(l10n.camCouldntRecord('$e'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// [take] with the tab burned in where it showed ([marks]); null when it
  /// couldn't be (the take is kept as it is, and a message says so).
  Future<XFile?> _burn(XFile take, List<(Duration, int)> marks) async {
    final l10n = context.l10n;
    setState(() => _burning = true);
    try {
      final pngs = <int, Uint8List>{};
      final bands = <(TabBand, Uint8List)>[];
      for (final band in bandsOf(marks)) {
        final png = pngs[band.line] ??= await renderBand(_lines[band.line]);
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

  /// Plays the last take back, or stops it.
  Future<void> _play() async {
    if (_player != null) return _stopPlaying();
    final take = _take;
    final event = widget.library.byId(widget.eventId);
    if (take == null || event == null) return;
    await _track.pause();
    try {
      final player = await openPlayer(widget.library, event, take);
      if (!mounted) {
        await player.dispose();
        return;
      }
      player.addListener(_follow);
      setState(() => _player = player);
      await player.play();
    } on Object catch (e) {
      debugPrint('TabCam: cam: $e');
      if (mounted) _snack(context.l10n.textViewCantPlay);
    }
  }

  /// While a take plays: the neckline that showed then; at its end, the
  /// camera again.
  void _follow() {
    final player = _player;
    if (player == null) return;
    final v = player.value;
    final at = v.position;
    var line = _line;
    for (final (time, index) in _takeMarks) {
      if (time > at) break;
      line = index;
    }
    if (line != _line) setState(() => _line = line);
    if (v.isCompleted ||
        (v.duration > Duration.zero && at >= v.duration && !v.isPlaying)) {
      _stopPlaying();
    }
  }

  Future<void> _stopPlaying() async {
    final player = _player;
    if (player == null) return;
    player.removeListener(_follow);
    if (mounted) setState(() => _player = null);
    await player.dispose();
  }

  /// Back while recording: the take is saved, then the screen closes.
  Future<void> _leave() async {
    await _stopRecording();
    if (mounted) Navigator.pop(context);
  }

  /// Shows or hides the sidebar; hidden, what plays along pauses.
  void _toggleSidebar() {
    _alongOpened = true;
    setState(() => _sidebar = !_sidebar);
    if (!_sidebar) unawaited(_track.pause());
  }

  /// Plays [page] along (or pauses it, chosen again).
  Future<void> _choose(EventPage page) async {
    _focus.requestFocus();
    final event = widget.library.byId(widget.eventId);
    if (event == null) return;
    await _track.choose(event, page);
  }

  @override
  void dispose() {
    widget.library.removeListener(_libraryChanged);
    _track.dispose();
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
      _ => const CircularProgressIndicator(),
    };
  }

  /// The tab, one neckline, along the bottom.
  Widget _neckline() {
    final l10n = context.l10n;
    const color = Colors.white;
    if (_lines.isEmpty) {
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
          onPressed: _line > 0 ? () => _show(_line - 1) : null,
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _show(_line + 1),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // As wide as the screen: a long staff shrinks to fit.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _lines[_line],
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
                  const SizedBox(height: 4),
                  Text(
                    '${_line + 1} / ${_lines.length}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
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
          onPressed: _line < _lines.length - 1 ? () => _show(_line + 1) : null,
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
    return PopScope(
      // Leaving while recording keeps the take.
      canPop: !_recording && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _leave();
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
              if (event?.pages.any(BackingTrack.plays) ?? false)
                IconButton(
                  key: const Key('cam-along'),
                  tooltip: _sidebar ? l10n.camAlongHide : l10n.camAlong,
                  isSelected: _sidebar,
                  color: _sidebar
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  icon: const Icon(Icons.queue_music),
                  onPressed: _toggleSidebar,
                ),
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
                  onPressed: _recording || _saving
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
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _main(controller, playing)),
              // Hidden, it's kept (offstage): a link's page isn't reloaded.
              if (event?.pages.any(BackingTrack.plays) ?? false)
                Offstage(
                  offstage: !_sidebar,
                  child: _Sidebar(
                    library: widget.library,
                    eventId: widget.eventId,
                    track: _track,
                    linkFrame: widget.linkFrame,
                    onChoose: _choose,
                    onStop: () {
                      _focus.requestFocus();
                      _track.stop();
                    },
                    onToggle: () {
                      _focus.requestFocus();
                      _track.toggle();
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The camera, the neckline and Rec and Play.
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
                        Text(
                          l10n.camAddingTab,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        ColoredBox(color: Colors.black87, child: _neckline()),
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
                  onPressed: controller == null || _saving || playing
                      ? null
                      : _rec,
                ),
                _Control(
                  key: const Key('cam-play'),
                  icon: playing ? Icons.stop : Icons.play_arrow,
                  color: Colors.white,
                  label: playing ? l10n.camStop : l10n.camPlay,
                  onPressed: _take == null || _recording || _saving
                      ? null
                      : _play,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Rec or Play: an icon over its label, on black.
class _Control extends StatelessWidget {
  const _Control({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: label,
          iconSize: 36,
          color: color,
          disabledColor: Colors.white24,
          icon: Icon(icon),
          onPressed: onPressed,
        ),
        Text(
          label,
          style: TextStyle(color: on ? Colors.white : Colors.white38),
        ),
      ],
    );
  }
}

/// The backing track's frame, compact, at the top of the sidebar and as
/// wide: the video or link playing (a recording shows its progress only),
/// its name, play / pause and stop. Nothing while there's none.
class _BackingFrame extends StatelessWidget {
  const _BackingFrame({
    required this.eventId,
    required this.track,
    required this.linkFrame,
    required this.onToggle,
    required this.onStop,
  });

  final String eventId;
  final BackingTrack track;
  final Widget Function(LinkFrameController controller) linkFrame;
  final VoidCallback onToggle;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: track,
    builder: (context, _) {
      final page = track.page;
      if (page == null) return const SizedBox.shrink();
      final l10n = context.l10n;
      final event = track.library.byId(eventId);
      final media = track.media;
      final link = track.link;
      // As wide as the sidebar, at most a third of the screen's height.
      final maxHeight = MediaQuery.sizeOf(context).height / 3;
      final Widget? content = switch ((media, link)) {
        _ when track.error != null => Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            page.isAudio ? l10n.textViewCantPlayAudio : l10n.textViewCantPlay,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        (final media?, _) when page.isVideo || media.value.size.width > 0 =>
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: AspectRatio(
              aspectRatio: media.value.aspectRatio,
              child: VideoPlayer(media),
            ),
          ),
        // 16:9, a YouTube video's shape.
        (_, final link?) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: AspectRatio(aspectRatio: 16 / 9, child: linkFrame(link)),
        ),
        _ => null,
      };
      const compact = VisualDensity(horizontal: -4, vertical: -4);
      return ColoredBox(
        key: const Key('cam-along-frame'),
        color: Colors.black,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (content != null) Center(child: content),
            if (media != null)
              VideoProgressIndicator(
                media,
                allowScrubbing: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  Icon(_icon(page), color: Colors.white70, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      event == null ? '' : fileLabel(l10n, event, page),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 40,
              child: track.loading
                  ? const Center(
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (track.canToggle) ...[
                          IconButton(
                            key: const Key('cam-along-toggle'),
                            tooltip: track.playing
                                ? l10n.camAlongPause
                                : l10n.camAlongPlay,
                            visualDensity: compact,
                            color: Colors.white,
                            icon: Icon(
                              track.playing ? Icons.pause : Icons.play_arrow,
                            ),
                            onPressed: onToggle,
                          ),
                          IconButton(
                            key: const Key('cam-along-stop'),
                            tooltip: l10n.camAlongStop,
                            visualDensity: compact,
                            color: Colors.white,
                            icon: const Icon(Icons.stop),
                            onPressed: onStop,
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      );
    },
  );
}

/// The sidebar: the backing track's frame at its top, always there, and
/// under it the capture's recordings, videos and links, the one playing
/// along marked; a tap plays one along.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.library,
    required this.eventId,
    required this.track,
    required this.linkFrame,
    required this.onChoose,
    required this.onToggle,
    required this.onStop,
  });

  final Library library;
  final String eventId;
  final BackingTrack track;
  final Widget Function(LinkFrameController controller) linkFrame;
  final void Function(EventPage page) onChoose;
  final VoidCallback onToggle;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = MediaQuery.sizeOf(context).width;
    return SizedBox(
      key: const Key('cam-along-sidebar'),
      // A third of a phone held upright; at most 280 px.
      width: (width * 0.4).clamp(120.0, 280.0),
      child: Material(
        color: const Color(0xFF1C1C1C),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BackingFrame(
              eventId: eventId,
              track: track,
              linkFrame: linkFrame,
              onToggle: onToggle,
              onStop: onStop,
            ),
            Expanded(child: _list(context, l10n)),
          ],
        ),
      ),
    );
  }

  /// The files to play along, under the frame.
  Widget _list(BuildContext context, AppLocalizations l10n) =>
      ListenableBuilder(
        listenable: Listenable.merge([library, track]),
        builder: (context, _) {
          final event = library.byId(eventId);
          final pages = [...?event?.pages.where(BackingTrack.plays)];
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  l10n.camAlongTitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              for (final page in pages)
                ListTile(
                  key: ValueKey('cam-along-${page.id}'),
                  dense: true,
                  selected: track.page?.id == page.id,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  textColor: Colors.white,
                  iconColor: Colors.white70,
                  leading: Icon(_icon(page)),
                  title: Text(
                    fileLabel(l10n, event!, page),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: track.page?.id == page.id && track.playing
                      ? const Icon(Icons.graphic_eq, size: 18)
                      : null,
                  onTap: () => onChoose(page),
                ),
            ],
          );
        },
      );
}

/// A recording's, video's or link's icon (a YouTube video's as a video).
IconData _icon(EventPage page) => switch (page) {
  EventPage(isAudio: true) => Icons.audiotrack,
  EventPage(isVideo: true) => Icons.movie_outlined,
  EventPage(:final url?) when youTubeVideoId(url) != null =>
    Icons.smart_display_outlined,
  _ => Icons.link,
};
