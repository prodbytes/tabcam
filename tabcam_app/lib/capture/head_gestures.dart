import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'web_head_tracker_stub.dart'
    if (dart.library.js_interop) 'web_head_tracker.dart';

/// What a head gesture asks for: the next neckline or the one before.
enum HeadGesture { next, previous }

/// Turns the head's angles, frame by frame, into deliberate gestures: a
/// nod up or a turn to the user's right is [HeadGesture.next], a nod down
/// or a turn to their left [HeadGesture.previous]. Pure Dart, tested
/// without a camera (test/head_gestures_test.dart).
///
/// Only a strong gesture counts, so playing (and looking down at the
/// fretboard) doesn't turn the tab: the head must swing [pitchThreshold]
/// up or down, or [yawThreshold] sideways, from where it rests, and come
/// back to rest within [maxGesture]. Held away longer, it's a new resting
/// place, not a gesture. After one, the next waits [cooldown].
class NodDetector {
  NodDetector({
    this.pitchThreshold = 20,
    this.yawThreshold = 25,
    this.rest = 8,
    this.maxGesture = const Duration(milliseconds: 1000),
    this.cooldown = const Duration(milliseconds: 800),
    this.settle = const Duration(seconds: 3),
  });

  /// Degrees from rest a nod (up, down) and a turn (sideways) must reach.
  final double pitchThreshold;
  final double yawThreshold;

  /// Within this many degrees of rest, the head is at rest.
  final double rest;

  /// How long a gesture may take, out and back.
  final Duration maxGesture;

  /// The pause after a gesture before the next counts.
  final Duration cooldown;

  /// Away from rest this long, the head has a new resting place.
  final Duration settle;

  /// Where the head rests (its pitch and yaw), once seen.
  double? _pitch0, _yaw0;

  /// When the head left rest, and the strongest gesture since.
  Duration? _left;
  HeadGesture? _strongest;
  double _strength = 0;
  Duration _quietUntil = Duration.zero;

  /// No face: the next one starts afresh.
  void reset() {
    _pitch0 = _yaw0 = null;
    _left = null;
    _strongest = null;
    _strength = 0;
  }

  /// The head's [pitch] (up positive) and [yaw] (to the user's right
  /// positive), in degrees, [at] a time; the gesture it ends, if any.
  HeadGesture? add(double pitch, double yaw, Duration at) {
    final (p0, y0) = (_pitch0, _yaw0);
    if (p0 == null || y0 == null) {
      _pitch0 = pitch;
      _yaw0 = yaw;
      return null;
    }
    final (dp, dy) = (pitch - p0, yaw - y0);
    final atRest = dp.abs() <= rest && dy.abs() <= rest;
    if (atRest) {
      final left = _left;
      final gesture = _strongest;
      _left = null;
      _strongest = null;
      _strength = 0;
      // Rest follows the head slowly as it settles.
      _pitch0 = p0 + (pitch - p0) * 0.1;
      _yaw0 = y0 + (yaw - y0) * 0.1;
      if (left == null || gesture == null) return null;
      if (at - left > maxGesture || at < _quietUntil) return null;
      _quietUntil = at + cooldown;
      return gesture;
    }
    final left = _left ??= at;
    if (at - left > settle) {
      // Held there: where it rests now.
      _pitch0 = pitch;
      _yaw0 = yaw;
      _left = null;
      _strongest = null;
      _strength = 0;
      return null;
    }
    // How far past its threshold each way went, the strongest kept.
    final nod = dp.abs() / pitchThreshold;
    final turn = dy.abs() / yawThreshold;
    final strength = max(nod, turn);
    if (strength >= 1 && strength > _strength) {
      _strength = strength;
      _strongest = (nod >= turn ? dp > 0 : dy > 0)
          ? HeadGesture.next
          : HeadGesture.previous;
    }
    return null;
  }
}

/// The head's pitch (up positive) and yaw (to the user's own right
/// positive), in degrees, from MediaPipe's facial transformation matrix
/// [m]: 4x4, column-major (the entry at row r, column c is `m[c * 4 + r]`),
/// null if it isn't one. Pure Dart, tested without a browser
/// (test/head_gestures_test.dart); [WebHeadTracker] uses it.
///
/// The matrix takes the canonical face model, which looks along its +Z,
/// into the camera's space: X to the right of the frame, Y up, Z out of
/// the screen towards the user (the camera looks along -Z). Its third
/// column is so where the face looks, in that space: facing the camera,
/// (0, 0, 1).
/// - Nodding up turns that towards +Y: pitch is its angle above the X-Z
///   plane, positive up.
/// - The frames are the camera's own, not mirrored (camera_web mirrors
///   the front camera's preview with CSS only, and MediaPipe reads the
///   video element's frames): the user is seen as someone facing them
///   sees them, their right on the frame's left. Turning to their own
///   right so turns the face towards -X: yaw is the angle of -X from +Z.
(double, double)? headAngles(List<double> m) {
  if (m.length != 16) return null;
  final (x, y, z) = (m[8], m[9], m[10]);
  if (![x, y, z].every((v) => v.isFinite)) return null;
  final flat = sqrt(x * x + z * z);
  if (flat == 0 && y == 0) return null;
  const degrees = 180 / pi;
  return (atan2(y, flat) * degrees, atan2(-x, z) * degrees);
}

