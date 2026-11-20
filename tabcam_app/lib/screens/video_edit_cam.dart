part of 'video_edit_screen.dart';

/// What a [StudioView] opened as Cam needs for its camera, its takes and
/// its play-along, as Cam's screen is given them: the cameras there
/// are, head gestures, the takes' recorder, a link's frame and a PDF's
/// view (tests pass their own of each), the time now and a take's name
/// from it, and, for a user without Premium, the preview's [gate].
class CamSetup {
  const CamSetup({
    required this.takeName,
    this.cameras = listCameras,
    this.headTracking = HeadTracking.start,
    this.takeRecorder = TakeRecorder.forPlatform,
    this.linkFrame = linkFrameFor,
    this.pdfView = pdfViewFor,
    this.now = DateTime.now,
    this.gate,
  });

  /// A take's name, from when it started ("Take 14:32").
  final String Function(AppLocalizations l10n, DateTime started) takeName;

  /// The cameras there are.
  final Future<List<CameraDescription>> Function() cameras;

  /// Watches for head gestures; null where it can't.
  final HeadTracking? Function(
    CameraController camera,
    void Function(HeadGesture) onGesture,
  )
  headTracking;

  /// Records takes where the camera plugin doesn't (the web); null where
  /// it does.
  final TakeRecorder? Function() takeRecorder;

  /// Shows a link in the backing track's frame.
  final Widget Function(LinkFrameController controller) linkFrame;

  /// Shows the PDF followed beside the camera.
  final Widget Function(Library library, CaptureEvent event, EventPage page)
  pdfView;

  /// The time now, which names the takes.
  final DateTime Function() now;

  /// Set for a user without Premium: Cam is a preview, greyed out under
  /// the Premium card ([PremiumGate]), and no camera opens.
  final ({CloudOcr ocr, String? email})? gate;
}

/// The least the camera keeps in Cam's view before the rows under its
/// controls give way.
const _cameraLeast = 160.0;

/// The narrowest the main row's bar is in Cam's view before the rows give
/// way: narrower, it can't be read or aimed at.
const _alongBarLeast = 120.0;

/// About how high Cam's controls are ([CamStrip]) at [scaler]'s text
/// size: their padding, Rec's button and its name under it.
double _camStripHeight(TextScaler scaler) => 16 + 52 + scaler.scale(14) * 1.43;

/// About how high the phrase under the camera is ([CamPhrase]) at
/// [scaler]'s text size, at the most (a long one shrinks to the width):
/// its strings and its count under them; with no tab, the note that
/// says so, on two lines.
double _camPhraseHeight(TextScaler scaler, CamSession cam) {
  final lines = cam.lines;
  final text = cam.playedLine ?? (lines.isEmpty ? null : lines[cam.line]);
  if (text == null) return 32 + 2 * scaler.scale(14) * 1.43;
  final strings = '\n'.allMatches(text).length + 1;
  return max(
    48.0,
    20 + strings * scaler.scale(18) * 1.2 + scaler.scale(12) * 1.43,
  );
}

/// Cam's view of [_StudioViewState]: with the camera in the main row's
/// place, the main row is what plays along ([PlayAlong.track]).
extension _CamRows on _StudioViewState {
  /// The camera state's main row ("Song"): the file playing along, its
  /// play / pause in its header and its bar on the time axis
  /// ([_AlongBar]); with none, where the capture has a file that plays,
  /// a dashed **Play along with a song…** that opens the sidebar's list,
  /// its first file loaded ([PlayAlong.show]); null where it has none.
  _Row? _alongRow(AppLocalizations l10n, PlayAlong along) {
    final track = along.track;
    final page = track.page;
    final name = l10n.videoEditLaneSong;
    final event = _library.byId(along.eventId);
    if (page == null) {
      final plays =
          event != null && PlayAlong.filesOf(event).any(BackingTrack.plays);
      if (!plays) return null;
      return (
        lane: 'main',
        header: _LaneHeader(width: _nameWidth, wide: _wide, name: name),
        bar: _AddAlong(
          label: l10n.videoEditMainAdd,
          onTap: () {
            along.show();
            _keys.requestFocus();
          },
        ),
      );
    }
    final playing = track.playing || track.countingIn;
    return (
      lane: 'main',
      header: _LaneHeader(
        width: _nameWidth,
        wide: _wide,
        name: name,
        volume: SizedBox(
          width: _LaneVolume.width,
          height: _SongBar.height,
          child: IconButton(
            key: const Key('video-edit-main-play'),
            tooltip: playing ? l10n.videoEditMainPause : l10n.videoEditMainPlay,
            padding: EdgeInsets.zero,
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            onPressed: track.canToggle
                ? () {
                    _keys.requestFocus();
                    unawaited(track.toggle());
                  }
                : null,
          ),
        ),
      ),
      bar: _AlongBar(
        track: track,
        name: event == null
            ? page.title ?? page.fileName
            : fileLabel(l10n, event, page),
        label: l10n.videoEditMainBar,
        onSeek: _seekAxis,
      ),
    );
  }
}

