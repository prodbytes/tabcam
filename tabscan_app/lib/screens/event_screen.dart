import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../capture/media.dart';
import '../capture/page_source.dart';
import '../cloud/cloud_ocr.dart';
import '../cloud/cloud_sync.dart';
import '../library/library.dart';
import '../library/capture_event.dart';
import '../processing/page_filter.dart';
import '../recognition/tab_reader.dart';
import 'account_sheet.dart';
import 'page_image.dart';
import 'rename_dialog.dart';
import 'share_sheet.dart';
import 'tab_text_screen.dart';
import 'video_page.dart';

/// One event: its pages (images and videos) to swipe through, and the tools
/// along the bottom: Add (scan, photos and videos, files), Filter, Rotate,
/// Read tab and Delete. Share and rename are in the app bar.
///
/// With TabScan Premium ([ocr]) the text tab comes from the cloud by itself;
/// without it, a hint offers it, and Read tab reads on the device.
class EventScreen extends StatefulWidget {
  const EventScreen({
    super.key,
    required this.library,
    required this.eventId,
    this.auth,
    this.sync,
    this.ocr,
  });

  final Library library;
  final String eventId;
  final AuthService? auth;
  final CloudSync? sync;
  final CloudOcr? ocr;

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
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

  Future<void> _rename(CaptureEvent event) =>
      renameEvent(context, _library, event);

  Future<void> _add(CaptureEvent event) async {
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
      final first = event.pages.length;
      if (source == _AddSource.scan) {
        final pages = await PageSource.scan();
        if (pages.isEmpty) return;
        await _library.addPages(event, pages);
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
        await _library.addMedia(event, pick.media);
      }
      // Show the first page added.
      if (mounted) {
        setState(() => _index = first);
        _pages.jumpToPage(first);
      }
    });
  }

  Future<void> _toggleFilter(CaptureEvent event, EventPage page) {
    final next = page.filter == PageFilter.tab
        ? PageFilter.original
        : PageFilter.tab;
    return _library.update(
      event.copyWith(
        pages: [
          for (final p in event.pages)
            p.id == page.id ? p.copyWith(filter: next) : p,
        ],
      ),
    );
  }

  Future<void> _readTab(
    CaptureEvent event,
  ) => _run('Couldn\'t read the tab', () async {
    if (widget.ocr case final ocr? when ocr.premium) {
      await _readInCloud(ocr, event);
      return;
    }
    if (!TabReader.supported) {
      _snack('Reading tabs needs the Android or iOS app, or TabScan Premium.');
      return;
    }
    final pages = [
      for (final p in event.pages)
        if (!p.isVideo) await _library.original(event, p),
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
    await _openText(await _library.update(event.copyWith(tabText: text)));
  });

  /// Premium: the cloud transcribes the event's synced pages; the text tab
  /// shows on the event when it's done.
  Future<void> _readInCloud(CloudOcr ocr, CaptureEvent event) async {
    if (!event.pages.any(CloudOcr.isImage)) {
      _snack('Read tab reads photos and scans, and this has only videos.');
      return;
    }
    final queued = await ocr.transcribe(event);
    if (!mounted) return;
    if (queued > 0) {
      _snack('Transcribing in the cloud. The text tab appears here when done.');
    } else if (event.tabText != null) {
      await _openText(event);
    } else {
      _snack(
        'The text tab appears here once the pages have synced and been '
        'transcribed.',
      );
      unawaited(widget.sync?.syncNow());
    }
  }

  /// The upgrade hint, for users without Premium where it's set up.
  Widget? _premiumHint(CaptureEvent event) {
    final ocr = widget.ocr;
    final (auth, sync) = (widget.auth, widget.sync);
    if (ocr == null || auth == null || sync == null || ocr.premium) {
      return null;
    }
    if (event.tabText != null || _hintClosed) return null;
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.auto_awesome),
        title: const Text(
          'TabScan Premium transcribes your scans automatically.',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => showAccountSheet(context, auth, sync, ocr),
              child: const Text('Upgrade'),
            ),
            IconButton(
              tooltip: 'Not now',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _hintClosed = true),
            ),
          ],
        ),
      ),
    );
  }

  bool _hintClosed = false;

  Future<void> _openText(CaptureEvent event) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TabTextScreen(library: _library, eventId: event.id),
    ),
  );

  Future<void> _deletePage(CaptureEvent event, EventPage page) async {
    if (event.pages.length == 1) {
      _snack('An event keeps at least one page; delete the event instead.');
      return;
    }
    await _library.deletePage(event, page);
    setState(() => _index = _index.clamp(0, event.pages.length - 2));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _library,
      builder: (context, _) {
        final event = _library.byId(widget.eventId);
        if (event == null) return const Scaffold();
        final index = _index.clamp(0, event.pages.length - 1);
        final page = event.pages.isEmpty ? null : event.pages[index];
        final enabled = !_busy && page != null;
        // Filter and Rotate are for images, not videos.
        final image = enabled && !page.isVideo;
        return Scaffold(
          appBar: AppBar(
            title: InkWell(
              onTap: () => _rename(event),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title, overflow: TextOverflow.ellipsis),
                  if (event.artist.isNotEmpty)
                    Text(
                      event.artist,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            actions: [
              if (event.tabText != null)
                IconButton(
                  tooltip: 'Text tab',
                  icon: const Icon(Icons.notes),
                  onPressed: () => _openText(event),
                ),
              IconButton(
                tooltip: 'Rename',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _rename(event),
              ),
              IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.ios_share),
                onPressed: _busy
                    ? null
                    : () => showShareSheet(context, _library, event),
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
              ?_premiumHint(event),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: event.pages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: event.pages[i].isVideo
                        ? VideoPage(
                            key: ValueKey(event.pages[i].id),
                            library: _library,
                            event: event,
                            page: event.pages[i],
                          )
                        : InteractiveViewer(
                            maxScale: 5,
                            child: PageImage(
                              library: _library,
                              event: event,
                              page: event.pages[i],
                            ),
                          ),
                  ),
                ),
              ),
              Text(
                '${index + 1} / ${event.pages.length}',
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
                    onPressed: _busy ? null : () => _add(event),
                  ),
                  _Tool(
                    icon: page?.filter == PageFilter.tab
                        ? Icons.contrast
                        : Icons.photo_outlined,
                    label: page?.filter.label ?? 'Filter',
                    onPressed: image ? () => _toggleFilter(event, page) : null,
                  ),
                  _Tool(
                    icon: Icons.rotate_90_degrees_cw_outlined,
                    label: 'Rotate',
                    onPressed: image
                        ? () => _run(
                            'Couldn\'t rotate',
                            () => _library.rotatePage(event, page),
                          )
                        : null,
                  ),
                  _Tool(
                    icon: Icons.text_snippet_outlined,
                    label: 'Read tab',
                    onPressed: enabled ? () => _readTab(event) : null,
                  ),
                  _Tool(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    onPressed: enabled ? () => _deletePage(event, page) : null,
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
