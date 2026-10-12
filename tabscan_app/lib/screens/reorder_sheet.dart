import 'package:flutter/material.dart';

import '../l10n/language.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import 'page_image.dart';

/// Reorder: the event's pages as a list (a thumbnail or an icon, and what
/// each is), dragged by their handles into a new order. Each drop is saved
/// at once ([Library.reorderPages]). With the images hidden, only the other
/// pages are listed; the images keep their places.
Future<void> showReorderSheet(
  BuildContext context,
  Library library,
  String eventId, {
  required void Function(Object error) onError,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) =>
      _ReorderSheet(library: library, eventId: eventId, onError: onError),
);

class _ReorderSheet extends StatelessWidget {
  const _ReorderSheet({
    required this.library,
    required this.eventId,
    required this.onError,
  });

  final Library library;
  final String eventId;
  final void Function(Object error) onError;

  Future<void> _move(List<EventPage> pages, int from, int to) async {
    final order = [...pages];
    order.insert(to, order.removeAt(from));
    try {
      await library.reorderPages(eventId, [for (final p in order) p.id]);
    } on Object catch (e) {
      onError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: ListenableBuilder(
          listenable: library,
          builder: (context, _) {
            final event = library.byId(eventId);
            if (event == null) return const SizedBox.shrink();
            final pages = event.visiblePages;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.eventReorderTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    itemCount: pages.length,
                    onReorderItem: (from, to) => _move(pages, from, to),
                    itemBuilder: (context, i) {
                      final page = pages[i];
                      return ListTile(
                        key: ValueKey(page.id),
                        leading: SizedBox.square(
                          dimension: 48,
                          child: page.isImage
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: PageImage(
                                    library: library,
                                    event: event,
                                    page: page,
                                    fit: BoxFit.cover,
                                    cacheWidth: 96,
                                  ),
                                )
                              : Icon(_iconOf(page)),
                        ),
                        title: Text('${i + 1}. ${_labelOf(context, page)}'),
                        subtitle: page.isLink && page.title != null
                            ? Text(
                                page.url.toString(),
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        trailing: ReorderableDragStartListener(
                          index: i,
                          child: const Icon(Icons.drag_handle),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

IconData _iconOf(EventPage page) => switch (page.kind) {
  PageKind.image => Icons.image_outlined,
  PageKind.video => Icons.videocam_outlined,
  PageKind.audio => Icons.music_note_outlined,
  PageKind.pdf => Icons.picture_as_pdf_outlined,
  PageKind.link => Icons.link,
};

String _labelOf(BuildContext context, EventPage page) {
  final l10n = context.l10n;
  return switch (page.kind) {
    PageKind.image => l10n.eventPagePhoto,
    PageKind.video => l10n.textViewVideo,
    PageKind.audio => l10n.textViewAudio,
    PageKind.pdf => l10n.eventPagePdf,
    PageKind.link => page.title ?? page.url?.host ?? l10n.textViewLink,
  };
}
