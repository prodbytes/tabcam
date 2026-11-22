import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/language.dart';

/// The Text view's zooms: its text's usual size times these. **Zoom in**
/// and **Zoom out** go one step; a pinch, or Ctrl / ⌘ + the wheel, goes
/// anywhere from the first to the last.
const textZooms = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0];

/// [zoom] kept within [textZooms].
double clampTextZoom(double zoom) =>
    zoom.clamp(textZooms.first, textZooms.last).toDouble();

/// The zoom one step in ([by] 1) or out (−1) from [zoom]: the next of
/// [textZooms] past it (a pinch can leave it between two), or the last
/// one there is.
double nextTextZoom(double zoom, int by) {
  const near = 0.001;
  if (by > 0) {
    return textZooms.firstWhere(
      (z) => z > zoom + near,
      orElse: () => textZooms.last,
    );
  }
  return textZooms.lastWhere(
    (z) => z < zoom - near,
    orElse: () => textZooms.first,
  );
}

/// Whether Ctrl or ⌘ is held: the wheel zooms then, and doesn't scroll.
bool _zoomKey() {
  final keyboard = HardwareKeyboard.instance;
  return keyboard.isControlPressed || keyboard.isMetaPressed;
}

/// The Text view's scrolling, which leaves the wheel to the zoom while
/// Ctrl or ⌘ is held ([TextMover]): the scroll view doesn't take it, so
/// it neither scrolls nor keeps the zoom from having it.
class TextZoomScrollPhysics extends ScrollPhysics {
  const TextZoomScrollPhysics({super.parent});

  @override
  TextZoomScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      TextZoomScrollPhysics(parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      !_zoomKey() && super.shouldAcceptUserOffset(position);
}

/// Over the Text view's bottom right, one over the other as a PDF's
/// zoom buttons: **Drag to move** (a hand; a toggle, filled while on),
/// **Zoom in** (+), the zoom (a percentage, once it isn't the usual size;
/// tapped, back to it) and **Zoom out** (−).
class TextViewControls extends StatelessWidget {
  const TextViewControls({
    super.key,
    required this.zoom,
    required this.onZoom,
    required this.dragging,
    required this.onDragging,
  });

  final double zoom;

  /// A button asks for this zoom.
  final ValueChanged<double> onZoom;

  /// Drag to move is on.
  final bool dragging;
  final ValueChanged<bool> onDragging;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const compact = VisualDensity(horizontal: -2, vertical: -2);
    final drag = dragging
        ? IconButton.filled(
            key: const Key('text-drag'),
            tooltip: l10n.textViewDragOn,
            visualDensity: compact,
            icon: const Icon(Icons.pan_tool),
            onPressed: () => onDragging(false),
          )
        : IconButton.filledTonal(
            key: const Key('text-drag'),
            tooltip: l10n.textViewDragTip,
            visualDensity: compact,
            icon: const Icon(Icons.pan_tool_outlined),
            onPressed: () => onDragging(true),
          );
    final usual = (zoom - 1).abs() < 0.001;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(toggled: dragging, child: drag),
        const SizedBox(height: 4),
        IconButton.filledTonal(
          key: const Key('text-zoom-in'),
          tooltip: l10n.pdfZoomIn,
          visualDensity: compact,
          icon: const Icon(Icons.zoom_in),
          onPressed: zoom < textZooms.last
              ? () => onZoom(nextTextZoom(zoom, 1))
              : null,
        ),
        if (!usual) ...[
          const SizedBox(height: 4),
          Tooltip(
            message: l10n.textViewZoomReset,
            child: Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              shape: const StadiumBorder(),
              child: InkWell(
                key: const Key('text-zoom'),
                customBorder: const StadiumBorder(),
                onTap: () => onZoom(1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    '${(zoom * 100).round()}%',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 4),
        IconButton.filledTonal(
          key: const Key('text-zoom-out'),
          tooltip: l10n.pdfZoomOut,
          visualDensity: compact,
          icon: const Icon(Icons.zoom_out),
          onPressed: zoom > textZooms.first
              ? () => onZoom(nextTextZoom(zoom, -1))
              : null,
        ),
      ],
    );
  }
}

/// The Text view's text, zoomed and moved:
///
/// - While [dragging], a layer over it takes the pointer: a drag (a
///   mouse's too) moves the text any way, scrolling [down] and the
///   sideways scroll under where the drag began ([across]), instead of
///   editing or selecting it; the wheel scrolls as it would.
/// - Always: two fingers pinched, a trackpad's pinch, or Ctrl / ⌘ + the
///   wheel zoom it, about where they are.
///
/// [across] are the sideways scrolls side by side, each as wide as the
/// rest (one, or two columns). A zoom keeps what's at its focus where it
/// is on screen ([zoomTo]): a pinch's or the wheel's, where they are; the
/// buttons', the top left of what shows, as a text editor's zoom does, so
/// the line being read stays in view from its start.
class TextMover extends StatefulWidget {
  const TextMover({
    super.key,
    required this.zoom,
    required this.onZoom,
    required this.dragging,
    required this.down,
    required this.across,
    required this.child,
  });

  final double zoom;
  final ValueChanged<double> onZoom;
  final bool dragging;
  final ScrollController down;
  final List<ScrollController> across;
  final Widget child;

