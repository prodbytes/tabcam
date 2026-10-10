import 'package:flutter/material.dart';

import '../capture/media.dart';
import '../capture/page_source.dart';
import '../library/library.dart';
import '../library/scan.dart';
import '../processing/page_filter.dart';
import '../recognition/tab_reader.dart';
import 'page_image.dart';
import 'share_sheet.dart';
import 'tab_text_screen.dart';
import 'video_page.dart';

/// One scan: its pages (images and videos) to swipe through, and the tools
/// along the bottom: Add (scan, photos and videos, files), Filter, Rotate,
/// Read tab and Delete. Share and rename are in the app bar.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.library, required this.scanId});

  final Library library;
  final String scanId;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _pages = PageController();
  int _index = 0;
  bool _busy = false;

  Library get _library => widget.library;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Runs [task] with the progress bar shown and buttons off, and reports
  /// a failure.
  Future<void> _run(String failure, Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } on Object catch (e) {
      if (mounted) _snack('$failure: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _rename(Scan scan) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _RenameDialog(scan: scan),
    );
    if (result == null) return;
    final (title, artist) = result;
    await _library.update(
      scan.copyWith(title: title.isEmpty ? scan.title : title, artist: artist),
    );
  }

  Future<void> _add(Scan scan) async {
    final source = await showModalBottomSheet<_AddSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final source in _AddSource.values)
              ListTile(
                leading: Icon(source.icon),
                title: Text(source.label),
                subtitle: Text(source.detail),
                onTap: () => Navigator.pop(context, source),
              ),
          ],
        ),
      ),
    );
    if (source == null) return;
    await _run('Couldn\'t add', () async {
      final first = scan.pages.length;
      if (source == _AddSource.scan) {
        final pages = await PageSource.scan();
        if (pages.isEmpty) return;
        await _library.addPages(scan, pages);
      } else {
        final pick = source == _AddSource.library
            ? await MediaSource.library()
            : await MediaSource.files();
        if (pick.skipped > 0) {
          _snack(
            '${pick.skipped} ${pick.skipped == 1 ? 'file isn\'t' : 'files aren\'t'} '
            'a photo or video, so not added.',
          );
        }
        if (pick.media.isEmpty) return;
        await _library.addMedia(scan, pick.media);
      }
      // Show the first page added.
      if (mounted) {
        setState(() => _index = first);
        _pages.jumpToPage(first);
      }
    });
  }

  Future<void> _toggleFilter(Scan scan, ScanPage page) {
    final next = page.filter == PageFilter.tab
        ? PageFilter.original
        : PageFilter.tab;
    return _library.update(
      scan.copyWith(
        pages: [
          for (final p in scan.pages)
            p.id == page.id ? p.copyWith(filter: next) : p,
        ],
      ),
    );
  }

  Future<void> _readTab(Scan scan) => _run('Couldn\'t read the tab', () async {
    if (!TabReader.supported) {
      _snack('Reading tabs needs the Android or iOS app.');
      return;
    }
    final pages = [
      for (final p in scan.pages)
        if (!p.isVideo) await _library.original(scan, p),
    ];
    if (pages.isEmpty) {
      _snack('Read tab reads photos and scans, and this has only videos.');
      return;
    }
    final text = await TabReader.read(pages);
    if (!mounted) return;
    if (text == null) {
      _snack('No tab found. Try the Tab filter, or rescan closer and flatter.');
      return;
    }
    await _openText(await _library.update(scan.copyWith(tabText: text)));
  });

  Future<void> _openText(Scan scan) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TabTextScreen(library: _library, scanId: scan.id),
    ),
  );

  Future<void> _deletePage(Scan scan, ScanPage page) async {
    if (scan.pages.length == 1) {
      _snack('A scan keeps at least one page; delete the scan instead.');
      return;
    }
    await _library.deletePage(scan, page);
    setState(() => _index = _index.clamp(0, scan.pages.length - 2));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _library,
      builder: (context, _) {
        final scan = _library.byId(widget.scanId);
        if (scan == null) return const Scaffold();
        final index = _index.clamp(0, scan.pages.length - 1);
        final page = scan.pages.isEmpty ? null : scan.pages[index];
        final enabled = !_busy && page != null;
        // Filter and Rotate are for images, not videos.
        final image = enabled && !page.isVideo;
        return Scaffold(
          appBar: AppBar(
            title: InkWell(
              onTap: () => _rename(scan),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(scan.title, overflow: TextOverflow.ellipsis),
                  if (scan.artist.isNotEmpty)
                    Text(
                      scan.artist,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            actions: [
              if (scan.tabText != null)
                IconButton(
                  tooltip: 'Text tab',
                  icon: const Icon(Icons.notes),
                  onPressed: () => _openText(scan),
                ),
              IconButton(
                tooltip: 'Rename',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _rename(scan),
              ),
              IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.ios_share),
                onPressed: _busy
                    ? null
                    : () => showShareSheet(context, _library, scan),
              ),
            ],
            bottom: _busy
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(4),
                    child: LinearProgressIndicator(),
                  )
                : null,
          ),
          body: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: scan.pages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: scan.pages[i].isVideo
                        ? VideoPage(
                            key: ValueKey(scan.pages[i].id),
                            library: _library,
                            scan: scan,
                            page: scan.pages[i],
                          )
                        : InteractiveViewer(
                            maxScale: 5,
                            child: PageImage(
                              library: _library,
                              scan: scan,
                              page: scan.pages[i],
                            ),
                          ),
                  ),
                ),
              ),
              Text(
                '${index + 1} / ${scan.pages.length}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Tool(
                    icon: Icons.add_circle_outline,
                    label: 'Add',
                    onPressed: _busy ? null : () => _add(scan),
                  ),
                  _Tool(
                    icon: page?.filter == PageFilter.tab
                        ? Icons.contrast
                        : Icons.photo_outlined,
                    label: page?.filter.label ?? 'Filter',
                    onPressed: image ? () => _toggleFilter(scan, page) : null,
                  ),
                  _Tool(
                    icon: Icons.rotate_90_degrees_cw_outlined,
                    label: 'Rotate',
                    onPressed: image
                        ? () => _run(
                            'Couldn\'t rotate',
                            () => _library.rotatePage(scan, page),
                          )
                        : null,
                  ),
                  _Tool(
                    icon: Icons.text_snippet_outlined,
                    label: 'Read tab',
                    onPressed: enabled ? () => _readTab(scan) : null,
                  ),
                  _Tool(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    onPressed: enabled ? () => _deletePage(scan, page) : null,
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

/// Where Add gets new pages.
enum _AddSource {
  scan(
    Icons.document_scanner_outlined,
    'Scan pages',
    'More tab pages, with the camera',
  ),
  library(
    Icons.photo_library_outlined,
    'Photos & videos',
    'From your photo library',
  ),
  files(Icons.folder_open_outlined, 'Files', 'Image and video files');

  const _AddSource(this.icon, this.label, this.detail);
  final IconData icon;
  final String label;
  final String detail;
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(tooltip: label, icon: Icon(icon), onPressed: onPressed),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.scan});

  final Scan scan;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _title = TextEditingController(text: widget.scan.title);
  late final _artist = TextEditingController(text: widget.scan.artist);

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    super.dispose();
  }

  void _done() =>
      Navigator.pop(context, (_title.text.trim(), _artist.text.trim()));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Song'),
            textInputAction: TextInputAction.next,
          ),
          TextField(
            controller: _artist,
            decoration: const InputDecoration(labelText: 'Artist'),
            onSubmitted: (_) => _done(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _done, child: const Text('Save')),
      ],
    );
  }
}
