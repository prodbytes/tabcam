import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../screens/youtube_link.dart';
import 'link_frame_io.dart'
    if (dart.library.js_interop) 'link_frame_web.dart'
    as platform;

/// What a link frame is told to do.
enum LinkCommand { play, pause, stop, back, forward }

/// What a [linkFrameFor] shows, and its play / pause / stop where it can
/// be told: a YouTube video (its embedded player, over its iframe API's
/// messages), and on Android and iOS a page's first video or sound.
/// Another site's page on the web can't be: [canToggle] is false.
class LinkFrameController extends ChangeNotifier {
  LinkFrameController(this.url, {this.autoplay = true}) : _playing = autoplay;

  final Uri url;

  /// Whether a YouTube video starts playing as it loads (else paused).
  final bool autoplay;

  /// The YouTube video [url] is for, or null.
  late final String? youTubeId = youTubeVideoId(url);

  /// Whether it plays, as far as the app knows: it starts playing if
  /// [autoplay]; the user may also play or pause it in the frame itself.
  bool get playing => _playing;
  bool _playing;

  Future<void> Function(LinkCommand command)? _command;

  /// Set by the frame showing it: how to tell it what to do.
  set command(Future<void> Function(LinkCommand command)? command) {
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
    await command(_playing ? LinkCommand.play : LinkCommand.pause);
  }

  Future<void> pause() async {
    if (_playing) await toggle();
  }

  /// Pauses it, back at its start.
  Future<void> stop() async {
    final command = _command;
    if (command == null) return;
    _playing = false;
    notifyListeners();
    await command(LinkCommand.stop);
  }

  /// Goes [skipBy] forward (or back, [by] negative).
  Future<void> skip(Duration by) async {
    await _command?.call(
      by.isNegative ? LinkCommand.back : LinkCommand.forward,
    );
  }
}

/// How far the backing track's « and » go.
const skipBy = Duration(seconds: 10);

/// [controller]'s link in a frame: a YouTube video in its embedded
/// player, any other page as it is (an iframe on the web, a web view on
/// Android and iOS).
Widget linkFrameFor(LinkFrameController controller) =>
    platform.buildLinkFrame(controller);

/// YouTube's embedded player for [id] (checked by [youTubeVideoId]),
/// playing if [autoplay], its iframe API on, for [origin].
Uri youTubeEmbed(String id, String origin, {bool autoplay = true}) =>
    Uri.https('www.youtube-nocookie.com', '/embed/$id', {
      'enablejsapi': '1',
      'autoplay': autoplay ? '1' : '0',
      'playsinline': '1',
      'origin': origin,
    });

/// The iframe API's messages for [command]: stop pauses, then goes back
/// to the start; back and forward go [skipBy] from [at], the video's
/// time in seconds as it last said ([youTubeTime]).
List<String> youTubeCommands(LinkCommand command, {double at = 0}) =>
    switch (command) {
      LinkCommand.play => [_youTube('playVideo', '""')],
      LinkCommand.pause => [_youTube('pauseVideo', '""')],
      LinkCommand.stop => [
        _youTube('pauseVideo', '""'),
        _youTube('seekTo', '[0,true]'),
      ],
      LinkCommand.back || LinkCommand.forward => [
        _youTube(
          'seekTo',
          '[${_skipTo(at, command == LinkCommand.back)},true]',
        ),
      ],
    };

num _skipTo(double at, bool back) {
  final to = at + (back ? -1 : 1) * skipBy.inSeconds;
  return to < 0 ? 0 : to;
}

/// The message asking a YouTube embed to say how it plays (its
/// "infoDelivery" messages, with its current time).
const youTubeListening = '{"event":"listening","id":"tabcam"}';

/// The current time, in seconds, a YouTube embed's [message] says, or
/// null if it says none.
double? youTubeTime(Object? message) {
  if (message is! String || !message.contains('currentTime')) return null;
  try {
    final data = jsonDecode(message);
    if (data is! Map) return null;
    final time = (data['info'] as Map?)?['currentTime'];
    return time is num ? time.toDouble() : null;
  } on FormatException {
    return null;
  }
}

String _youTube(String func, String args) =>
    '{"event":"command","func":"$func","args":$args}';
