import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A file in the app's private Application Support folder (never shared,
/// not in the Files app).
class EmailStore {
  const EmailStore();

  Future<File> get _file async => File(
    '${(await getApplicationSupportDirectory()).path}/email_sign_in.json',
  );

  Future<String?> load() async {
    try {
      final f = await _file;
      return await f.exists() ? await f.readAsString() : null;
    } catch (e) {
      debugPrint('TabCam: reading the email session failed: $e');
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
      debugPrint('TabCam: saving the email session failed: $e');
    }
  }
}
