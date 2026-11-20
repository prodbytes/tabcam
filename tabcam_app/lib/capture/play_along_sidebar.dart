import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../l10n/language.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import '../screens/file_delete.dart';
import '../screens/file_screen.dart';
import '../screens/page_image.dart';
import '../screens/pdf_page.dart';
import '../screens/youtube_link.dart';
import '../screens/sidebar_widths.dart';
import '../screens/split_handle.dart';
import '../screens/mono_font.dart';
import 'backing_track.dart';
import 'link_frame.dart';

/// Playing along with a capture's recordings, videos and links, in Cam,
/// the Text view and a PDF: the [BackingTrack], and whether its sidebar
/// ([PlayAlongSidebar]) shows. The sidebar opens by itself, with the first
/// of them loaded, paused, the first time the capture has one (when the
/// screen opens, or when one arrives: a sync, a take); hidden by the user
/// ([toggle]), it isn't opened again.
///
/// In Cam ([withPdfs]) the sidebar lists the capture's PDFs too, to
/// follow one beside the camera: the one chosen ([followed]) shows in a
/// pane on the other side ([PlayAlongBeside]); the Text view's sidebar
/// lists them too, to check the reading against the page; a recording's
/// file screen lists its pages as well ([withImages]), to follow one
/// while it plays. With [withText] (Cam and the file screen), the
/// capture's text tab is listed first, to follow in the same pane
/// ([followsText]). On a capture shared to read, the reader's own files
/// (their takes) are listed too, after the capture's ([filesOf]).
class PlayAlong extends ChangeNotifier {
  PlayAlong(
    this.library,
    this.eventId, {
    BackingTrack? track,
    this.withPdfs = false,
    this.withImages = false,
    this.withText = false,
    this.startId,
    this.opensByItself = true,
  }) : track = track ?? BackingTrack(library) {
    library.addListener(_changed);
    _changed();
  }

  final Library library;
  final String eventId;
  final BackingTrack track;

  /// The files of [event] the sidebar may list: the capture's own, then,
  /// on one the user contributes to, their own contribution's (Cam's
  /// takes among them), but those published (the capture's copy is
  /// listed already).
  static List<EventPage> filesOf(CaptureEvent event) => [
    ...event.pages,
    for (final page in event.myContribution?.pages ?? const <EventPage>[])
      if (!event.isPublished(page)) page,
  ];

  /// Whether [event] still has [page] among the files the sidebar lists.
  static bool _has(CaptureEvent? event, EventPage page) =>
      event != null && filesOf(event).any((p) => p.id == page.id);

  /// Whether the sidebar lists the capture's PDFs, to follow one.
  final bool withPdfs;

  /// Whether the sidebar lists the capture's images, to follow one.
  final bool withImages;

  /// Whether the sidebar lists the capture's text tab, to follow it.
  final bool withText;

  /// The file the screen opened on (a recording), loaded in the frame
  /// when the sidebar opens by itself, instead of the first to play.
  final String? startId;

  /// Whether the sidebar opens by itself once the capture has something
  /// to list. False (the Text view on a phone, where it would take half
  /// the width): it stays closed until the user opens it, and loads the
  /// file to play then.
  final bool opensByItself;

  /// The page or PDF followed beside the screen, if one is.
  EventPage? get followed => _followed;
  EventPage? _followed;

  /// Whether the text tab is followed beside the screen (then no page is).
  bool get followsText => _followsText;
  bool _followsText = false;

  /// The capture's text tab, when the sidebar lists it: [withText] and
  /// the capture has one.
  String? get text {
    if (!withText) return null;
    final text = library.byId(eventId)?.tabText;
    return text == null || text.trim().isEmpty ? null : text;
  }

  /// Whether the sidebar shows.
  bool get open => _open;
  bool _open = false;

  /// Whether it has opened by itself yet (or the user has toggled it).
  bool _opened = false;

  /// Whether the capture has anything to play along with (or, with
  /// [withPdfs], a PDF to follow; with [withText], its text). The text
  /// alone doesn't open the sidebar by itself: ♫ does.
  bool get available {
    if (text != null) return true;
    final event = library.byId(eventId);
    return event != null && filesOf(event).any(_listed);
  }

  /// Whether the sidebar lists [page].
  bool _listed(EventPage page) => BackingTrack.plays(page) || follows(page);

  /// Whether the sidebar lists [page] to follow beside the screen.
  bool follows(EventPage page) =>
      (withPdfs && page.isPdf) || (withImages && page.isImage);

  /// The capture's PDFs and images the sidebar lists, to follow one.
  List<EventPage> get toFollow => [
    if (library.byId(eventId) case final event?)
      ...filesOf(event).where(follows),
  ];

  /// Shows [page] (a PDF or an image) beside the screen, or hides it,
  /// chosen again.
  void follow(EventPage page) {
    _followed = _followed?.id == page.id ? null : page;
    _followsText = false;
    notifyListeners();
  }

  /// Shows the text tab beside the screen, or hides it, chosen again.
  void followText() {
    _followsText = !_followsText;
    _followed = null;
    notifyListeners();
  }

  /// How wide the pane followed is, once the user has dragged its edge;
  /// null: its default ([PdfPaneWidth.of]). Kept while the screen is
  /// open, for the next file followed too.
  double? get paneWidth => _paneWidth;
  double? _paneWidth;

  /// Sets the pane's width (kept within the screen by its layout).
  void setPaneWidth(double width) {
    if (width == _paneWidth) return;
    _paneWidth = width;
    notifyListeners();
  }

  /// Puts the pane back to its default width.
  void resetPaneWidth() {
    if (_paneWidth == null) return;
    _paneWidth = null;
    notifyListeners();
  }

  /// Hides what's followed beside the screen.
  void unfollow() {
    if (_followed == null && !_followsText) return;
    _followed = null;
    _followsText = false;
    notifyListeners();
  }

  /// Shows or hides the sidebar; hidden, what plays pauses.
  void toggle() {
    _opened = true;
    _open = !_open;
    if (!_open) unawaited(track.pause());
    if (_open) _loadFirst();
    notifyListeners();
  }

  /// Shows the sidebar, with a file loaded to play (not playing) when
  /// none is ([_loadFirst]): Cam's **Play along with a song…**.
  void show() {
    _opened = true;
    _open = true;
    _loadFirst();
    notifyListeners();
  }

  /// Loads the file the screen opened on, if it plays, else the first
  /// that does, into the frame (not playing), when nothing is loaded yet:
  /// a song to play along with rather than one of Cam's takes ([isTake]),
  /// the most recent take only when there's nothing else.
  void _loadFirst() {
    final event = library.byId(eventId);
    if (event == null || track.page != null) return;
    final playing = filesOf(event).where(BackingTrack.plays);
    final first =
        playing.where((p) => p.id == startId).firstOrNull ??
        playing.where((p) => !isTake(p)).firstOrNull ??
        playing.lastOrNull;
    if (first != null) unawaited(track.choose(event, first, play: false));
  }

  /// Lets go of [page], about to be deleted: it stops playing (the
  /// track closes) and stops showing beside the screen.
  Future<void> letGo(EventPage page) async {
    if (_followed?.id == page.id) {
      _followed = null;
      notifyListeners();
    }
    if (track.page?.id == page.id) await track.close();
  }

