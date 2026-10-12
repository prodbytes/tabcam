import 'package:flutter/material.dart';

import '../l10n/language.dart';
import '../library/library.dart';
import '../library/capture_event.dart';
import '../processing/page_filter.dart';
import 'audio_page.dart';
import 'link_page.dart';
import 'page_image.dart';
import 'pdf_page.dart';
import 'video_page.dart';

/// What a file is called in its capture's list: "Page 2", "Video 1", "PDF
/// 1", "Recording 1" (numbered among the files of its kind), or a link's
/// title (else its host).
String fileLabel(AppLocalizations l10n, CaptureEvent event, EventPage page) {
  if (page.isLink) return page.title ?? page.url?.host ?? '';
  final number =
      event.pages.where((p) => p.kind == page.kind).toList().indexOf(page) + 1;
  return switch (page.kind) {
    PageKind.video => l10n.eventFileVideo(number),
    PageKind.pdf => l10n.eventFilePdf(number),
    PageKind.audio => l10n.eventFileRecording(number),
    _ => l10n.eventFilePage(number),
  };
}

/// A file's small preview, for its capture's list: an image's picture (as
/// its filter shows it), else its kind's badge.
class FileThumbnail extends StatelessWidget {
  const FileThumbnail({
    super.key,
    required this.library,
    required this.event,
    required this.page,
  });

  final Library library;
  final CaptureEvent event;
  final EventPage page;

  @override
  Widget build(BuildContext context) {
    const badge = Colors.black54;
    return SizedBox.square(
      dimension: 64,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: Colors.white,
          child: switch (page.kind) {
            PageKind.image => PageImage(
              library: library,
              event: event,
              page: page,
              fit: BoxFit.cover,
              cacheWidth: 192,
            ),
            PageKind.video => const VideoThumbnail(),
            PageKind.pdf => const Icon(
              Icons.picture_as_pdf_outlined,
              color: badge,
            ),
            PageKind.audio => const Icon(Icons.music_note, color: badge),
            PageKind.link => const Icon(Icons.link, color: badge),
          },
        ),
      ),
    );
  }
}

/// A file shown whole, as what it is: an image pinch-zoomable, a PDF's
/// pages, a video or a recording to play, a link to open.
class FilePreview extends StatelessWidget {
  const FilePreview({
    super.key,
    required this.library,
    required this.event,
    required this.page,
  });

  final Library library;
  final CaptureEvent event;
  final EventPage page;

  @override
  Widget build(BuildContext context) {
    final key = ValueKey(page.id);
    return switch (page.kind) {
      PageKind.link => LinkPage(key: key, page: page),
      PageKind.video => VideoPage(
        key: key,
        library: library,
        event: event,
        page: page,
      ),
      PageKind.audio => AudioPage(
        key: key,
        library: library,
        event: event,
        page: page,
      ),
      PageKind.pdf => PdfPage(
        key: key,
        library: library,
        event: event,
        page: page,
      ),
      PageKind.image => InteractiveViewer(
        maxScale: 5,
        child: PageImage(library: library, event: event, page: page),
      ),
    };
  }
}

/// One file of a capture, opened from its list on its own screen: the
/// file, and its tools: the view (Original or Scan, for an image), Rotate
/// (an image) and Delete.
class FileScreen extends StatefulWidget {
  const FileScreen({
    super.key,
    required this.library,
    required this.eventId,
    required this.pageId,
  });

  final Library library;
  final String eventId;
  final String pageId;

  @override
  State<FileScreen> createState() => _FileScreenState();
}

class _FileScreenState extends State<FileScreen> {
  /// The file shown: Rotate stores it as a new page in its place.
  late String _pageId = widget.pageId;
  bool _busy = false;

  /// What an image shows here, when it isn't its saved filter (a capture
  /// shared read only).
  PageFilter? _shown;

  Library get _library => widget.library;

  Future<void> _run(String failure, Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } on Object catch (e, stack) {
      debugPrint('TabScan: $failure: $e\n$stack');
      if (mounted) _snack('$failure: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  /// Original ↔ Scan: the image's filter, saved (its thumbnail and the
  /// exports follow), or only what shows on a capture shared read only.
  Future<void> _nextView(CaptureEvent event, EventPage page) async {
    final next = (_shown ?? page.filter) == PageFilter.original
        ? PageFilter.tab
        : PageFilter.original;
    setState(() => _shown = next);
    if (event.readOnly) return;
    await _library.update(
      event.copyWith(
        pages: [
          for (final p in event.pages)
            p.id == page.id ? p.copyWith(filter: next) : p,
        ],
      ),
    );
  }

  Future<void> _rotate(CaptureEvent event, EventPage page) =>
      _run(context.l10n.eventCouldntRotate, () async {
        final index = event.pages.indexOf(page);
        final turned = await _library.rotatePage(event, page);
        if (mounted) setState(() => _pageId = turned.pages[index].id);
      });

  Future<void> _delete(CaptureEvent event, EventPage page) async {
    if (event.pages.length == 1) {
      _snack(context.l10n.eventKeepOnePage);
      return;
    }
    final navigator = Navigator.of(context);
    await _run(context.l10n.eventDelete, () async {
      await _library.deletePage(event, page);
      navigator.pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _library,
      builder: (context, _) {
        final event = _library.byId(widget.eventId);
        final page = event?.pages.where((p) => p.id == _pageId).firstOrNull;
        if (event == null || page == null) return const Scaffold();
        final l10n = context.l10n;
        final editable = !_busy && !event.readOnly;
        final filter = _shown ?? page.filter;
        final original = filter == PageFilter.original;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              fileLabel(l10n, event, page),
              overflow: TextOverflow.ellipsis,
            ),
            bottom: _busy
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(4),
                    child: LinearProgressIndicator(),
                  )
                : null,
          ),
          // The whole body: an image fits it, not its own size.
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox.expand(
              child: FilePreview(
                library: _library,
                event: event,
                page: page.isImage ? page.copyWith(filter: filter) : page,
              ),
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (page.isImage) ...[
                    EventTool(
                      key: const Key('view'),
                      icon: original ? Icons.photo_outlined : Icons.contrast,
                      label: original
                          ? l10n.eventViewOriginal
                          : l10n.eventViewScan,
                      onPressed: _busy ? null : () => _nextView(event, page),
                    ),
                    EventTool(
                      icon: Icons.rotate_90_degrees_cw_outlined,
                      label: l10n.eventRotate,
                      onPressed: editable ? () => _rotate(event, page) : null,
                    ),
                  ],
                  EventTool(
                    icon: Icons.delete_outline,
                    label: l10n.eventDelete,
                    onPressed: editable ? () => _delete(event, page) : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A tool along the bottom of the capture and file screens: an icon over
/// its label, highlighted when [selected].
class EventTool extends StatelessWidget {
  const EventTool({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // An equal share of the bar; a label longer than it (some languages')
    // shrinks to fit.
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: label,
            icon: Icon(icon),
            isSelected: selected,
            style: selected
                ? IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    foregroundColor: theme.colorScheme.onSecondaryContainer,
                  )
                : null,
            onPressed: onPressed,
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: selected ? FontWeight.bold : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
