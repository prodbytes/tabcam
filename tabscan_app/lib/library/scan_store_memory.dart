import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'scan.dart';
import 'scan_store.dart';

/// Scans kept in memory, for the web: they last until the tab is closed.
class PlatformScanStore implements ScanStore {
  final Map<String, Scan> _scans = {};
  final Map<String, Uint8List> _pages = {};

  String _key(String scanId, ScanPage page) => '$scanId/${page.fileName}';

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
  Future<void> putPage(String scanId, ScanPage page, Uint8List bytes) async =>
      _pages[_key(scanId, page)] = bytes;

  @override
  Future<void> putPageFile(String scanId, ScanPage page, XFile file) async =>
      _pages[_key(scanId, page)] = await file.readAsBytes();

  @override
  Future<Uint8List> page(String scanId, ScanPage page) async =>
      _pages[_key(scanId, page)] ?? (throw StateError('No page ${page.id}'));

  @override
  Future<String?> pagePath(String scanId, ScanPage page) async => null;

  @override
  Future<void> deletePage(String scanId, ScanPage page) async =>
      _pages.remove(_key(scanId, page));
}