  @override
  State<TextMover> createState() => TextMoverState();
}

class TextMoverState extends State<TextMover> {
  /// The sideways scroll the drag under way moves.
  ScrollController? _dragged;
  bool _grabbing = false;

  /// The fingers on the text, for a pinch: where each is.
  final _fingers = <int, Offset>{};

  /// A pinch's distance between its two fingers when it began, and the
  /// zoom then.
  double? _pinchFrom;
  double _pinchZoom = 1;

  /// Zooms to [zoom] (kept within [textZooms]) keeping what's at [focus]
  /// (in this view) where it is: down, and sideways in the column it's
  /// on. Without one, and in the other column, the top left of what
  /// shows stays.
  void zoomTo(double zoom, [Offset? focus]) {
    zoom = clampTextZoom(zoom);
    final was = widget.zoom;
    if ((zoom - was).abs() < 0.0001) return;
    final size = context.size ?? Size.zero;
    final ratio = zoom / was;
    final width = widget.across.isEmpty
        ? 0.0
        : size.width / widget.across.length;
    // The focus in column [i], from its left; none (0) off it.
    double x(int i) {
      final dx = (focus?.dx ?? -1) - i * width;
      return dx >= 0 && dx < width ? dx : 0;
    }

    final y = focus?.dy ?? 0;
    // Where each scroll should be once the text is laid out at the new
    // size: what was at the focus, still there.
    final targets = <(ScrollController, double)>[
      if (widget.down.hasClients)
        (widget.down, (widget.down.offset + y) * ratio - y),
      for (final (i, c) in widget.across.indexed)
        if (c.hasClients) (c, (c.offset + x(i)) * ratio - x(i)),
    ];
    widget.onZoom(zoom);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final (c, offset) in targets) {
        if (!c.hasClients) continue;
        final p = c.position;
        c.jumpTo(offset.clamp(p.minScrollExtent, p.maxScrollExtent));
      }
    });
  }

  /// Scrolls [c] by [by] pixels, within its ends.
  static void _scrollBy(ScrollController? c, double by) {
    if (c == null || !c.hasClients || by == 0) return;
    final p = c.position;
    c.jumpTo((c.offset + by).clamp(p.minScrollExtent, p.maxScrollExtent));
  }

  ScrollController? _acrossAt(Offset at) {
    final across = widget.across;
    if (across.isEmpty) return null;
    final width = (context.size?.width ?? 0) / across.length;
    if (width <= 0) return across.first;
    return across[(at.dx ~/ width).clamp(0, across.length - 1)];
  }

  void _signal(PointerSignalEvent event) {
    final resolver = GestureBinding.instance.pointerSignalResolver;
    if (event is PointerScaleEvent) {
      resolver.register(event, (e) {
        zoomTo(widget.zoom * (e as PointerScaleEvent).scale, e.localPosition);
      });
    } else if (event is PointerScrollEvent && _zoomKey()) {
      // A wheel's notch (about 100) zooms by a fifth; a trackpad's pinch,
      // which comes as small deltas, smoothly.
      resolver.register(event, (e) {
        final dy = (e as PointerScrollEvent).scrollDelta.dy;
        zoomTo(widget.zoom * pow(2, -dy / 400), e.localPosition);
      });
    } else if (event is PointerScrollEvent && widget.dragging) {
      // The layer over the text has the wheel: it scrolls as it would.
      resolver.register(event, (e) {
        final scroll = e as PointerScrollEvent;
        var delta = scroll.scrollDelta;
        if (HardwareKeyboard.instance.isShiftPressed &&
            scroll.kind == PointerDeviceKind.mouse) {
          delta = Offset(delta.dy, delta.dx);
        }
        _scrollBy(widget.down, delta.dy);
        _scrollBy(_acrossAt(scroll.localPosition), delta.dx);
      });
    }
  }

  void _down(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _fingers[event.pointer] = event.localPosition;
    if (_fingers.length == 2) {
      final [a, b] = _fingers.values.toList();
      _pinchFrom = (a - b).distance;
      _pinchZoom = widget.zoom;
    } else {
      _pinchFrom = null;
    }
  }

  void _move(PointerMoveEvent event) {
    if (!_fingers.containsKey(event.pointer)) return;
    _fingers[event.pointer] = event.localPosition;
    final from = _pinchFrom;
    if (from == null || from < 1 || _fingers.length != 2) return;
    final [a, b] = _fingers.values.toList();
    zoomTo(_pinchZoom * (a - b).distance / from, (a + b) / 2);
  }

  void _up(PointerEvent event) {
    if (_fingers.remove(event.pointer) != null) _pinchFrom = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _signal,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (widget.dragging)
            Positioned.fill(
              child: MouseRegion(
                cursor: _grabbing
                    ? SystemMouseCursors.grabbing
                    : SystemMouseCursors.grab,
                child: GestureDetector(
                  key: const Key('text-drag-layer'),
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => setState(() {
                    _grabbing = true;
                    _dragged = _acrossAt(d.localPosition);
                  }),
                  onPanUpdate: (d) {
                    // A pinch zooms; it doesn't move the text too.
                    if (_pinchFrom != null) return;
                    _scrollBy(widget.down, -d.delta.dy);
                    _scrollBy(_dragged, -d.delta.dx);
                  },
                  onPanEnd: (_) => setState(() => _grabbing = false),
                  onPanCancel: () => setState(() => _grabbing = false),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