  /// Plays [page] along (or pauses it, chosen again).
  Future<void> choose(EventPage page) async {
    final event = library.byId(eventId);
    if (event != null) await track.choose(event, page);
  }

  void _changed() {
    final event = library.byId(eventId);
    // The file followed, deleted (or synced away): the pane closes.
    if (_followed case final followed? when !_has(event, followed)) {
      _followed = null;
      notifyListeners();
    }
    // The file playing, deleted (or synced away): the player lets go.
    if (track.page case final playing? when !_has(event, playing)) {
      unawaited(track.close());
    }
    // The text, cleared: its pane closes.
    if (_followsText && text == null) {
      _followsText = false;
      notifyListeners();
    }
    if (_opened || !opensByItself) return;
    if (event == null || !filesOf(event).any(_listed)) return;
    _opened = true;
    _open = true;
    _loadFirst();
    notifyListeners();
  }

  @override
  void dispose() {
    library.removeListener(_changed);
    track.dispose();
    super.dispose();
  }
}

/// **Play along** for an app bar: ♫, in the primary colour while the
/// sidebar shows; nothing when there's nothing to play along with.
class PlayAlongButton extends StatelessWidget {
  const PlayAlongButton({super.key, required this.along, this.onPressed});

  final PlayAlong along;

  /// After the sidebar shows or hides.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: along,
    builder: (context, _) {
      if (!along.available) return const SizedBox.shrink();
      final l10n = context.l10n;
      return IconButton(
        key: const Key('cam-along'),
        tooltip: along.open ? l10n.camAlongHide : l10n.camAlong,
        isSelected: along.open,
        color: along.open ? Theme.of(context).colorScheme.primary : null,
        icon: const Icon(Icons.queue_music),
        onPressed: () {
          along.toggle();
          onPressed?.call();
        },
      );
    },
  );
}

/// A PDF's view for [PlayAlongBeside]'s pane ([PdfPage]).
Widget pdfViewFor(Library library, CaptureEvent event, EventPage page) =>
    PdfPage(
      key: ValueKey('cam-pdf-${page.id}'),
      library: library,
      event: event,
      page: page,
    );

/// An image's view for [PlayAlongBeside]'s pane: the page, pinch-zoomable,
/// as the file screen shows it.
Widget imageViewFor(Library library, CaptureEvent event, EventPage page) =>
    InteractiveViewer(
      key: ValueKey('cam-image-${page.id}'),
      maxScale: 5,
      child: PageImage(library: library, event: event, page: page),
    );

/// The text tab's view for [PlayAlongBeside]'s pane: the text in the
/// tab's font, as written (lines not wrapped, so the strings line up),
/// scrolling both ways and selectable; it follows the capture's edits.
class FollowedText extends StatelessWidget {
  const FollowedText({super.key, required this.library, required this.eventId});

  final Library library;
  final String eventId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) => SingleChildScrollView(
      key: const Key('cam-text-view'),
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          library.byId(eventId)?.tabText ?? '',
          style: const TextStyle(
            fontFamily: monoFont,
            fontSize: 13,
            height: 1.25,
            color: Colors.white,
          ),
        ),
      ),
    ),
  );
}

/// [along]'s sidebar, beside [child]: kept while hidden (offstage), so a
/// link's page isn't reloaded; nothing when there's nothing to play along
/// with. Its left edge is a separator to drag ([SplitHandle]): the
/// sidebar gets wider or narrower, the same on every screen
/// ([SidebarWidths]), and a double tap puts its default width back. On
/// the other side, the text, PDF or image followed ([PlayAlong.followsText],
/// [PlayAlong.followed]), when one is, in a pane of its own
/// ([_FollowPane]), with a separator to drag ([SplitHandle]) between it
/// and [child]: wider, the page reads better; [child] (the camera) gets
/// smaller, down to [minChild].
class PlayAlongBeside extends StatelessWidget {
  const PlayAlongBeside({
    super.key,
    required this.along,
    required this.child,
    this.linkFrame = linkFrameFor,
    this.pdfView = pdfViewFor,
    this.onUse,
    this.footer,
    this.deletes = false,
    this.canDelete = true,
    this.keepIds = const {},
    this.letGo,
    this.run,
    this.onEdit,
    this.choose,
    this.keys = true,
  });

  final PlayAlong along;
  final Widget child;

  /// Plays a file tapped in the sidebar along; null, [PlayAlong.choose].
  /// Cam's view puts the camera back first, where a take is edited in
  /// its place.
  final Future<void> Function(EventPage page)? choose;

  /// Whether the player's keys work ([PlayAlongKeys]); false in a
  /// preview, where no key does anything.
  final bool keys;

  /// Whether the sidebar's files show Delete (those the user may delete,
  /// [mayDeleteFile]); false (a preview), none does.
  final bool deletes;

  /// Whether Delete (and a take's Edit, [onEdit]) works now; false (Cam
  /// recording or saving a take, the screen busy), they're greyed.
  final bool canDelete;

  /// The files that show no Delete, nor Edit, in the sidebar: the file
  /// screen's own (its own tools delete and edit it); in Cam's view, the
  /// page edited and those Back puts back.
  final Set<String> keepIds;

  /// Opens the video editor on one of the sidebar's takes: in Cam, in the
  /// camera's place (`StudioView`); in the Text view, over it
  /// ([VideoEditScreen.open], as the file screen's Edit does), done when
  /// the user is back. Null (a preview, a capture opened by its link):
  /// no take shows Edit. With it, the user's own takes do
  /// ([PlayAlongSidebar.mayEdit]), before Delete, and work when Delete
  /// does ([canDelete]).
  final Future<void> Function(EventPage page)? onEdit;

  /// Before a file deleted from the sidebar goes, once the user confirms,
  /// besides the sidebar's own player: the screen lets go of it too (the
  /// event screen's list player, which may be playing it).
  final Future<void> Function(EventPage page)? letGo;

  /// Runs a delete from the sidebar ([deleteFile]'s `run`): the screen's
  /// own, as its list's Delete does (its progress bar, its message on a
  /// failure); without it, a failure shows in a snack bar.
  final Future<void> Function(String failure, Future<void> Function() task)?
  run;
  final Widget Function(LinkFrameController controller) linkFrame;

  /// Under the sidebar's list, if anything (the Text view's notation
  /// sheet).
  final Widget? footer;

  /// Shows a PDF in its pane; tests pass their own. An image shows as
  /// [imageViewFor].
  final Widget Function(Library library, CaptureEvent event, EventPage page)
  pdfView;

  /// After each tap in the sidebar (Cam takes the keys back).
  final VoidCallback? onUse;

  /// The narrowest [child] gets when the PDF's pane or the sidebar is
  /// dragged wider (room for the tab's line under the camera).
  static const minChild = 120.0;

  /// The narrowest the PDF's pane gets dragged.
  static const minPdf = 120.0;

  /// Deletes [page] from the sidebar, as the capture's list does
  /// ([deleteFile]), once the user confirms: if it's what plays, the
  /// player lets go of it first (the screen's too, [letGo]); if it's
  /// followed, its pane closes.
  Future<void> _delete(BuildContext context, EventPage page) async {
    onUse?.call();
    final event = along.library.byId(along.eventId);
    if (event != null) {
      await deleteFile(
        context,
        along.library,
        event,
        page,
        letGo: () async {
          await along.letGo(page);
          await letGo?.call(page);
        },
        run: run,
      );
    }
    onUse?.call();
  }

