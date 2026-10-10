import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'scan.dart';
import 'scan_store.dart';

/// Scans kept as files, one folder per scan in the app's documents folder:
/// `scans/<scan id>/scan.json` and a `<page id>.img` per page (the image as
/// scanned, JPEG or PNG).
class PlatformScanStore implements ScanStore {
  /// [_root] defaults to `scans/` in the app's documents folder.
  PlatformScanStore([this._root]);

  Directory? _root;

  Future<Directory> _scans() async {
    _root ??= Directory(
      '${(await getApplicationDocumentsDirectory()).path}/scans',
    );
    return _root!.create(recursive: true);
  }

  Future<Directory> _dir(String scanId) async =>
      Directory('${(await _scans()).path}/${checkId(scanId)}');

  @override
  Future<List<Scan>> list() async {
    final scans = <Scan>[];
    await for (final entry in (await _scans()).list()) {
      final file = File('${entry.path}/scan.json');
      if (entry is! Directory || !await file.exists()) continue;
      try {
        scans.add(Scan.fromJson(jsonDecode(await file.readAsString())));
      } on Object catch (e) {
        // One broken scan shouldn't hide the others.
        debugPrint('Skipping ${entry.path}: $e');
      }
    }
    return scans..sort((a, b) => b.created.compareTo(a.created));
  }

  @override
  Future<void> save(Scan scan) async {
    final dir = await (await _dir(scan.id)).create();
    // Written beside, then renamed over, so a crash never leaves half a file.
    final temp = File('${dir.path}/scan.json.tmp');
    await temp.writeAsString(jsonEncode(scan.toJson()), flush: true);
    await temp.rename('${dir.path}/scan.json');
  }

  @override
  Future<void> delete(String scanId) async {
    final dir = await _dir(scanId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<File> _page(String scanId, String pageId) async =>
      File('${(await _dir(scanId)).path}/${checkId(pageId)}.img');

  @override
  Future<void> putPage(String scanId, String pageId, Uint8List bytes) async {
    await (await _dir(scanId)).create();
    await (await _page(scanId, pageId)).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<Uint8List> page(String scanId, String pageId) async =>
      (await _page(scanId, pageId)).readAsBytes();

  @override
  Future<void> deletePage(String scanId, String pageId) async {
    final file = await _page(scanId, pageId);
    if (await file.exists()) await file.delete();
  }
}
