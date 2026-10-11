import 'dart:async';

import 'package:flutter/material.dart';

import '../capture/media.dart';
import '../capture/page_source.dart';
import '../library/library.dart';
import '../library/capture_event.dart';
import '../processing/page_filter.dart';
import '../recognition/auto_reader.dart';
import '../cloud/cloud_ocr.dart';
import '../cloud/cloud_sync.dart';
import 'account_panel.dart';
import 'clone.dart';
import 'link_page.dart';
import 'page_image.dart';
import 'people_sheet.dart';
import 'premium_card.dart';
import 'rename_dialog.dart';
import 'share_sheet.dart';
import 'sign_in_gate.dart';
import 'tab_text_view.dart';
import 'text_page.dart';
import 'video_page.dart';

/// One event: its pages (images, videos and links) to swipe through, and
/// the tools along the bottom: the view (Original or Scan: the photos as
/// taken, or processed), Text (the tab read from them, in place of the
/// pages), Add (scan, photos and videos, files, a link), Rotate and
/// Delete. Share and rename are in the app bar. The tab is read by itself ([AutoReader]): there's
/// no Read tab button. With its images hidden, the pages are the text tab,
/// then the videos and links.
class EventScreen extends StatefulWidget {
  const EventScreen({
    super.key,
    required this.library,
    required this.eventId,
    this.sync,
    this.ocr,
    this.store,
  });

  final Library library;
  final String eventId;

  /// Cloud sync, for sharing the event with people (null: no sharing).
  final CloudSync? sync;

  /// TabScan Premium: the text tab comes from the cloud by itself; without
  /// it, a hint offers it on the web (null: not set up).
  final CloudOcr? ocr;

  /// Whether to leave out the Premium hint (null: [storeApp]).
  final bool? store;

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  final _pages = PageController();
  int _index = 0;
  bool _busy = false;

  Library get _library => widget.library;

