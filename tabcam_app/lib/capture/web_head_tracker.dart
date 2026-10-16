import 'dart:async';
import 'dart:js_interop';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'head_gestures.dart';

/// In the browser, head gestures come from [WebHeadTracker].
HeadTracking? webHeadTracking(void Function(HeadGesture) onGesture) =>
    WebHeadTracker(onGesture);

/// MediaPipe Tasks Vision, pinned, and its WebAssembly from the same
/// place; the Face Landmarker model from Google's own storage. Only these
/// are downloaded: the camera's frames never leave the browser.
const _mediapipe =
    'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.21';
const _model =
    'https://storage.googleapis.com/mediapipe-models/face_landmarker/'
    'face_landmarker/float16/1/face_landmarker.task';

/// Head gestures in the browser: MediaPipe's Face Landmarker reads the
/// camera preview's own `<video>` (the web camera streams no frames to
/// Dart, so [onImage] gets none) about 10 times a second, and its
/// facial transformation matrix gives the head's angles ([headAngles])
/// for a [NodDetector].
///
/// MediaPipe loads when the tracker first runs (Cam open with head
/// gestures on), not with the app. If it can't (offline, blocked), the
/// tracker logs it and sees no face: Cam works on without gestures.
class WebHeadTracker implements HeadTracking {
  WebHeadTracker(this.onGesture) {
    _run();
  }

  final void Function(HeadGesture) onGesture;
  final _nods = NodDetector();
  final _clock = Stopwatch()..start();

  @override
  final ValueNotifier<bool> face = ValueNotifier(false);

  bool _active = true;
  bool _closed = false;
  bool _failed = false;
  Future<_FaceLandmarker?>? _loading;
  _FaceLandmarker? _landmarker;
  Timer? _timer;
  web.HTMLVideoElement? _video;
  Duration _lastFace = Duration.zero;
  String? _lastError;

  @override
  void onImage(CameraImage image) {}

  @override
  set camera(CameraController camera) {
    // Another camera: another video element, and another face.
    _video = null;
    _nods.reset();
  }

  @override
  set active(bool active) {
    _active = active;
    if (active) {
      _run();
    } else {
      _timer?.cancel();
      _timer = null;
      _nods.reset();
      face.value = false;
    }
  }

  void _run() {
    if (_closed || _failed || !_active || _timer != null) return;
    _loading ??= _load();
    // One detection at a time, about 10 a second.
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  Future<_FaceLandmarker?> _load() async {
    try {
      final vision = _TasksVision(
        await importModule('$_mediapipe/vision_bundle.mjs'.toJS).toDart,
      );
      final files = await vision.FilesetResolver.forVisionTasks(
        '$_mediapipe/wasm',
      ).toDart;
      Future<_FaceLandmarker> create(String delegate) =>
          vision.FaceLandmarker.createFromOptions(
            files,
            {
                  'baseOptions': {
                    'modelAssetPath': _model,
                    'delegate': delegate,
                  },
                  'runningMode': 'VIDEO',
                  'numFaces': 1,
                  'outputFaceBlendshapes': false,
                  'outputFacialTransformationMatrixes': true,
                }.jsify()!
                as JSObject,
          ).toDart;
      _FaceLandmarker landmarker;
      try {
        landmarker = await create('GPU');
      } on Object catch (e) {
        debugPrint('TabCam: head gestures: no GPU ($e), on the CPU');
        landmarker = await create('CPU');
      }
      if (_closed) {
        landmarker.close();
        return null;
      }
      return _landmarker = landmarker;
    } on Object catch (e) {
      debugPrint('TabCam: head gestures: MediaPipe didn\'t load: $e');
      _failed = true;
      _timer?.cancel();
      _timer = null;
      return null;
    }
  }

  void _tick() {
    final landmarker = _landmarker;
    if (_closed || !_active || landmarker == null) return;
    final at = _clock.elapsed;
    final video = _video = cameraVideo(_video);
    (double, double)? angles;
    if (video != null &&
        video.readyState >= 2 && // HAVE_CURRENT_DATA: a frame to read
        video.videoWidth > 0) {
      try {
        final result = landmarker.detectForVideo(
          video,
          web.window.performance.now(),
        );
        final matrices = result.facialTransformationMatrixes?.toDart;
        if (matrices != null && matrices.isNotEmpty) {
          angles = headAngles([
            for (final v in matrices.first.data.toDart) v.toDartDouble,
          ]);
        }
        _lastError = null;
      } on Object catch (e) {
        // Logged once, not ten times a second.
        if ('$e' != _lastError) {
          debugPrint('TabCam: head gestures: $e');
          _lastError = '$e';
        }
      }
    }
    if (angles == null) {
      if (at - _lastFace > const Duration(seconds: 1)) {
        _nods.reset();
        face.value = false;
      }
      return;
    }
    _lastFace = at;
    face.value = true;
    final (pitch, yaw) = angles;
    final gesture = _nods.add(pitch, yaw, at);
    if (gesture != null) onGesture(gesture);
  }

  @override
  void dispose() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _landmarker?.close();
    _landmarker = null;
    face.dispose();
  }
}

/// The camera preview's `<video>`: [known] while it still shows the
/// camera, otherwise looked up. camera_web gives it no id or class: it
/// creates a bare `<video>` (in a `<div>`) playing the camera's
/// MediaStream through `srcObject`, and Flutter puts that in a
/// `<flt-platform-view>` once the preview is built. So: a `<video>` in
/// the page playing a live camera stream (video_player's videos play a
/// `src` instead), one in a platform view first.
web.HTMLVideoElement? cameraVideo(web.HTMLVideoElement? known) {
  if (known != null && known.isConnected && _live(known)) return known;
  final videos = web.document.querySelectorAll('video');
  web.HTMLVideoElement? found;
  for (var i = 0; i < videos.length; i++) {
    final node = videos.item(i);
    if (node == null || !node.isA<web.HTMLVideoElement>()) continue;
    final video = node as web.HTMLVideoElement;
    if (!_live(video)) continue;
    if (video.closest('flt-platform-view') != null) return video;
    found ??= video;
  }
  return found;
}

/// Whether [video] plays a camera's live MediaStream.
bool _live(web.HTMLVideoElement video) {
  final source = video.srcObject;
  if (source == null || !source.isA<web.MediaStream>()) return false;
  final tracks = (source as web.MediaStream).getVideoTracks().toDart;
  return tracks.any((t) => t.readyState == 'live');
}

// MediaPipe Tasks Vision's API, as much of it as is used
// (https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.21/vision.d.ts).

extension type _TasksVision(JSObject _) implements JSObject {
  // ignore: non_constant_identifier_names
  external _FilesetResolverClass get FilesetResolver;
  // ignore: non_constant_identifier_names
  external _FaceLandmarkerClass get FaceLandmarker;
}

extension type _FilesetResolverClass(JSObject _) implements JSObject {
  external JSPromise<JSObject> forVisionTasks(String basePath);
}

extension type _FaceLandmarkerClass(JSObject _) implements JSObject {
  external JSPromise<_FaceLandmarker> createFromOptions(
    JSObject fileset,
    JSObject options,
  );
}

extension type _FaceLandmarker(JSObject _) implements JSObject {
  external _FaceLandmarkerResult detectForVideo(
    web.HTMLVideoElement video,
    double timestamp,
  );
  external void close();
}

extension type _FaceLandmarkerResult(JSObject _) implements JSObject {
  external JSArray<_Matrix>? get facialTransformationMatrixes;
}

/// A matrix, its values flattened column by column.
extension type _Matrix(JSObject _) implements JSObject {
  external JSArray<JSNumber> get data;
}
