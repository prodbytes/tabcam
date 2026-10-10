import 'dart:async';

import 'package:flutter/material.dart';

import '../capture/media.dart';
import '../capture/page_source.dart';
import '../library/library.dart';
import '../library/capture_event.dart';
import '../processing/page_filter.dart';
import '../recognition/tab_reader.dart';
import '../cloud/cloud_ocr.dart';
import '../cloud/cloud_sync.dart';
import 'account_panel.dart';
import 'clone.dart';
import 'link_page.dart';
import 'page_image.dart';
import 'people_sheet.dart';
import 'rename_dialog.dart';
import 'share_sheet.dart';
import 'sign_in_gate.dart';
import 'tab_text_screen.dart';
import 'video_page.dart';

/// One event: its pages (images, videos and links) to swipe through, and
/// the tools along the bottom: Add (scan, photos and videos, files, a
/// link), Filter, Rotate, Read tab and Delete. Share and rename are in the app bar.
class EventScreen extends StatefulWidget {
  const EventScreen({
    super.key,
    required this.library,
    required this.eventId,
    this.sync,
    this.ocr,
  });

  final Library library;
  final String eventId;

  /// Cloud sync, for sharing the event with people (null: no sharing).
  final CloudSync? sync;

  /// TabScan Premium: the text tab comes from the cloud by itself; without
  /// it, a hint offers it (null: not set up).
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

  Future<void> _rename(CaptureEvent event) =>
      renameEvent(context, _library, event);

  /// Opens the share sheet, once the user is signed in.
  Future<void> _share(CaptureEvent event) async {
    if (await requireSignIn(context, widget.sync?.auth, Gated.share) &&
        mounted) {
      await showShareSheet(context, _library, event);
    }
  }

  /// Clones the event and opens the copy in this one's place.
  Future<void> _clone(CaptureEvent event) async {
    setState(() => _busy = true);
    final copy = await cloneEvent(context, _library, event);
    if (!mounted) return;
    setState(() => _busy = false);
    if (copy == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            EventScreen(library: _library, eventId: copy.id, sync: widget.sync),
      ),
    );
  }

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
    if (source == null || !mounted) return;
    final link = source == _AddSource.link ? await askForLink(context) : null;
    if (source == _AddSource.link && link == null) return;
    await _run('Couldn\'t add', () async {
      final first = event.pages.length;
      if (link != null) {
        await _library.addLink(event, link.$1, title: link.$2);
      } else if (source == _AddSource.scan) {
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

  /// Reads the tab, once the user is signed in (reading needs it).
  Future<void> _readTab(CaptureEvent event) async {
    final auth = widget.sync?.auth;
    _log(
      'event ${event.id}, ${event.pages.length} pages '
      '(${event.pages.map((p) => '${p.kind.name}/${p.extension}').join(', ')}), '
      'auth ${auth == null
          ? 'not set up'
          : auth.user == null
          ? 'signed out'
          : 'signed in'}',
    );
    if (await requireSignIn(context, auth, Gated.readTab) && mounted) {
      await _readTabNow(event);
    } else {
      _log('not signed in, stopped');
    }
  }

  /// Read tab's troubleshooting log (`devbox run android-log`, or the
  /// browser's console).
  static void _log(String message) => debugPrint('TabScan: read tab: $message');

  Future<void> _readTabNow(
    CaptureEvent event,
  ) => _run('Couldn\'t read the tab', () async {
    final ocr = widget.ocr;
    _log(
      ocr == null
          ? 'cloud OCR not set up'
          : 'cloud OCR: premium ${ocr.premium}, status '
                '${ocr.status == null ? 'unknown' : 'checked ${ocr.status!.checked}'}'
                '${ocr.error == null ? '' : ', error ${ocr.error}'}',
    );
    if (ocr != null && ocr.premium) {
      await _readInCloud(ocr, event);
      return;
    }
    _log('on the device: supported ${TabReader.supported}');
    if (!TabReader.supported) {
      _snack('Reading tabs needs the Android or iOS app, or TabScan Premium.');
      return;
    }
    final pages = [
      for (final p in event.pages)
        if (p.isImage) await _library.original(event, p),
    ];
    _log(
      '${pages.length} image pages (${pages.map((p) => p.length).join(', ')} bytes)',
    );
    if (pages.isEmpty) {
      _snack('Read tab reads photos and scans, and this event has none.');
      return;
    }
    final text = await TabReader.read(pages);
    _log(text == null ? 'no tab found' : 'read ${text.length} characters');
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
    final images = event.pages.where(CloudOcr.isImage).length;
    _log(
      'in the cloud: $images image pages the service reads, '
      'synced ${event.owner != null}, text tab ${event.tabText != null}',
    );
    if (images == 0) {
      _snack('Read tab reads photos and scans, and this event has none.');
      return;
    }
    final queued = await ocr.transcribe(event);
    _log('$queued pages queued');
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

  bool _hintClosed = false;

  /// The upgrade hint, for users without Premium where it's set up.
  Widget? _premiumHint(CaptureEvent event) {
    final (ocr, sync) = (widget.ocr, widget.sync);
    if (ocr == null || sync == null || ocr.premium) return null;
    if (event.tabText != null || event.readOnly || _hintClosed) return null;
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
              onPressed: () => showAccountSheet(context, sync.auth, sync, ocr),
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

  Future<void> _openText(CaptureEvent event) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TabTextScreen(
        library: _library,
        eventId: event.id,
        auth: widget.sync?.auth,
      ),
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
        // Shared read only: everything that changes it is off.
        final editable = !event.readOnly;
        final enabled = !_busy && page != null && editable;
        // Filter and Rotate are for images, not videos or links.
        final image = enabled && page.isImage;
        final sync = widget.sync;
        return Scaffold(
          appBar: AppBar(
            title: InkWell(
              onTap: editable ? () => _rename(event) : null,
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
              if (editable)
                IconButton(
                  tooltip: 'Rename',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _rename(event),
                ),
              if (sync != null && sync.canShare && !event.isShared)
                IconButton(
                  tooltip: 'Share with people',
                  icon: const Icon(Icons.group_add_outlined),
                  onPressed: () => showPeopleSheet(context, sync, event),
                ),
              IconButton(
                tooltip: 'Clone',
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: _busy ? null : () => _clone(event),
              ),
              IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.ios_share),
                onPressed: _busy ? null : () => _share(event),
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
              if (event.sharedBy case final owner?)
                _SharedBanner(owner: owner, readOnly: event.readOnly),
              ?_premiumHint(event),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: event.pages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: event.pages[i].isLink
                        ? LinkPage(
                            key: ValueKey(event.pages[i].id),
                            page: event.pages[i],
                          )
                        : event.pages[i].isVideo
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
                    onPressed: _busy || !editable ? null : () => _add(event),
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
  files(Icons.folder_open_outlined, 'Files', 'Image and video files'),
  link(Icons.link, 'Link', 'A lesson, a recording, the song online');

  const _AddSource(this.icon, this.label, this.detail);
  final IconData icon;
  final String label;
  final String detail;
}

/// Who shared the event with the user, and whether they can change it.
class _SharedBanner extends StatelessWidget {
  const _SharedBanner({required this.owner, required this.readOnly});

  final String owner;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              readOnly ? Icons.visibility_outlined : Icons.group_outlined,
              size: 18,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Shared by $owner · ${readOnly ? 'Read only' : 'Can edit'}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
