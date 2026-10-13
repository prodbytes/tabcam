import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../library/capture_event.dart';
import '../library/library.dart';
import 'page_image.dart';
import 'video_page.dart';
import 'mono_font.dart';

/// What a Home card shows above its title: a preview of the capture.
///
/// In order: the first visible image page; else the first PDF's first
/// page, rendered; else the text tab's first lines, in miniature; else a
/// video's play badge; else the first link's title and host; else an icon
/// (a recording's music note, or a document). A small badge in the corner
/// says what else the capture holds (a PDF, a video, a recording, a link).
/// Hidden images ([CaptureEvent.hideImages]) are never shown.
class CardPreview extends StatelessWidget {
  const CardPreview({super.key, required this.library, required this.event});

  final Library library;
  final CaptureEvent event;

  @override
  Widget build(BuildContext context) {
    final visible = event.visiblePages;
    EventPage? first(bool Function(EventPage) test) =>
        visible.where(test).firstOrNull;
    final cover = first((p) => p.isImage);
    if (cover != null) {
      return PageImage(
        library: library,
        event: event,
        page: cover,
        fit: BoxFit.cover,
        cacheWidth: 400,
      );
    }
    final pdf = first((p) => p.isPdf);
    final video = first((p) => p.isVideo);
    final audio = first((p) => p.isAudio);
    final link = first((p) => p.isLink);
    final text = event.tabText?.trim() ?? '';

    // The badge for what the capture holds besides what's previewed.
    IconData? badge({bool pdfShown = false}) => !pdfShown && pdf != null
        ? Icons.picture_as_pdf_outlined
        : video != null
        ? Icons.play_arrow
        : audio != null
        ? Icons.music_note
        : link != null
        ? Icons.link
        : null;

    // What shows without a PDF, or while it renders, or if it can't.
    Widget withoutPdf() {
      if (text.isNotEmpty) {
        return _Badged(
          badge: badge(pdfShown: pdf != null),
          child: TextPreview(text),
        );
      }
      if (pdf != null) return const _Icon(Icons.picture_as_pdf_outlined);
      if (video != null) return const VideoThumbnail();
      if (link != null) {
        return _Badged(
          badge: Icons.link,
          child: LinkPreview(page: link),
        );
      }
      if (audio != null) return const _Icon(Icons.music_note);
      return const _Icon(Icons.description_outlined);
    }

    if (pdf != null) {
      return _Badged(
        badge: Icons.picture_as_pdf_outlined,
        child: _PdfPreview(
          library: library,
          event: event,
          page: pdf,
          fallback: withoutPdf(),
        ),
      );
    }
    return withoutPdf();
  }
}

/// A big icon on the card's white: when there's nothing to preview.
class _Icon extends StatelessWidget {
  const _Icon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Center(child: Icon(icon, size: 48, color: Colors.black54));
}

/// [child] with a small round [badge] in its bottom right corner.
class _Badged extends StatelessWidget {
  const _Badged({required this.child, this.badge});

  final Widget child;
  final IconData? badge;

