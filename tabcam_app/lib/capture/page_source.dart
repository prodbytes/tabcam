import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/language.dart';
import '../processing/page_crop.dart';

import 'camera_capture_screen.dart';

/// Where new pages come from.
///
/// On Android and iOS, [scan] opens the system's document scanner (ML Kit's
/// on Android, VisionKit's on iOS): it finds the page's edges, lets the
/// user adjust them, straightens the page and takes several pages in a
/// row. Elsewhere (the web) it opens [CameraCaptureScreen], the camera
/// through the browser, several pages in a row, uncropped; with no camera
/// there, photos picked instead.
abstract final class PageSource {
  static bool get _nativeScanner =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Scans pages with the camera. Empty when the user cancels.
  static Future<List<Uint8List>> scan(BuildContext context) async {
    if (!_nativeScanner) {
      final result = await Navigator.of(context).push<CameraCaptureResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const CameraCaptureScreen(),
        ),
      );
      if (result == null) return const [];
      final pages = result.chooseInstead
          ? [
              for (final f in await ImagePicker().pickMultiImage())
                await f.readAsBytes(),
            ]
          : result.pages;
      // No scanner straightened them: cropped to the page here, when one
      // stands out, as photos added by hand are.
      return [for (final p in pages) await cropToPage(p) ?? p];
    }
    final notAllowed = context.l10n.scanCameraNotAllowed;
    final paths = await scanAskingForCamera(
      () => CunningDocumentScanner.getPictures(
        scannerSource: ScannerSource.camera,
        // No filters: TabCam applies its own (the Tab filter).
        androidScannerMode: AndroidScannerMode.base,
      ),
      askForCamera: _askForCamera,
      notAllowed: notAllowed,
    );
    return _readAndClean(paths);
  }

  static const _cameraPermission = MethodChannel('tabcam/camera_permission');

  /// Asks Android for the camera; true when it's granted.
  static Future<bool> _askForCamera() async =>
      await _cameraPermission.invokeMethod<bool>('request') ?? false;

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

/// Runs [scan], the native scanner. Without Google Play services, ML Kit's
/// scanner isn't there and the plugin falls back to the system camera app,
/// which Android won't open while the camera permission (declared for Cam)
/// isn't granted: then the camera is asked for ([askForCamera]) and the
/// scan tried again. Still not allowed, it fails with [notAllowed].
@visibleForTesting
Future<List<String>?> scanAskingForCamera(
  Future<List<String>?> Function() scan, {
  required Future<bool> Function() askForCamera,
  required String notAllowed,
}) async {
  try {
    return await scan();
  } on CunningDocumentScannerException catch (e) {
    if (!cameraNotGranted(e)) rethrow;
  }
  if (!await askForCamera()) throw ScanCameraNotAllowed(notAllowed);
  return scan();
}

/// Whether the scanner failed for want of the camera permission.
@visibleForTesting
bool cameraNotGranted(CunningDocumentScannerException e) =>
    e.code == 'permission_denied' ||
    e.message.contains('android.permission.CAMERA');

/// The scan failed: the camera isn't allowed. Its text is the message.
class ScanCameraNotAllowed implements Exception {
  const ScanCameraNotAllowed(this.message);

  final String message;

  @override
  String toString() => message;
}