/// The file playing along in Cam's main row ([BackingTrack]): its name
/// on a bar as long as the time axis, the part played filled (red while
/// a take records), and its section, where one is set, outlined. Tapped
/// or dragged along, it goes there ([onSeek]: the track's seek, kept in
/// the section). A link in a frame has no time to go to: its name on a
/// dashed bar; a file still loading, its name alone.
class _AlongBar extends StatefulWidget {
  const _AlongBar({
    required this.track,
    required this.name,
    required this.label,
    required this.onSeek,
  });

  final BackingTrack track;
  final String name;

  /// What it does, for screen readers.
  final String label;

  final void Function(Duration at, {required bool exact}) onSeek;

  @override
  State<_AlongBar> createState() => _AlongBarState();
}

class _AlongBarState extends State<_AlongBar> {
  /// Where a drag is, along the bar.
  double _dragX = 0;

  Widget _name(Color color) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        widget.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontSize: 12),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final track = widget.track;
    final media = track.media;
    final length = media?.value.duration ?? Duration.zero;
    if (media == null || length <= Duration.zero) {
      final link = track.link != null;
      return SizedBox(
        key: const Key('video-edit-main-bar'),
        height: _SongBar.height,
        child: CustomPaint(
          painter: link ? _Dashed(scheme.outline) : null,
          child: DecoratedBox(
            decoration: link
                ? const BoxDecoration()
                : BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
            child: _name(
              link ? scheme.onSurfaceVariant : scheme.onPrimaryContainer,
            ),
          ),
        ),
      );
    }
    final ms = length.inMilliseconds;
    final played = media.value.position;
    final section = track.section;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        double x(Duration d) => (d.inMilliseconds / ms * width).clamp(0, width);
        Duration at(double dx) => Duration(
          milliseconds: (dx.clamp(0, width) / max(1.0, width) * ms).round(),
        );
        return Semantics(
          label: widget.label,
          child: GestureDetector(
            key: const Key('video-edit-main-bar'),
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => widget.onSeek(at(d.localPosition.dx), exact: true),
            onHorizontalDragStart: (d) => _dragX = d.localPosition.dx,
            onHorizontalDragUpdate: (d) {
              _dragX = d.localPosition.dx;
              widget.onSeek(at(_dragX), exact: false);
            },
            onHorizontalDragEnd: (_) => widget.onSeek(at(_dragX), exact: true),
            child: SizedBox(
              height: _SongBar.height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(color: scheme.primaryContainer),
                    ),
                    // The part played.
                    Positioned(
                      key: const Key('video-edit-main-played'),
                      left: 0,
                      width: x(played),
                      top: 0,
                      bottom: 0,
                      child: ColoredBox(
                        color: (track.recording ? Colors.red : scheme.primary)
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    if (section != null)
                      Positioned(
                        key: const Key('video-edit-main-section'),
                        left: x(section.start),
                        width: max(2.0, x(section.end) - x(section.start)),
                        top: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.tertiary.withValues(alpha: 0.15),
                            border: Border.all(
                              color: scheme.tertiary,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: _name(scheme.onPrimaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Cam's main row with nothing playing along: a dashed **Play along with
/// a song…** ([label]), tapped to open the sidebar's list ([onTap]).
class _AddAlong extends StatelessWidget {
  const _AddAlong({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      painter: _Dashed(theme.colorScheme.outline),
      child: InkWell(
        key: const Key('video-edit-main-add'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          height: _SongBar.height,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.queue_music,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dashed rounded outline.
class _Dashed extends CustomPainter {
  _Dashed(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          const Radius.circular(8),
        ),
      );
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Dashed old) => old.color != color;
}
