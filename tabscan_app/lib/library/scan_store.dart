import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

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

  /// Saves the scan's details (not its pages' files).
  Future<void> save(Scan scan);

  Future<void> delete(String scanId);

  /// Stores [bytes] as the page's file.
  Future<void> putPage(String scanId, ScanPage page, Uint8List bytes);

  /// Stores a copy of [file] as the page's file, without reading it into
  /// memory where the platform has files (videos can be large).
  Future<void> putPageFile(String scanId, ScanPage page, XFile file);

  /// The page's file, read.
  Future<Uint8List> page(String scanId, ScanPage page);

  /// The page's file on disk, for players that stream from a path; null
  /// where there are no files (the web).
  Future<String?> pagePath(String scanId, ScanPage page);

  Future<void> deletePage(String scanId, ScanPage page);
}
