import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

Future<void> discardTakeFile(XFile file) async {
  if (file.path.isEmpty) return;
  try {
    // At once (a temporary file, the camera's): no I/O left waiting.
    final f = File(file.path);
    if (f.existsSync()) f.deleteSync();
  } on Object catch (e) {
    debugPrint('TabCam: cam: the take thrown away wasn\'t deleted: $e');
  }
}
