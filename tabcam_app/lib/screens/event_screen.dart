import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/link.dart';

import '../capture/media.dart';
import '../capture/page_source.dart';
import '../capture/play_along_screen.dart';
import '../capture/play_along_sidebar.dart';
import '../dictionary/dictionary_sidebar.dart';
import '../export/capture_link.dart';
import '../export/download.dart';
import '../import/tab_page_import.dart';
import '../l10n/language.dart';
import '../library/library.dart';
import '../library/capture_event.dart';
import '../metronome/metronome.dart';
import '../recognition/auto_reader.dart';
import '../recognition/file_dividers.dart';
import '../sound/ding.dart';
import '../cloud/cloud_ocr.dart';
import '../cloud/cloud_sync.dart';
import 'account_panel.dart';
import 'clone.dart';
import 'file_delete.dart';
import 'file_drop_area.dart';
import 'file_screen.dart';
import 'link_page.dart';
import 'premium_card.dart';
import 'rename_dialog.dart';
import 'share_sheet.dart';
import 'place.dart';
import 'sign_in_gate.dart';
import 'tab_notation.dart';
import 'tab_text_view.dart';
import 'video_edit_screen.dart';
import 'keys_help.dart';
import 'mono_font.dart';
import 'mini_player.dart';
import 'messages.dart';

/// One event (a capture): the list of its files (images, videos,
/// recordings, PDFs and links), each with a preview, a tap opening it alone
/// on a [FileScreen]; and the tools along the bottom: Files (the list),
/// Text (the tab read from them, in place of the list), Add (scan,
/// a document, photos and videos, files, a link) and Cam (recording the
/// user playing along with the tab, [PlayAlongScreen]). Rename, Clone and Share
/// are in the app bar. Editable, with more than one file, the list reorders
/// in place, each file dragged by its handle. The tab is read by itself
/// ([AutoReader]): there's no Read tab button. With its images hidden, the
/// list is the text tab, then the other files. In a build with Premium set
/// up ([ocr]), Text and Cam are Premium's ([premiumLocked]): for the
/// others, each tool shows its screen as a preview, greyed out and taking
/// nothing, under the Premium card ([PremiumGate]).
///
/// A capture shared with the user is read only: only its owner changes it.
/// Add (and files dropped on it) adds to the user's own copy of it instead
/// ([Library.copyToAdd]), and Cam opens on that copy; either way the copy
/// opens in its place.
///
/// Below the files, what people added before that ([Contribution]): on the
/// owner's capture, each person's files, which the owner publishes into
/// the capture (or takes back) one by one; on a capture shared with the
/// user, their own, which only they and the owner see.
class EventScreen extends StatefulWidget {
  const EventScreen({
    super.key,
    required this.library,
    required this.eventId,
    this.sync,
    this.ocr,
    this.initialFile,
    this.initialText,
    this.initialCam = false,
    this.initialEdit = false,
    this.byLink = false,
    this.onSignIn,
  });

  final Library library;
  final String eventId;

  /// Opened by its link, by someone it isn't shared with
  /// ([PublicCaptureScreen]): read only, no Clone (it isn't in their
  /// library), and a banner saying so.
  final bool byLink;

  /// With [byLink], signed out: the banner's **Sign in**. Signed out, the
  /// screen (and a file's opened from it) has none of the tools
  /// (Dictionary, Metronome, the keys' help), which are signed-in users'.
  final VoidCallback? onSignIn;

  /// The file it opens over its list (a reload: where the user was).
  final String? initialFile;

  /// Whether it opens on its Text view (null: if its text is marked correct).
  final bool? initialText;

  /// Whether Cam opens over it at once (a reload: where the user was),
  /// once Premium is known ([_reopenCam]).
  final bool initialCam;

  /// With [initialFile], whether the video editor opens over it (a link to
  /// the file's edit view, or a reload with the editor open). On a capture
  /// shared with the user (read only) the editor opens on their copy of it
  /// instead ([_editOnCopy]); opened by its link ([byLink]), the file
  /// alone.
  final bool initialEdit;

