import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../l10n/language.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import '../screens/file_screen.dart';
import '../screens/youtube_link.dart';
import 'backing_track.dart';
import 'link_frame.dart';

/// Playing along with a capture's recordings, videos and links, in Cam,
/// the Text view and a PDF: the [BackingTrack], and whether its sidebar
/// ([PlayAlongSidebar]) shows. The sidebar opens by itself, with the first
/// of them loaded, paused, the first time the capture has one (when the
/// screen opens, or when one arrives: a sync, a take); hidden by the user
/// ([toggle]), it isn't opened again.
class PlayAlong extends ChangeNotifier {
  PlayAlong(this.library, this.eventId, {BackingTrack? track})
    : track = track ?? BackingTrack(library) {
    library.addListener(_changed);
    _changed();
  }

  final Library library;
  final String eventId;
  final BackingTrack track;

  /// Whether the sidebar shows.
  bool get open => _open;
  bool _open = false;

  /// Whether it has opened by itself yet (or the user has toggled it).
  bool _opened = false;

  /// Whether the capture has anything to play along with.
  bool get available =>
      library.byId(eventId)?.pages.any(BackingTrack.plays) ?? false;

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
    if (_opened) return;
    final event = library.byId(eventId);
    final first = event?.pages.where(BackingTrack.plays).firstOrNull;
    if (event == null || first == null) return;
    _opened = true;
    _open = true;
    if (track.page == null) {
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

/// [along]'s sidebar, beside [child]: kept while hidden (offstage), so a
/// link's page isn't reloaded; nothing when there's nothing to play along
/// with.
class PlayAlongBeside extends StatelessWidget {
  const PlayAlongBeside({
    super.key,
    required this.along,
    required this.child,
    this.linkFrame = linkFrameFor,
    this.onUse,
  });

  final PlayAlong along;
  final Widget child;
  final Widget Function(LinkFrameController controller) linkFrame;

  /// After each tap in the sidebar (Cam takes the keys back).
  final VoidCallback? onUse;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: along,
    builder: (context, _) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: child),
        if (along.available)
          Offstage(
            offstage: !along.open,
            child: PlayAlongSidebar(
              library: along.library,
              eventId: along.eventId,
              track: along.track,
              linkFrame: linkFrame,
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
            ),
          ),
      ],
    ),
  );
}

/// The backing track's frame, compact, at the top of the sidebar and as
/// wide: the video or link playing (a recording shows its progress only),
/// its name, « (10 seconds back), play / pause, stop, » (10 forward) and
/// repeat (on by default); for a recording or video of the capture's own,
/// the section that repeats ([_SectionBar]). Nothing while there's none.
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
/// along marked; a tap plays one along.
class PlayAlongSidebar extends StatelessWidget {
  const PlayAlongSidebar({
    super.key,
    required this.library,
    required this.eventId,
    required this.track,
    required this.linkFrame,
    required this.onChoose,
    required this.onToggle,
    required this.onStop,
    required this.onSkip,
    required this.onRepeat,
    required this.onSection,
    required this.onSectionHere,
    required this.onSectionClear,
  });

  final Library library;
  final String eventId;
  final BackingTrack track;
  final Widget Function(LinkFrameController controller) linkFrame;
  final void Function(EventPage page) onChoose;
  final VoidCallback onToggle;
  final VoidCallback onStop;
  final void Function(Duration by) onSkip;
  final VoidCallback onRepeat;
  final void Function(Duration start, Duration end) onSection;
  final void Function({required bool end}) onSectionHere;
  final VoidCallback onSectionClear;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = MediaQuery.sizeOf(context).width;
    return SizedBox(
      key: const Key('cam-along-sidebar'),
      // A third of a phone held upright; at most 280 px.
      width: (width * 0.4).clamp(120.0, 280.0),
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
            ),
            Expanded(child: _list(context, l10n)),
          ],
        ),
      ),
    );
  }

  /// The files to play along, under the frame.
  Widget _list(BuildContext context, AppLocalizations l10n) =>
      ListenableBuilder(
        listenable: Listenable.merge([library, track]),
        builder: (context, _) {
          final event = library.byId(eventId);
          final pages = [...?event?.pages.where(BackingTrack.plays)];
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  l10n.camAlongTitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
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
            ],
          );
        },
      );
}

/// A recording's, video's or link's icon (a YouTube video's as a video).
IconData _icon(EventPage page) => switch (page) {
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
