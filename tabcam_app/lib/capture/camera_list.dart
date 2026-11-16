import 'package:camera/camera.dart';

import 'camera_list_stub.dart'
    if (dart.library.js_interop) 'camera_list_web.dart'
    as platform;

/// The device's cameras, for Cam and the web's Scan: the camera plugin's
/// list, but on the web one camera that won't start (an infrared Windows
/// Hello camera, a virtual camera whose app isn't running, one another app
/// holds) no longer fails the whole list ([platform.listCameras]).
/// Infrared cameras ([looksInfrared]) come last, so they're never the one
/// opened first.
Future<List<CameraDescription>> listCameras() async =>
    orderCameras(await platform.listCameras());

/// [cameras] with those that look infrared ([looksInfrared]) last, the
/// others in their order.
List<CameraDescription> orderCameras(List<CameraDescription> cameras) => [
  for (final c in cameras)
    if (!looksInfrared(c.name)) c,
  for (final c in cameras)
    if (looksInfrared(c.name)) c,
];

final RegExp _infrared = RegExp(r'\bIR\b|infrared', caseSensitive: false);

/// Whether a camera's name ([CameraDescription.name], the browser's label
/// on the web) says it's an infrared one, as Windows Hello's are
/// ("Integrated IR Camera"): no picture a browser can use.
bool looksInfrared(String name) => _infrared.hasMatch(name);

/// Whether [e] says the camera couldn't start: the browser's
/// NotReadableError (another app holds it, which on Windows locks it, or
/// it failed), as the camera plugin reports it (`cameraNotReadable`).
bool cameraNotReadable(Object e) {
  if (e is! CameraException) return false;
  final code = e.code.toLowerCase();
  return code.contains('notreadable') || code.contains('trackstart');
}
