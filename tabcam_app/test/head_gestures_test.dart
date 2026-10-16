import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/head_gestures.dart';

void main() {
  late NodDetector nods;
  late Duration now;
  setUp(() {
    nods = NodDetector();
    now = Duration.zero;
  });

  /// The head at [pitch] and [yaw] for [ms] milliseconds, a frame every
  /// 100 ms; the gestures that ended.
  List<HeadGesture> hold(double pitch, double yaw, int ms) => [
    for (var t = 0; t < ms; t += 100)
      ?nods.add(pitch, yaw, now += const Duration(milliseconds: 100)),
  ];

  /// At rest a while, out to [pitch], [yaw] for [ms], back to rest.
  List<HeadGesture> gesture(double pitch, double yaw, {int ms = 300}) => [
    ...hold(0, 0, 1000),
    ...hold(pitch, yaw, ms),
    ...hold(0, 0, 500),
  ];

  test('a strong nod up or turn right is next; down or left, the one '
      'before', () {
    expect(gesture(25, 0), [HeadGesture.next]);
    expect(gesture(-25, 0), [HeadGesture.previous]);
    expect(gesture(0, 30), [HeadGesture.next]);
    expect(gesture(0, -30), [HeadGesture.previous]);
  });

  test('a small movement is no gesture', () {
    expect(gesture(15, 0), isEmpty);
    expect(gesture(0, -20), isEmpty);
    expect(gesture(5, 5), isEmpty);
  });

  test('looking down a while (at the fretboard) is no gesture', () {
    expect(gesture(-35, 0, ms: 1500), isEmpty);
  });

  test('held away long, it rests there: a nod counts from there', () {
    expect(hold(0, 0, 500), isEmpty);
    expect(hold(-30, 0, 4000), isEmpty);
    // Up from there, and back: next.
    expect([...hold(-5, 0, 300), ...hold(-30, 0, 500)], [HeadGesture.next]);
    // Back up to where it rested before, and staying: no gesture.
    expect(hold(0, 0, 4000), isEmpty);
  });

  test('the strongest way counts', () {
    expect(gesture(22, -40), [HeadGesture.previous]);
  });

  test('one gesture, then a pause before the next', () {
    expect(hold(0, 0, 500), isEmpty);
    expect([...hold(25, 0, 200), ...hold(0, 0, 100)], [HeadGesture.next]);
    expect([...hold(25, 0, 200), ...hold(0, 0, 100)], isEmpty);
    expect(
      [...hold(0, 0, 1000), ...hold(25, 0, 200), ...hold(0, 0, 100)],
      [HeadGesture.next],
    );
  });

  test('a new face starts afresh', () {
    expect(hold(0, 0, 500), isEmpty);
    nods.reset();
    // Its first angles are where it rests.
    expect(hold(30, 0, 500), isEmpty);
  });
}
