import 'dart:math';

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

  group('headAngles', () {
    /// A made-up facial transformation matrix, column-major as MediaPipe
    /// gives it: the face turned by [rotation] (rows of a 3x3 matrix),
    /// [away] centimetres in front of the camera.
    List<double> matrix(List<List<double>> rotation, {double away = 40}) => [
      for (var c = 0; c < 4; c++)
        for (var r = 0; r < 4; r++)
          c < 3 && r < 3
              ? rotation[r][c]
              : c == 3
              ? [0.0, 0.0, -away, 1.0][r]
              : 0.0,
    ];

    /// Turned about the camera's X axis (right) and Y axis (up).
    List<List<double>> aboutX(double degrees) {
      final a = degrees * pi / 180;
      return [
        [1, 0, 0],
        [0, cos(a), -sin(a)],
        [0, sin(a), cos(a)],
      ];
    }

    List<List<double>> aboutY(double degrees) {
      final a = degrees * pi / 180;
      return [
        [cos(a), 0, sin(a)],
        [0, 1, 0],
        [-sin(a), 0, cos(a)],
      ];
    }

    void expectAngles(List<double> m, double pitch, double yaw) {
      final (p, y) = headAngles(m)!;
      expect(p, closeTo(pitch, 1e-9));
      expect(y, closeTo(yaw, 1e-9));
    }

    test('facing the camera, the head is level and straight', () {
      expectAngles(matrix(aboutX(0)), 0, 0);
    });

    test('nodding up is positive pitch, down negative', () {
      // Up: where the face looks swings from +Z towards +Y, which is a
      // turn of minus that angle about +X.
      expectAngles(matrix(aboutX(-30)), 30, 0);
      expectAngles(matrix(aboutX(25)), -25, 0);
    });

    test('turning to the user\'s right is positive yaw, left negative', () {
      // The frame isn't mirrored: the user's right is the camera's -X, so
      // turning that way swings the face from +Z towards -X: a turn of
      // minus that angle about +Y.
      expectAngles(matrix(aboutY(-40)), 0, 40);
      expectAngles(matrix(aboutY(35)), 0, -35);
    });

    test('where the face is doesn\'t matter, only where it looks', () {
      expectAngles(matrix(aboutX(-20), away: 90), 20, 0);
    });

    test('a nod and a turn at once give both', () {
      // Turned right 30 degrees, then nodding up 20.
      final y = aboutY(-30), x = aboutX(-20);
      final both = [
        for (var r = 0; r < 3; r++)
          [
            for (var c = 0; c < 3; c++)
              y[r][0] * x[0][c] + y[r][1] * x[1][c] + y[r][2] * x[2][c],
          ],
      ];
      expectAngles(matrix(both), 20, 30);
    });

    test('anything but a 4x4 matrix of numbers is none', () {
      expect(headAngles(const []), isNull);
      expect(headAngles(List.filled(9, 0)), isNull);
      expect(headAngles(List.filled(16, 0)), isNull);
      expect(headAngles(matrix(aboutX(0))..[10] = double.nan), isNull);
    });
  });
}
