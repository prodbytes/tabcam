import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../library/library.dart';
import '../library/capture_event.dart';
import '../l10n/language.dart';

/// A PDF's page: the document itself, its pages scrolling down, zoomable
/// (pinched, or with its **Zoom in** and **Zoom out** buttons,
/// [PdfZoomButtons]). It's read from the page's file (from memory on the
/// web).
class PdfPage extends StatefulWidget {
  const PdfPage({
    super.key,
    required this.library,
    required this.event,
    required this.page,
  });

  final Library library;
  final CaptureEvent event;
  final EventPage page;

  @override
  State<PdfPage> createState() => _PdfPageState();
}

class _PdfPageState extends State<PdfPage> {
  final _controller = PdfViewerController();

  /// The device's copy of the file, or its bytes where there's none.
  late final Future<Object> _source = () async {
    final PdfPage(:library, :event, :page) = widget;
    return await library.path(event, page) ??
        await library.original(event, page);
  }();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _source,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 56),
                const SizedBox(height: 8),
                Text(context.l10n.textViewCantShowPdf),
              ],
            ),
          );
        }
        final viewer = switch (snapshot.data) {
          null => null,
          final String path => PdfViewer.file(path, controller: _controller),
          final source => PdfViewer.data(
            source as Uint8List,
            sourceName: widget.page.fileName,
            controller: _controller,
          ),
        };
        if (viewer == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return Stack(
          children: [
            Positioned.fill(child: viewer),
            Positioned(
              right: 8,
              bottom: 8,
              child: PdfZoomButtons(controller: _controller),
            ),
          ],
        );
      },
    );
  }
}

/// **Zoom in** (+) and **Zoom out** (−), one over the other, over a PDF's
/// pages: each goes to the viewer's next zoom step, about the middle of
/// what shows. Nothing happens before the document is ready.
class PdfZoomButtons extends StatelessWidget {
  const PdfZoomButtons({super.key, required this.controller});

  final PdfViewerController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const compact = VisualDensity(horizontal: -2, vertical: -2);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          key: const Key('pdf-zoom-in'),
          tooltip: l10n.pdfZoomIn,
          visualDensity: compact,
          icon: const Icon(Icons.zoom_in),
          onPressed: () {
            if (controller.isReady) controller.zoomUp();
          },
        ),
        const SizedBox(height: 4),
        IconButton.filledTonal(
          key: const Key('pdf-zoom-out'),
          tooltip: l10n.pdfZoomOut,
          visualDensity: compact,
          icon: const Icon(Icons.zoom_out),
          onPressed: () {
            if (controller.isReady) controller.zoomDown();
          },
        ),
      ],
    );
  }
}
