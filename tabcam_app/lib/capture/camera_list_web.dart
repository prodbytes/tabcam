import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:camera_web/camera_web.dart';
// What the plugin keeps of each camera it lists, to open it: not exported.
// ignore: implementation_imports
import 'package:camera_web/src/types/camera_metadata.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// The cameras, on the web. The plugin's own list opens every camera to
/// learn which way it faces, and fails as a whole when one won't start:
/// on Windows, an infrared camera, a virtual one, or one another app holds.
/// Then this lists them itself the same way, leaving out those that don't
/// start, and records each for the plugin to open
/// ([CameraPlugin.camerasMetadata]), as its own list would. None starting,
/// the plugin's error stands.
Future<List<CameraDescription>> listCameras() async {
  final plugin = CameraPlatform.instance;
  try {
    return await availableCameras();
  } on CameraException catch (error) {
    if (plugin is! CameraPlugin) rethrow;
    debugPrint('TabCam: cameras: the list failed ($error); one by one');
    final cameras = await _oneByOne(plugin);
    if (cameras.isEmpty) rethrow;
    return cameras;
  }
}

Future<List<CameraDescription>> _oneByOne(CameraPlugin plugin) async {
  final media = web.window.navigator.mediaDevices;
  final List<web.MediaDeviceInfo> devices;
  try {
    devices = (await media.enumerateDevices().toDart).toDart;
  } on Object catch (e) {
    debugPrint('TabCam: cameras: enumerateDevices failed: $e');
    return const [];
  }
  final cameras = <CameraDescription>[];
  for (final device in devices) {
    if (device.kind != 'videoinput' || device.deviceId.isEmpty) continue;
    try {
      final stream = await media
          .getUserMedia(
            web.MediaStreamConstraints(
              video: {
                'deviceId': {'exact': device.deviceId},
              }.jsify()!,
            ),
          )
          .toDart;
      final tracks = stream.getVideoTracks().toDart;
      final facing = tracks.isEmpty ? '' : _facingOf(tracks.first);
      for (final track in tracks) {
        track.stop();
      }
      if (tracks.isEmpty) continue;
      final camera = CameraDescription(
        name: device.label,
        lensDirection: switch (facing) {
          'user' => CameraLensDirection.front,
          'environment' => CameraLensDirection.back,
          _ => CameraLensDirection.external,
        },
        sensorOrientation: 0,
      );
      // The plugin opens only cameras it has metadata for, and fills
      // this map only from its own list (the one that failed): the one way
      // to hand it a camera it didn't list. Public, marked for tests.
      // ignore: invalid_use_of_visible_for_testing_member
      plugin.camerasMetadata[camera] = CameraMetadata(
        deviceId: device.deviceId,
        facingMode: facing.isEmpty ? null : facing,
      );
      cameras.add(camera);
    } on Object catch (e) {
      debugPrint('TabCam: cameras: "${device.label}" left out: $e');
    }
  }
  return cameras;
}

/// Which way [track]'s camera faces (`user`, `environment`), or '' when
/// it doesn't say: desktop webcams leave `facingMode` out of their
/// settings, which the typed getter can't take (it's undefined).
String _facingOf(web.MediaStreamTrack track) {
  final settings = track.getSettings() as JSObject;
  final facing = settings.getProperty<JSAny?>('facingMode'.toJS);
  return facing.isA<JSString>() ? (facing as JSString).toDart : '';
}
