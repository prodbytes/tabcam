import 'package:camera/camera.dart';

import 'take_file_stub.dart' if (dart.library.io) 'take_file_io.dart' as impl;

/// Deletes the file of a take thrown away (Cam's . key) from the device;
/// on the web, where it's only in memory, nothing to do. A file that can't
/// be deleted is left (the system clears its temporary files).
Future<void> discardTakeFile(XFile file) => impl.discardTakeFile(file);