/// Watches the camera for head gestures ([NodDetector]): from its frames
/// with ML Kit's face detector on Android and iOS ([HeadTracker]); in the
/// browser, from the preview's video with MediaPipe's Face Landmarker
/// ([WebHeadTracker]). [start] gives null elsewhere.
abstract class HeadTracking {
  /// A frame from the camera (none come on the web: it reads the preview
  /// itself).
  void onImage(CameraImage image);

  /// Whether a face is in view.
  ValueListenable<bool> get face;

  /// The camera the frames come from (it and how the device is held set
  /// how they're turned).
  set camera(CameraController camera);

  /// Whether the user has head gestures on: off, it watches nothing.
  set active(bool active);

  void dispose();

  /// The image format the camera must stream in for [HeadTracker].
  static ImageFormatGroup get imageFormat =>
      defaultTargetPlatform == TargetPlatform.iOS
      ? ImageFormatGroup.bgra8888
      : ImageFormatGroup.nv21;

  static HeadTracking? start(
    CameraController camera,
    void Function(HeadGesture) onGesture,
  ) {
    if (kIsWeb) return webHeadTracking(onGesture);
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS => HeadTracker(camera, onGesture),
      _ => null,
    };
  }
}

class HeadTracker implements HeadTracking {
  HeadTracker(this._camera, this.onGesture);

  CameraController _camera;
  final void Function(HeadGesture) onGesture;
  final _nods = NodDetector();
  final _clock = Stopwatch()..start();
  // Accurate mode: the fast one doesn't promise the sideways angle.
  final _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.2,
    ),
  );

  @override
  final ValueNotifier<bool> face = ValueNotifier(false);

  bool _busy = false;
  bool _closed = false;
  Duration _last = Duration.zero;
  Duration _lastFace = Duration.zero;

  @override
  set camera(CameraController camera) {
    _camera = camera;
    _nods.reset();
  }

  /// Off, the screen stops the frames too; these ignore any on the way.
  @override
  bool active = true;

  @override
  void onImage(CameraImage image) {
    final at = _clock.elapsed;
    // One frame at a time, about 10 a second.
    if (!active ||
        _busy ||
        _closed ||
        at - _last < const Duration(milliseconds: 100)) {
      return;
    }
    final input = _input(image);
    if (input == null) return;
    _busy = true;
    _last = at;
    _detect(input, at);
  }

  Future<void> _detect(InputImage input, Duration at) async {
    try {
      final faces = await _detector.processImage(input);
      if (_closed) return;
      // The nearest face: the biggest.
      Face? nearest;
      for (final f in faces) {
        if (nearest == null ||
            f.boundingBox.width > nearest.boundingBox.width) {
          nearest = f;
        }
      }
      final (pitch, yaw) = (nearest?.headEulerAngleX, nearest?.headEulerAngleY);
      if (pitch == null || yaw == null) {
        if (at - _lastFace > const Duration(seconds: 1)) {
          _nods.reset();
          face.value = false;
        }
        return;
      }
      _lastFace = at;
      face.value = true;
      // ML Kit's positive yaw is to the camera's right: the user's left.
      final gesture = _nods.add(pitch, -yaw, at);
      if (gesture != null) onGesture(gesture);
    } on Object catch (e) {
      debugPrint('TabCam: head gestures: $e');
    } finally {
      _busy = false;
    }
  }

  static const _turns = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// [image] as ML Kit takes it: one plane, turned upright.
  InputImage? _input(CameraImage image) {
    final camera = _camera.description;
    final sensor = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      rotation = InputImageRotationValue.fromRawValue(sensor);
    } else {
      final device = _turns[_camera.value.deviceOrientation] ?? 0;
      final turn = camera.lensDirection == CameraLensDirection.front
          ? (sensor + device) % 360
          : (sensor - device + 360) % 360;
      rotation = InputImageRotationValue.fromRawValue(turn);
    }
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (rotation == null || format == null || image.planes.length != 1) {
      return null;
    }
    final plane = image.planes.single;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _closed = true;
    _detector.close();
    face.dispose();
  }
}
