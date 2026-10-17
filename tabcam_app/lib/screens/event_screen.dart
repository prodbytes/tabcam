import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

import '../capture/media.dart';
import '../capture/page_source.dart';
import '../capture/play_along_screen.dart';
import '../capture/play_along_sidebar.dart';
import '../export/download.dart';
import '../import/tab_page_import.dart';
import '../l10n/language.dart';
import '../library/library.dart';
import '../library/capture_event.dart';
import '../recognition/auto_reader.dart';
import '../cloud/cloud_ocr.dart';
import '../cloud/cloud_sync.dart';
import 'account_panel.dart';
import 'clone.dart';
import 'file_drop_area.dart';
import 'file_screen.dart';
import 'link_page.dart';
import 'premium_card.dart';
import 'rename_dialog.dart';
import 'share_sheet.dart';
import 'people_sheet.dart';
import 'place.dart';
import 'sign_in_gate.dart';
import 'tab_text_view.dart';
import 'mono_font.dart';
import 'mini_player.dart';

/// One event (a capture): the list of its files (images, videos,
/// recordings, PDFs and links), each with a preview, a tap opening it alone
/// on a [FileScreen]; and the tools along the bottom: Files (the list),
/// Text (the tab read from them, in place of the list), Add (scan,
/// a document, photos and videos, files, a link) and Cam (recording the
/// user playing along with the tab, [PlayAlongScreen]). Rename, Clone and Share
/// are in the app bar. Editable, with more than one file, the list reorders
/// in place, each file dragged by its handle. The tab is read by itself
/// ([AutoReader]): there's no Read tab button. With its images hidden, the
/// list is the text tab, then the other files.
///
/// Below them, what people added ([Contribution]): on the owner's capture,
/// each person's files, which the owner publishes into the capture (or
/// takes back) one by one; on a capture shared with the user to read, their
/// own, which only they and the owner see. There, Add and Cam add to it.
class EventScreen extends StatefulWidget {
  const EventScreen({
    super.key,
    required this.library,
    required this.eventId,
    this.sync,
    this.ocr,
    this.store,
    this.initialFile,
    this.initialText,
    this.byLink = false,
    this.onSignIn,
  });

  final Library library;
  final String eventId;

  /// Opened by its link, by someone it isn't shared with
  /// ([PublicCaptureScreen]): read only, no Clone (it isn't in their
  /// library), and a banner saying so.
  final bool byLink;

  /// With [byLink], signed out: the banner's **Sign in**.
  final VoidCallback? onSignIn;

  /// The file it opens over its list (a reload: where the user was).
  final String? initialFile;

  /// Whether it opens on its Text view (null: if its text is marked correct).
  final bool? initialText;

  /// Cloud sync, for sharing the event with people (null: no sharing).
  final CloudSync? sync;

  /// TabCam Premium: the text tab comes from the cloud by itself; without
  /// it, a hint offers it on the web (null: not set up).
  final CloudOcr? ocr;

  /// Whether to leave out the Premium hint (null: [storeApp]).
  final bool? store;

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  final _list = ScrollController();
  bool _busy = false;

  Library get _library => widget.library;

