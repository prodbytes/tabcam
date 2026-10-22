import 'dart:async';

import 'package:flutter/material.dart';

import '../cloud/cloud_ocr.dart';
import '../cloud/cloud_sync.dart';
import '../library/library.dart';
import '../library/capture_event.dart';
import '../library/search.dart';
import '../l10n/language.dart';
import 'card_preview.dart';
import 'clone.dart';
import 'own_tabs_note.dart';
import 'rename_dialog.dart';
import 'event_screen.dart';
import 'place.dart';
import 'share_sheet.dart';

/// The Home tab: every event as a card, newest first; once something is
/// shared with the user, in two sections, My captures and Shared with me. A new event
/// ([fresh]) is scrolled to and outlined for a moment. Tapping a card opens
/// its [EventScreen]. A search field above the cards keeps only the events
/// that match ([matchesSearch]).
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
  final _search = TextEditingController();

  /// What the search field holds: the events shown match it.
  String get _query => _search.text.trim();

  Library get library => widget.library;

  @override
  void didUpdateWidget(LibraryView old) {
    super.didUpdateWidget(old);
    if (widget.fresh != null && widget.fresh != old.fresh) {
      // A new event shows, whatever was searched.
      _search.clear();
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
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([library, _search, ?widget.sync]),
    builder: (context, _) {
      if (!library.loaded) {
        return const Center(child: CircularProgressIndicator());
      }
      if (library.events.isEmpty) {
        final sync = widget.sync;
        // Signed in, the user's captures may not have come down yet.
        if (sync != null && !sync.firstPassDone) return const _Loading();
        if (sync?.state == SyncState.failed) {
          return _LoadFailed(
            message: sync!.message,
            onRetry: () => unawaited(sync.syncNow()),
          );
        }
        return const _Empty();
      }
      final l10n = context.l10n;
      final query = _query;
      final searching = query.isNotEmpty;
      final found = [
        for (final e in library.events)
          if (matchesSearch(e, query)) e,
      ];
      final mine = found.where((e) => !e.isShared).toList();
      final shared = found.where((e) => e.isShared).toList();
      // Headed sections only once something is shared with the user;
      // searching, only those with a match.
      final plain = library.events.every((e) => !e.isShared);
      return CustomScrollView(
        controller: _grid,
        slivers: [
          SliverToBoxAdapter(child: _searchField(l10n)),
          if (found.isEmpty)
            _NoMatch(query, onClear: _search.clear)
          else if (plain)
            _section(mine)
          else ...[
            if (mine.isNotEmpty || !searching) ...[
              _Heading(l10n.homeLibraryMine),
              if (mine.isEmpty)
                _None(l10n.homeLibraryMineEmpty)
              else
                _section(mine),
            ],
            if (shared.isNotEmpty) ...[
              _Heading(l10n.homeLibraryShared),
              _section(shared),
            ],
          ],
          const SliverToBoxAdapter(child: OwnTabsNote()),
        ],
      );
    },
  );

  Widget _searchField(AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    child: TextField(
      key: const Key('home-search'),
      controller: _search,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: l10n.homeSearch,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: l10n.homeSearchClear,
                icon: const Icon(Icons.close),
                onPressed: _search.clear,
              ),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    ),
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

/// No event matches the search: says so, with Clear.
class _NoMatch extends StatelessWidget {
  const _NoMatch(this.query, {required this.onClear});

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.all(32),
    sliver: SliverToBoxAdapter(
      child: Column(
        children: [
          const Icon(Icons.search_off, size: 48),
          const SizedBox(height: 12),
          Text(context.l10n.homeSearchNone(query), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onClear,
            child: Text(context.l10n.homeSearchClear),
          ),
        ],
      ),
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

/// Signed in, while the first pass brings the user's captures.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      key: const Key('library-loading'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(context.l10n.homeLibraryLoading),
      ],
    ),
  );
}

/// Nothing here, and the captures couldn't be brought: why, and Try again.
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              l10n.homeLibraryLoadFailed,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (message case final message?) ...[
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: Text(l10n.homeLibraryTryAgain),
            ),
          ],
        ),
      ),
    );
  }
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
            const SizedBox(height: 16),
            const OwnTabsNote(),
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
        await shareCapture(context, event, sync: sync);
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
    // On a phone, the text and the ⋮ a little smaller.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    TextStyle? smaller(TextStyle? style) => narrow && style?.fontSize != null
        ? style!.copyWith(fontSize: style.fontSize! - 1)
        : style;
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
                child: CardPreview(library: library, event: event),
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
                          style: smaller(theme.textTheme.titleSmall),
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
                          style: smaller(theme.textTheme.bodySmall),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<_CardAction>(
                    tooltip: l10n.homeLibraryMore,
                    iconSize: narrow ? 20 : null,
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
