import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../library/library.dart';
import '../library/capture_event.dart';
import '../l10n/language.dart';

/// A PDF's page: the document itself, its pages scrolling down, zoomable.
/// It's read from the page's file (from memory on the web).
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
        return switch (snapshot.data) {
          null => const Center(child: CircularProgressIndicator()),
          final String path => PdfViewer.file(path),
          final source => PdfViewer.data(
            source as Uint8List,
            sourceName: widget.page.fileName,
          ),
        };
      },
    );
  }
}
