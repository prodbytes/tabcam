import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../export/capture_link.dart';

/// A YouTube video a link points to: its ID, and where to start (from
/// `t=` or `start=`, in seconds).
typedef YouTubeVideo = ({String id, int? start});

final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// The YouTube video [url] is for (`youtube.com/watch?v=…`, `youtu.be/…`,
/// `/shorts/…`, `/live/…`, `/embed/…`), or null for any other link.
YouTubeVideo? youTubeVideo(Uri url) {
  if (url.scheme != 'https' && url.scheme != 'http') return null;
  final host = url.host.toLowerCase();
  final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
  final String? id;
  if (host == 'youtu.be') {
    id = segments.firstOrNull;
  } else if (host == 'youtube.com' ||
      host.endsWith('.youtube.com') ||
      host == 'youtube-nocookie.com' ||
      host.endsWith('.youtube-nocookie.com')) {
    id = switch (segments) {
      ['watch'] => url.queryParameters['v'],
      ['shorts' || 'live' || 'embed' || 'v', final id, ...] => id,
      _ => null,
    };
  } else {
    id = null;
  }
  if (id == null || !_videoId.hasMatch(id)) return null;
  return (
    id: id,
    start: _seconds(url.queryParameters['t'] ?? url.queryParameters['start']),
  );
}

/// `90`, `90s` or `1m30s` as seconds; null if it's none of those.
int? _seconds(String? time) {
  if (time == null) return null;
  final match = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s?)?$')
      .firstMatch(time);
  if (match == null || time.isEmpty) return null;
  int part(int i) => int.parse(match.group(i) ?? '0');
  final seconds = part(1) * 3600 + part(2) * 60 + part(3);
  return seconds > 0 ? seconds : null;
}

/// Whether YouTube videos can play inside the app here: in the browser,
/// and in a web view on Android and iOS.
bool get canEmbedYouTube =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// YouTube's player for [video], playing; [onFailed] when it can't play
/// here for any reason: an error from the player (the video can't be
/// embedded, isn't found, …), the page not loading, or no player ready
/// in time.
class YouTubePlayerView extends StatefulWidget {
  const YouTubePlayerView({
    super.key,
    required this.video,
    required this.onFailed,
  });

  final YouTubeVideo video;
  final VoidCallback onFailed;

  /// How long the player may take to come up before giving up.
  static const timeout = Duration(seconds: 20);

  @override
  State<YouTubePlayerView> createState() => _YouTubePlayerViewState();
}

class _YouTubePlayerViewState extends State<YouTubePlayerView> {
  YoutubePlayerController? _controller;
  StreamSubscription<YoutubePlayerValue>? _values;
  Timer? _timeout;
  bool _failed = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // YouTube's controls in the app's language; captions as the viewer
    // set them on YouTube.
    final language = Localizations.localeOf(context).languageCode;
    try {
      final controller = YoutubePlayerController(
        params: YoutubePlayerParams(
          // The site, which YouTube asks embeds to identify themselves
          // by; the web build is its own origin.
          origin: kIsWeb ? null : CaptureLink.app.origin,
          interfaceLanguage: language,
          captionLanguage: language,
          enableCaption: false,
          showFullscreenButton: kIsWeb,
          strictRelatedVideos: true,
        ),
        onWebResourceError: (error) {
          if (error.isForMainFrame ?? true) _fail();
        },
      );
      _controller = controller;
      _values = controller.listen((value) {
        if (value.hasError) {
          _fail();
        } else if (value.playerState != PlayerState.unknown) {
          _timeout?.cancel();
        }
      });
      _timeout = Timer(YouTubePlayerView.timeout, _fail);
      unawaited(
        controller
            .loadVideoById(
              videoId: widget.video.id,
              startSeconds: widget.video.start?.toDouble(),
            )
            .catchError((_) => _fail()),
      );
    } catch (_) {
      // No web view here (or it couldn't start): the link it is.
      _controller = null;
      scheduleMicrotask(_fail);
    }
  }

  void _fail() {
    if (_failed || !mounted) return;
    _failed = true;
    _timeout?.cancel();
    widget.onFailed();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    unawaited(_values?.cancel());
    unawaited(_controller?.close().catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch (_controller) {
    final controller? => YoutubePlayer(
      controller: controller,
      autoFullScreen: false,
      enableFullScreenOnVerticalDrag: false,
    ),
    null => const AspectRatio(aspectRatio: 16 / 9),
  };
}
