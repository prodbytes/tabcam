import 'dart:typed_data';

import 'package:video_player/video_player.dart';

import 'media_url_stub.dart' if (dart.library.js_interop) 'media_url_web.dart';

/// A player for a video or recording held in memory (the web: the library
/// is in memory there), initialized, not playing yet. The browser plays it
/// from a blob URL of the bytes (made in no time, and let go when the
/// player is), not a data URL (the whole file written out as base64,
/// which a long video makes slow and heavy).
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
  return controller;
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
