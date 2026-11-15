import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/level_meter.dart';

void main() {
  const ms = Duration(milliseconds: 1);

  group('LevelBallistics', () {
    test('peaks in dBFS, silence and nothing at the floor', () {
      expect(LevelBallistics.toDb(1), 0);
      expect(LevelBallistics.toDb(0.5), closeTo(-6.02, 0.01));
      expect(LevelBallistics.toDb(2), 0);
      expect(LevelBallistics.toDb(0), LevelBallistics.floorDb);
      expect(LevelBallistics.toDb(null), LevelBallistics.floorDb);
      expect(LevelBallistics.toDb(1e-6), LevelBallistics.floorDb);
    });

    test('green up to -18 dBFS, yellow to -6, red above', () {
      expect(LevelBallistics.lit(LevelBallistics.floorDb), 0);
      expect(LevelBallistics.lit(-59), 1);
      expect(LevelBallistics.lit(-26), 5);
      expect(LevelBallistics.lit(-6.02), 10);
      expect(LevelBallistics.lit(-6), 11);
      expect(LevelBallistics.lit(0), LevelBallistics.segments);
      final colors = [
        for (var i = 0; i < LevelBallistics.segments; i++)
          LevelBallistics.colorOf(i),
      ];
      final green = Colors.greenAccent.shade400;
      expect(colors, [
        ...List.filled(7, green),
        ...List.filled(3, Colors.amber),
        ...List.filled(2, Colors.redAccent),
      ]);
    });

    test('rises at once, falls back slowly, the peak held a moment', () {
      final meter = LevelBallistics()..update(0.5, Duration.zero);
      expect(meter.shown, closeTo(-6.02, 0.01));
      expect(meter.litSegments, 10);
      expect(meter.heldSegment, 9);
      // Silence: half a second later it has fallen 12 dB, the peak held.
      meter.update(null, ms * 500);
      expect(meter.shown, closeTo(-18.02, 0.01));
      expect(meter.held, closeTo(-6.02, 0.01));
      // The hold over, the peak falls too, never below the level.
      meter.update(null, ms * 1600);
      expect(meter.shown, closeTo(-44.42, 0.01));
      expect(meter.held, closeTo(-32.42, 0.01));
      meter.update(null, ms * 5000);
      expect(meter.shown, LevelBallistics.floorDb);
      expect(meter.held, LevelBallistics.floorDb);
      expect(meter.litSegments, 0);
      expect(meter.heldSegment, -1);
      // Louder at once.
      meter.update(1, ms * 5040);
      expect(meter.litSegments, LevelBallistics.segments);
    });
  });

  group('LevelMeter', () {
    LevelMeterPainter painter(WidgetTester tester) =>
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(LevelMeter),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as LevelMeterPainter;

    testWidgets('asks for the peak as it goes and lights the segments', (
      tester,
    ) async {
      double? level;
      var asked = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: LevelMeter(
              read: () async {
                asked++;
                return level;
              },
            ),
          ),
        ),
      );
      expect(painter(tester).lit, 0);
      level = 0.75;
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump();
      expect(painter(tester).lit, LevelBallistics.segments);
      level = null;
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(painter(tester).lit, 0);
      expect(asked, greaterThan(90));
      // Gone, it asks no more.
      await tester.pumpWidget(const SizedBox());
      final before = asked;
      await tester.pump(const Duration(seconds: 1));
      expect(asked, before);
    });

    testWidgets('stops asking where there is no level to read', (tester) async {
      var asked = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LevelMeter(
            read: () async {
              asked++;
              throw MissingPluginException();
            },
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(asked, 1);
      expect(painter(tester).lit, 0);
    });
  });
}
