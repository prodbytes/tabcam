import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../library/library.dart';
import '../library/capture_event.dart';
import '../l10n/language.dart';

/// A video page: a play button until tapped, then the video, with a play /
/// pause button and tap to pause and resume. It plays from the page's file
/// (from memory on the web), and is let go when the page scrolls away.
class VideoPage extends StatefulWidget {
  const VideoPage({
    super.key,
    required this.library,
    required this.event,
    required this.page,
  });

  final Library library;
  final CaptureEvent event;
  final EventPage page;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  VideoPlayerController? _controller;
  Object? _error;
  bool _loading = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _loading = true);
    try {
      final controller = await openPlayer(
        widget.library,
        widget.event,
        widget.page,
      );
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle() {
    final c = _controller!;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return _Poster(
        icon: Icons.error_outline,
        label: context.l10n.textViewCantPlay,
      );
    }
    if (controller == null) {
      return _loading
          ? const Center(child: CircularProgressIndicator())
          : _Poster(
              icon: Icons.play_circle_fill,
              label: context.l10n.textViewVideo,
              onTap: _start,
            );
    }
    return GestureDetector(
      onTap: _toggle,
      child: Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              VideoPlayer(controller),
              Material(
                color: Colors.black45,
                child: Row(
                  children: [
                    PlayPauseButton(controller, color: Colors.white),
                    Expanded(
                      child: VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A player for [page]'s file: from the device's copy, or from memory on
/// the web. Initialized, not playing yet.
///
/// With [mixWithOthers], its sound plays along with the app's other
/// sound, such as a recording's microphone (iOS).
Future<VideoPlayerController> openPlayer(
  Library library,
  CaptureEvent event,
  EventPage page, {
  bool mixWithOthers = false,
}) async {
  final path = await library.path(event, page);
  final options = VideoPlayerOptions(mixWithOthers: mixWithOthers);
  final controller = path != null
      ? VideoPlayerController.file(File(path), videoPlayerOptions: options)
      : VideoPlayerController.networkUrl(
          Uri.dataFromBytes(
            await library.original(event, page),
            mimeType: page.mimeType,
          ),
          videoPlayerOptions: options,
        );
  try {
    await controller.initialize();
  } on Object {
    await controller.dispose();
    rethrow;
  }
  return controller;
}

/// Plays or pauses [controller], its icon following it; at the end, plays
/// from the start.
class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton(this.controller, {super.key, this.size, this.color});

  final VideoPlayerController controller;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, _) {
        final playing = value.isPlaying;
        return IconButton(
          key: const Key('play-pause'),
          iconSize: size,
          color: color,
          tooltip: playing ? l10n.textViewPause : l10n.textViewPlay,
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          onPressed: () async {
            if (playing) return controller.pause();
            final ended =
                value.duration > Duration.zero &&
                value.position >= value.duration;
            if (ended) await controller.seekTo(Duration.zero);
            await controller.play();
          },
        );
      },
    );
  }
}

/// A video's placeholder: an icon and a label on a dark card.
class _Poster extends StatelessWidget {
  const _Poster({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 72, color: Colors.white),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small video badge, for thumbnails.
class VideoThumbnail extends StatelessWidget {
  const VideoThumbnail({super.key});

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Colors.black,
    child: Center(
      child: Icon(Icons.play_circle_outline, size: 48, color: Colors.white),
    ),
  );
}
