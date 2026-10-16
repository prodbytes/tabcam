import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:video_player/video_player.dart';

import '../library/capture_event.dart';
import '../library/library.dart';
import 'video_page.dart';

/// A PDF's first page, drawn on the device (PDFium) for its row in the
/// capture's list; [fallback] (its kind's badge) while it loads and when
/// it can't be drawn.
class PdfThumbnail extends StatefulWidget {
  const PdfThumbnail({
    super.key,
    required this.library,
    required this.event,
    required this.page,
    required this.fallback,
  });

  final Library library;
  final CaptureEvent event;
  final EventPage page;
  final Widget fallback;

  @override
  State<PdfThumbnail> createState() => _PdfThumbnailState();
}

class _PdfThumbnailState extends State<PdfThumbnail> {
  /// The document: the device's copy of the file, or its bytes where
  /// there's none (the web).
  late final Future<PdfDocumentRef> _ref = () async {
    final PdfThumbnail(:library, :event, :page) = widget;
    final path = await library.path(event, page);
    if (path != null) return PdfDocumentRefFile(path);
    return PdfDocumentRefData(
      await library.original(event, page),
      sourceName: page.fileName,
    );
  }();

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _ref,
    builder: (context, snapshot) {
      final ref = snapshot.data;
      if (ref == null) return widget.fallback;
      return PdfDocumentViewBuilder(
        documentRef: ref,
        loadingBuilder: (_) => widget.fallback,
        errorBuilder: (_, _, _) => widget.fallback,
        builder: (context, document) =>
            document == null || document.pages.isEmpty
            ? widget.fallback
            : PdfPageView(
                document: document,
                pageNumber: 1,
                // Small: a thumbnail, not the page to read.
                maximumDpi: 96,
                alignment: Alignment.topCenter,
                decoration: const BoxDecoration(color: Colors.white),
              ),
      );
    },
  );
}

/// A video's first frame, for its row in the capture's list, with a play
/// mark over it; [fallback] (its kind's badge) while it loads and when the
/// video can't be read here.
class VideoFrameThumbnail extends StatefulWidget {
  const VideoFrameThumbnail({
    super.key,
    required this.library,
    required this.event,
    required this.page,
    required this.fallback,
  });

  final Library library;
  final CaptureEvent event;
  final EventPage page;
  final Widget fallback;

  @override
  State<VideoFrameThumbnail> createState() => _VideoFrameThumbnailState();
}

class _VideoFrameThumbnailState extends State<VideoFrameThumbnail> {
  VideoPlayerController? _controller;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final controller = await openPlayer(
        widget.library,
        widget.event,
        widget.page,
      );
      if (_disposed) {
        await controller.dispose();
        return;
      }
      // Paused on its first frame, silent: never played here.
      await controller.setVolume(0);
      await controller.seekTo(Duration.zero);
      if (_disposed) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on Object catch (e) {
      debugPrint('TabCam: no frame for ${widget.page.fileName}: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final size = controller?.value.size;
    if (controller == null || size == null || size.isEmpty) {
      return widget.fallback;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.black,
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        const Center(
          child: Icon(
            Icons.play_circle_outline,
            size: 28,
            color: Colors.white,
            shadows: [Shadow(blurRadius: 4)],
          ),
        ),
      ],
    );
  }
}
