import 'package:flutter/material.dart';

import '../cloud/cloud_ocr.dart';
import '../cloud/cloud_sync.dart';
import '../library/library.dart';
import '../library/capture_event.dart';
import '../l10n/language.dart';
import 'clone.dart';
import 'page_image.dart';
import 'rename_dialog.dart';
import 'event_screen.dart';
import 'place.dart';
import 'share_sheet.dart';
import 'sign_in_gate.dart';
import 'video_page.dart';

/// The Home tab: every event as a card, newest first; once something is
/// shared with the user, in two sections, My captures and Shared with me. A new event
/// ([fresh]) is scrolled to and outlined for a moment. Tapping a card opens
/// its [EventScreen].
class LibraryView extends StatefulWidget {
  const LibraryView({
    super.key,
    required this.library,
    this.sync,
    this.ocr,
    this.fresh,
  });

  final Library library;
  final CloudSync? sync;
  final CloudOcr? ocr;

  /// The event just added: outlined, and the list scrolls up to it.
  final String? fresh;

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  final _grid = ScrollController();

  Library get library => widget.library;

  @override
  void didUpdateWidget(LibraryView old) {
    super.didUpdateWidget(old);
    if (widget.fresh != null && widget.fresh != old.fresh) {
      // New events are first: after this frame, the list scrolls up.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_grid.hasClients) {
          _grid.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _grid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) {
      if (!library.loaded) {
        return const Center(child: CircularProgressIndicator());
      }
      if (library.events.isEmpty) return const _Empty();
      final mine = library.events.where((e) => !e.isShared).toList();
      final shared = library.events.where((e) => e.isShared).toList();
      // Headed sections only once something is shared with the user.
      final plain = shared.isEmpty;
      return CustomScrollView(
        controller: _grid,
        slivers: [
          if (plain)
            _section(mine)
          else ...[
            _Heading(context.l10n.homeLibraryMine),
            if (mine.isEmpty)
              _None(context.l10n.homeLibraryMineEmpty)
            else
              _section(mine),
            _Heading(context.l10n.homeLibraryShared),
            _section(shared),
          ],
        ],
      );
    },
  );

  Widget _section(List<CaptureEvent> events) => SliverPadding(
    padding: const EdgeInsets.all(12),
    sliver: SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.62,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: events.length,
      itemBuilder: (context, i) {
        final event = events[i];
        return _EventCard(
          library: library,
          event: event,
          fresh: event.id == widget.fresh,
          onOpen: () =>
              openEvent(context, library, event, widget.sync, widget.ocr),
          sync: widget.sync,
        );
      },
    ),
  );
}

