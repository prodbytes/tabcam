import 'dart:async';
import 'dart:typed_data';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tabscan_app/capture/camera_capture_screen.dart';

/// The browser's camera, faked: it opens at once, and each picture is a
/// new few bytes.
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

  @override
  Widget buildPreview(int cameraId) =>
      const ColoredBox(key: Key('preview'), color: Colors.grey);

  @override
  Future<void> dispose(int cameraId) async {}
}

const _back = CameraDescription(
  name: 'back',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 0,
);
const _front = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 0,
);

void main() {
  late FakeCameraPlatform platform;
  setUp(() => CameraPlatform.instance = platform = FakeCameraPlatform());

  /// Opens the screen from a button, and gives what it returned.
  Future<CameraCaptureResult? Function()> open(
    WidgetTester tester,
    Future<List<CameraDescription>> Function() cameras,
  ) async {
    CameraCaptureResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await Navigator.of(context)
                .push<CameraCaptureResult>(
                  MaterialPageRoute(
                    builder: (_) => CameraCaptureScreen(cameras: cameras),
                  ),
                ),
            child: const Text('Scan'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('the camera opens (the back one), takes pages, and Done '
      'returns them', (tester) async {
    final result = await open(tester, () async => [_front, _back]);
    expect(platform.opened, ['back']);
    expect(find.byKey(const Key('preview')), findsOneWidget);

    await tester.tap(find.byTooltip('Take a picture'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Take a picture'));
    await tester.pumpAndSettle();
    expect(find.text('2 pages'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(result()!.pages, [
      [1, 1],
      [2, 2],
    ]);
  });

  testWidgets('Flip moves to the other camera', (tester) async {
    await open(tester, () async => [_back, _front]);
    await tester.tap(find.byTooltip('Flip camera'));
    await tester.pumpAndSettle();
    expect(platform.opened, ['back', 'front']);
  });

  testWidgets('cancelling with pages asks before discarding them', (
    tester,
  ) async {
    final result = await open(tester, () async => [_back]);
    await tester.tap(find.byTooltip('Take a picture'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard 1 page?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(result()!.pages, isEmpty);
  });

  testWidgets('without a camera, it offers photos instead', (tester) async {
    final result = await open(tester, () async => []);
    expect(find.text('No camera found.'), findsOneWidget);
    await tester.tap(find.text('Choose photos instead'));
    await tester.pumpAndSettle();
    expect(result()!.chooseInstead, isTrue);
  });

  testWidgets('a camera that isn\'t allowed says how to allow it', (
    tester,
  ) async {
    await open(
      tester,
      () async => throw CameraException('CameraAccessDenied', 'denied'),
    );
    expect(find.textContaining('site settings'), findsOneWidget);
  });
}