  /// Opens the editor on the take [page] ([onEdit]): what plays along
  /// pauses first, so only the editor's preview sounds.
  Future<void> _edit(EventPage page) async {
    onUse?.call();
    await along.track.pause();
    await onEdit?.call(page);
    onUse?.call();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([along, SidebarWidths.instance]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final screen = MediaQuery.sizeOf(context).width;
        final widths = SidebarWidths.instance;
        final shown = along.available && along.open;
        // The sidebar leaves [child] [minChild] and its edge.
        final sidebarMax = box.maxWidth - minChild - 2 * SplitHandle.thickness;
        final sidebarWidth = widths.widthOf(
          SidebarWidths.playAlong,
          fallback: PlayAlongSidebar.widthFor(screen),
          max: sidebarMax,
        );
        final sidebar = shown ? sidebarWidth + SplitHandle.thickness : 0.0;
        // What's left for the pane, the separator and [child].
        final room = box.maxWidth - sidebar - SplitHandle.thickness;
        final max = room - minChild;
        double clamp(double w) =>
            max <= minPdf ? max.clamp(0.0, room) : w.clamp(minPdf, max);
        final paneWidth = clamp(along.paneWidth ?? PdfPaneWidth.of(screen));
        final event = along.library.byId(along.eventId);
        final followed = event == null ? null : along.followed;
        final l10n = context.l10n;
        final pane = switch (followed) {
          _ when along.followsText && along.text != null => _FollowPane(
            icon: Icons.notes,
            label: l10n.textViewTextTab,
            closeTooltip: l10n.camAlongTextHide,
            width: paneWidth,
            view: FollowedText(library: along.library, eventId: along.eventId),
            onUse: onUse,
            onClose: () {
              onUse?.call();
              along.unfollow();
            },
          ),
          final followed? => _FollowPane(
            icon: _icon(followed),
            label: fileLabel(l10n, event!, followed),
            closeTooltip: followed.isPdf
                ? l10n.camAlongPdfHide
                : l10n.camAlongPageHide,
            width: paneWidth,
            view: followed.isPdf
                ? pdfView(along.library, event, followed)
                : imageViewFor(along.library, event, followed),
            onUse: onUse,
            onClose: () {
              onUse?.call();
              along.unfollow();
            },
          ),
          null => null,
        };
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (pane != null) ...[
              pane,
              SplitHandle(
                key: const Key('cam-pdf-split'),
                axis: Axis.horizontal,
                color: Colors.white38,
                background: Colors.black,
                // From the width now: updates come faster than frames.
                onDrag: (dx) => along.setPaneWidth(
                  clamp((along.paneWidth ?? paneWidth) + dx),
                ),
                onReset: along.resetPaneWidth,
              ),
            ],
            Expanded(child: child),
            if (shown)
              SplitHandle(
                key: const Key('cam-along-split'),
                axis: Axis.horizontal,
                color: Colors.white38,
                background: Colors.black,
                // Dragged left, the sidebar (on the right) gets wider.
                onDrag: (dx) => widths.set(
                  SidebarWidths.playAlong,
                  (sidebarWidth - dx).clamp(
                    SidebarWidths.min,
                    sidebarMax < SidebarWidths.min
                        ? SidebarWidths.min
                        : sidebarMax,
                  ),
                ),
                onDragEnd: widths.save,
                onReset: () => widths.reset(SidebarWidths.playAlong),
              ),
            if (along.available)
              Offstage(
                offstage: !along.open,
                child: PlayAlongKeys(
                  track: along.track,
                  active: along.open && keys,
                  child: PlayAlongSidebar(
                    width: sidebarWidth,
                    library: along.library,
                    eventId: along.eventId,
                    track: along.track,
                    linkFrame: linkFrame,
                    toFollow: along.toFollow,
                    followed: along.followed,
                    hasText: along.text != null,
                    followsText: along.followsText,
                    footer: footer,
                    keepIds: keepIds,
                    canDelete: canDelete,
                    onDelete: deletes ? (page) => _delete(context, page) : null,
                    onEdit: onEdit == null ? null : _edit,
                    onFollow: (page) {
                      onUse?.call();
                      along.follow(page);
                    },
                    onFollowText: () {
                      onUse?.call();
                      along.followText();
                    },
                    onChoose: (page) {
                      onUse?.call();
                      unawaited((choose ?? along.choose)(page));
                    },
                    onStop: () {
                      onUse?.call();
                      unawaited(along.track.stop());
                    },
                    onToggle: () {
                      onUse?.call();
                      unawaited(along.track.toggle());
                    },
                    onSkip: (by) {
                      onUse?.call();
                      unawaited(along.track.skip(by));
                    },
                    onRepeat: () {
                      onUse?.call();
                      unawaited(along.track.setRepeat(!along.track.repeat));
                    },
                    onSection: (start, end) {
                      onUse?.call();
                      unawaited(along.track.setSection(start, end));
                    },
                    onSectionHere: ({required bool end}) {
                      onUse?.call();
                      unawaited(along.track.sectionHere(end: end));
                    },
                    onSectionClear: () {
                      onUse?.call();
                      unawaited(along.track.clearSection());
                    },
                    onPhrasesClear: () {
                      onUse?.call();
                      unawaited(along.track.clearPhrases());
                    },
                    onCountIn: () {
                      onUse?.call();
                      unawaited(along.track.setCountIn(!along.track.countIn));
                    },
                    onSpeed: (speed) {
                      onUse?.call();
                      unawaited(along.track.setSpeed(speed));
                    },
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// The play-along player's keys, in every screen with the sidebar, while
/// it shows ([active]) and its screen is the one in front, wherever the
/// keyboard is but in a field being typed in: **0** goes back to the
/// start of the file or its section, count-in and all
/// ([BackingTrack.restart]); the **space bar** and **1** pause and play
/// it. They get the keys first
/// ([FocusManager.addEarlyKeyEventHandler]), so the screen under them
/// doesn't (Cam's turn the tab). A tap in the sidebar takes the keyboard
/// out of a field, so the keys are the player's again.
class PlayAlongKeys extends StatefulWidget {
  const PlayAlongKeys({
    super.key,
    required this.track,
    required this.child,
    this.active = true,
  });

  final BackingTrack track;
  final Widget child;

  /// Whether the sidebar shows: hidden, the keys are the screen's.
  final bool active;

  /// The keys that go back to the start: 0, on the top row or the keypad.
  static final restart = {
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.numpad0,
  };

  /// The keys that pause and play, with the space bar: 1, on the top row
  /// or the keypad.
  static final toggle = {LogicalKeyboardKey.digit1, LogicalKeyboardKey.numpad1};

  /// ← and →: « and », [skipBy] back and on.
  static final skips = {
    LogicalKeyboardKey.arrowLeft: -skipBy,
    LogicalKeyboardKey.arrowRight: skipBy,
  };

  /// Whether [event] is one of [keys] pressed alone (Ctrl / ⌘ + 0 is the
  /// browser's zoom, Ctrl / ⌘ + 1 its first tab, left to it).
  static bool _alone(KeyEvent event, Set<LogicalKeyboardKey> keys) {
    final keyboard = HardwareKeyboard.instance;
    return keys.contains(event.logicalKey) &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed;
  }

  @override
  State<PlayAlongKeys> createState() => _PlayAlongKeysState();
}

class _PlayAlongKeysState extends State<PlayAlongKeys> {
  final _focus = FocusNode(debugLabel: 'play-along keys');

  /// The screen the sidebar is in: under another (a dialog, a menu, the
  /// editor), the keys aren't the player's.
  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_key);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_key);
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(KeyEvent event) {
    final track = widget.track;
    if (event is KeyUpEvent ||
        !widget.active ||
        track.page == null ||
        !(_route?.isCurrent ?? true)) {
      return KeyEventResult.ignored;
    }
    // Typing in a field isn't playing.
    final field = FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<EditableText>();
    if (field != null && !field.readOnly) return KeyEventResult.ignored;
    if (PlayAlongKeys._alone(event, PlayAlongKeys.restart)) {
      if (event is KeyDownEvent) unawaited(track.restart());
      return KeyEventResult.handled;
    }
    // ← and →, as « and » (held, again and again: a repeat skips too).
    if (PlayAlongKeys._alone(event, PlayAlongKeys.skips.keys.toSet())) {
      if (track.canToggle) {
        unawaited(track.skip(PlayAlongKeys.skips[event.logicalKey]!));
      }
      return KeyEventResult.handled;
    }
    final toggles =
        event.logicalKey == LogicalKeyboardKey.space ||
        PlayAlongKeys._alone(event, PlayAlongKeys.toggle);
    if (toggles) {
      // Nothing to play or pause yet (it's loading): still the player's.
      if (event is KeyDownEvent && track.canToggle) {
        unawaited(track.toggle());
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    // A tap anywhere in the sidebar takes the keyboard (its buttons
    // don't), out of a field being typed in, unless something in the
    // sidebar already has it.
    onPointerDown: (_) {
      if (!_focus.hasFocus) _focus.requestFocus();
    },
    child: Focus(focusNode: _focus, child: widget.child),
  );
}

/// The PDF pane's width before it's dragged: 40% of the screen's width,
/// from 160 to 480 px, so the page reads.
abstract final class PdfPaneWidth {
  static double of(double screen) => (screen * 0.4).clamp(160.0, 480.0);
}

/// The text, PDF or image followed, beside the screen: its [icon], [label]
/// and **Close** at the top, the document under them, scrolling
/// ([FollowedText], [PdfPage], [imageViewFor]), [width] wide
/// ([PdfPaneWidth], or as the user dragged it).
class _FollowPane extends StatelessWidget {
  const _FollowPane({
    required this.icon,
    required this.label,
    required this.closeTooltip,
    required this.width,
    required this.view,
    required this.onClose,
    this.onUse,
  });

  final IconData icon;
  final String label;
  final String closeTooltip;
  final double width;
  final Widget view;
  final VoidCallback onClose;
  final VoidCallback? onUse;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('cam-pdf-pane'),
      width: width,
      child: Listener(
        onPointerDown: (_) => onUse?.call(),
        child: Material(
          color: const Color(0xFF1C1C1C),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                child: Row(
                  children: [
                    Icon(icon, color: Colors.white70, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('cam-pdf-close'),
                      tooltip: closeTooltip,
                      visualDensity: const VisualDensity(
                        horizontal: -4,
                        vertical: -4,
                      ),
                      color: Colors.white70,
                      iconSize: 18,
                      icon: const Icon(Icons.close),
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
              Expanded(child: view),
            ],
          ),
        ),
      ),
    );
  }
}

/// The backing track's frame, compact, at the top of the sidebar and as
/// wide: the video or link playing (a recording shows its progress only),
/// its name, « (10 seconds back), play / pause, stop, » (10 forward) and
/// repeat (on by default); for a recording or video of the capture's own,
/// the section that repeats ([_SectionBar]; while repeat is on, and while
/// its range is dragged, the section shows over the progress bar too,
/// [_SectionMark]), and for
/// anything playing in the app, its speed ([_SpeedBar]). Nothing while
/// there's none.
class _BackingFrame extends StatefulWidget {
  const _BackingFrame({
    required this.eventId,
    required this.track,
    required this.linkFrame,
    required this.onToggle,
    required this.onStop,
    required this.onSkip,
    required this.onRepeat,
    required this.onSection,
    required this.onSectionHere,
    required this.onSectionClear,
    required this.onSpeed,
    this.onPhrasesClear,
    this.onCountIn,
  });

  final String eventId;
  final BackingTrack track;
  final Widget Function(LinkFrameController controller) linkFrame;
  final VoidCallback onToggle;
  final VoidCallback onStop;
  final void Function(Duration by) onSkip;
  final VoidCallback onRepeat;
  final void Function(Duration start, Duration end) onSection;
  final void Function({required bool end}) onSectionHere;
  final VoidCallback onSectionClear;
  final void Function(double speed) onSpeed;
  final VoidCallback? onPhrasesClear;
  final VoidCallback? onCountIn;

  @override
  State<_BackingFrame> createState() => _BackingFrameState();
}

class _BackingFrameState extends State<_BackingFrame> {
  /// The file whose section's range is being dragged, if any: its section
  /// shows over the progress bar meanwhile.
  String? _sectionDrag;

  @override
  Widget build(BuildContext context) {
    final _BackingFrame(
      :eventId,
      :track,
      :linkFrame,
      :onToggle,
      :onStop,
      :onSkip,
      :onRepeat,
      :onSection,
      :onSectionHere,
      :onSectionClear,
      :onSpeed,
      :onPhrasesClear,
      :onCountIn,
    ) = widget;
    return ListenableBuilder(
      listenable: track,
      builder: (context, _) {
        final page = track.page;
        if (page == null) return const SizedBox.shrink();
        // A drag the range never ended (its file went meanwhile) is over.
        if (!track.canSection || page.id != _sectionDrag) _sectionDrag = null;
        // Over the progress bar while it repeats, and while its range is
        // dragged (with repeat off, it only plays to its end).
        final section = _sectionDrag != null || track.repeat
            ? track.section
            : null;
        final l10n = context.l10n;
        final event = track.library.byId(eventId);
        final media = track.media;
        final link = track.link;
        final phrases = track.phrases;
        // As wide as the sidebar, at most a third of the screen's height
        // (taller, the sidebar's column runs out of room on a short screen).
        final maxHeight = MediaQuery.sizeOf(context).height / 3;
        final Widget? content = switch ((media, link)) {
          _ when track.error != null => Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              page.isAudio ? l10n.textViewCantPlayAudio : l10n.textViewCantPlay,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          (final media?, _) when page.isVideo || media.value.size.width > 0 =>
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: AspectRatio(
                aspectRatio: media.value.aspectRatio,
                child: VideoPlayer(media),
              ),
            ),
          // 16:9, a YouTube video's shape.
          (_, final link?) => ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: AspectRatio(aspectRatio: 16 / 9, child: linkFrame(link)),
          ),
          _ => null,
        };
        const compact = VisualDensity(horizontal: -2, vertical: -2);
        return ColoredBox(
          key: const Key('cam-along-frame'),
          color: Colors.black,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The video gives way first where the frame is short of room
              // (the sidebar caps the frame's height).
              if (content != null)
                Flexible(child: Center(heightFactor: 1, child: content)),
              // The progress bar's line: the count-in's button and its
              // seconds, then the progress bar, and at its right, while the
              // song has phrase passes marked on it, the button that clears
              // them.
              if (media != null)
                Row(
                  children: [
                    _CountIn(
                      track: track,
                      onToggle:
                          onCountIn ?? () => track.setCountIn(!track.countIn),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          VideoProgressIndicator(
                            media,
                            key: const Key('cam-along-progress'),
                            allowScrubbing: true,
                            colors: VideoProgressColors(
                              playedColor: _SectionMark.played(
                                Theme.of(context).colorScheme,
                                recording: track.recording,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: _SectionMark.inset,
                            ),
                          ),
                          if (section != null)
                            Positioned.fill(
                              top: _SectionMark.inset,
                              bottom: _SectionMark.inset,
                              child: IgnorePointer(
                                child: _SectionMark(
                                  start: section.start,
                                  end: section.end,
                                  length: media.value.duration,
                                  color: _SectionMark.band(
                                    Theme.of(context).colorScheme,
                                  ),
                                ),
                              ),
                            ),
                          if (phrases.isNotEmpty)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  key: const Key('cam-along-phrase-marks'),
                                  painter: _PhraseMarks(
                                    phrases,
                                    media.value.duration,
                                    Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (phrases.isNotEmpty)
                      IconButton(
                        key: const Key('cam-along-phrases-clear'),
                        tooltip: l10n.camAlongPhrasesClear,
                        visualDensity: compact,
                        color: Theme.of(context).colorScheme.primary,
                        iconSize: 18,
                        icon: const Icon(Icons.clear_all),
                        onPressed: onPhrasesClear ?? () => track.clearPhrases(),
                      )
                    else
                      const SizedBox(width: 8),
                  ],
                ),
              if (track.canSection)
                _SectionBar(
                  track: track,
                  onSection: onSection,
                  onSectionHere: onSectionHere,
                  onSectionClear: onSectionClear,
                  onDrag: (dragging) => setState(
                    () => _sectionDrag = dragging ? track.page?.id : null,
                  ),
                ),
              if (media != null && track.error == null)
                _SpeedBar(track: track, onSpeed: onSpeed),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    Icon(_icon(page), color: Colors.white70, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        event == null ? '' : fileLabel(l10n, event, page),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 44,
                child: track.loading
                    ? const Center(
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    // Shrunk to fit a sidebar dragged narrow.
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (track.canToggle) ...[
                              IconButton(
                                key: const Key('cam-along-back'),
                                tooltip: l10n.camAlongBack,
                                visualDensity: compact,
                                color: Colors.white,
                                icon: const Icon(Icons.fast_rewind),
                                onPressed: () => onSkip(-skipBy),
                              ),
                              IconButton(
                                key: const Key('cam-along-toggle'),
                                tooltip: track.playing || track.countingIn
                                    ? l10n.camAlongPause
                                    : l10n.camAlongPlay,
                                visualDensity: compact,
                                color: Colors.white,
                                icon: Icon(
                                  track.playing || track.countingIn
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                ),
                                onPressed: onToggle,
                              ),
                              IconButton(
                                key: const Key('cam-along-stop'),
                                tooltip: l10n.camAlongStop,
                                visualDensity: compact,
                                color: Colors.white,
                                icon: const Icon(Icons.stop),
                                onPressed: onStop,
                              ),
                              IconButton(
                                key: const Key('cam-along-forward'),
                                tooltip: l10n.camAlongForward,
                                visualDensity: compact,
                                color: Colors.white,
                                icon: const Icon(Icons.fast_forward),
                                onPressed: () => onSkip(skipBy),
                              ),
                              IconButton(
                                key: const Key('cam-along-repeat'),
                                tooltip: track.repeat
                                    ? l10n.camAlongRepeatOn
                                    : l10n.camAlongRepeatOff,
                                isSelected: track.repeat,
                                visualDensity: compact,
                                color: track.repeat
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white54,
                                icon: const Icon(Icons.repeat),
                                onPressed: onRepeat,
                              ),
                            ],
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The sidebar: the backing track's frame at its top, always there, and
/// under it, first, the capture's text tab when it [hasText], marked when
/// [followsText]: a tap shows it beside the screen, or hides it, tapped
/// again. Then the capture's recordings, videos and links, the one playing
/// along marked; a tap plays one along. Then the PDFs and images
/// [toFollow], if any, under a heading of their own, the one [followed]
/// marked; a tap shows it beside the screen, or hides it, tapped again.
/// Last, Cam's takes ([isTake]), under a heading of their own, the most
/// recent first (the capture's order reversed); a tap plays one along, as
/// the other files. At the bottom, [footer], if any, out of the scrolling
/// list.
class PlayAlongSidebar extends StatelessWidget {
  const PlayAlongSidebar({
    super.key,
    required this.library,
    required this.eventId,
    required this.track,
    required this.linkFrame,
    required this.onChoose,
    this.toFollow = const [],
    this.followed,
    this.onFollow,
    this.hasText = false,
    this.followsText = false,
    this.onFollowText,
    this.footer,
    this.onDelete,
    this.onEdit,
    this.canDelete = true,
    this.keepIds = const {},
    required this.onToggle,
    required this.onStop,
    required this.onSkip,
    required this.onRepeat,
    required this.onSection,
    required this.onSectionHere,
    required this.onSectionClear,
    required this.onSpeed,
    this.onPhrasesClear,
    this.onCountIn,
    this.width,
  });

  /// How wide it is; null: [widthFor] the screen.
  final double? width;

  final Library library;
  final String eventId;
  final BackingTrack track;
  final Widget Function(LinkFrameController controller) linkFrame;
  final void Function(EventPage page) onChoose;
  final List<EventPage> toFollow;
  final EventPage? followed;
  final void Function(EventPage page)? onFollow;
  final bool hasText;
  final bool followsText;
  final VoidCallback? onFollowText;
  final Widget? footer;

  /// Deletes one of the files listed; null: none shows Delete. With it,
  /// those the user may delete ([mayDeleteFile]) do, at the right of
  /// their row, all but those in [keepIds].
  final void Function(EventPage page)? onDelete;

  /// Opens the video editor on one of the takes listed; null: none shows
  /// Edit. With it, the takes the user may edit ([mayEdit]) do, before
  /// Delete, all but those in [keepIds].
  final void Function(EventPage page)? onEdit;

  /// Whether Delete and Edit work now; false, they're greyed.
  final bool canDelete;

  /// The files that show no Delete, nor Edit (the file screen's own).
  final Set<String> keepIds;

  /// Whether [page] is a take the user may edit, as the file screen's
  /// Edit says: a video of Cam's ([isTake]), one of the capture's own
  /// files (not a contribution's), in a capture that isn't read only.
  static bool mayEdit(CaptureEvent event, EventPage page) =>
      page.isVideo &&
      isTake(page) &&
      !event.readOnly &&
      event.pages.contains(page);
  final VoidCallback onToggle;
  final VoidCallback onStop;
  final void Function(Duration by) onSkip;
  final VoidCallback onRepeat;
  final void Function(Duration start, Duration end) onSection;
  final void Function({required bool end}) onSectionHere;
  final VoidCallback onSectionClear;
  final void Function(double speed) onSpeed;

  /// Forgets the phrase passes of what plays; null: the track forgets
  /// them itself.
  final VoidCallback? onPhrasesClear;

  /// Turns the count-in on or off; null: the track does it itself.
  final VoidCallback? onCountIn;

  /// Its default width on a screen [screen] wide: half of it, from 160
  /// to 360 px; the user drags it wider or narrower ([PlayAlongBeside]).
  static double widthFor(double screen) => (screen * 0.5).clamp(160.0, 360.0);

  /// What the list keeps of the sidebar's height, at least (two of its
  /// rows): the frame shrinks its video rather than take it (a short
  /// screen).
  static const listRoom = 96.0;

  /// The most of the sidebar's height [footer] takes; taller (the notation
  /// sheet in a phone's narrow sidebar, its lines wrapped), it scrolls,
  /// so the frame keeps room for its buttons.
  static const footerShare = 0.3;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      key: const Key('cam-along-sidebar'),
      width: width ?? widthFor(MediaQuery.sizeOf(context).width),
      child: Material(
        color: const Color(0xFF1C1C1C),
        child: LayoutBuilder(
          builder: (context, sidebar) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The footer takes its height first, up to [footerShare] of
              // the sidebar's; the frame gets what's left over the list's
              // [listRoom].
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: (box.maxHeight - listRoom).clamp(
                            0.0,
                            double.infinity,
                          ),
                        ),
                        child: _BackingFrame(
                          eventId: eventId,
                          track: track,
                          linkFrame: linkFrame,
                          onToggle: onToggle,
                          onStop: onStop,
                          onSkip: onSkip,
                          onRepeat: onRepeat,
                          onSection: onSection,
                          onSectionHere: onSectionHere,
                          onSectionClear: onSectionClear,
                          onSpeed: onSpeed,
                          onPhrasesClear: onPhrasesClear,
                          onCountIn: onCountIn,
                        ),
                      ),
                      Expanded(child: _list(context, l10n)),
                    ],
                  ),
                ),
              ),
              if (footer case final footer?)
                ConstrainedBox(
                  key: const Key('cam-along-footer'),
                  constraints: BoxConstraints(
                    maxHeight: sidebar.maxHeight * footerShare,
                  ),
                  child: SingleChildScrollView(child: footer),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// A heading in the list, small and muted.
  static Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white54, fontSize: 12),
    ),
  );

  /// The heading of the takes of [day], under Takes: "Today",
  /// "Yesterday", else the date ("Sat, Nov 14"; with the year when it
  /// isn't this one).
  static Widget _dayHeading(
    BuildContext context,
    AppLocalizations l10n,
    DateTime day,
  ) => Padding(
    key: ValueKey('cam-along-day-${day.year}-${day.month}-${day.day}'),
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
    child: Text(
      dayLabel(context, l10n, day, DateTime.now()),
      style: const TextStyle(color: Colors.white38, fontSize: 11),
    ),
  );

  /// The end of a file's row: its [mark] (playing, followed), if any, and
  /// at the right, a take's Edit (scissors, as the file screen's), if it
  /// shows ([onEdit]), then Delete, if it shows ([onDelete]).
  Widget? _trailing(
    BuildContext context,
    AppLocalizations l10n,
    CaptureEvent event,
    EventPage page,
    IconData? mark,
  ) {
    final onDelete = this.onDelete;
    final onEdit = this.onEdit;
    final deletes =
        onDelete != null &&
        !keepIds.contains(page.id) &&
        mayDeleteFile(event, page);
    final edits =
        onEdit != null && !keepIds.contains(page.id) && mayEdit(event, page);
    if (!deletes && !edits) return mark == null ? null : Icon(mark, size: 18);
    Widget button(
      String name,
      String tooltip,
      IconData icon,
      void Function(EventPage page) onPressed,
    ) => IconButton(
      key: ValueKey('cam-along-$name-${page.id}'),
      tooltip: tooltip,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      color: Colors.white70,
      disabledColor: Colors.white24,
      iconSize: 18,
      icon: Icon(icon),
      onPressed: canDelete ? () => onPressed(page) : null,
    );
    final label = fileLabel(l10n, event, page);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (mark != null) Icon(mark, size: 18),
        if (edits)
          button('edit', l10n.camAlongEdit(label), Icons.content_cut, onEdit),
        if (deletes)
          button(
            'delete',
            l10n.camAlongDelete(label),
            Icons.delete_outline,
            onDelete,
          ),
      ],
    );
  }

  /// The files to play along, under the frame, then the PDFs to follow,
  /// then Cam's takes.
  Widget _list(BuildContext context, AppLocalizations l10n) =>
      ListenableBuilder(
        listenable: Listenable.merge([library, track]),
        builder: (context, _) {
          final event = library.byId(eventId);
          final playing = [
            if (event != null)
              ...PlayAlong.filesOf(event).where(BackingTrack.plays),
          ];
          final pages = [...playing.where((p) => !isTake(p))];
          // The most recent first.
          final takes = [...playing.where(isTake)].reversed.toList();
          final primary = Theme.of(context).colorScheme.primary;
          // A file to play along (a song or a take): the one playing marked,
          // a take's Edit, then Delete, at its right.
          Widget fileRow(EventPage page) => ListTile(
            key: ValueKey('cam-along-${page.id}'),
            dense: true,
            selected: track.page?.id == page.id,
            selectedColor: Theme.of(context).colorScheme.primary,
            textColor: Colors.white,
            iconColor: Colors.white70,
            leading: Icon(_icon(page)),
            title: Text(
              fileLabel(l10n, event!, page),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _trailing(
              context,
              l10n,
              event,
              page,
              track.page?.id == page.id && track.playing
                  ? Icons.graphic_eq
                  : null,
            ),
            onTap: () => onChoose(page),
          );
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              if (hasText)
                Tooltip(
                  message: followsText
                      ? l10n.camAlongTextHide
                      : l10n.camAlongTextShow,
                  child: ListTile(
                    key: const Key('cam-along-text'),
                    dense: true,
                    selected: followsText,
                    selectedColor: primary,
                    textColor: Colors.white,
                    iconColor: Colors.white70,
                    leading: const Icon(Icons.notes),
                    title: Text(
                      l10n.textViewTextTab,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: followsText
                        ? const Icon(Icons.vertical_split, size: 18)
                        : null,
                    onTap: onFollowText,
                  ),
                ),
              if (pages.isNotEmpty) _heading(l10n.camAlongTitle),
              for (final page in pages) fileRow(page),
              if (toFollow.isNotEmpty && event != null) ...[
                // "Follow a PDF" while only PDFs are listed.
                _heading(
                  toFollow.any((p) => p.isImage)
                      ? l10n.camAlongFollow
                      : l10n.camAlongPdfs,
                ),
                for (final page in toFollow)
                  Tooltip(
                    message: followed?.id == page.id
                        ? (page.isPdf
                              ? l10n.camAlongPdfHide
                              : l10n.camAlongPageHide)
                        : (page.isPdf
                              ? l10n.camAlongPdfShow
                              : l10n.camAlongPageShow),
                    child: ListTile(
                      key: ValueKey('cam-along-${page.id}'),
                      dense: true,
                      selected: followed?.id == page.id,
                      selectedColor: primary,
                      textColor: Colors.white,
                      iconColor: Colors.white70,
                      leading: Icon(_icon(page)),
                      title: Text(
                        fileLabel(l10n, event, page),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: _trailing(
                        context,
                        l10n,
                        event,
                        page,
                        followed?.id == page.id ? Icons.vertical_split : null,
                      ),
                      onTap: () => onFollow?.call(page),
                    ),
                  ),
              ],
              // Cam's takes, last, under their days.
              if (takes.isNotEmpty) ...[
                _heading(l10n.camAlongTakes),
                for (final (day, group) in takesByDay(takes)) ...[
                  if (day != null) _dayHeading(context, l10n, day),
                  for (final page in group) fileRow(page),
                ],
              ],
            ],
          );
        },
      );
}

/// [takes] (the most recent first) in runs of the same day, by when each
/// was made ([timeOfId]): the day, and its takes in the same order. A take
/// whose time isn't known is in a run of no day (null), where it is.
List<(DateTime?, List<EventPage>)> takesByDay(List<EventPage> takes) {
  final runs = <(DateTime?, List<EventPage>)>[];
  for (final page in takes) {
    final made = timeOfId(page.id);
    final day = made == null ? null : DateUtils.dateOnly(made);
    if (runs.isNotEmpty && runs.last.$1 == day) {
      runs.last.$2.add(page);
    } else {
      runs.add((day, [page]));
    }
  }
  return runs;
}

/// What a day of takes is called, as of [now]: "Today", "Yesterday",
/// else its date in the app's language, the weekday, month and day
/// ("Sat, Nov 14"), and the year when it isn't [now]'s.
String dayLabel(
  BuildContext context,
  AppLocalizations l10n,
  DateTime day,
  DateTime now,
) {
  if (DateUtils.isSameDay(day, now)) return l10n.camAlongToday;
  if (DateUtils.isSameDay(day, DateTime(now.year, now.month, now.day - 1))) {
    return l10n.camAlongYesterday;
  }
  final locale = Localizations.localeOf(context).toString();
  try {
    return (day.year == now.year
            ? DateFormat.MMMEd(locale)
            : DateFormat.yMMMEd(locale))
        .format(day);
  } on Object {
    return MaterialLocalizations.of(context).formatMediumDate(day);
  }
}

/// Whether [page] is one of Cam's takes: marked so when Cam saved it
/// ([EventPage.take]; renamed, it still is), or, saved before takes were
/// marked, a video named as Cam names them, in any of the app's languages
/// ("Take 2", "Toma 2").
bool isTake(EventPage page) =>
    page.take || (page.isVideo && _takeNames.hasMatch(page.title ?? ''));

/// The names Cam gives its takes ([AppLocalizations.camTake]), in all the
/// app's languages: by the time ("Take 14:32", "Take 14:32:07"), and as
/// they were named before, by number ("Take 3").
final _takeNames = () {
  const n = '7654321';
  final names = {
    for (final locale in AppLocalizations.supportedLocales)
      lookupAppLocalizations(locale)
          .camTake(n)
          .split(n)
          .map(RegExp.escape)
          .join(r'(?:\d+|\d{1,2}:\d{2}(?::\d{2})?)'),
  };
  return RegExp('^(?:${names.join('|')})\$');
}();

/// A recording's, video's, link's, PDF's or image's icon (a YouTube
/// video's as a video).
IconData _icon(EventPage page) => switch (page) {
  EventPage(isPdf: true) => Icons.picture_as_pdf_outlined,
  EventPage(isImage: true) => Icons.image_outlined,
  EventPage(isAudio: true) => Icons.audiotrack,
  EventPage(isVideo: true) => Icons.movie_outlined,
  EventPage(:final url?) when youTubeVideoId(url) != null =>
    Icons.smart_display_outlined,
  _ => Icons.link,
};

/// The count-in, at the start of the progress bar's line: a button to turn
/// it on or off ([BackingTrack.countIn]), then, while it's on (or counts
/// in all the same, a take recording), its seconds
/// in [color] (not the progress bar's): "2s" and a short bar, which count
/// down and fill while it counts in.
class _CountIn extends StatelessWidget {
  const _CountIn({required this.track, required this.onToggle});

  final BackingTrack track;
  final VoidCallback onToggle;

  /// The count-in's colour, apart from the progress bar's and the
  /// sections' and passes' (the primary colour).
  static const color = Colors.amber;

  /// How wide its bar is.
  static const barWidth = 28.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final on = track.countIn;
    final length = BackingTrack.countInLength;
    Widget seconds(double done) {
      final left = (length.inMilliseconds * (1 - done) / 1000).ceil().clamp(
        1,
        length.inSeconds,
      );
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${track.countingIn ? left : length.inSeconds}s',
              key: const Key('cam-along-count-in-seconds'),
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: track.countingIn ? color : color.withValues(alpha: 0.7),
                fontSize: 11,
                fontWeight: track.countingIn ? FontWeight.bold : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(
            width: barWidth,
            child: LinearProgressIndicator(
              key: const Key('cam-along-count-in-bar'),
              value: done,
              minHeight: 4,
              color: color,
              backgroundColor: color.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(width: 4),
        ],
      );
    }

    return Row(
      key: const Key('cam-along-count-in'),
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const Key('cam-along-count-in-toggle'),
          tooltip: on ? l10n.camAlongCountInOn : l10n.camAlongCountInOff,
          isSelected: on,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          iconSize: 16,
          color: on ? color : Colors.white38,
          icon: Icon(on ? Icons.timer_outlined : Icons.timer_off_outlined),
          onPressed: onToggle,
        ),
        // Off, it still counts in while a take records.
        if (on || track.countingIn)
          track.countingIn
              ? TweenAnimationBuilder<double>(
                  // Each count-in fills from empty.
                  key: ValueKey(track.countInRun),
                  tween: Tween(begin: 0, end: 1),
                  duration: length,
                  builder: (context, done, _) => seconds(done),
                )
              : seconds(0),
      ],
    );
  }
}

/// Where the tab turns along the song ([BackingTrack.phrases]): a tick
/// across the progress bar at each phrase pass.
class _PhraseMarks extends CustomPainter {
  _PhraseMarks(this.times, this.length, this.color);

  final PhraseTimes times;
  final Duration length;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final ms = length.inMilliseconds;
    if (ms <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (final p in times.passes) {
      final x = size.width * (p.at.inMilliseconds / ms).clamp(0.0, 1.0);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_PhraseMarks old) =>
      old.times != times || old.length != length || old.color != color;
}

/// The section that repeats, over the progress bar while repeat is on and
/// while its range is dragged ([_SectionBar]): a band from its start to its end, in the
/// range's colour, over the bar's line (the part played and the rest), so
/// the two can be told apart where the range is set. Both are see-through
/// ([alpha], [played]): where the section and the part played overlap, the
/// two colours mix, and each still shows on its own past the other.
class _SectionMark extends StatelessWidget {
  const _SectionMark({
    required this.start,
    required this.end,
    required this.length,
    required this.color,
  });

  /// How opaque the bars are: the part played, the band and the range's
  /// track, a little see-through.
  static const alpha = 0.75;

  /// The part played's colour on the progress bar: the theme's primary
  /// colour, or its red (error) while a take records.
  static Color played(ColorScheme scheme, {required bool recording}) =>
      (recording ? scheme.error : scheme.primary).withValues(alpha: alpha);

  /// The section's colour, the band's and the range's: the theme's
  /// secondary colour.
  static Color band(ColorScheme scheme) =>
      scheme.secondary.withValues(alpha: alpha);

  /// The progress bar's padding above and below its line: the band is as
  /// high as the line.
  static const inset = 4.0;

  final Duration start;
  final Duration end;
  final Duration length;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ms = length.inMilliseconds;
    if (ms <= 0) return const SizedBox.shrink();
    final from = (start.inMilliseconds / ms).clamp(0.0, 1.0);
    final to = (end.inMilliseconds / ms).clamp(from, 1.0);
    return LayoutBuilder(
      builder: (context, box) => Padding(
        padding: EdgeInsets.only(
          left: box.maxWidth * from,
          right: box.maxWidth * (1 - to),
        ),
        child: ColoredBox(
          key: const Key('cam-along-section-mark'),
          color: color,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// The section of a recording or video that repeats: a range over the
/// whole file (dragging either end sets it, and tells [onDrag] while it's
/// dragged), its times, and buttons to start or end it where it plays
/// now, or to play all of it again.
class _SectionBar extends StatelessWidget {
  const _SectionBar({
    required this.track,
    required this.onSection,
    required this.onSectionHere,
    required this.onSectionClear,
    required this.onDrag,
  });

  final BackingTrack track;
  final void Function(Duration start, Duration end) onSection;
  final void Function({required bool end}) onSectionHere;
  final VoidCallback onSectionClear;
  final void Function(bool dragging) onDrag;

  /// m:ss.t: a section's ends are set to the tenth of a second.
  static String time(Duration d) {
    final tenths = d.inMilliseconds ~/ 100;
    final s = (tenths ~/ 10) % 60;
    return '${tenths ~/ 600}:${s.toString().padLeft(2, '0')}.${tenths % 10}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final media = track.media!;
    final length = media.value.duration;
    final range = track.section;
    final start = range?.start ?? Duration.zero;
    final end = range?.end ?? length;
    final ms = length.inMilliseconds.toDouble();
    const compact = VisualDensity(horizontal: -4, vertical: -4);
    // The section's colour: the theme's secondary, as its band over the
    // progress bar ([_SectionMark.band]); the thumbs and the times solid.
    final secondary = Theme.of(context).colorScheme.secondary;
    return Column(
      key: const Key('cam-along-section'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            rangeThumbShape: const RoundRangeSliderThumbShape(
              enabledThumbRadius: 7,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: range == null
                ? Colors.white24
                : _SectionMark.band(Theme.of(context).colorScheme),
            inactiveTrackColor: Colors.white12,
            thumbColor: range == null ? Colors.white70 : secondary,
          ),
          child: SizedBox(
            height: 28,
            child: RangeSlider(
              key: const Key('cam-along-section-range'),
              min: 0,
              max: ms,
              values: RangeValues(
                start.inMilliseconds.clamp(0, ms).toDouble(),
                end.inMilliseconds.clamp(0, ms).toDouble(),
              ),
              onChangeStart: (_) => onDrag(true),
              onChangeEnd: (_) => onDrag(false),
              onChanged: (v) => onSection(
                Duration(milliseconds: v.start.round()),
                Duration(milliseconds: v.end.round()),
              ),
            ),
          ),
        ),
        Row(
          children: [
            IconButton(
              key: const Key('cam-along-section-start'),
              tooltip: l10n.camAlongSectionStart,
              visualDensity: compact,
              color: Colors.white70,
              iconSize: 18,
              icon: const Icon(Icons.first_page),
              onPressed: () => onSectionHere(end: false),
            ),
            Expanded(
              child: Text(
                l10n.camAlongSection(time(start), time(end)),
                key: const Key('cam-along-section-times'),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: range == null ? Colors.white54 : secondary,
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (range != null)
              IconButton(
                key: const Key('cam-along-section-clear'),
                tooltip: l10n.camAlongSectionClear,
                visualDensity: compact,
                color: Colors.white70,
                iconSize: 16,
                icon: const Icon(Icons.close),
                onPressed: onSectionClear,
              ),
            IconButton(
              key: const Key('cam-along-section-end'),
              tooltip: l10n.camAlongSectionEnd,
              visualDensity: compact,
              color: Colors.white70,
              iconSize: 18,
              icon: const Icon(Icons.last_page),
              onPressed: () => onSectionHere(end: true),
            ),
          ],
        ),
      ],
    );
  }
}

/// How fast a recording or video plays, under the section: a slider from
/// a quarter of its speed to one and a half times it, in steps of 5 %,
/// and the speed (`0.75×`, in the primary colour once changed; a tap on
/// it, or on the speed icon before the slider, goes back to 1×).
class _SpeedBar extends StatelessWidget {
  const _SpeedBar({required this.track, required this.onSpeed});

  final BackingTrack track;
  final void Function(double speed) onSpeed;

  /// 5 % steps, so a speed is easy to come back to.
  static const step = 0.05;

  /// `0.75×`, `1×`, `1.25×`.
  static String label(double speed) {
    final percent = (speed * 100).round();
    final text = percent % 100 == 0
        ? '${percent ~/ 100}'
        : (percent / 100).toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
    return '$text×';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final speed = track.speed;
    final normal = (speed - 1).abs() < step / 2;
    final primary = Theme.of(context).colorScheme.primary;
    final divisions = ((BackingTrack.maxSpeed - BackingTrack.minSpeed) / step)
        .round();
    return Padding(
      key: const Key('cam-along-speed'),
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          _button(
            key: const Key('cam-along-speed-slower'),
            tooltip: l10n.camAlongSlower,
            icon: Icons.remove,
            onTap: speed > BackingTrack.minSpeed + step / 2
                ? () => onSpeed(_rounded(speed - step))
                : null,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: normal ? Colors.white24 : primary,
                inactiveTrackColor: Colors.white12,
                thumbColor: normal ? Colors.white70 : primary,
                // No value bubble: the speed shows beside the slider.
                showValueIndicator: ShowValueIndicator.never,
              ),
              child: SizedBox(
                height: 28,
                child: Slider(
                  key: const Key('cam-along-speed-slider'),
                  min: BackingTrack.minSpeed,
                  max: BackingTrack.maxSpeed,
                  divisions: divisions,
                  value: speed.clamp(
                    BackingTrack.minSpeed,
                    BackingTrack.maxSpeed,
                  ),
                  semanticFormatterCallback: label,
                  onChanged: onSpeed,
                ),
              ),
            ),
          ),
          _button(
            key: const Key('cam-along-speed-faster'),
            tooltip: l10n.camAlongFaster,
            icon: Icons.add,
            onTap: speed < BackingTrack.maxSpeed - step / 2
                ? () => onSpeed(_rounded(speed + step))
                : null,
          ),
          Tooltip(
            message: l10n.camAlongSpeedNormal,
            child: InkWell(
              key: const Key('cam-along-speed-label'),
              onTap: normal ? null : () => onSpeed(1),
              child: SizedBox(
                width: 42,
                child: Text(
                  label(speed),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: normal ? Colors.white54 : primary,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          _button(
            key: const Key('cam-along-speed-reset'),
            tooltip: l10n.camAlongSpeedNormal,
            icon: Icons.restart_alt,
            color: normal ? Colors.white38 : primary,
            onTap: normal ? null : () => onSpeed(1),
          ),
        ],
      ),
    );
  }

  /// To the step, so −/+ land on the slider's stops (0.75, not 0.7499).
  static double _rounded(double speed) => (speed / step).round() * step;

  /// A small button of the row: −, + and reset; greyed out with no
  /// [onTap] (at the slider's end, or at 1× already).
  static Widget _button({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onTap,
    Color color = Colors.white70,
  }) => Tooltip(
    message: tooltip,
    child: InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          color: onTap == null ? Colors.white24 : color,
          size: 18,
        ),
      ),
    ),
  );
}
