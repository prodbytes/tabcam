import 'dart:math';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../screens/mono_font.dart';
import 'web_take_recorder_stub.dart'
    if (dart.library.js_interop) 'web_take_recorder.dart';

/// A neckline in a take: which one ([line]), from [start] to [end] (null:
/// to the end of the take).
@immutable
class TabBand {
  const TabBand(this.line, this.start, [this.end]);

  final int line;
  final Duration start;
  final Duration? end;

  @override
  bool operator ==(Object other) =>
      other is TabBand &&
      other.line == line &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(line, start, end);

  @override
  String toString() => 'TabBand($line, $start, $end)';
}

/// When each neckline showed in a take, from the times the tab moved
/// ([marks]: when, and to which neckline, the first at the start): one
/// band per neckline shown, each until the next.
List<TabBand> bandsOf(List<(Duration, int)> marks) {
  final bands = <TabBand>[];
  for (final (i, (start, line)) in marks.indexed) {
    // Moved twice at once: only the last counts.
    final end = i + 1 < marks.length ? marks[i + 1].$1 : null;
    if (end != null && end <= start) continue;
    // Back to the neckline showing: the same band goes on.
    if (bands.lastOrNull case final last? when last.line == line) {
      bands[bands.length - 1] = TabBand(line, last.start, end);
      continue;
    }
    bands.add(TabBand(line, start, end));
  }
  return bands;
}

/// How wide a band is drawn, in pixels; the video scales it to its own
/// width.
const int bandWidth = 1280;

/// [neckline] drawn as a band to put along the bottom of a take: white
/// monospaced text on a dark, see-through background, as wide as
/// [width], its text as big as fits (a long staff gets smaller). PNG.
Future<Uint8List> renderBand(String neckline, {int width = bandWidth}) async {
  final pad = width / 40;
  TextPainter painter(double size) => TextPainter(
    text: TextSpan(
      text: neckline,
      style: TextStyle(
        fontFamily: monoFont,
        fontSize: size,
        height: 1.2,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  // Measured at 100, then sized to fit (never bigger than width / 24).
  final probe = painter(100);
  final fit = probe.width <= 0 ? 100.0 : 100 * (width - 2 * pad) / probe.width;
  probe.dispose();
  final text = painter(min(fit, width / 24));
  final height = (text.height + 2 * pad).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xB3000000),
  );
  text.paint(canvas, Offset((width - text.width) / 2, pad));
  text.dispose();
  final image = await recorder.endRecording().toImage(width, height);
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Burns the tab into a take on Android and iOS, after it's recorded: the
/// platform's own video tools (Media3 Transformer; AVFoundation) put
/// each band along the bottom of the video while its neckline showed,
/// on the device. The web records the tab in as it goes instead
/// ([TakeRecorder]).
abstract final class TakeOverlay {
  static const _channel = MethodChannel('tabcam/take_overlay');

  /// Whether takes are burned here (Android, iOS).
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// [take] with [bands] (their PNGs, [renderBand]) burned in: a new MP4;
  /// null when it can't be done (the take is then kept as it is).
  static Future<XFile?> burn(
    XFile take,
    List<(TabBand, Uint8List)> bands,
  ) async {
    if (!supported || bands.isEmpty) return null;
    try {
      final dir = await getTemporaryDirectory();
      final output =
          '${dir.path}/take-${DateTime.now().millisecondsSinceEpoch}.mp4';
      final path = await _channel.invokeMethod<String>('burn', {
        'input': take.path,
        'output': output,
        'bands': [
          for (final (band, png) in bands)
            {
              'startMs': band.start.inMilliseconds,
              'endMs': band.end?.inMilliseconds,
              'png': png,
            },
        ],
      });
      return path == null ? null : XFile(path, mimeType: 'video/mp4');
    } on Object catch (e) {
      debugPrint('TabCam: cam: the tab wasn\'t burned in: $e');
      return null;
    }
  }
}

/// Records a take with the tab in it as it goes, where the camera's own
/// recording can't have it added after (the web: [TakeOverlay] works on
/// Android and iOS).
abstract class TakeRecorder {
  /// Starts recording the camera with the band for [neckline] (what shows
  /// now; null: none) along its bottom.
  Future<void> start(String? Function() neckline);

  /// The browser's; null elsewhere.
  static TakeRecorder? forPlatform() => webTakeRecorder();

  /// Stops, and gives the take.
  Future<XFile> stop();

  void dispose();
}
