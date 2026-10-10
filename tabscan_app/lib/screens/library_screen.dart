import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_version.dart';
import '../auth/auth_service.dart';
import '../capture/page_source.dart';
import '../cloud/cloud_sync.dart';
import '../library/library.dart';
import '../library/capture_event.dart';
import 'account_sheet.dart';
import 'page_image.dart';
import 'rename_dialog.dart';
import 'event_screen.dart';
import 'share_sheet.dart';
import 'video_page.dart';

/// The home screen: every event as a card, newest first, and the Scan button.
/// A new event lands at the top of the list, highlighted, with Open in the
/// message that confirms it. With [auth] and [sync] (a build with sign-in
/// and cloud sync set up), the app bar has the account button.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.library, this.auth, this.sync});

  final Library library;
  final AuthService? auth;
  final CloudSync? sync;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _grid = ScrollController();

  /// The event just added, highlighted for a moment.
  String? _fresh;

  Library get library => widget.library;

  @override
  void dispose() {
    _grid.dispose();
    super.dispose();
  }

  Future<void> _newScan({bool import = false}) async {
    final List<Uint8List> pages;
    try {
      pages = import ? await PageSource.import() : await PageSource.scan();
    } on Object catch (e) {
      if (mounted) _snack(context, 'Couldn\'t scan: $e');
      return;
    }
    if (pages.isEmpty || !mounted) return;
    final event = await library.create(pages);
    if (!mounted) return;
    setState(() => _fresh = event.id);
    if (_grid.hasClients) {
      _grid.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    final count = event.pages.length;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Saved "${event.title}" ($count ${count == 1 ? 'page' : 'pages'})',
          ),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => _open(context, event),
          ),
        ),
      );
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _fresh == event.id) setState(() => _fresh = null);
    });
  }

  void _open(BuildContext context, CaptureEvent event) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EventScreen(library: library, eventId: event.id),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TabScan'),
        actions: [
          if ((widget.auth, widget.sync) case (final auth?, final sync?))
            AccountButton(auth: auth, sync: sync),
          IconButton(
            tooltip: 'Import photos',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () => _newScan(import: true),
          ),
          IconButton(
            tooltip: 'About',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: AppVersion.title,
              applicationVersion: AppVersion.version.isEmpty
                  ? 'development build'
                  : AppVersion.version,
              applicationLegalese:
                  'Scan guitar tabs, read them as text, and share them.',
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newScan(),
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan'),
      ),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          if (!library.loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          if (library.events.isEmpty) return const _Empty();
          return GridView.builder(
            controller: _grid,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              childAspectRatio: 0.62,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: library.events.length,
            itemBuilder: (context, i) {
              final event = library.events[i];
              return _EventCard(
                library: library,
                event: event,
                fresh: event.id == _fresh,
                onOpen: () => _open(context, event),
              );
            },
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            Text('No tabs yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Tap Scan and point the camera at a tab: the page is found, '
              'straightened and cleaned up for you.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

enum _CardAction { rename, share, delete }

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.library,
    required this.event,
    required this.fresh,
    required this.onOpen,
  });

  final Library library;
  final CaptureEvent event;

  /// Just added: outlined in the theme's primary color.
  final bool fresh;
  final VoidCallback onOpen;

  Future<void> _action(BuildContext context, _CardAction action) async {
    switch (action) {
      case _CardAction.rename:
        await renameEvent(context, library, event);
      case _CardAction.share:
        await showShareSheet(context, library, event);
      case _CardAction.delete:
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete "${event.title}"?'),
            content: const Text('Its pages and text tab are deleted too.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
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
    final videos = event.pages.where((p) => p.isVideo).length;
    final links = event.pages.where((p) => p.isLink).length;
    final pages = event.pages.length - videos - links;
    // The first image is the thumbnail; without images, a video's badge,
    // or else a link's.
    final cover = event.pages.where((p) => p.isImage).firstOrNull;
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
        onLongPress: () => _action(context, _CardAction.rename),
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
                    : videos > 0
                    ? const VideoThumbnail()
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
                            if (pages > 0 || videos + links == 0)
                              '$pages ${pages == 1 ? 'page' : 'pages'}',
                            if (videos > 0)
                              '$videos ${videos == 1 ? 'video' : 'videos'}',
                            if (links > 0)
                              '$links ${links == 1 ? 'link' : 'links'}',
                            if (event.tabText != null) 'text',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<_CardAction>(
                    tooltip: 'More',
                    onSelected: (a) => _action(context, a),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _CardAction.rename,
                        child: Text('Rename'),
                      ),
                      PopupMenuItem(
                        value: _CardAction.share,
                        child: Text('Share'),
                      ),
                      PopupMenuItem(
                        value: _CardAction.delete,
                        child: Text('Delete'),
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
