import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How a recording program's meter moves ([LevelMeter]): the microphone's
/// peaks in dBFS, shown at once as they rise and falling back at
/// [fallDbPerSecond]; the highest kept for [hold] (the peak-hold mark),
/// then falling with the rest. Shown in segments from [floorDb] to 0
/// dBFS, finer near the top as in a recording program ([bottoms]): green,
/// yellow from [yellowDb], red from [redDb].
class LevelBallistics {
  LevelBallistics();

  static const floorDb = -60.0;

  /// Each segment's bottom edge, in dBFS, from the lowest: it lights once
  /// the level reaches it.
  static const bottoms = [
    floorDb, -48.0, -40.0, -34.0, -28.0, -24.0, -20.0, //
    -16.0, -12.0, -9.0, //
    -6.0, -3.0,
  ];
  static int get segments => bottoms.length;
  static const yellowDb = -18.0;
  static const redDb = -6.0;
  static const fallDbPerSecond = 24.0;
  static const hold = Duration(milliseconds: 1500);

  /// The level shown and the peak held, in dBFS ([floorDb]: nothing).
  double shown = floorDb;
  double held = floorDb;
  Duration? _last;
  Duration _heldAt = Duration.zero;

  /// [peak] (0 to 1, full scale; null: no sound read) at [now]: the meter
  /// moves.
  void update(double? peak, Duration now) {
    final seconds = switch (_last) {
      final last? => (now - last).inMicroseconds / 1e6,
      null => 0.0,
    };
    _last = now;
    final db = toDb(peak);
    final fallen = math.max(floorDb, shown - fallDbPerSecond * seconds);
    shown = math.max(db, fallen);
    if (shown >= held) {
      held = shown;
      _heldAt = now;
    } else if (now - _heldAt > hold) {
      held = math.max(shown, held - fallDbPerSecond * seconds);
    }
  }

  /// [peak] (0 to 1) in dBFS, no lower than [floorDb].
  static double toDb(double? peak) {
    if (peak == null || peak <= 0) return floorDb;
    return math.max(floorDb, 20 * math.log(math.min(peak, 1)) / math.ln10);
  }

  /// How many segments [db] lights, from the bottom: those whose bottom
  /// edge it reaches (the first, anything over [floorDb]).
  static int lit(double db) {
    if (db <= floorDb) return 0;
    return bottoms.where((bottom) => db >= bottom).length;
  }

  /// The [i]th segment's colour (0: the bottom), by its bottom edge.
  static Color colorOf(int i) {
    final bottom = bottoms[i];
    if (bottom >= redDb) return Colors.redAccent;
    if (bottom >= yellowDb) return Colors.amber;
    return Colors.greenAccent.shade400;
  }

  int get litSegments => lit(shown);

  /// The segment of the peak held (-1: none).
  int get heldSegment => lit(held) - 1;
}

/// The microphone's level beside Rec, as recording programs show it: a
/// column of segments, green, then yellow, then red near full scale, with
/// the latest peak held a moment. It asks [read] for the loudest the
/// microphone has been since it last asked (0 to 1; null: not read now),
/// [interval] apart; should [read] not be there (a
/// [MissingPluginException]), it stops asking.
class LevelMeter extends StatefulWidget {
  const LevelMeter({
    super.key,
    required this.read,
    this.tooltip,
    this.interval = const Duration(milliseconds: 40),
    this.size = const Size(8, 36),
  });

  final Future<double?> Function() read;
  final String? tooltip;
  final Duration interval;
  final Size size;

  @override
  State<LevelMeter> createState() => _LevelMeterState();
}

class _LevelMeterState extends State<LevelMeter> {
  final _ballistics = LevelBallistics();
  Timer? _timer;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, _tick);
  }

  Future<void> _tick(Timer timer) async {
    // One question at a time (a slow answer skips a turn).
    if (_asking) return;
    _asking = true;
    double? peak;
    try {
      peak = await widget.read();
    } on MissingPluginException {
      _timer?.cancel();
    } on Object catch (e) {
      debugPrint('TabCam: cam: level: $e');
    } finally {
      _asking = false;
    }
    if (!mounted) return;
    final lit = _ballistics.litSegments;
    final held = _ballistics.heldSegment;
    // The time by the timer's ticks (late ones counted).
    _ballistics.update(peak, widget.interval * timer.tick);
    // Rebuilt only when a segment changes.
    if (lit != _ballistics.litSegments || held != _ballistics.heldSegment) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meter = CustomPaint(
      size: widget.size,
      painter: LevelMeterPainter(
        _ballistics.litSegments,
        _ballistics.heldSegment,
      ),
    );
    return switch (widget.tooltip) {
      final tooltip? => Tooltip(message: tooltip, child: meter),
      null => meter,
    };
  }
}

/// Draws a [LevelMeter]: [lit] segments from the bottom, and the [held]
/// one (-1: none); the others dim.
class LevelMeterPainter extends CustomPainter {
  LevelMeterPainter(this.lit, this.held);

  final int lit;
  final int held;

  @override
  void paint(Canvas canvas, Size size) {
    final n = LevelBallistics.segments;
    const gap = 1.0;
    final height = (size.height - gap * (n - 1)) / n;
    final paint = Paint();
    for (var i = 0; i < n; i++) {
      final color = LevelBallistics.colorOf(i);
      final on = i < lit || i == held;
      paint.color = on ? color : color.withValues(alpha: 0.18);
      final top = size.height - (i + 1) * height - i * gap;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, size.width, height),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(LevelMeterPainter old) =>
      old.lit != lit || old.held != held;
}
