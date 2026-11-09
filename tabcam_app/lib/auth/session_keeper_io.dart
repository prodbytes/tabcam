import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A file in the app's private Application Support folder (never shared,
/// not in the Files app).
class SessionKeeper {
  const SessionKeeper();

  Future<File> get _file async =>
      File('${(await getApplicationSupportDirectory()).path}/session.json');

  Future<String?> load() async {
    try {
      final f = await _file;
      return await f.exists() ? await f.readAsString() : null;
    } catch (e) {
      debugPrint('TabCam: reading the session failed: $e');
      return null;
    }
  }

  Future<void> save(String? data) async {
    try {
      final f = await _file;
      if (data == null) {
        if (await f.exists()) await f.delete();
        return;
      }
      await f.parent.create(recursive: true);
      await f.writeAsString(data, flush: true);
    } catch (e) {
      debugPrint('TabCam: saving the session failed: $e');
    }
  }
}