  @override
  Widget build(BuildContext context) {
    final badge = this.badge;
    if (badge == null) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          right: 6,
          bottom: 6,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(badge, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// The text tab's first lines, monospaced and small, unwrapped and cut at
/// the card's edges: a miniature of the tab.
class TextPreview extends StatelessWidget {
  const TextPreview(this.text, {super.key});

  final String text;

  /// No more lines than a card can show.
  static const int maxLines = 24;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n').take(maxLines).join('\n');
    return ClipRect(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: Text(
            lines,
            softWrap: false,
            style: const TextStyle(
              fontFamily: monoFont,
              fontFamilyFallback: ['Menlo', 'Courier New', 'Courier'],
              fontSize: 8,
              height: 1.2,
              color: Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}

/// A link's title (if it has one) and host, on the card's white.
class LinkPreview extends StatelessWidget {
  const LinkPreview({super.key, required this.page});

  final EventPage page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final host = page.url?.host ?? '';
    final title = page.title?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: Colors.black87,
              ),
            ),
          Text(
            host,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

/// A PDF's first page as a card preview, from [PdfPreviews]; [fallback]
/// while it renders, or if it can't be.
class _PdfPreview extends StatefulWidget {
  const _PdfPreview({
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
  State<_PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<_PdfPreview> {
  late Future<ui.Image?> _image = _load();

  Future<ui.Image?> _load() =>
      PdfPreviews.of(widget.library, widget.event, widget.page);

  @override
  void didUpdateWidget(_PdfPreview old) {
    super.didUpdateWidget(old);
    if (old.event.id != widget.event.id || old.page.id != widget.page.id) {
      _image = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _image,
    initialData: PdfPreviews.ready(widget.event, widget.page),
    builder: (context, snapshot) => switch (snapshot.data) {
      final image? => RawImage(
        image: image,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
      ),
      null => widget.fallback,
    },
  );
}

/// PDFs' first pages rendered for Home's cards, kept in memory (page files
/// never change, so a page's preview never does). The most recently used
/// [capacity] are kept.
abstract final class PdfPreviews {
  /// The rendered width, in pixels: a card's at a phone's pixel ratio.
  static const int width = 480;

  /// How many previews are kept.
  static const int capacity = 48;

  static final _cache = <String, Future<ui.Image?>>{};
  static final _done = <String, ui.Image>{};

  /// Renders a page's preview; null when it can't. Replaced in tests, where
  /// the app's PDFium can't load.
  @visibleForTesting
  static Future<ui.Image?> Function(Library, CaptureEvent, EventPage) render =
      _render;

  /// Forgets every preview (for tests).
  @visibleForTesting
  static void clear() {
    _cache.clear();
    _done.clear();
  }

  static String _key(CaptureEvent event, EventPage page) =>
      '${event.id}/${page.id}';

  /// The preview, if it's already rendered: shown at once, no flicker.
  static ui.Image? ready(CaptureEvent event, EventPage page) =>
      _done[_key(event, page)];

  /// [page]'s preview: rendered once, then from memory. A failure isn't
  /// kept, so the next card built for it tries again (its file may not
  /// have synced down yet).
  static Future<ui.Image?> of(
    Library library,
    CaptureEvent event,
    EventPage page,
  ) {
    final key = _key(event, page);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached; // Most recently used last.
      return cached;
    }
    final future = () async {
      try {
        final image = await render(library, event, page);
        if (image != null && _cache.containsKey(key)) _done[key] = image;
        if (image == null) _cache.remove(key);
        return image;
      } on Object catch (e) {
        debugPrint('TabScan: PDF preview: $e');
        _cache.remove(key);
        return null;
      }
    }();
    _cache[key] = future;
    while (_cache.length > capacity) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest);
      _done.remove(oldest);
    }
    return future;
  }

  static Future<ui.Image?> _render(
    Library library,
    CaptureEvent event,
    EventPage page,
  ) async {
    await pdfrxFlutterInitialize();
    final path = await library.path(event, page);
    final doc = path != null
        ? await PdfDocument.openFile(path)
        : await PdfDocument.openData(
            await library.original(event, page),
            sourceName: 'preview:${_key(event, page)}',
          );
    try {
      if (doc.pages.isEmpty) return null;
      final first = doc.pages.first;
      if (first.width <= 0 || first.height <= 0) return null;
      final scale = width / first.width;
      final rendered = await first.render(
        fullWidth: width.toDouble(),
        fullHeight: (first.height * scale).roundToDouble(),
        backgroundColor: 0xffffffff,
      );
      if (rendered == null) return null;
      try {
        return await rendered.createImage();
      } finally {
        rendered.dispose();
      }
    } finally {
      await doc.dispose();
    }
  }
}
