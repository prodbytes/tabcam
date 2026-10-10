import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_version.dart';
import '../capture/page_source.dart';
import '../library/library.dart';
import '../library/scan.dart';
import 'page_image.dart';
import 'scan_screen.dart';
import 'share_sheet.dart';

/// The home screen: every scan as a card, newest first, and the Scan button.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.library});

  final Library library;

  Future<void> _newScan(BuildContext context, {bool import = false}) async {
    final List<Uint8List> pages;
    try {
      pages = import ? await PageSource.import() : await PageSource.scan();
    } on Object catch (e) {
      if (context.mounted) _snack(context, 'Couldn\'t scan: $e');
      return;
    }
    if (pages.isEmpty || !context.mounted) return;
    final scan = await library.create(pages);
    if (context.mounted) _open(context, scan);
  }

  void _open(BuildContext context, Scan scan) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ScanScreen(library: library, scanId: scan.id),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TabScan'),
        actions: [
          IconButton(
            tooltip: 'Import photos',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () => _newScan(context, import: true),
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
        onPressed: () => _newScan(context),
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan'),
      ),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          if (!library.loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          if (library.scans.isEmpty) return const _Empty();
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              childAspectRatio: 0.62,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: library.scans.length,
            itemBuilder: (context, i) {
              final scan = library.scans[i];
              return _ScanCard(
                library: library,
                scan: scan,
                onOpen: () => _open(context, scan),
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

enum _CardAction { share, delete }

class _ScanCard extends StatelessWidget {
  const _ScanCard({
    required this.library,
    required this.scan,
    required this.onOpen,
  });

  final Library library;
  final Scan scan;
  final VoidCallback onOpen;

  Future<void> _action(BuildContext context, _CardAction action) async {
    switch (action) {
      case _CardAction.share:
        await showShareSheet(context, library, scan);
      case _CardAction.delete:
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete "${scan.title}"?'),
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
        if (ok == true) await library.delete(scan);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = scan.pages.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ColoredBox(
                color: Colors.white,
                child: scan.pages.isEmpty
                    ? const Icon(Icons.description_outlined)
                    : PageImage(
                        library: library,
                        scan: scan,
                        page: scan.pages.first,
                        fit: BoxFit.cover,
                        cacheWidth: 400,
                      ),
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
                          scan.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          [
                            if (scan.artist.isNotEmpty) scan.artist,
                            '$pages ${pages == 1 ? 'page' : 'pages'}',
                            if (scan.tabText != null) 'text',
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
