import 'dart:typed_data';

import 'scan.dart';
import 'scan_store.dart';

/// Scans kept in memory, for the web: they last until the tab is closed.
class PlatformScanStore implements ScanStore {
  final Map<String, Scan> _scans = {};
  final Map<String, Uint8List> _pages = {};

  @override
  Future<List<Scan>> list() async =>
      _scans.values.toList()..sort((a, b) => b.created.compareTo(a.created));

  @override
  Future<void> save(Scan scan) async => _scans[scan.id] = scan;

  @override
  Future<void> delete(String scanId) async {
    _scans.remove(scanId);
    _pages.removeWhere((key, _) => key.startsWith('$scanId/'));
  }

  @override
  Future<void> putPage(String scanId, String pageId, Uint8List bytes) async =>
      _pages['$scanId/$pageId'] = bytes;

  @override
  Future<Uint8List> page(String scanId, String pageId) async =>
      _pages['$scanId/$pageId'] ?? (throw StateError('No page $pageId'));

  @override
  Future<void> deletePage(String scanId, String pageId) async =>
      _pages.remove('$scanId/$pageId');
}