/// A section's title on Home.
class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    sliver: SliverToBoxAdapter(
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

/// What an empty section says.
class _None extends StatelessWidget {
  const _None(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    sliver: SliverToBoxAdapter(
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    ),
  );
}

/// Opens [event]'s [EventScreen] (its Text view, or its files with
/// [fileId] open over them), and remembers it's open until it's closed
/// ([PlaceMemory]).
Future<void> openEvent(
  BuildContext context,
  Library library,
  CaptureEvent event,
  CloudSync? sync, [
  CloudOcr? ocr,
  String? fileId,
  bool? text,
]) async {
  final memory = PlaceMemory.of(library);
  memory.update(
    (p) => p.copyWith(
      eventId: () => event.id,
      text: text ?? false,
      fileId: () => fileId,
    ),
  );
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => EventScreen(
        library: library,
        eventId: event.id,
        sync: sync,
        ocr: ocr,
        initialFile: fileId,
        initialText: text,
      ),
    ),
  );
  memory.update(
    (p) => p.eventId == event.id
        ? p.copyWith(eventId: () => null, text: false, fileId: () => null)
        : p,
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.queue_music_outlined,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(l10n.homeLibraryEmpty, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              l10n.homeLibraryEmptyDetail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

enum _CardAction { rename, share, clone, delete }

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.library,
    required this.event,
    required this.fresh,
    required this.onOpen,
    this.sync,
  });

  /// For removing an event shared with the user (leaving the share).
  final CloudSync? sync;

  final Library library;
  final CaptureEvent event;

  /// Just added: outlined in the theme's primary color.
  final bool fresh;
  final VoidCallback onOpen;

  Future<void> _action(BuildContext context, _CardAction action) async {
    final l10n = context.l10n;
    switch (action) {
      case _CardAction.rename:
        await renameEvent(context, library, event);
      case _CardAction.clone:
        await cloneEvent(context, library, event);
      case _CardAction.share:
        if (await requireSignIn(context, sync?.auth, Gated.share) &&
            context.mounted) {
          await showShareSheet(context, library, event, sync: sync);
        }
      case _CardAction.delete when event.isShared:
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.homeLibraryRemoveTitle(event.title)),
            content: Text(l10n.homeLibraryRemoveBody('${event.sharedBy}')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.homeLibraryCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.homeLibraryRemove),
              ),
            ],
          ),
        );
        if (ok != true || !context.mounted) return;
        try {
          await sync?.leave(event);
        } on Object catch (e) {
          if (context.mounted) {
            _snack(context, l10n.homeLibraryRemoveFailed('$e'));
          }
        }
      case _CardAction.delete:
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.homeLibraryDeleteTitle(event.title)),
            content: Text(l10n.homeLibraryDeleteBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.homeLibraryCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.homeLibraryDelete),
              ),
            ],
          ),
        );
        if (ok == true) await library.delete(event);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    int count(bool Function(EventPage) test) => event.pages.where(test).length;
    final videos = count((p) => p.isVideo);
    final audio = count((p) => p.isAudio);
    final pdfs = count((p) => p.isPdf);
    final links = count((p) => p.isLink);
    final pages = count((p) => p.isImage);
    // The first image is the thumbnail; without images (or with them
    // hidden), the text tab's badge, a video's, a PDF's, a recording's, or
    // else a link's.
    final cover = event.visiblePages.where((p) => p.isImage).firstOrNull;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: fresh
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.primary, width: 3),
            )
          : null,
      child: InkWell(
        onTap: onOpen,
        // Long-press is a shortcut to Rename.
        onLongPress: event.readOnly
            ? null
            : () => _action(context, _CardAction.rename),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ColoredBox(
                color: Colors.white,
                child: cover != null
                    ? PageImage(
                        library: library,
                        event: event,
                        page: cover,
                        fit: BoxFit.cover,
                        cacheWidth: 400,
                      )
                    : event.hideImages && event.tabText != null
                    ? const Icon(Icons.notes, size: 48, color: Colors.black54)
                    : videos > 0
                    ? const VideoThumbnail()
                    : pdfs > 0
                    ? const Icon(
                        Icons.picture_as_pdf_outlined,
                        size: 48,
                        color: Colors.black54,
                      )
                    : audio > 0
                    ? const Icon(
                        Icons.music_note,
                        size: 48,
                        color: Colors.black54,
                      )
                    : links > 0
                    ? const Icon(Icons.link, size: 48, color: Colors.black54)
                    : const Icon(Icons.description_outlined),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          [
                            if (event.artist.isNotEmpty) event.artist,
                            if (event.hideImages)
                              l10n.homeLibraryImagesHidden
                            else if (pages > 0 || pages == event.pages.length)
                              l10n.homePages(pages),
                            if (videos > 0) l10n.homeVideos(videos),
                            if (audio > 0) l10n.homeAudio(audio),
                            if (pdfs > 0) l10n.homePdfs(pdfs),
                            if (links > 0) l10n.homeLinks(links),
                            if (event.tabText != null) l10n.homeLibraryText,
                            if (event.sharedBy case final owner?)
                              l10n.homeLibrarySharedBy(owner),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<_CardAction>(
                    tooltip: l10n.homeLibraryMore,
                    onSelected: (a) => _action(context, a),
                    itemBuilder: (_) => [
                      if (!event.readOnly)
                        PopupMenuItem(
                          value: _CardAction.rename,
                          child: Text(l10n.homeLibraryRename),
                        ),
                      PopupMenuItem(
                        value: _CardAction.share,
                        child: Text(l10n.homeLibraryShare),
                      ),
                      PopupMenuItem(
                        value: _CardAction.clone,
                        child: Text(l10n.homeLibraryClone),
                      ),
                      PopupMenuItem(
                        value: _CardAction.delete,
                        child: Text(
                          event.isShared
                              ? l10n.homeLibraryRemove
                              : l10n.homeLibraryDelete,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
