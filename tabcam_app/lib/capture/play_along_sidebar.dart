import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../l10n/language.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import '../screens/file_screen.dart';
import '../screens/pdf_page.dart';
import '../screens/youtube_link.dart';
import '../screens/split_handle.dart';
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
/// follow one beside the camera: the one chosen ([pdf]) shows in a pane
/// on the other side ([PlayAlongBeside]); the Text view's sidebar lists
/// them too, to check the reading against the page.
class PlayAlong extends ChangeNotifier {
  PlayAlong(
    this.library,
    this.eventId, {
    BackingTrack? track,
    this.withPdfs = false,
  }) : track = track ?? BackingTrack(library) {
    library.addListener(_changed);
    _changed();
  }

  final Library library;
  final String eventId;
  final BackingTrack track;

  /// Whether the sidebar lists the capture's PDFs, to follow one.
  final bool withPdfs;

  /// The PDF followed beside the screen, if one is.
  EventPage? get pdf => _pdf;
  EventPage? _pdf;

  /// Whether the sidebar shows.
  bool get open => _open;
  bool _open = false;

  /// Whether it has opened by itself yet (or the user has toggled it).
  bool _opened = false;

  /// Whether the capture has anything to play along with (or, with
  /// [withPdfs], a PDF to follow).
  bool get available => library.byId(eventId)?.pages.any(_listed) ?? false;

  /// Whether the sidebar lists [page].
  bool _listed(EventPage page) =>
      BackingTrack.plays(page) || (withPdfs && page.isPdf);

  /// The capture's PDFs, when the sidebar lists them.
  List<EventPage> get pdfs => [
    if (withPdfs) ...?library.byId(eventId)?.pages.where((p) => p.isPdf),
  ];

  /// Shows [page] (a PDF) beside the screen, or hides it, chosen again.
  void showPdf(EventPage page) {
    _pdf = _pdf?.id == page.id ? null : page;
    notifyListeners();
  }

  /// How wide the PDF's pane is, once the user has dragged its edge;
  /// null: its default ([PdfPaneWidth.of]). Kept while the screen is
  /// open, for the next PDF too.
  double? get pdfWidth => _pdfWidth;
  double? _pdfWidth;

  /// Sets the PDF pane's width (kept within the screen by its layout).
  void setPdfWidth(double width) {
    if (width == _pdfWidth) return;
    _pdfWidth = width;
    notifyListeners();
  }

  /// Puts the PDF pane back to its default width.
  void resetPdfWidth() {
    if (_pdfWidth == null) return;
    _pdfWidth = null;
    notifyListeners();
  }

  /// Hides the PDF beside the screen.
  void hidePdf() {
    if (_pdf == null) return;
    _pdf = null;
    notifyListeners();
  }

  /// Shows or hides the sidebar; hidden, what plays pauses.
  void toggle() {
    _opened = true;
    _open = !_open;
    if (!_open) unawaited(track.pause());
    notifyListeners();
  }

  /// Plays [page] along (or pauses it, chosen again).
  Future<void> choose(EventPage page) async {
    final event = library.byId(eventId);
    if (event != null) await track.choose(event, page);
  }

