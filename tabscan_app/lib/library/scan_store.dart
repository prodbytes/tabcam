import 'dart:typed_data';

import 'scan.dart';
import 'scan_store_memory.dart'
    if (dart.library.io) 'scan_store_io.dart'
    as platform;

/// Where scans are kept: files in the app's documents folder on Android and
/// iOS (scan_store_io.dart), memory on the web (scan_store_memory.dart).
abstract class ScanStore {
  factory ScanStore() = platform.PlatformScanStore;

  /// Every scan, newest first.
  Future<List<Scan>> list();

  /// Saves the scan's details (not its pages' images).
  Future<void> save(Scan scan);

  Future<void> delete(String scanId);

  Future<void> putPage(String scanId, String pageId, Uint8List bytes);

  Future<Uint8List> page(String scanId, String pageId);

  Future<void> deletePage(String scanId, String pageId);
}
