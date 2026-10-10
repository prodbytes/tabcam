import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../library/library.dart';
import '../library/scan.dart';

/// A video page: a play button until tapped, then the video, with tap to
/// pause and resume. It plays from the page's file (from memory on the
/// web), and is let go when the page scrolls away.
class VideoPage extends StatefulWidget {
  const VideoPage({
    super.key,
    required this.library,
    required this.scan,
    required this.page,
  });

  final Library library;
  final Scan scan;
  final ScanPage page;

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
      final path = await widget.library.path(widget.scan, widget.page);
      final controller = path != null
          ? VideoPlayerController.file(File(path))
          : VideoPlayerController.networkUrl(
              Uri.dataFromBytes(
                await widget.library.original(widget.scan, widget.page),
                mimeType: _mime(widget.page.extension),
              ),
            );
      await controller.initialize();
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

  static String _mime(String extension) => switch (extension) {
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    '3gp' => 'video/3gpp',
    _ => 'video/mp4',
  };

  void _toggle() {
    final c = _controller!;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return const _Poster(
        icon: Icons.error_outline,
        label: 'This video can\'t be played here',
      );
    }
    if (controller == null) {
      return _loading
          ? const Center(child: CircularProgressIndicator())
          : _Poster(
              icon: Icons.play_circle_fill,
              label: 'Video',
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
              if (!controller.value.isPlaying)
                const Center(child: Icon(Icons.play_arrow, size: 72)),
              VideoProgressIndicator(controller, allowScrubbing: true),
            ],
          ),
        ),
      ),
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
