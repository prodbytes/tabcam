import 'package:flutter/material.dart';

import '../library/library.dart';
import '../library/capture_event.dart';

/// A page's image with its filter applied, loaded from the library.
class PageImage extends StatelessWidget {
  const PageImage({
    super.key,
    required this.library,
    required this.event,
    required this.page,
    this.fit = BoxFit.contain,
    this.cacheWidth,
  });

  final Library library;
  final CaptureEvent event;
  final EventPage page;
  final BoxFit fit;

  /// Decodes the image at this width, for thumbnails.
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      key: ValueKey('${page.id}/${page.filter.name}/${library.revision}'),
      future: library.filtered(event, page),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Icon(Icons.broken_image_outlined));
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return Image.memory(
          bytes,
          fit: fit,
          cacheWidth: cacheWidth,
          gaplessPlayback: true,
        );
      },
    );
  }
}
