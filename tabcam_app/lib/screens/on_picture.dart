import 'dart:math';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../capture/render_plan.dart';

/// What can be picked on the video editor's preview ([OnPicture]): the
/// layer of a plan with that id.
enum PictureLayer {
  tab('tab'),
  title('title'),
  watermark('mark');

  const PictureLayer(this.id);

  /// Its layers' id in the plan ([PlanLayer.id]).
  final String id;

  /// The kind of [layer], if it's one that can be picked.
  static PictureLayer? of(PlanLayer layer) =>
      values.where((kind) => kind.id == layer.id).firstOrNull;
}

/// The editor's on-picture controls, over the preview (a video editor's
/// on-screen controls): while the video is paused, an outline around each
/// layer drawn at that frame (the take's band showing, the title, the
/// watermark), the one [selected] in the primary colour with its
/// [toolbar] beside it and, for the tab's band, a handle at its top
/// right that resizes it ([onResizeStart], [onResize] with how much
/// taller it's dragged, as a ratio of its height when the drag began,
/// [onResizeEnd]); and, while a fade covers that frame, a badge at the
/// top right saying so ([fadeBadge], a tap opening the fades, [onFades]).
/// Nothing shows while it plays, and nothing but the handle, the toolbar
/// and the badge takes a tap: the preview's own taps pick a layer.
class OnPicture extends StatelessWidget {
  const OnPicture({
    super.key,
    required this.video,
    required this.layers,
    required this.start,
    required this.size,
    required this.sizeOf,
    required this.selected,
    required this.toolbar,
    required this.resizeLabel,
    required this.onResizeStart,
    required this.onResize,
    required this.onResizeEnd,
    required this.fadeBadge,
    required this.onFades,
  });

  final VideoPlayerController video;
  final List<PlanLayer> layers;

  /// The kept part's start in the video (0 in the output).
  final Duration start;

  /// How big the picture is.
  final Size size;

  /// How big [look] is drawn, for its place ([PlanLayer.rectIn]).
  final Size Function(LayerLook look) sizeOf;

  final PictureLayer? selected;
  final Widget Function(PictureLayer layer) toolbar;
  final String resizeLabel;
  final VoidCallback onResizeStart;
  final void Function(double ratio) onResize;
  final VoidCallback onResizeEnd;

  /// The badge's text at [at] in the output: a fade's, or null.
  final String? Function(Duration at) fadeBadge;
  final VoidCallback onFades;

  /// How high the toolbar is.
  static const toolbarHeight = 40.0;

  /// The layers drawn at [at] in the output, each with where it is on a
  /// picture [size] big: the take's band showing then, the title's card
  /// and the watermark (those two outlined through their whole time, as
  /// they're there to edit even while they fade).
  static List<(PictureLayer, Rect)> shown(
    List<PlanLayer> layers,
    Duration at,
    Size size,
    Size Function(LayerLook look) sizeOf,
  ) => [
    for (final layer in layers)
      if (PictureLayer.of(layer) case final kind?)
        if (kind == PictureLayer.tab ? layer.alphaAt(at) > 0 : layer.within(at))
          if (layer.rectIn(size, sizeOf(layer.look)) case final rect
              when !rect.isEmpty)
            (kind, rect),
  ];

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: video,
    builder: (context, value, _) {
      if (value.isPlaying) return const SizedBox.shrink();
      final at = value.position - start;
      final scheme = Theme.of(context).colorScheme;
      final drawn = shown(layers, at, size, sizeOf);
      final picked = drawn.where((d) => d.$1 == selected).firstOrNull;
      final badge = fadeBadge(at);
      return Stack(
        key: const Key('video-edit-picture'),
        clipBehavior: Clip.none,
        children: [
          for (final (kind, rect) in drawn)
            Positioned.fromRect(
              rect: rect.inflate(1),
              child: IgnorePointer(
                child: DecoratedBox(
                  key: Key('video-edit-picture-${kind.name}'),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: kind == selected
                          ? scheme.primary
                          : Colors.white.withValues(alpha: 0.6),
                      width: kind == selected ? 2 : 1,
                    ),
                  ),
                ),
              ),
            ),
          if (picked case (final kind, final rect)) ...[
            if (kind == PictureLayer.tab)
              Positioned(
                left: max(0, rect.right - _ResizeHandle.box - 4),
                top: max(0, rect.top - _ResizeHandle.box / 2),
                width: _ResizeHandle.box,
                height: _ResizeHandle.box,
                child: _ResizeHandle(
                  label: resizeLabel,
                  height: rect.height,
                  onStart: onResizeStart,
                  onDrag: onResize,
                  onEnd: onResizeEnd,
                ),
              ),
            _toolbarFor(kind, rect),
          ],
          if (badge != null)
            Positioned(
              top: 4,
              right: 4,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: size.width / 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      key: const Key('video-edit-picture-fade'),
                      borderRadius: BorderRadius.circular(6),
                      onTap: onFades,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          badge,
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  /// [kind]'s toolbar, beside its [rect]: above it where there's room,
  /// else under it, else over its top; across from its centre, kept on
  /// the picture (narrowed to fit it, however large the text).
  Widget _toolbarFor(PictureLayer kind, Rect rect) {
    const gap = 6.0;
    final double top;
    if (rect.top >= toolbarHeight + gap) {
      top = rect.top - toolbarHeight - gap;
    } else if (rect.bottom + gap + toolbarHeight <= size.height) {
      top = rect.bottom + gap;
    } else {
      top = max(0, rect.top);
    }
    final across = size.width <= 0 ? 0.0 : rect.center.dx / size.width * 2 - 1;
    return Positioned(
      left: 0,
      right: 0,
      top: top,
      height: toolbarHeight,
      child: Align(
        alignment: Alignment(across.clamp(-1.0, 1.0), 0),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Material(
            key: const Key('video-edit-picture-toolbar'),
            color: const Color(0xE6202020),
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(height: toolbarHeight, child: toolbar(kind)),
          ),
        ),
      ),
    );
  }
}

/// The handle at the tab's band's top right: dragged up, the band grows;
/// down, it shrinks ([onDrag]'s ratio: the band's [height] when the drag
/// began, plus how far up it's dragged, over that height).
class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({
    required this.label,
    required this.height,
    required this.onStart,
    required this.onDrag,
    required this.onEnd,
  });

  /// How big its box is (to grab), its dot smaller.
  static const box = 32.0;

  final String label;
  final double height;
  final VoidCallback onStart;
  final void Function(double ratio) onDrag;
  final VoidCallback onEnd;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  double _from = 1;
  double _dragged = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: widget.label,
      child: Semantics(
        label: widget.label,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: GestureDetector(
            key: const Key('video-edit-picture-tab-resize'),
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) {
              _from = max(1, widget.height);
              _dragged = 0;
              widget.onStart();
            },
            onVerticalDragUpdate: (d) {
              _dragged -= d.delta.dy;
              widget.onDrag(max(0.05, (_from + _dragged) / _from));
            },
            onVerticalDragEnd: (_) => widget.onEnd(),
            onVerticalDragCancel: widget.onEnd,
            child: Center(
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: scheme.primary, width: 2),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