  void _changed() {
    final event = library.byId(eventId);
    // The PDF followed, deleted (or synced away): the pane closes.
    if (_pdf case final pdf?
        when event?.pages.any((p) => p.id == pdf.id) != true) {
      _pdf = null;
      notifyListeners();
    }
    if (_opened) return;
    if (event == null || !event.pages.any(_listed)) return;
    _opened = true;
    _open = true;
    final first = event.pages.where(BackingTrack.plays).firstOrNull;
    if (track.page == null && first != null) {
      unawaited(track.choose(event, first, play: false));
    }
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

/// [along]'s sidebar, beside [child]: kept while hidden (offstage), so a
/// link's page isn't reloaded; nothing when there's nothing to play along
/// with. On the other side, the PDF followed ([PlayAlong.pdf]), when one
/// is, in a pane of its own ([_PdfPane]), with a separator to drag
/// ([SplitHandle]) between it and [child]: wider, the page reads better;
/// [child] (the camera) gets smaller, down to [minChild].
class PlayAlongBeside extends StatelessWidget {
  const PlayAlongBeside({
    super.key,
    required this.along,
    required this.child,
    this.linkFrame = linkFrameFor,
    this.pdfView = pdfViewFor,
    this.onUse,
    this.footer,
  });

  final PlayAlong along;
  final Widget child;
  final Widget Function(LinkFrameController controller) linkFrame;

  /// Under the sidebar's list, if anything (the Text view's notation
  /// sheet).
  final Widget? footer;

  /// Shows a PDF in its pane; tests pass their own.
  final Widget Function(Library library, CaptureEvent event, EventPage page)
  pdfView;

  /// After each tap in the sidebar (Cam takes the keys back).
  final VoidCallback? onUse;

  /// The narrowest [child] gets when the PDF's pane is dragged wider.
  static const minChild = 96.0;

  /// The narrowest the PDF's pane gets dragged.
  static const minPdf = 120.0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: along,
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final screen = MediaQuery.sizeOf(context).width;
        final sidebar = along.available && along.open
            ? PlayAlongSidebar.widthFor(screen)
            : 0.0;
        // What's left for the pane, the separator and [child].
        final room = box.maxWidth - sidebar - SplitHandle.thickness;
        final max = room - minChild;
        double clamp(double w) =>
            max <= minPdf ? max.clamp(0.0, room) : w.clamp(minPdf, max);
        final pdfWidth = clamp(along.pdfWidth ?? PdfPaneWidth.of(screen));
        final event = along.library.byId(along.eventId);
        final pdf = event == null ? null : along.pdf;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (pdf != null) ...[
              _PdfPane(
                event: event!,
                page: pdf,
                width: pdfWidth,
                view: pdfView(along.library, event, pdf),
                onUse: onUse,
                onClose: () {
                  onUse?.call();
                  along.hidePdf();
                },
              ),
              SplitHandle(
                key: const Key('cam-pdf-split'),
                axis: Axis.horizontal,
                color: Colors.white38,
                background: Colors.black,
                // From the width now: updates come faster than frames.
                onDrag: (dx) =>
                    along.setPdfWidth(clamp((along.pdfWidth ?? pdfWidth) + dx)),
                onReset: along.resetPdfWidth,
              ),
            ],
            Expanded(child: child),
            if (along.available)
              Offstage(
                offstage: !along.open,
                child: PlayAlongSidebar(
                  library: along.library,
                  eventId: along.eventId,
                  track: along.track,
                  linkFrame: linkFrame,
                  pdfs: along.pdfs,
                  pdf: along.pdf,
                  footer: footer,
                  onPdf: (page) {
                    onUse?.call();
                    along.showPdf(page);
                  },
                  onChoose: (page) {
                    onUse?.call();
                    unawaited(along.choose(page));
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
                  onSpeed: (speed) {
                    onUse?.call();
                    unawaited(along.track.setSpeed(speed));
                  },
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// The PDF pane's width before it's dragged: 40% of the screen's width,
/// from 160 to 480 px, so the page reads.
abstract final class PdfPaneWidth {
  static double of(double screen) => (screen * 0.4).clamp(160.0, 480.0);
}

/// The PDF followed, beside the screen: its name and **Close** at the top,
/// the document under them, scrolling and zoomable ([PdfPage]), [width]
/// wide ([PdfPaneWidth], or as the user dragged it).
class _PdfPane extends StatelessWidget {
  const _PdfPane({
    required this.event,
    required this.page,
    required this.width,
    required this.view,
    required this.onClose,
    this.onUse,
  });

  final CaptureEvent event;
  final EventPage page;
  final double width;
  final Widget view;
  final VoidCallback onClose;
  final VoidCallback? onUse;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
                    const Icon(
                      Icons.picture_as_pdf_outlined,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        fileLabel(l10n, event, page),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('cam-pdf-close'),
                      tooltip: l10n.camAlongPdfHide,
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
/// the section that repeats ([_SectionBar]), and for anything playing in
/// the app, its speed ([_SpeedBar]). Nothing while there's none.
class _BackingFrame extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: track,
    builder: (context, _) {
      final page = track.page;
      if (page == null) return const SizedBox.shrink();
      final l10n = context.l10n;
      final event = track.library.byId(eventId);
      final media = track.media;
      final link = track.link;
      // As wide as the sidebar, at most a third of the screen's height.
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
      const compact = VisualDensity(horizontal: -4, vertical: -4);
      return ColoredBox(
        key: const Key('cam-along-frame'),
        color: Colors.black,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (content != null) Center(child: content),
            if (media != null)
              VideoProgressIndicator(
                media,
                allowScrubbing: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
              ),
            if (track.canSection)
              _SectionBar(
                track: track,
                onSection: onSection,
                onSectionHere: onSectionHere,
                onSectionClear: onSectionClear,
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
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 40,
              child: track.loading
                  ? const Center(
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Row(
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
                            tooltip: track.playing
                                ? l10n.camAlongPause
                                : l10n.camAlongPlay,
                            visualDensity: compact,
                            color: Colors.white,
                            icon: Icon(
                              track.playing ? Icons.pause : Icons.play_arrow,
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
          ],
        ),
      );
    },
  );
}

/// The sidebar: the backing track's frame at its top, always there, and
/// under it the capture's recordings, videos and links, the one playing
/// along marked; a tap plays one along. Then its [pdfs], if any, under a
/// heading of their own, the one followed ([pdf]) marked; a tap shows it
/// beside the screen, or hides it, tapped again. At the bottom, [footer],
/// if any, out of the scrolling list.
class PlayAlongSidebar extends StatelessWidget {
  const PlayAlongSidebar({
    super.key,
    required this.library,
    required this.eventId,
    required this.track,
    required this.linkFrame,
    required this.onChoose,
    this.pdfs = const [],
    this.pdf,
    this.onPdf,
    this.footer,
    required this.onToggle,
    required this.onStop,
    required this.onSkip,
    required this.onRepeat,
    required this.onSection,
    required this.onSectionHere,
    required this.onSectionClear,
    required this.onSpeed,
  });

  final Library library;
  final String eventId;
  final BackingTrack track;
  final Widget Function(LinkFrameController controller) linkFrame;
  final void Function(EventPage page) onChoose;
  final List<EventPage> pdfs;
  final EventPage? pdf;
  final void Function(EventPage page)? onPdf;
  final Widget? footer;
  final VoidCallback onToggle;
  final VoidCallback onStop;
  final void Function(Duration by) onSkip;
  final VoidCallback onRepeat;
  final void Function(Duration start, Duration end) onSection;
  final void Function({required bool end}) onSectionHere;
  final VoidCallback onSectionClear;
  final void Function(double speed) onSpeed;

  /// Its width on a screen [screen] wide: 40% of it, from 120 to 280 px
  /// (a third of a phone held upright).
  static double widthFor(double screen) => (screen * 0.4).clamp(120.0, 280.0);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      key: const Key('cam-along-sidebar'),
      width: widthFor(MediaQuery.sizeOf(context).width),
      child: Material(
        color: const Color(0xFF1C1C1C),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BackingFrame(
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
            ),
            Expanded(child: _list(context, l10n)),
            ?footer,
          ],
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

  /// The files to play along, under the frame, then the PDFs to follow.
  Widget _list(BuildContext context, AppLocalizations l10n) =>
      ListenableBuilder(
        listenable: Listenable.merge([library, track]),
        builder: (context, _) {
          final event = library.byId(eventId);
          final pages = [...?event?.pages.where(BackingTrack.plays)];
          final primary = Theme.of(context).colorScheme.primary;
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              if (pages.isNotEmpty) _heading(l10n.camAlongTitle),
              for (final page in pages)
                ListTile(
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
                  trailing: track.page?.id == page.id && track.playing
                      ? const Icon(Icons.graphic_eq, size: 18)
                      : null,
                  onTap: () => onChoose(page),
                ),
              if (pdfs.isNotEmpty && event != null) ...[
                _heading(l10n.camAlongPdfs),
                for (final page in pdfs)
                  Tooltip(
                    message: pdf?.id == page.id
                        ? l10n.camAlongPdfHide
                        : l10n.camAlongPdfShow,
                    child: ListTile(
                      key: ValueKey('cam-along-${page.id}'),
                      dense: true,
                      selected: pdf?.id == page.id,
                      selectedColor: primary,
                      textColor: Colors.white,
                      iconColor: Colors.white70,
                      leading: Icon(_icon(page)),
                      title: Text(
                        fileLabel(l10n, event, page),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: pdf?.id == page.id
                          ? const Icon(Icons.vertical_split, size: 18)
                          : null,
                      onTap: () => onPdf?.call(page),
                    ),
                  ),
              ],
            ],
          );
        },
      );
}

/// A recording's, video's, link's or PDF's icon (a YouTube video's as a
/// video).
IconData _icon(EventPage page) => switch (page) {
  EventPage(isPdf: true) => Icons.picture_as_pdf_outlined,
  EventPage(isAudio: true) => Icons.audiotrack,
  EventPage(isVideo: true) => Icons.movie_outlined,
  EventPage(:final url?) when youTubeVideoId(url) != null =>
    Icons.smart_display_outlined,
  _ => Icons.link,
};

/// The section of a recording or video that repeats: a range over the
/// whole file (dragging either end sets it), its times, and buttons to
/// start or end it where it plays now, or to play all of it again.
class _SectionBar extends StatelessWidget {
  const _SectionBar({
    required this.track,
    required this.onSection,
    required this.onSectionHere,
    required this.onSectionClear,
  });

  final BackingTrack track;
  final void Function(Duration start, Duration end) onSection;
  final void Function({required bool end}) onSectionHere;
  final VoidCallback onSectionClear;

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
    final primary = Theme.of(context).colorScheme.primary;
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
            activeTrackColor: range == null ? Colors.white24 : primary,
            inactiveTrackColor: Colors.white12,
            thumbColor: range == null ? Colors.white70 : primary,
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
                  color: range == null ? Colors.white54 : primary,
                  fontSize: 11,
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
/// it goes back to 1×).
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
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        children: [
          Tooltip(
            message: l10n.camAlongSpeed,
            child: const Icon(
              Icons.slow_motion_video,
              color: Colors.white70,
              size: 16,
            ),
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
          Tooltip(
            message: l10n.camAlongSpeedNormal,
            child: InkWell(
              key: const Key('cam-along-speed-label'),
              onTap: normal ? null : () => onSpeed(1),
              child: SizedBox(
                width: 44,
                child: Text(
                  label(speed),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: normal ? Colors.white54 : primary,
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
