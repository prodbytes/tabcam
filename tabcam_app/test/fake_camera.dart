import 'dart:async';
import 'dart:typed_data';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The device's camera, faked: it opens at once, each picture is a new
/// few bytes, and a video recording is a few bytes more.
class FakeCameraPlatform extends CameraPlatform
    with MockPlatformInterfaceMixin {
  final _initialized = StreamController<CameraInitializedEvent>.broadcast();
  int shots = 0;
  final List<String> opened = [];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings? mediaSettings,
  ) async {
    opened.add(cameraDescription.name);
    return opened.length;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    scheduleMicrotask(
      () => _initialized.add(
        CameraInitializedEvent(
          cameraId,
          1920,
          1080,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      ),
    );
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _initialized.stream.where((e) => e.cameraId == cameraId);

  // Streams that never emit (the controller waits on their first event:
  // an empty one would fail that wait).
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>().stream;

  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) =>
      StreamController<CameraClosingEvent>().stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Future<XFile> takePicture(int cameraId) async {
    shots++;
    return XFile.fromData(Uint8List.fromList([shots, shots]), name: 'p.jpg');
  }

  /// What `availableCameras` finds.
  List<CameraDescription> available = const [
    CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 0,
    ),
    CameraDescription(
      name: 'front',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 0,
    ),
  ];

  @override
  Future<List<CameraDescription>> availableCameras() async => available;

  int recordings = 0;
  bool recording = false;

  /// Frames streamed to the app (none come: whether it listens counts).
  late final _frames = StreamController<CameraImageData>.broadcast(
    onListen: () => streaming = true,
    onCancel: () => streaming = false,
  );
  bool streaming = false;

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) => _frames.stream;

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    recording = true;
    if (options.streamCallback case final callback?) {
      _recordingFrames = _frames.stream.listen(callback);
    }
  }

  StreamSubscription<CameraImageData>? _recordingFrames;

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    await _recordingFrames?.cancel();
    _recordingFrames = null;
    recording = false;
    recordings++;
    return XFile.fromData(
      Uint8List.fromList([9, recordings]),
      name: 'REC_$recordings.mp4',
      mimeType: 'video/mp4',
    );
  }

  @override
  Widget buildPreview(int cameraId) =>
      const ColoredBox(key: Key('preview'), color: Colors.grey);

  @override
  Future<void> dispose(int cameraId) async {}
}
