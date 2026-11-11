import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'edit_formats.dart';
import 'render_plan.dart';
import 'web_video_editor_stub.dart'
    if (dart.library.js_interop) 'web_video_editor.dart';

export '../library/page_edit.dart' show EditSound, PageEdit, trackSpan;
export 'edit_formats.dart' show EditFormat, EditFormats;
export 'render_plan.dart';

/// Renders an edit's [RenderPlan] to a file, on the device.
abstract class VideoEditing {
  /// [plan] made into a new file (its input is left as it is): the video
  /// as edited, or its sound alone. [onProgress] gets how much is done, 0
  /// to 1, where that's known.
  Future<XFile> render(
    RenderPlan plan, {
    void Function(double done)? onProgress,
  });

  /// How long [file] (a video or sound file) is, where the player can't
  /// say (the browser, for a file it recorded itself: a take); null where
  /// the player knows.
  Future<Duration?> length(XFile file);

  /// The formats [render] makes here: the video's (MP4, or WebM in a
  /// browser that can't record MP4) and the sound's alone (M4A, or WAV in
  /// a browser that can't make AAC).
  Future<EditFormats> formats();
}

/// The video editor for this platform: the browser's ([webVideoEditor]),
/// or the platform's own video tools on Android and iOS
/// ([ChannelVideoEditor]); none elsewhere.
abstract final class VideoEditor {
  /// The editor here; null where videos can't be edited.
  static VideoEditing? get instance => _instance ??= _forPlatform();
  static VideoEditing? _instance;

  /// Tests put their own in.
  @visibleForTesting
  static set instance(VideoEditing? editor) => _instance = editor;

  static bool get supported => instance != null;

  static VideoEditing? _forPlatform() {
    if (kIsWeb) return webVideoEditor();
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return const ChannelVideoEditor();
    }
    return null;
  }
}

/// Renders a plan with the platform's own tools (Media3 Transformer on
/// Android, AVFoundation on iOS) over the method channel
/// `tabcam/video_edit`, method `render`, its arguments the plan's
/// ([RenderPlan.toChannel]): the input and output paths, whether the
/// picture goes in (`video`), the part kept in ms, the video's own sound
/// (`own`: its `volume`, 0 to 1; left out: none) and the song lane
/// (`song`: its `path`, `volume` and `clips`, each `atMs` in the output,
/// the song from `fromMs` to `toMs`, at `speed`), and `job`, which the
/// platform's `progress` calls back name, with `done` (0 to 1), every
/// quarter of a second while it renders. It replies with the output
/// path.
class ChannelVideoEditor implements VideoEditing {
  const ChannelVideoEditor();

  static const channel = MethodChannel('tabcam/video_edit');

  /// The renders under way, by job, and what their progress goes to.
  static final _progress = <int, void Function(double done)>{};
  static var _jobs = 0;
  static var _listening = false;

  static Future<Object?> _onCall(MethodCall call) async {
    if (call.method != 'progress') return null;
    final args = call.arguments;
    if (args is! Map) return null;
    final done = args['done'];
    if (done is! num || !done.isFinite) return null;
    _progress[args['job']]?.call(done.clamp(0, 1).toDouble());
    return null;
  }

  /// The platforms' players know every file's length.
  @override
  Future<Duration?> length(XFile file) async => null;

  /// H.264 and AAC in MP4; AAC in M4A for the sound alone.
  @override
  Future<EditFormats> formats() async => EditFormats.standard;

  @override
  Future<XFile> render(
    RenderPlan plan, {
    void Function(double done)? onProgress,
  }) async {
    if (plan.input == null) throw ArgumentError('A render needs its video');
    if (!plan.video && !plan.hasSound) {
      throw ArgumentError('A video without sound has no sound to save');
    }
    if (plan.song case final song? when song.file == null) {
      throw ArgumentError('A song lane needs a file');
    }
    final dir = await getTemporaryDirectory();
    final format = plan.video ? EditFormat.mp4 : EditFormat.m4a;
    final output =
        '${dir.path}/edit-${DateTime.now().millisecondsSinceEpoch}'
        '.${format.extension}';
    int? job;
    if (onProgress != null) {
      if (!_listening) {
        _listening = true;
        channel.setMethodCallHandler(_onCall);
      }
      job = ++_jobs;
      _progress[job] = onProgress;
    }
    try {
      final path = await channel.invokeMethod<String>(
        'render',
        plan.toChannel(output: output, job: job),
      );
      if (path == null) throw StateError('The video was not written');
      return XFile(path, mimeType: format.mimeType);
    } finally {
      _progress.remove(job);
    }
  }

  /// Lets go of the progress calls (tests swap the channel's handler).
  @visibleForTesting
  static void reset() {
    _listening = false;
    _progress.clear();
  }
}

/// [channels] (one or two, of samples from -1 to 1, all as long) as a
/// 16-bit PCM WAV file at [sampleRate].
Uint8List wavBytes(List<Float32List> channels, int sampleRate) {
  final count = channels.length;
  final frames = count == 0 ? 0 : channels.first.length;
  final data = frames * count * 2;
  final bytes = ByteData(44 + data);
  void text(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, 36 + data, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, count, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * count * 2, Endian.little);
  bytes.setUint16(32, count * 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, data, Endian.little);
  var at = 44;
  for (var f = 0; f < frames; f++) {
    for (final channel in channels) {
      final v = channel[f].clamp(-1.0, 1.0);
      bytes.setInt16(
        at,
        (v < 0 ? v * 0x8000 : v * 0x7fff).round(),
        Endian.little,
      );
      at += 2;
    }
  }
  return bytes.buffer.asUint8List();
}
