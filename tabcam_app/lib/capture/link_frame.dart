import 'dart:async';

import 'package:flutter/widgets.dart';

import '../screens/youtube_link.dart';
import 'link_frame_io.dart'
    if (dart.library.js_interop) 'link_frame_web.dart'
    as platform;

/// What a [linkFrameFor] shows, and its play / pause where it can be told:
/// a YouTube video (its embedded player, over its iframe API's messages),
/// and on Android and iOS a page's first video or sound. Another site's
/// page on the web can't be: [canToggle] is false.
class LinkFrameController extends ChangeNotifier {
  LinkFrameController(this.url);

  final Uri url;

  /// The YouTube video [url] is for, or null.
  late final String? youTubeId = youTubeVideoId(url);

  /// Whether it plays, as far as the app knows: it starts playing; the
  /// user may also pause it in the frame itself.
  bool get playing => _playing;
  bool _playing = true;

  Future<void> Function(bool play)? _command;

  /// Set by the frame showing it: how to play (true) or pause it.
  set command(Future<void> Function(bool play)? command) {
    _command = command;
    // Set while the frame builds or goes: said after it.
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool get canToggle => _command != null;

  Future<void> toggle() async {
    final command = _command;
    if (command == null) return;
    _playing = !_playing;
    notifyListeners();
    await command(_playing);
  }

  Future<void> pause() async {
    if (_playing) await toggle();
  }
}

/// [controller]'s link in a frame: a YouTube video in its embedded
/// player, any other page as it is (an iframe on the web, a web view on
/// Android and iOS).
Widget linkFrameFor(LinkFrameController controller) =>
    platform.buildLinkFrame(controller);

/// YouTube's embedded player for [id] (checked by [youTubeVideoId]),
/// playing, its iframe API on, for [origin].
Uri youTubeEmbed(String id, String origin) => Uri.https(
  'www.youtube-nocookie.com',
  '/embed/$id',
  {'enablejsapi': '1', 'autoplay': '1', 'playsinline': '1', 'origin': origin},
);

/// The iframe API's message playing (true) or pausing the video.
String youTubeCommand(bool play) =>
    '{"event":"command","func":"${play ? 'playVideo' : 'pauseVideo'}","args":""}';
