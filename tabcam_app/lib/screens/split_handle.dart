import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// The separator between two panes, dragged to share the space between
/// them differently: a thin line with a grip on it, in a strip wide
/// enough to take a finger. [axis] is the one the panes are laid along
/// (horizontal: side by side, the handle a vertical bar). A double tap
/// puts the share back ([onReset]).
class SplitHandle extends StatelessWidget {
  const SplitHandle({
    super.key,
    required this.axis,
    required this.onDrag,
    this.onReset,
    this.color,
    this.background,
  });

  final Axis axis;

  /// How far it was dragged along [axis], in logical pixels.
  final void Function(double delta) onDrag;
  final VoidCallback? onReset;

  /// The line's and grip's colour; the theme's outline by default.
  final Color? color;

  /// The strip's; the theme's surface by default.
  final Color? background;

  /// How thick the strip is: enough to drag with a finger.
  static const thickness = 12.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = color ?? scheme.outlineVariant;
    final across = axis == Axis.horizontal;
    return MouseRegion(
      cursor: across
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // It follows the finger from where it went down (the slop too).
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragUpdate: across ? (d) => onDrag(d.delta.dx) : null,
        onVerticalDragUpdate: across ? null : (d) => onDrag(d.delta.dy),
        onDoubleTap: onReset,
        child: ColoredBox(
          color: background ?? scheme.surface,
          child: SizedBox(
            width: across ? thickness : double.infinity,
            height: across ? double.infinity : thickness,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // The line, the whole length.
                SizedBox(
                  width: across ? 1 : double.infinity,
                  height: across ? double.infinity : 1,
                  child: ColoredBox(color: line),
                ),
                // The grip, in the middle.
                Container(
                  width: across ? 4 : 32,
                  height: across ? 32 : 4,
                  decoration: BoxDecoration(
                    color: line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