  @override
  void initState() {
    super.initState();
    // A text tab marked correct is what the user wants to see: it opens on
    // the Text view (the Text tool goes back to the pages).
    final event = _library.byId(widget.eventId);
    _text = event != null && event.tabText != null && event.tabTextCorrect;
  }

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
      await showShareSheet(context, _library, event, sync: widget.sync);
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
      final first = _pagesOf(event).length;
      if (link != null) {
        await _library.addLink(event, link.$1, title: link.$2);
      } else if (source == _AddSource.scan) {
        final pages = await PageSource.scan(context);
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
      if (event.hideImages && link == null) {
        _snack('Added. Images are hidden on this capture.');
      }
      // Show the first page added.
      if (mounted) {
        setState(() => _index = first);
        _pages.jumpToPage(first);
      }
    });
  }

  bool _hintClosed = false;

  /// The upgrade hint, for users without Premium where it's set up; never
  /// in a [storeApp], which can't point to buying it.
  Widget? _premiumHint(CaptureEvent event) {
    final (ocr, sync) = (widget.ocr, widget.sync);
    if (ocr == null || sync == null || ocr.premium) return null;
    if (widget.store ?? storeApp) return null;
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

  /// Whether the Text view shows, in place of the pages.
  bool _text = false;

  /// What the image pages show here, when it isn't their saved filter (an
  /// event shared read only).
  _View? _shown;

  _View _viewOf(CaptureEvent event) {
    if (_shown case final shown?) return shown;
    final first = event.pages.where((p) => p.isImage).firstOrNull;
    return first?.filter == PageFilter.original ? _View.original : _View.scan;
  }

  /// Original ↔ Scan: sets the filter of every image page (saved, so
  /// thumbnails and exports follow), but only what shows for an event
  /// shared read only.
  Future<void> _nextView(CaptureEvent event) async {
    final next = _viewOf(event) == _View.original ? _View.scan : _View.original;
    setState(() => _shown = next);
    final filter = next == _View.original
        ? PageFilter.original
        : PageFilter.tab;
    if (event.readOnly) return;
    if (event.pages.every((p) => !p.isImage || p.filter == filter)) return;
    await _library.update(
      event.copyWith(
        pages: [
          for (final p in event.pages)
            p.isImage ? p.copyWith(filter: filter) : p,
        ],
      ),
    );
  }

  /// The Text view: the tab, or why there's none yet.
  Widget _textView(CaptureEvent event) {
    if (event.tabText != null) {
      return TabTextView(
        key: ValueKey('text-${event.id}'),
        library: _library,
        eventId: event.id,
        auth: widget.sync?.auth,
      );
    }
    final reader = AutoReaderScope.of(context);
    final images = event.pages.any((p) => p.isImage);
    void again() => reader?.readSoon(event.id);
    final (message, action) = switch (reader?.stateOf(event.id)) {
      _ when !images => ('Nothing to read: add a scan or a photo.', null),
      ReadState.reading => ('Reading the tab…', null),
      ReadState.inCloud => (
        'Transcribing in the cloud. The text appears here when it\'s done.',
        null,
      ),
      ReadState.noTab => (
        'No tab found in the pages. Try rescanning closer and flatter.',
        ('Read again', again),
      ),
      ReadState.failed => ('Reading the tab failed.', ('Read again', again)),
      ReadState.unsupported => (
        'Reading tabs needs the Android or iOS app, or TabScan Premium.',
        null,
      ),
      ReadState.needsSignIn => (
        'Reading tabs needs you signed in.',
        (
          'Sign in',
          () async {
            if (await requireSignIn(
                  context,
                  widget.sync?.auth,
                  Gated.readTab,
                ) &&
                mounted) {
              again();
            }
          },
        ),
      ),
      null when reader == null => ('No text yet.', null),
      null => ('Not read yet.', ('Read', again)),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reader?.stateOf(event.id) == ReadState.reading) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
            ],
            Text(message, textAlign: TextAlign.center),
            if (action case (final label, final onPressed)) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onPressed, child: Text(label)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _deletePage(CaptureEvent event, EventPage page) async {
    if (event.pages.length == 1) {
      _snack('An event keeps at least one page; delete the event instead.');
      return;
    }
    await _library.deletePage(event, page);
    setState(() => _index = _index.clamp(0, _pagesOf(event).length - 2));
  }

  /// What the pager shows: the pages, or with the images hidden, the text
  /// tab (null) and then the videos and links.
  List<EventPage?> _pagesOf(CaptureEvent event) =>
      event.hideImages ? [null, ...event.visiblePages] : event.pages;

  /// The owner hides the images, or shows them again, for everyone.
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _library,
      builder: (context, _) {
        final event = _library.byId(widget.eventId);
        if (event == null) return const Scaffold();
        final shown = _pagesOf(event);
        final index = _index.clamp(0, shown.length - 1);
        final page = shown.isEmpty ? null : shown[index];
        // Shared read only: everything that changes it is off.
        final editable = !event.readOnly;
        final enabled = !_busy && page != null && editable;
        final view = _viewOf(event);
        final text = _text;
        // Rotate is for images, not videos or links; nor in the Text view.
        final image = enabled && page.isImage && !text;
        final sync = widget.sync;
        // What the image pages show: Original or Scan.
        final filter = view == _View.original
            ? PageFilter.original
            : PageFilter.tab;
        EventPage shownPage(EventPage p) =>
            p.isImage && !text ? p.copyWith(filter: filter) : p;
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
              if (text)
                Expanded(child: _textView(event))
              else ...[
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: shown.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: switch (shown[i]) {
                        null => TextPage(
                          event: event,
                          onOpen: () => setState(() => _text = true),
                        ),
                        final p when p.isLink => LinkPage(
                          key: ValueKey(p.id),
                          page: p,
                        ),
                        final p when p.isVideo => VideoPage(
                          key: ValueKey(p.id),
                          library: _library,
                          event: event,
                          page: p,
                        ),
                        final p => InteractiveViewer(
                          maxScale: 5,
                          child: PageImage(
                            library: _library,
                            event: event,
                            page: shownPage(p),
                          ),
                        ),
                      },
                    ),
                  ),
                ),
                Text(
                  '${index + 1} / ${shown.length}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Tool(
                    key: const Key('view'),
                    icon: view.icon,
                    label: view.label,
                    onPressed: _busy || text ? null : () => _nextView(event),
                  ),
                  _Tool(
                    key: const Key('text'),
                    icon: text ? Icons.photo_library_outlined : Icons.notes,
                    label: text ? 'Pages' : 'Text',
                    onPressed: _busy
                        ? null
                        : () => setState(() => _text = !_text),
                  ),
                  _Tool(
                    icon: Icons.add_circle_outline,
                    label: 'Add',
                    onPressed: _busy || !editable ? null : () => _add(event),
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
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    onPressed: enabled && !text
                        ? () => _deletePage(event, page)
                        : null,
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

/// How the event screen shows the image pages, chosen with its first tool.
enum _View {
  original('Original', Icons.photo_outlined),
  scan('Scan', Icons.contrast);

  const _View(this.label, this.icon);
  final String label;
  final IconData icon;
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
  const _Tool({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
  });

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
