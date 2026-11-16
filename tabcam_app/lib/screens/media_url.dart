import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../capture/video_edit.dart';
import 'media_url_stub.dart' if (dart.library.js_interop) 'media_url_web.dart';

/// A player for a video or recording held in memory (the web: the library
/// is in memory there), initialized, not playing yet. The browser plays it
/// from a blob URL of the bytes (made in no time, and let go when the
/// player is), not a data URL (the whole file written out as base64,
/// which a long video makes slow and heavy). On the web, a file the
/// browser recorded (a take, a recording: MediaRecorder writes no length)
/// gets its length from the editor ([VideoEditing.length]), so the player
/// seeks in it ([knowLength]).
Future<VideoPlayerController> openBytesPlayer(
  Uint8List bytes,
  String mimeType, {
  VideoPlayerOptions? options,
}) async {
  final url = mediaUrl(bytes, mimeType);
  final controller = _BytesPlayerController(url, options);
  try {
    await controller.initialize();
  } on Object {
    await controller.dispose();
    rethrow;
  }
  if (kIsWeb && controller.value.duration <= Duration.zero) {
    try {
      final length = await VideoEditor.instance?.length(
        XFile.fromData(bytes, mimeType: mimeType),
      );
      if (length != null) knowLength(controller, length);
    } on Object catch (e) {
      debugPrint('TabCam: video: no length: $e');
    }
  }
  return controller;
}

/// Tells [player], which can't say how long its file is, that it's
/// [length] long. The browser's player says a file it recorded is
/// endless (video_player_web's unset duration, far below zero), and
/// video_player keeps every seek within the length it has: until told,
/// each seek goes to that, not where it was asked (the editor's timeline
/// and Play, a take's playback, stuck at its start).
void knowLength(VideoPlayerController player, Duration length) {
  if (length <= Duration.zero || player.value.duration > Duration.zero) return;
  player.value = player.value.copyWith(duration: length);
}

/// A player on a URL made for it, let go with the player.
class _BytesPlayerController extends VideoPlayerController {
  _BytesPlayerController(this.url, VideoPlayerOptions? options)
    : super.networkUrl(Uri.parse(url), videoPlayerOptions: options);

  final String url;

  @override
  Future<void> dispose() async {
    await super.dispose();
    releaseMediaUrl(url);
  }
}