  /// Cloud sync, for sharing the event with people (null: no sharing).
  final CloudSync? sync;

  /// TabCam Premium: Text and Cam, and the text tab from the cloud by
  /// itself; without it, each offers Premium (null: not set up, and
  /// nothing is locked).
  final CloudOcr? ocr;

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> implements LinkAdder {
  final _list = ScrollController();
  bool _busy = false;

  Library get _library => widget.library;

  @override
  void initState() {
    super.initState();
    // The list of files, unless a reload puts the user back on the Text
    // view (Text shows the tab; the list is quick to open, the Text view
    // loads the sidebar's player).
    final event = _library.byId(widget.eventId);
    _text = widget.initialText ?? false;
    // The dictionary's results add their links here, on a capture the
    // user can change.
    if (event != null && !event.readOnly && !widget.byLink) {
      DictionaryState.instance.attachLinker(this);
    }
    // A reload: the file the user had open, over the list again.
    final file = event?.allPages.where((p) => p.id == widget.initialFile);
    if (file?.firstOrNull case final page?) {
      final edit = widget.initialEdit && !widget.byLink;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // The editor opens on a video of the capture's own files; on a
        // capture shared with the user, on their copy of it.
        final editable = edit && page.isVideo && event!.pages.contains(page);
        if (editable && event.isShared) {
          unawaited(_editOnCopy(event, page));
        } else {
          unawaited(_openFile(page, edit: editable));
        }
      });
    } else if (widget.initialCam) {
      // A reload: Cam, where the user was.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reopenCam();
      });
    }
  }

  /// Stops [_reopenCam] waiting.
  VoidCallback? _stopReopenCam;

  /// How long a reload waits for Premium's answer to reopen Cam.
  static const camReopenWait = Duration(seconds: 30);

  /// A reload with Cam open: Cam again, once the service says the user has
  /// Premium (until then Cam would open as its preview). Not if they
  /// haven't (or it doesn't answer in [camReopenWait], signed out say), nor
  /// if the user moved on meanwhile (a file opened, the screen left), nor
  /// where Cam can't add (read only); the place then forgets Cam.
  void _reopenCam() {
    final ocr = widget.ocr;
    final event = _library.byId(widget.eventId);
    final canAdd =
        event != null && !widget.byLink && (!event.readOnly || event.isShared);
    void forget() => PlaceMemory.of(
      _library,
    ).update((p) => p.eventId == widget.eventId ? p.copyWith(cam: false) : p);
    if (!canAdd) return forget();
    late final VoidCallback check;
    Timer? timer;
    void stop() {
      ocr?.removeListener(check);
      timer?.cancel();
      _stopReopenCam = null;
    }

    check = () {
      if (!mounted) return stop();
      final ready = ocr == null || ocr.premium;
      if (!ready && ocr.status == null) return;
      stop();
      if (ready && ModalRoute.isCurrentOf(context) == true && !_busy) {
        unawaited(_cam());
      } else {
        forget();
      }
    };
    _stopReopenCam = stop;
    ocr?.addListener(check);
    timer = Timer(camReopenWait, () {
      stop();
      if (mounted) forget();
    });
    check();
  }

  /// Whether Text and Cam are Premium's and the user has no Premium.
  bool get _locked => premiumLocked(widget.ocr);

  /// Who to subscribe as (null signed out, or in a build without sign-in).
  String? get _email => widget.sync?.auth.user?.email;

  /// Opened by its link, signed out ([EventScreen.onSignIn]): no tools.
  bool get _signedOut => widget.onSignIn != null;

  /// Remembers the view, for a reload ([PlaceMemory]).
  void _remember() => PlaceMemory.of(_library)
      .update((p) => p.eventId == widget.eventId ? p.copyWith(text: _text) : p);

  /// Opens [page] alone on its [FileScreen], remembered until it's closed.
  /// Opens [page]'s file screen over the list, and, with [edit], the
  /// video editor over that.
  Future<void> _openFile(EventPage page, {bool edit = false}) async {
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
          sync: widget.sync,
          ocr: widget.ocr,
          initialEdit: edit,
          signedOut: _signedOut,
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
    DictionaryState.instance.detachLinker(this);
    _stopReopenCam?.call();
    _stopFollowing();
    _list.dispose();
    _player.dispose();
    _alongOrNull?.dispose();
    _textActions.dispose();
    super.dispose();
  }

  /// The Text view's Copy, Fix, Rescan and Verified, in the app bar.
  final _textActions = TabTextActions();

  /// Playing along beside the Text view, made when it first shows.
  PlayAlong? _alongOrNull;
  // With the PDFs to follow beside the text, as in Cam.
  // On a phone it starts closed: open, it takes half the width from the
  // text and its tools (♫ in the More menu opens it).
  PlayAlong get _along => _alongOrNull ??= PlayAlong(
    _library,
    widget.eventId,
    withPdfs: true,
    opensByItself: MediaQuery.sizeOf(context).width >= 600,
  );

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

  /// On a phone, in the Text view: Dictionary and Metronome (their
  /// sidebars shown or hidden; signed in only), Play along, Rename, Clone,
  /// Download all and Share, in a menu at the app bar's end.
  Widget _moreMenu(CaptureEvent event, {required bool editable}) {
    final l10n = context.l10n;
    final along = _along;
    PopupMenuItem<VoidCallback> item(
      String key,
      IconData icon,
      String label,
      VoidCallback action, {
      bool enabled = true,
    }) => PopupMenuItem(
      key: Key(key),
      value: action,
      enabled: enabled,
      child: ListTile(leading: Icon(icon), title: Text(label)),
    );
    return PopupMenuButton<VoidCallback>(
      key: const Key('event-more'),
      tooltip: l10n.eventFileMore,
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        if (!_signedOut) ...[
          item(
            'more-dictionary',
            Icons.menu_book_outlined,
            DictionaryState.instance.open
                ? l10n.dictionaryHide
                : l10n.dictionary,
            DictionaryState.instance.toggle,
          ),
          item(
            'more-metronome',
            Icons.av_timer,
            MetronomeState.instance.open ? l10n.metronomeHide : l10n.metronome,
            MetronomeState.instance.toggle,
          ),
        ],
        if (along.available)
          item(
            'more-along',
            Icons.queue_music,
            along.open ? l10n.camAlongHide : l10n.camAlong,
            along.toggle,
          ),
        if (editable)
          item(
            'more-rename',
            Icons.edit_outlined,
            l10n.eventRename,
            () => _rename(event),
          ),
        if (!widget.byLink)
          item(
            'more-clone',
            Icons.copy_all_outlined,
            l10n.eventClone,
            () => _clone(event),
            enabled: !_busy,
          ),
        item(
          'more-download-all',
          Icons.download_outlined,
          l10n.eventDownloadAll,
          () => _downloadAll(event),
          enabled: !_busy,
        ),
        item(
          'more-share',
          Icons.link,
          l10n.eventShare,
          () => _share(event),
          enabled: !_busy,
        ),
      ],
    );
  }

  void _snack(String message) => showMessage(context, message);

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

  /// Clones the event and opens the copy in this one's place.
  Future<void> _clone(CaptureEvent event) async {
    setState(() => _busy = true);
    final copy = await cloneEvent(context, _library, event);
    if (!mounted) return;
    setState(() => _busy = false);
    if (copy == null) return;
    await _openInstead(copy);
  }

  /// Opens [copy] (a clone of this one, or the user's copy of this shared
  /// capture) in this one's place, with Cam over it at once if [cam].
  /// A link to a file's edit view on a capture shared with the user (read
  /// only: the editor doesn't open on it): the editor opens on their copy
  /// of it ([Library.copyToAdd], as Cam and Add do), over the copy's page
  /// of that file (the one showing it: copy on write), in this screen's
  /// place. When the user's copy has no page showing that file (it owns
  /// its files since it was shared, or the file came after it), or the
  /// copy can't be made, the file opens here instead, read only, as its
  /// plain link opens it.
  Future<void> _editOnCopy(CaptureEvent shown, EventPage page) async {
    final l10n = context.l10n;
    final origin = FileOrigin(shown.id, page.id);
    EventPage? showing(CaptureEvent copy) =>
        copy.pages.where((p) => p.source == origin).firstOrNull;
    final had = _library.copyOf(shown.id);
    if (had != null && showing(had) == null) return _openFile(page);
    final CaptureEvent copy;
    try {
      copy = had ?? await _library.copyToAdd(shown);
    } on Object catch (e) {
      if (!mounted) return;
      _snack('${l10n.eventCouldntAdd}: $e');
      return _openFile(page);
    }
    if (!mounted) return;
    final own = showing(copy);
    if (own == null) return _openFile(page);
    _snack(l10n.eventEditOnCopy(copy.title));
    await _openInstead(copy, file: own.id, edit: true);
  }

  Future<void> _openInstead(
    CaptureEvent copy, {
    bool cam = false,
    String? file,
    bool edit = false,
  }) async {
    // The copy is where the user is now (a reload opens it), until it's
    // closed.
    final memory = PlaceMemory.of(_library);
    memory.update(
      (p) => p.copyWith(
        eventId: () => copy.id,
        text: false,
        fileId: () => file,
        cam: cam,
        edit: edit,
      ),
    );
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        // With Premium's service: the copy is locked as this one is (Text,
        // Cam, the video editor's watermark).
        builder: (_) => EventScreen(
          library: _library,
          eventId: copy.id,
          sync: widget.sync,
          ocr: widget.ocr,
          initialCam: cam,
          initialFile: file,
          initialEdit: edit,
        ),
      ),
    );
    memory.update(
      (p) => p.eventId == copy.id
          ? p.copyWith(eventId: () => null, text: false, fileId: () => null)
          : p,
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
      final before = event.pages.length;
      // The event they went to: this one, or the user's copy of it when
      // it's shared with them.
      CaptureEvent target;
      if (link != null) {
        target = (await _addLinkTo(event, link.$1, link.$2)).target;
      } else if (source == _AddSource.scan) {
        widget.ocr?.warm();
        final pages = await PageSource.scan(context);
        if (pages.isEmpty) return;
        target = await _library.addPages(event, pages);
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
        target = await _library.addMedia(event, pick.media);
      }
      _showAdded(event, target, before, images: link == null);
    });
  }

  /// Adds [url] to [event] (or to the user's copy of it, [Library.addLink])
  /// as a link named [title]; a tab site's page is imported beside it, as
  /// a PDF to read, and the import says how it went. Returns where it went
  /// and whether the import said so.
  Future<({CaptureEvent target, bool told})> _addLinkTo(
    CaptureEvent event,
    Uri url,
    String? title,
  ) async {
    final l10n = context.l10n;
    final site = importableTabSite(url);
    if (site != null) _snack(l10n.linkTabImporting(site.name));
    final target = await _library.addLink(event, url, title: title);
    // A tab site's page, printed as a PDF beside the link, to read.
    final imported = await TabPageImporter.create(widget.ocr)
        .addTo(_library, target, url);
    if (imported != null && mounted) {
      replaceMessage(context, tabImportMessage(l10n, imported));
    }
    return (target: target, told: imported != null);
  }

  /// The dictionary's + on a YouTube or Cifra Club result: [url] added to
  /// this capture as a link named [title], as Add's Link adds one, the
  /// view kept (the Text view stays); unless it already has that link.
  @override
  Future<void> addLink(Uri url, {String? title}) async {
    final event = _library.byId(widget.eventId);
    if (event == null || !mounted) return;
    final l10n = context.l10n;
    // In place of the message showing: a + after another says at once.
    if (event.pages.any((p) => p.isLink && p.url == url)) {
      replaceMessage(context, l10n.dictionaryLinkThere);
      return;
    }
    await _run(l10n.eventCouldntAdd, () async {
      final added = await _addLinkTo(event, url, title);
      if (mounted && !added.told) {
        replaceMessage(context, l10n.dictionaryLinkAdded);
      }
    });
  }

  /// Cam: the camera, with the tab under it, to record playing along
  /// ([PlayAlongScreen]); back from it, the takes it added show, at the
  /// end of the list.
  Future<void> _cam() async {
    await _player.stop();
    await _alongOrNull?.track.pause();
    if (!mounted) return;
    final shown = _library.byId(widget.eventId);
    final before = shown?.pages.length ?? 0;
    // Without Premium, Cam opens as a preview: no camera, nothing works,
    // the Premium card over it.
    final gate = _locked ? (ocr: widget.ocr!, email: _email) : null;
    // Its takes are the user's: on a capture shared with them, Cam opens
    // on their copy of it (a preview adds nothing: it opens here).
    if (shown != null && shown.isShared && gate == null) {
      final l10n = context.l10n;
      final CaptureEvent copy;
      try {
        copy = await _library.copyToAdd(shown);
      } on Object catch (e) {
        if (mounted) _snack('${l10n.eventCouldntAdd}: $e');
        return;
      }
      if (!mounted) return;
      _snack(l10n.eventCamOnCopy(copy.title));
      return _openInstead(copy, cam: true);
    }
    // Remembered while it's open, for a reload (not the preview).
    final memory = PlaceMemory.of(_library);
    void remember(bool cam) => memory.update(
      (p) => p.eventId == widget.eventId ? p.copyWith(cam: cam) : p,
    );
    remember(gate == null);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayAlongScreen(
          library: _library,
          eventId: widget.eventId,
          gate: gate,
          ocr: widget.ocr,
          sync: widget.sync,
        ),
      ),
    );
    remember(false);
    final event = _library.byId(widget.eventId);
    if (mounted && event != null) {
      _showAdded(event, event, before, images: false);
    }
  }

  void _fileAction(_FileAction action, CaptureEvent event, EventPage page) =>
      switch (action) {
        _FileAction.rename => _renamePage(event, page),
        _FileAction.download => _download(event, page),
        _FileAction.delete => _deleteFile(event, page),
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

  /// Deletes one of its files, or one of the reader's own, once the user
  /// confirms ([deleteFile]); the capture's last one stays (the event is
  /// deleted instead).
  Future<void> _deleteFile(CaptureEvent event, EventPage page) => deleteFile(
    context,
    _library,
    event,
    page,
    letGo: () => _letGo(page),
    run: _run,
  );

  /// Lets go of [page], about to be deleted (from the list or the Text
  /// view's sidebar): it may be the one playing in the list, which plays on
  /// in the Text view.
  Future<void> _letGo(EventPage page) async {
    if (_player.holds(page)) await _player.stop();
  }

  /// Opens the video editor on [take], from the Text view's sidebar, as
  /// its file screen's Edit does. The list's player, which plays on in the
  /// Text view, stops first, so only the editor's preview sounds.
  Future<void> _editTake(EventPage take) async {
    await _player.stop();
    if (!mounted) return;
    await VideoEditScreen.open(
      context,
      library: _library,
      eventId: widget.eventId,
      page: take,
      ocr: widget.ocr,
      sync: widget.sync,
    );
  }

  /// Files the user dragged onto the screen ([FileDropArea]): added, as
  /// Add's Files would.
  Future<void> _addDropped(
    CaptureEvent event,
    List<XFile> files,
    int skipped,
  ) => _run(context.l10n.eventCouldntAdd, () async {
    final l10n = context.l10n;
    final pick = await MediaPick.from(files);
    if (!mounted) return;
    final notPages = pick.skipped + skipped;
    if (notPages > 0) _snack(l10n.eventSkippedFiles(notPages));
    if (pick.media.isEmpty) return;
    final before = event.pages.length;
    final target = await _library.addMedia(event, pick.media);
    _showAdded(event, target, before, images: true);
  });

  /// After files were added to [event] (which had [before] pages): when
  /// they went to the user's copy of it ([target], [Library.copyToAdd]),
  /// says so and opens the copy in its place; else says so when its images
  /// are hidden, and shows them at the end of the list.
  void _showAdded(
    CaptureEvent event,
    CaptureEvent target,
    int before, {
    required bool images,
  }) {
    if (!mounted) return;
    if (target.id != event.id) {
      _snack(context.l10n.eventAddedToCopy(target.title));
      unawaited(_openInstead(target));
      return;
    }
    if (event.hideImages && images) {
      _snack(context.l10n.eventAddedHidden);
    }
    final now = _library.byId(event.id);
    if (now == null || now.pages.length <= before) return;
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

  /// Whether the Text view shows, in place of the pages.
  bool _text = false;

  /// Rescan is reading the pages: the Text view spins, its text kept.
  bool get _rescanning => _unfollow != null;

  /// When Rescan's read started: the Text view's timer counts from it.
  DateTime? _rescanStarted;

  /// The Text view's Rescan: asks, then reads every photo and PDF again.
  /// The text stays (and the Text view spins, a timer counting) until the
  /// read ends: a tab found replaces it; none found, or a failure, keeps
  /// it and says why. Either way a ding, and a message says how long it
  /// took.
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
            onPressed: () {
              // From the tap, so the browser lets the ding play at the end.
              primeDing();
              Navigator.pop(context, true);
            },
            child: Text(l10n.textViewRescan),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    reader.readSoon(event.id, replace: true);
    _stopFollowing();
    final id = event.id;
    final started = DateTime.now();
    void follow() {
      final state = reader.stateOf(id);
      // Still reading: on the device, or in the cloud until its text comes.
      if (state == ReadState.reading || state == ReadState.inCloud) return;
      _stopFollowing();
      if (!mounted) return;
      setState(() {});
      // Done: a ding, and how long it took.
      unawaited(playDing());
      final l10n = context.l10n;
      final took = elapsedText(DateTime.now().difference(started));
      _snack(switch (state) {
        null => l10n.eventRescanned(took), // a tab found: the text replaced
        ReadState.noTab => l10n.eventRescanKept(took, l10n.eventNoTab),
        ReadState.unsupported => l10n.eventRescanKept(
          took,
          l10n.eventReadUnsupported,
        ),
        ReadState.needsSignIn => l10n.eventRescanKept(
          took,
          l10n.eventReadNeedsSignIn,
        ),
        _ => l10n.eventRescanKept(took, l10n.eventReadFailed),
      });
    }

    reader.addListener(follow);
    setState(() {
      _rescanStarted = started;
      _unfollow = () => reader.removeListener(follow);
    });
    follow();
  }

  /// Stops waiting on Rescan's read.
  VoidCallback? _unfollow;
  void _stopFollowing() {
    _unfollow?.call();
    _unfollow = null;
  }

  /// The Text view: the tab, or why there's none yet. Locked, a preview of
  /// it (the event's text, or a sample tab) under the Premium card.
  Widget _textView(CaptureEvent event) {
    final reader = AutoReaderScope.of(context);
    final state = reader?.stateOf(event.id);
    if (_locked) {
      final l10n = context.l10n;
      final sample = event.tabText == null;
      return PremiumGate(
        ocr: widget.ocr!,
        email: _email,
        lead: l10n.premiumTextFeature,
        onClose: () => setState(() => _text = false),
        child: Column(
          children: [
            if (sample)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  l10n.premiumSamplePreview,
                  key: const Key('premium-sample'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Expanded(
              child: TabTextView(
                key: ValueKey('text-preview-${event.id}'),
                library: _library,
                eventId: event.id,
                sample: sample ? premiumSampleTab : null,
              ),
            ),
          ],
        ),
      );
    }
    if (event.tabText != null) {
      return TabTextView(
        key: ValueKey('text-${event.id}'),
        library: _library,
        eventId: event.id,
        ocr: widget.ocr,
        actions: _textActions,
        // Rescan: the text replaced by a new reading of the pages.
        onRescan: reader != null && event.pages.any((p) => p.isImage || p.isPdf)
            ? () => _rescan(event)
            : null,
        rescanning: _rescanning,
        rescanStarted: _rescanStarted,
        onUpgrade: switch ((widget.sync, widget.ocr)) {
          (final sync?, final ocr?) => () => showAccountSheet(
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
      ReadState.needsPremium => (l10n.homePremiumBanner, null),
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

  /// What people added, below the capture's own files: each person's on
  /// the owner's capture, or the reader's own; null when there's none.
  Widget? _contributionList(CaptureEvent event) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final mine = event.isShared;
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

  /// A file's name in the list, then the date it was made, smaller and
  /// dimmer ([fileDate]; none for a file whose ID isn't a time): beside the
  /// name where the row has room, else on the line under it (a phone),
  /// so neither cuts the other short.
  Widget _fileName(CaptureEvent event, EventPage page) {
    final name = _fileLink(event, page);
    final made = timeOfId(page.id);
    if (made == null) return name;
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        name,
        Text(
          fileDate(context, made, DateTime.now()),
          key: ValueKey('file-date-${page.id}'),
          maxLines: 1,
          softWrap: false,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  /// A file's name as a link (on the web, a real one: Cmd or Ctrl-click,
  /// a middle click or the browser's menu opens it in a new tab): the
  /// file's own link ([CaptureLink], with `f`), or a link file's address.
  /// A plain tap opens it here, as the row does.
  Widget _fileLink(CaptureEvent event, EventPage page) {
    final name = Text(
      fileLabel(context.l10n, event, page),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final url = page.isLink ? page.url : CaptureLink.of(event, file: page);
    if (url == null) return name;
    return Link(
      uri: url,
      target: LinkTarget.blank,
      builder: (context, followLink) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // With a modifier the browser opens it (a new tab, a window).
          final keys = HardwareKeyboard.instance;
          if (kIsWeb &&
              (keys.isMetaPressed ||
                  keys.isControlPressed ||
                  keys.isShiftPressed)) {
            followLink?.call();
          } else if (page.isLink) {
            openLink(context, url);
          } else {
            _openFile(page);
          }
        },
        child: name,
      ),
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
      title: _fileName(event, page),
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
            MiniPlayButton(player: _player, event: event, page: page)
          else
            _openPlayButton(page),
          if (mine)
            IconButton(
              key: ValueKey('delete-contribution-${page.id}'),
              tooltip: l10n.eventDeleteFile,
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : () => _deleteFile(event, page),
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

  /// The play button of a file that doesn't play in the list (a video's
  /// or recording's is [MiniPlayButton]): a link's opens it in a new tab
  /// (on a phone, the browser or the app the system hands it to, such as
  /// YouTube); an image's or a PDF's opens its view ([FileScreen]), the
  /// play-along sidebar beside it. Each does what a tap on the row does.
  Widget _openPlayButton(EventPage page) {
    final url = page.isLink ? page.url : null;
    return IconButton.filledTonal(
      key: ValueKey(
        url != null ? 'link-play-${page.id}' : 'file-play-${page.id}',
      ),
      tooltip: url != null
          ? context.l10n.eventPlayLink
          : context.l10n.eventPlayFile,
      icon: const Icon(Icons.play_arrow),
      onPressed: url != null
          ? () => openLink(context, url)
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
                  // Its first line, past a file's divider.
                  ? tab
                            .split('\n')
                            .where((l) => l.trim().isNotEmpty)
                            .where((l) => !isFileDivider(l))
                            .firstOrNull ??
                        tab.split('\n').first
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
          title: _fileName(event, page),
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
                MiniPlayButton(player: _player, event: event, page: page)
              else
                _openPlayButton(page),
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
      listenable: Listenable.merge([_library, ?widget.ocr]),
      builder: (context, _) {
        final event = _library.byId(widget.eventId);
        if (event == null) return const Scaffold();
        // Shared with the user: read only, everything that changes it is
        // off, but Add and Cam add to the user's own copy of it.
        final editable = !event.readOnly;
        final canAdd = !widget.byLink && (editable || event.isShared);
        // The dictionary, the metronome and the keys' help: signed in only.
        final tools = !_signedOut;
        final text = _text;
        final locked = _locked;
        // The tools say they're Premium's only to a user the service said
        // has none ([CloudOcr.free]); until it has, no lock shows.
        final offered = locked && widget.ocr!.free;
        final l10n = context.l10n;
        final narrow = MediaQuery.sizeOf(context).width < 600;
        // The Text view's buttons are icons below 900 px too (a tablet
        // held upright): labelled, they'd leave the title no room beside
        // the other buttons.
        final compactText = MediaQuery.sizeOf(context).width < 900;
        // The Text view shows the tab: its buttons go in the app bar.
        final textActions = text && !locked && event.tabText != null;
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
                  if (event.study.isNotEmpty && !event.isShared)
                    Row(
                      key: const Key('event-study-line'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            event.study,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            actions: [
              // The Text view's Copy, Fix, Rescan and Verified, right of
              // the title: icons on a phone.
              if (textActions)
                ListenableBuilder(
                  listenable: _textActions,
                  builder: (context, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ..._textActions.build(context, compact: compactText),
                      if (!compactText) const SizedBox(width: 8),
                    ],
                  ),
                ),
              // On a phone they leave room for the title only with the
              // other buttons in a menu.
              if (textActions && narrow) ...[
                if (tools)
                  const KeysHelpButton(screen: KeysScreen.player, hidden: true),
                _moreMenu(event, editable: editable),
              ] else ...[
                if (tools) ...[
                  const DictionaryButton(),
                  const MetronomeButton(),
                ],
                if (text && !locked) PlayAlongButton(along: _along),
                if (tools) const KeysHelpButton(screen: KeysScreen.player),
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
            ],
            bottom: _busy
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(4),
                    child: LinearProgressIndicator(),
                  )
                : null,
          ),
          // Files dragged onto the screen are added to the capture.
          body: MetronomeBeside(
            enabled: tools,
            child: DictionaryBeside(
              enabled: tools,
              title: event.title,
              child: FileDropArea(
                enabled: !_busy && canAdd,
                onFiles: (files, skipped) => _addDropped(event, files, skipped),
                child: Column(
                  children: [
                    if (widget.byLink)
                      _LinkBanner(onSignIn: widget.onSignIn)
                    else if (event.sharedBy case final owner?)
                      _SharedBanner(owner: owner),
                    Expanded(
                      // Locked, the preview has no sidebar (nothing plays).
                      child: !text
                          ? _fileList(event)
                          : locked
                          ? _textView(event)
                          : PlayAlongBeside(
                              along: _along,
                              footer: const NotationSheet(),
                              deletes: !widget.byLink,
                              canDelete: !_busy,
                              // As the list's Delete: its player, its run.
                              letGo: _letGo,
                              run: _run,
                              onEdit: widget.byLink ? null : _editTake,
                              child: _textView(event),
                            ),
                    ),
                  ],
                ),
              ),
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
                    locked: offered,
                    tooltip: offered
                        ? l10n.eventPremiumTool(l10n.eventText)
                        : reading
                        ? l10n.eventReadingTab
                        : null,
                    // Reading again is the Text view's Rescan.
                    onPressed: _busy
                        ? null
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
                    locked: offered,
                    tooltip: offered
                        ? l10n.eventPremiumTool(l10n.eventCam)
                        : null,
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

  /// Renaming and deleting change the capture ([mayDeleteFile]); links
  /// have no file.
  bool offered(CaptureEvent event, EventPage page) => switch (this) {
    rename => !event.readOnly,
    delete => mayDeleteFile(event, page),
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

/// Who shared the event with the user, and that it's read only (what they
/// add goes to their copy).
class _SharedBanner extends StatelessWidget {
  const _SharedBanner({required this.owner});

  final String owner;

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
              Icons.visibility_outlined,
              size: 18,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.eventSharedBy(owner, l10n.eventReadOnly),
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

/// The date a file was [made], after its name in the capture's list, as of
/// [now]: in the app's language, the month and day ("Nov 21"), with the
/// year when it isn't [now]'s ("Mar 4, 2025").
String fileDate(BuildContext context, DateTime made, DateTime now) {
  final locale = Localizations.localeOf(context).toString();
  try {
    return (made.year == now.year
            ? DateFormat.MMMd(locale)
            : DateFormat.yMMMd(locale))
        .format(made);
  } on Object {
    return MaterialLocalizations.of(context).formatShortDate(made);
  }
}
