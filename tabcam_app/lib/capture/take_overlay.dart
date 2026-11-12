import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'edit_layers.dart';
import 'take_log.dart';
import 'take_priority.dart';
import 'web_take_recorder_stub.dart'
    if (dart.library.js_interop) 'web_take_recorder.dart';

export 'edit_layers.dart' show bandWidth, renderBand;
export 'take_log.dart' show TabBand, bandsOf;

/// Burns the tab into a take on Android and iOS, after it's recorded: the
/// platform's own video tools (Media3 Transformer; AVFoundation) put
/// each band along the bottom of the video while its neckline showed,
/// on the device. The web records the tab in as it goes instead
/// ([TakeRecorder]).
abstract final class TakeOverlay {
  static const _channel = MethodChannel('tabcam/take_overlay');

  /// Why the last [burn] gave nothing, for the message saying so.
  static String? lastError;

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
    lastError = null;
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
    } on PlatformException catch (e) {
      lastError = e.message ?? e.code;
      debugPrint('TabCam: cam: the tab wasn\'t burned in: $e');
      return null;
    } on Object catch (e) {
      lastError = '$e';
      debugPrint('TabCam: cam: the tab wasn\'t burned in: $e');
      return null;
    }
  }
}

/// Records a take with the tab in it as it goes, where the camera's own
/// recording can't have it added after (the web: [TakeOverlay] works on
/// Android and iOS).
abstract class TakeRecorder {
  /// Gets ready for takes when Cam opens (the web: opens the microphone,
  /// as [TakePriority.webMicConstraints], and keeps it open), so a take
  /// starts without waiting for it.
  Future<void> prepare();

  /// Whether a take would have sound: the microphone open (opened now if
  /// it isn't, which may ask the user), or the camera's own. Cam records
  /// no take without it: the take's sound matters most.
  Future<bool> hasSound();

  /// Should [start] fail, gives the camera's own recording (the take
  /// without the tab) the microphone's sound: the web's camera is opened
  /// without sound, so its stream gets the microphone's track. Whether the
  /// camera's stream has sound now.
  Future<bool> lendSoundToCamera();

  /// Starts recording the camera with the band for [neckline] (what shows
  /// now; null: none) along its bottom; returns once the recording has
  /// started (or, should it not say, soon after).
  Future<void> start(String? Function() neckline);

  /// How long ago the recording started, in ms, as of now (the web: the
  /// MediaRecorder's `start` event, on the page's clock); null when it
  /// isn't known. Cam reads it as the take's clock starts: the take's lag
  /// (`TakeLog.lagMs`).
  double? msSinceStart();

  /// The browser's; null elsewhere.
  static TakeRecorder? forPlatform() => webTakeRecorder();

  /// Stops, and gives the take.
  Future<XFile> stop();

  void dispose();
}
