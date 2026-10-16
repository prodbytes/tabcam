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
import '../screens/mono_font.dart';
import '../screens/video_page.dart';
import 'head_gestures.dart';
import 'media.dart';

/// Cam: the guitarist records themselves playing along with the capture's
/// tab. The camera (the front one first: it faces the player) fills the
/// screen, with the tab under it one neckline at a time ([necklines]).
/// Any key moves to the next neckline (a page-turner pedal, a keyboard);
/// Backspace, ← , ↑ and Page Up to the one before; a tap on the neckline
/// or its arrows too; on Android and iOS, a strong nod up or turn to the
/// right too, a nod down or turn to the left to the one before
/// ([HeadTracking]). **Rec** records (video and sound) until it's
/// tapped again, and adds the take to the capture as a video ("Take 1",
/// "Take 2"…). **Play** plays the last take back, the necklines turning
/// where they turned while it was recorded.
class PlayAlongScreen extends StatefulWidget {
  const PlayAlongScreen({
    super.key,
    required this.library,
    required this.eventId,
    this.cameras = availableCameras,
    this.headTracking = HeadTracking.start,
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

  @override
  void initState() {
    super.initState();
    _start();
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
    _heads?.camera = controller;
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
      // Its frames still go to the head gestures while it records.
      await controller.startVideoRecording(
        onAvailable: _heads == null ? null : _frame,
      );
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
      final file = await controller.stopVideoRecording();
      unawaited(_stream());
      final known = Media.of(file);
      final media = known?.kind == PageKind.video
          ? known!
          : Media(file, PageKind.video, kIsWeb ? 'webm' : 'mp4');
      final library = widget.library;
      final event = library.byId(widget.eventId);
      if (event == null) return;
      final names = {for (final p in event.pages) p.title};
      var n = 1;
      while (names.contains(l10n.camTake(n))) {
        n++;
      }
      final updated = await library.addMedia(event, [media]);
      final page = updated.pages.last;
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

  /// Plays the last take back, or stops it.
  Future<void> _play() async {
    if (_player != null) return _stopPlaying();
    final take = _take;
    final event = widget.library.byId(widget.eventId);
    if (take == null || event == null) return;
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

  @override
  void dispose() {
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
              if (_heads case final heads?)
                ValueListenableBuilder(
                  valueListenable: heads.face,
                  builder: (context, face, _) => IconButton(
                    key: const Key('cam-heads'),
                    tooltip: _headsOn ? l10n.camHeadsOn : l10n.camHeadsOff,
                    // On, green while it sees the user's face.
                    color: _headsOn && face ? Colors.greenAccent : null,
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
          body: Column(
            children: [
              Expanded(child: Center(child: _view())),
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
                        icon: _recording
                            ? Icons.stop
                            : Icons.fiber_manual_record,
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
          ),
        ),
      ),
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
