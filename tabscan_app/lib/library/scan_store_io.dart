import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'scan.dart';
import 'scan_store.dart';

/// Scans kept as files, one folder per scan in the app's documents folder:
/// `scans/<scan id>/scan.json` and a `<page id>.<extension>` per page (the
/// image as scanned, or the video as picked).
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

  Future<File> _page(String scanId, ScanPage page) async => File(
    '${(await _dir(scanId)).path}/${checkId(page.id)}.'
    '${checkExtension(page.extension)}',
  );

  @override
  Future<void> putPage(String scanId, ScanPage page, Uint8List bytes) async {
    await (await _dir(scanId)).create();
    await (await _page(scanId, page)).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> putPageFile(String scanId, ScanPage page, XFile file) async {
    await (await _dir(scanId)).create();
    await file.saveTo((await _page(scanId, page)).path);
  }

  @override
  Future<Uint8List> page(String scanId, ScanPage page) async =>
      (await _page(scanId, page)).readAsBytes();

  @override
  Future<String?> pagePath(String scanId, ScanPage page) async =>
      (await _page(scanId, page)).path;

  @override
  Future<void> deletePage(String scanId, ScanPage page) async {
    final file = await _page(scanId, page);
    if (await file.exists()) await file.delete();
  }
}
