import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Where new pages come from.
///
/// On Android and iOS, [scan] opens the system's document scanner (ML Kit's
/// on Android, VisionKit's on iOS): it finds the page's edges, lets the
/// user adjust them, straightens the page and takes several pages in a
/// row. Elsewhere (the web) it takes a photo with the browser's camera, or
/// picks one, uncropped.
abstract final class PageSource {
  static bool get _nativeScanner =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Scans pages with the camera. Empty when the user cancels.
  static Future<List<Uint8List>> scan() async {
    if (!_nativeScanner) return _pick(ImageSource.camera);
    final paths = await CunningDocumentScanner.getPictures(
      scannerSource: ScannerSource.camera,
    );
    return _readAndClean(paths);
  }

  static Future<List<Uint8List>> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source);
    return file == null ? const [] : [await file.readAsBytes()];
  }

  /// The scanner's files, read; then its cache is emptied (the store keeps
  /// its own copies).
  static Future<List<Uint8List>> _readAndClean(List<String>? paths) async {
    if (paths == null) return const [];
    final pages = [for (final p in paths) await File(p).readAsBytes()];
    await CunningDocumentScanner.cleanCache().catchError((Object e) {
      debugPrint('Scanner cache not cleaned: $e');
    });
    return pages;
  }
}
