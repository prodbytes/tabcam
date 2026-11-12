import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'video_edit.dart' show ChannelVideoEditor;

/// iOS: a take that plays in every browser. The camera plugin
/// (camera_avfoundation) writes a take as an MP4 in the codec the device
/// recommends: H.264, or HEVC, which Chrome and Firefox don't play
/// everywhere. As Cam saves a take, it asks for its codec ([needed]): an
/// H.264 take is saved as it is; any other is made H.264 once
/// ([convert]: AVFoundation, on the device, its sound kept, nothing drawn
/// on it). Method channel `tabcam/video_edit`, methods `codec` and `h264`
/// (ios/Runner/AppDelegate.swift). Elsewhere it does nothing: Android's
/// camera writes H.264, and the web's takes are what its browser records.
abstract final class TakeH264 {
  static const MethodChannel channel = ChannelVideoEditor.channel;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// The four letters naming H.264 in an MP4 (`avc1`); HEVC is `hvc1`.
  static const h264 = 'avc1';

  /// Whether [take] is to be made H.264: its video's codec is told, and
  /// isn't H.264. False where it isn't [supported], or the codec can't be
  /// told (it's then saved as it is).
  static Future<bool> needed(XFile take) async {
    if (!supported) return false;
    try {
      final codec = await channel.invokeMethod<String>('codec', {
        'input': take.path,
      });
      debugPrint('TabCam: cam: the take\'s codec: $codec');
      return codec != null && codec != h264;
    } on Object catch (e) {
      debugPrint('TabCam: cam: the take\'s codec unknown: $e');
      return false;
    }
  }

  /// [take] made H.264 (its sound kept as it is): a new MP4 in the
  /// temporary folder. Throws when it can't be.
  static Future<XFile> convert(XFile take) async {
    final dir = await getTemporaryDirectory();
    final output =
        '${dir.path}/take-h264-${DateTime.now().millisecondsSinceEpoch}.mp4';
    final path = await channel.invokeMethod<String>('h264', {
      'input': take.path,
      'output': output,
    });
    if (path == null) throw StateError('no file came back');
    return XFile(path, mimeType: 'video/mp4');
  }
}