  @override
  void initState() {
    super.initState();
    // A text tab marked correct is what the user wants to see: it opens on
    // the Text view (the Text tool goes back to the pages).
    final event = _library.byId(widget.eventId);
    _text =
        widget.initialText ??
        (event != null && event.tabText != null && event.tabTextCorrect);
    // A reload: the file the user had open, over the list again.
    final file = event?.allPages.where((p) => p.id == widget.initialFile);
    if (file?.firstOrNull case final page?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openFile(page);
      });
    }
  }

  /// Remembers the view, for a reload ([PlaceMemory]).
  void _remember() => PlaceMemory.of(_library)
      .update((p) => p.eventId == widget.eventId ? p.copyWith(text: _text) : p);

  /// Opens [page] alone on its [FileScreen], remembered until it's closed.
  Future<void> _openFile(EventPage page) async {
    // The file screen has its own player: the list's stops.
    await _player.stop();
    if (!mounted) return;
    final memory = PlaceMemory.of(_library);
    void remember(String? id) => memory.update(
      (p) => p.eventId == widget.eventId ? p.copyWith(fileId: () => id) : p,
    );
    remember(page.id);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FileScreen(
          library: _library,
          eventId: widget.eventId,
          pageId: page.id,
        ),
      ),
    );
    remember(null);
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _remember();
  }

  @override
  void dispose() {
    _stopFollowing();
    _list.dispose();
    _player.dispose();
    _alongOrNull?.dispose();
    super.dispose();
  }

  /// Playing along beside the Text view, made when it first shows.
  PlayAlong? _alongOrNull;
  PlayAlong get _along => _alongOrNull ??= PlayAlong(_library, widget.eventId);

  /// Plays videos and recordings from the list, one at a time.
  late final ListPlayer _player = ListPlayer(_library);

  /// Runs [task] with the progress bar shown and buttons off, and reports
  /// a failure.
  Future<void> _run(String failure, Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } on Object catch (e, stack) {
      debugPrint('TabCam: $failure: $e\n$stack');
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

  /// Names one of its files (a photo, a PDF, a link, ...).
  Future<void> _renamePage(CaptureEvent event, EventPage page) => renamePage(
    context,
    _library,
    event,
    page,
    fileLabel(context.l10n, event, page),
  );

  /// Share: copies the capture's link, at once (signed out, after signing
  /// in).
  Future<void> _share(CaptureEvent event) =>
      shareCapture(context, event, sync: widget.sync);

  /// Share with people: who it's shared with, by email.
  Future<void> _people(CaptureEvent event) async {
    final sync = widget.sync;
    if (sync == null) return;
    if (await requireSignIn(context, sync.auth, Gated.share) && mounted) {
      await showPeopleSheet(context, sync, event);
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
    final l10n = context.l10n;
    final source = await showModalBottomSheet<_AddSource>(
      context: context,
      showDragHandle: true,
      // Five sources: taller than a sheet's default on a small phone.
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final source in _AddSource.values)
                ListTile(
                  leading: Icon(source.icon),
                  title: Text(source.label(context.l10n)),
                  subtitle: Text(source.detail(context.l10n)),
                  onTap: () => Navigator.pop(context, source),
                ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    final link = source == _AddSource.link ? await askForLink(context) : null;
    if (source == _AddSource.link && link == null) return;
    await _run(l10n.eventCouldntAdd, () async {
      final before = Library.addedPages(event).length;
      if (link != null) {
        final url = link.$1;
        final site = tabSiteOf(url);
        if (site != null) _snack(l10n.linkTabImporting(site.name));
        final added = await _library.addLink(event, url, title: link.$2);
        // A tab site's page, printed as a PDF beside the link, to read.
        final imported = await TabPageImporter.create(widget.ocr)
            .addTo(_library, added, url);
        if (imported != null && mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          _snack(tabImportMessage(l10n, imported));
        }
      } else if (source == _AddSource.scan) {
        final pages = await PageSource.scan(context);
        if (pages.isEmpty) return;
        await _library.addPages(event, pages);
      } else {
        final pick = switch (source) {
          _AddSource.document => await MediaSource.documents(),
          _AddSource.library => await MediaSource.library(),
          _ => await MediaSource.files(),
        };
        if (pick.skipped > 0) {
          _snack(l10n.eventSkippedFiles(pick.skipped));
        }
        if (pick.media.isEmpty) return;
        await _library.addMedia(event, pick.media);
      }
      _showAdded(event, before, images: link == null);
    });
  }

  /// Cam: the camera, with the tab under it, to record playing along
  /// ([PlayAlongScreen]); back from it, the takes it added show, at the
  /// end of the list.
  Future<void> _cam() async {
    await _player.stop();
    await _alongOrNull?.track.pause();
    if (!mounted) return;
    final before = switch (_library.byId(widget.eventId)) {
      final event? => Library.addedPages(event).length,
      null => 0,
    };
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PlayAlongScreen(library: _library, eventId: widget.eventId),
      ),
    );
    final event = _library.byId(widget.eventId);
    if (mounted && event != null) _showAdded(event, before, images: false);
  }

  void _fileAction(_FileAction action, CaptureEvent event, EventPage page) =>
      switch (action) {
        _FileAction.rename => _renamePage(event, page),
        _FileAction.download => _download(event, page),
        _FileAction.delete => _deletePage(event, page),
      };

  /// Downloads one file: the browser's download, or the system's "save
  /// as" on Android and iOS.
  Future<void> _download(CaptureEvent event, EventPage page) {
    final l10n = context.l10n;
    return _run(
      l10n.eventCouldntDownload,
      () => Downloads.saveFile(
        _library,
        event,
        page,
        fileLabel(l10n, event, page),
      ),
    );
  }

  /// Downloads every file, the text tab and the links, as one zip.
  Future<void> _downloadAll(CaptureEvent event) {
    final l10n = context.l10n;
    return _run(
      l10n.eventCouldntDownload,
      () => Downloads.saveAll(
        _library,
        event,
        (page) => fileLabel(l10n, event, page),
      ),
    );
  }

  /// Deletes one of its files from the list, once the user confirms; the
  /// last one stays (the event is deleted instead).
  Future<void> _deletePage(CaptureEvent event, EventPage page) async {
    final l10n = context.l10n;
    if (event.pages.length == 1) {
      _snack(l10n.eventKeepOnePage);
      return;
    }
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.homeLibraryDeleteTitle(fileLabel(l10n, event, page))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.eventCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.eventDelete),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    // It may be the one playing in the list.
    if (_player.holds(page)) await _player.stop();
    await _run(l10n.eventCouldntDelete, () async {
      // As it is now: a read may have changed it meanwhile.
      final now = _library.byId(event.id);
      if (now != null) await _library.deletePage(now, page);
    });
  }

  /// Files the user dragged onto the screen ([FileDropArea]): added, as
  /// Add's Files would.
  Future<void> _addDropped(
    CaptureEvent event,
    List<XFile> files,
    int skipped,
  ) => _run(context.l10n.eventCouldntAdd, () async {
    final pick = MediaPick.of(files);
    final notPages = pick.skipped + skipped;
    if (notPages > 0) _snack(context.l10n.eventSkippedFiles(notPages));
    if (pick.media.isEmpty) return;
    final before = Library.addedPages(event).length;
    await _library.addMedia(event, pick.media);
    _showAdded(event, before, images: true);
  });

  /// After files were added to [event] (which had [before] pages, or its
  /// reader's contribution had): says so when its images are hidden, and
  /// shows them at the end of the list.
  void _showAdded(CaptureEvent event, int before, {required bool images}) {
    if (event.hideImages && images && !event.contributes) {
      _snack(context.l10n.eventAddedHidden);
    }
    final now = _library.byId(event.id);
    if (!mounted || now == null || Library.addedPages(now).length <= before) {
      return;
    }
    setState(() => _text = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_list.hasClients) {
        _list.animateTo(
          _list.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Moves the listed file at [from] to [to] and saves the order at once
  /// ([Library.reorderPages]). Only the listed (visible) files are
  /// reordered: with the images hidden, they keep their places.
  Future<void> _move(List<EventPage> listed, int from, int to) async {
    final order = [...listed];
    order.insert(to, order.removeAt(from));
    try {
      await _library.reorderPages(widget.eventId, [
        for (final p in order) p.id,
      ]);
    } on Object catch (e, stack) {
      debugPrint('TabCam: reorder: $e\n$stack');
      if (mounted) _snack('${context.l10n.eventCouldntReorder}: $e');
    }
  }

  bool _hintClosed = false;

  /// The upgrade hint, for users without Premium where it's set up; never
  /// in a [storeApp], which can't point to buying it.
  Widget? _premiumHint(CaptureEvent event) {
    final (ocr, sync) = (widget.ocr, widget.sync);
    if (ocr == null || sync == null || ocr.premium) return null;
    if (widget.store ?? storeApp) return null;
    if (event.tabText != null || event.readOnly || _hintClosed) return null;
    final l10n = context.l10n;
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.auto_awesome),
        title: Text(l10n.eventPremiumHint),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => showAccountSheet(context, sync.auth, sync, ocr),
              child: Text(l10n.eventUpgrade),
            ),
            IconButton(
              tooltip: l10n.eventNotNow,
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

  /// The Text tool tapped on the Text view: asks, then reads the tab again
  /// (a text the user edited or marked correct is kept).
  Future<void> _readAgain(CaptureEvent event) async {
    final reader = AutoReaderScope.of(context);
    if (reader == null) return;
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.eventReadAgainTitle),
        content: Text(l10n.eventReadAgainBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.eventCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.eventReadAgain),
          ),
        ],
      ),
    );
    if (sure == true && mounted) reader.readSoon(event.id, again: true);
  }

  /// Rescan is reading the pages: the Text view spins, its text kept.
  bool get _rescanning => _unfollow != null;

  /// The Text view's Rescan: asks, then reads every photo and PDF again.
  /// The text stays (and the Text view spins) until the read ends: a tab
  /// found replaces it, even one the user edited or marked verified (the
  /// mark is cleared); none found, or a failure, keeps it and says why.
  Future<void> _rescan(CaptureEvent event) async {
    final reader = AutoReaderScope.of(context);
    if (reader == null) return;
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.eventRescanTitle),
        content: Text(l10n.eventRescanBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.eventCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.textViewRescan),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    reader.readSoon(event.id, replace: true);
    _stopFollowing();
    final id = event.id;
    void follow() {
      final state = reader.stateOf(id);
      // Still reading: on the device, or in the cloud until its text comes.
      if (state == ReadState.reading || state == ReadState.inCloud) return;
      _stopFollowing();
      if (!mounted) return;
      setState(() {});
      if (state == null) return; // a tab found: the text is replaced
      final l10n = context.l10n;
      _snack(
        l10n.eventRescanKept(switch (state) {
          ReadState.noTab => l10n.eventNoTab,
          ReadState.unsupported => l10n.eventReadUnsupported,
          ReadState.needsSignIn => l10n.eventReadNeedsSignIn,
          _ => l10n.eventReadFailed,
        }),
      );
    }

    reader.addListener(follow);
    setState(() => _unfollow = () => reader.removeListener(follow));
    follow();
  }

  /// Stops waiting on Rescan's read.
  VoidCallback? _unfollow;
  void _stopFollowing() {
    _unfollow?.call();
    _unfollow = null;
  }

  /// The Text view: the tab, or why there's none yet.
  Widget _textView(CaptureEvent event) {
    final reader = AutoReaderScope.of(context);
    final state = reader?.stateOf(event.id);
    if (event.tabText != null) {
      return TabTextView(
        key: ValueKey('text-${event.id}'),
        library: _library,
        eventId: event.id,
        ocr: widget.ocr,
        // Rescan: the text replaced by a new reading of the pages.
        onRescan: reader != null && event.pages.any((p) => p.isImage || p.isPdf)
            ? () => _rescan(event)
            : null,
        rescanning: _rescanning,
        // Store apps can't point to buying Premium.
        onUpgrade: switch ((
          widget.sync,
          widget.ocr,
          widget.store ?? storeApp,
        )) {
          (final sync?, final ocr?, false) => () => showAccountSheet(
            context,
            sync.auth,
            sync,
            ocr,
          ),
          _ => null,
        },
      );
    }
    final l10n = context.l10n;
    // What a read reads: photos and PDFs.
    final images = event.pages.any((p) => p.isImage || p.isPdf);
    void again() => reader?.readSoon(event.id, again: true);
    final (message, action) = switch (state) {
      _ when !images => (l10n.eventNothingToRead, null),
      ReadState.reading => (l10n.eventReadingTab, null),
      // The cloud may find no tab: Read again asks it again.
      ReadState.inCloud => (l10n.eventInCloud, (l10n.eventReadAgain, again)),
      ReadState.noTab => (l10n.eventNoTab, (l10n.eventReadAgain, again)),
      ReadState.failed => (l10n.eventReadFailed, (l10n.eventReadAgain, again)),
      ReadState.unsupported => (l10n.eventReadUnsupported, null),
      ReadState.needsSignIn => (
        l10n.eventReadNeedsSignIn,
        (
          l10n.eventSignIn,
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
      null when reader == null => (l10n.eventNoTextYet, null),
      null => (l10n.eventNotReadYet, (l10n.eventRead, again)),
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

  /// The owner publishes [page], someone's contribution, into the capture
  /// (everyone sees it), or takes it back.
  Future<void> _togglePublished(CaptureEvent event, EventPage page) {
    final l10n = context.l10n;
    return _run(l10n.eventCouldntPublish, () async {
      final now = _library.byId(event.id);
      if (now == null) return;
      if (now.isPublished(page)) {
        if (_player.holds(page)) await _player.stop();
        await _library.unpublish(now, page);
      } else {
        await _library.publish(now, page);
        if (mounted) {
          _snack(l10n.eventPublishedSnack(fileLabel(l10n, now, page)));
        }
      }
    });
  }

  /// A reader deletes one of their own files, once they confirm.
  Future<void> _deleteContribution(CaptureEvent event, EventPage page) async {
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.homeLibraryDeleteTitle(fileLabel(l10n, event, page))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.eventCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.eventDelete),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    if (_player.holds(page)) await _player.stop();
    await _run(l10n.eventCouldntDelete, () async {
      final now = _library.byId(event.id);
      if (now != null) await _library.deleteContributionPage(now, page);
    });
  }

  /// What people added, below the capture's own files: each person's on
  /// the owner's capture, or the reader's own; null when there's none.
  Widget? _contributionList(CaptureEvent event) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final mine = event.contributes;
    final groups = [
      for (final c in event.contributions)
        if (c.pages.isNotEmpty) c,
    ]..sort((a, b) => (a.email ?? '~').compareTo(b.email ?? '~'));
    if (groups.isEmpty) return null;
    return Column(
      key: const Key('contributions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in groups) ...[
          const Divider(height: 24),
          ListTile(
            dense: true,
            leading: Icon(
              mine ? Icons.person_outline : Icons.inbox_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(
              mine
                  ? l10n.eventYourFiles
                  : l10n.eventFilesFrom(c.email ?? l10n.eventSomeone),
              style: theme.textTheme.titleSmall,
            ),
            subtitle: Text(
              mine
                  ? l10n.eventYourFilesDetail(event.sharedBy ?? '')
                  : l10n.eventPublishHint,
            ),
          ),
          for (final page in c.pages) _contributionTile(event, page, mine),
        ],
      ],
    );
  }

  /// One contribution's file: on the owner's capture with Publish (or
  /// Published, to take back); on the reader's with Delete.
  Widget _contributionTile(CaptureEvent event, EventPage page, bool mine) {
    final l10n = context.l10n;
    final published = event.isPublished(page);
    final playable = page.kind == PageKind.video || page.kind == PageKind.audio;
    final thumbnail = FileThumbnail(
      library: _library,
      event: event,
      page: page,
    );
    return ListTile(
      key: ValueKey('contribution-${page.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      minVerticalPadding: 10,
      leading: page.kind == PageKind.video
          ? MiniVideo(player: _player, page: page, thumbnail: thumbnail)
          : thumbnail,
      title: Text(
        fileLabel(l10n, event, page),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: published
          ? Text(l10n.eventPublished)
          : page.url != null
          ? Text('${page.url}', maxLines: 1, overflow: TextOverflow.ellipsis)
          : playable
          ? MiniProgress(player: _player, page: page)
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (playable)
            MiniPlayButton(player: _player, event: event, page: page),
          if (mine)
            IconButton(
              key: ValueKey('delete-contribution-${page.id}'),
              tooltip: l10n.eventDeleteFile,
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : () => _deleteContribution(event, page),
            )
          else
            IconButton(
              key: ValueKey('publish-${page.id}'),
              tooltip: published ? l10n.eventUnpublish : l10n.eventPublish,
              isSelected: published,
              icon: const Icon(Icons.publish_outlined),
              selectedIcon: const Icon(Icons.check_circle),
              onPressed: _busy ? null : () => _togglePublished(event, page),
            ),
        ],
      ),
      onTap: page.isLink && page.url != null
          ? () => openLink(context, page.url!)
          : () => _openFile(page),
    );
  }

  /// The list: each file with its preview, a tap opening it alone; with
  /// the images hidden, the text tab first (a tap goes to the Text view).
  /// What people added follows ([_contributionList]).
  Widget _fileList(CaptureEvent event) {
    final l10n = context.l10n;
    final tab = event.tabText?.trim() ?? '';
    final pages = event.visiblePages;
    // Editable with more than one file: each has a drag handle.
    final reorder = !event.readOnly && pages.length > 1 && !_busy;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final textTab = !event.hideImages
        ? null
        : ListTile(
            key: const Key('text-tab'),
            leading: const SizedBox.square(
              dimension: fileThumbnailSize,
              child: Icon(Icons.notes),
            ),
            title: Text(
              tab.isNotEmpty ? l10n.textViewTextTab : l10n.textViewNoTextTab,
            ),
            subtitle: Text(
              tab.isNotEmpty
                  ? tab.split('\n').first
                  : event.readOnly
                  ? l10n.textViewHiddenNotRead
                  : l10n.textViewHiddenStillRead,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tab.isNotEmpty
                  ? const TextStyle(fontFamily: monoFont)
                  : null,
            ),
            onTap: () => setState(() => _text = true),
          );
    return ReorderableListView.builder(
      scrollController: _list,
      padding: const EdgeInsets.symmetric(vertical: 8),
      header: textTab,
      footer: _contributionList(event),
      buildDefaultDragHandles: false,
      itemCount: pages.length,
      onReorderItem: (from, to) => _move(pages, from, to),
      itemBuilder: (context, i) {
        final page = pages[i];
        final playable =
            page.kind == PageKind.video || page.kind == PageKind.audio;
        final thumbnail = FileThumbnail(
          library: _library,
          event: event,
          page: page,
        );
        return ListTile(
          key: ValueKey('file-${page.id}'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          minVerticalPadding: 10,
          // A video plays in its thumbnail's place.
          leading: page.kind == PageKind.video
              ? MiniVideo(player: _player, page: page, thumbnail: thumbnail)
              : thumbnail,
          title: Text(
            fileLabel(l10n, event, page),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: page.url != null
              ? Text(
                  '${page.url}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              // Playing: its progress and time.
              : playable
              ? MiniProgress(player: _player, page: page)
              : null,
          // A link's details (Copy, Delete) are behind its Details button:
          // a tap opens the link itself, outside the app. Editable, with
          // more than one file, each ends in a drag handle.
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (playable)
                MiniPlayButton(player: _player, event: event, page: page),
              // Rename, Download and Delete: buttons where there's room,
              // a menu on a narrow phone (the name needs the room).
              if (narrow)
                PopupMenuButton<_FileAction>(
                  key: ValueKey('more-${page.id}'),
                  tooltip: l10n.eventFileMore,
                  icon: const Icon(Icons.more_vert),
                  onSelected: (action) => _fileAction(action, event, page),
                  itemBuilder: (context) => [
                    for (final action in _FileAction.values)
                      if (action.offered(event, page))
                        PopupMenuItem(
                          key: ValueKey('${action.name}-${page.id}'),
                          value: action,
                          enabled: !_busy,
                          child: ListTile(
                            leading: Icon(action.icon),
                            title: Text(action.label(l10n)),
                          ),
                        ),
                  ],
                )
              else
                for (final action in _FileAction.values)
                  if (action.offered(event, page))
                    IconButton(
                      key: ValueKey('${action.name}-${page.id}'),
                      tooltip: action.label(l10n),
                      icon: Icon(action.icon),
                      onPressed: _busy && action != _FileAction.rename
                          ? null
                          : () => _fileAction(action, event, page),
                    ),
              if (page.isLink)
                IconButton(
                  key: ValueKey('details-${page.id}'),
                  tooltip: l10n.eventFileDetails,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _openFile(page),
                ),
              if (reorder)
                ReorderableDragStartListener(
                  key: ValueKey('drag-${page.id}'),
                  index: i,
                  child: Tooltip(
                    message: l10n.eventReorder,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                )
              else if (!page.isLink)
                const Icon(Icons.chevron_right),
            ],
          ),
          onTap: page.isLink && page.url != null
              ? () => openLink(context, page.url!)
              : () => _openFile(page),
          onLongPress: event.readOnly ? null : () => _renamePage(event, page),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _library,
      builder: (context, _) {
        final event = _library.byId(widget.eventId);
        if (event == null) return const Scaffold();
        // Shared to read: everything that changes it is off, but Add and
        // Cam add to the user's own contribution.
        final editable = !event.readOnly;
        final canAdd = !widget.byLink && (editable || event.contributes);
        final text = _text;
        final l10n = context.l10n;
        final hasText = event.tabText?.trim().isNotEmpty ?? false;
        final reading = switch (AutoReaderScope.of(context)
            ?.stateOf(event.id)) {
          ReadState.reading || ReadState.inCloud => true,
          _ => false,
        };
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
              if (text) PlayAlongButton(along: _along),
              if (editable)
                IconButton(
                  tooltip: l10n.eventRename,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _rename(event),
                ),
              if (!widget.byLink)
                IconButton(
                  tooltip: l10n.eventClone,
                  icon: const Icon(Icons.copy_all_outlined),
                  onPressed: _busy ? null : () => _clone(event),
                ),
              if (widget.sync case final sync?
                  when sync.canShare && !event.isShared)
                IconButton(
                  tooltip: l10n.eventShareWithPeople,
                  icon: const Icon(Icons.group_add_outlined),
                  onPressed: _busy ? null : () => _people(event),
                ),
              IconButton(
                key: const Key('download-all'),
                tooltip: l10n.eventDownloadAll,
                icon: const Icon(Icons.download_outlined),
                onPressed: _busy ? null : () => _downloadAll(event),
              ),
              IconButton(
                tooltip: l10n.eventShare,
                icon: const Icon(Icons.link),
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
          // Files dragged onto the screen are added to the capture.
          body: FileDropArea(
            enabled: !_busy && canAdd,
            onFiles: (files, skipped) => _addDropped(event, files, skipped),
            child: Column(
              children: [
                if (widget.byLink)
                  _LinkBanner(onSignIn: widget.onSignIn)
                else if (event.sharedBy case final owner?)
                  _SharedBanner(owner: owner, readOnly: event.readOnly),
                ?_premiumHint(event),
                Expanded(
                  child: text
                      ? PlayAlongBeside(along: _along, child: _textView(event))
                      : _fileList(event),
                ),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  EventTool(
                    key: const Key('files'),
                    icon: Icons.folder_copy_outlined,
                    label: l10n.eventFiles,
                    selected: !text,
                    // The Files view has no sidebar: what plays along
                    // pauses.
                    onPressed: _busy
                        ? null
                        : () {
                            unawaited(_alongOrNull?.track.pause());
                            setState(() => _text = false);
                          },
                  ),
                  EventTool(
                    key: const Key('text'),
                    icon: Icons.notes,
                    label: l10n.eventText,
                    selected: text,
                    // How the tab stands: being read, there, or not.
                    working: reading,
                    dimmed: !reading && !hasText,
                    tooltip: reading ? l10n.eventReadingTab : null,
                    // Again on the Text view, with a tab: read it again.
                    onPressed: _busy
                        ? null
                        : text && hasText && editable && !reading
                        ? () => _readAgain(event)
                        : () => setState(() => _text = true),
                  ),
                  EventTool(
                    icon: Icons.add_circle_outline,
                    label: l10n.eventAdd,
                    onPressed: _busy || !canAdd ? null : () => _add(event),
                  ),
                  EventTool(
                    key: const Key('cam'),
                    icon: Icons.videocam_outlined,
                    label: l10n.eventCam,
                    onPressed: _busy || !canAdd ? null : _cam,
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

/// What a file's row offers besides opening it.
enum _FileAction {
  rename(Icons.edit_outlined),
  download(Icons.download_outlined),
  delete(Icons.delete_outline);

  const _FileAction(this.icon);
  final IconData icon;

  /// Renaming and deleting change the capture; links have no file.
  bool offered(CaptureEvent event, EventPage page) => switch (this) {
    rename || delete => !event.readOnly,
    download => page.hasFile,
  };

  String label(AppLocalizations l10n) => switch (this) {
    rename => l10n.eventRenameFile,
    download => l10n.eventDownload,
    delete => l10n.eventDeleteFile,
  };
}

/// Where Add gets new pages.
enum _AddSource {
  scan(Icons.document_scanner_outlined),
  document(Icons.picture_as_pdf_outlined),
  library(Icons.photo_library_outlined),
  files(Icons.folder_open_outlined),
  link(Icons.link);

  const _AddSource(this.icon);
  final IconData icon;

  String label(AppLocalizations l10n) => switch (this) {
    scan => l10n.eventAddScan,
    document => l10n.eventAddDocument,
    library => l10n.eventAddLibrary,
    files => l10n.eventAddFiles,
    link => l10n.eventAddLink,
  };

  String detail(AppLocalizations l10n) => switch (this) {
    scan => l10n.eventAddScanDetail,
    document => l10n.eventAddDocumentDetail,
    library => l10n.eventAddLibraryDetail,
    files => l10n.eventAddFilesDetail,
    link => l10n.eventAddLinkDetail,
  };
}

/// A capture opened by its link: read only, and, signed out, **Sign in**.
class _LinkBanner extends StatelessWidget {
  const _LinkBanner({this.onSignIn});

  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final color = theme.colorScheme.onSecondaryContainer;
    return ColoredBox(
      key: const Key('link-banner'),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Icon(Icons.visibility_outlined, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.eventByLink,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color),
              ),
            ),
            if (onSignIn case final signIn?)
              TextButton(onPressed: signIn, child: Text(l10n.linkSignIn)),
          ],
        ),
      ),
    );
  }
}

/// Who shared the event with the user, and whether they can change it.
class _SharedBanner extends StatelessWidget {
  const _SharedBanner({required this.owner, required this.readOnly});

  final String owner;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
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
                l10n.eventSharedBy(
                  owner,
                  readOnly ? l10n.eventReadOnly : l10n.eventCanEdit,
                ),
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
