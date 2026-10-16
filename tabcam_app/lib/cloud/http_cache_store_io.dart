import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'http_cache.dart';

/// Cached responses as files in the app's cache folder (which the system
/// may empty when space runs low): `<name>.body` and its headers,
/// `<name>.json`. Over [maxBytes], the least recently used go first.
class PlatformHttpCacheStore implements HttpCacheStore {
  PlatformHttpCacheStore({this.maxBytes = 512 * 1024 * 1024, this._dir});

  final int maxBytes;
  Directory? _dir;

  Future<Directory> _folder() async {
    final dir = _dir ??= Directory(
      '${(await getApplicationCacheDirectory()).path}/user-data',
    );
    await dir.create(recursive: true);
    return dir;
  }

  Future<(File, File)> _files(String key) async {
    final dir = await _folder();
    final name = cacheName(key);
    return (File('${dir.path}/$name.body'), File('${dir.path}/$name.json'));
  }

  @override
  Future<CachedResponse?> read(String key) async {
    final (body, meta) = await _files(key);
    if (!await body.exists() || !await meta.exists()) return null;
    final entry = CachedResponse.fromMeta(
      (jsonDecode(await meta.readAsString()) as Map).cast<String, Object?>(),
      await body.readAsBytes(),
    );
    // Most recently used: kept the longest.
    await body.setLastModified(DateTime.now());
    return entry;
  }

  @override
  Future<void> write(String key, CachedResponse entry) async {
    final (body, meta) = await _files(key);
    // The body first: a headers file without its body is a miss.
    await body.writeAsBytes(entry.body, flush: true);
    await meta.writeAsString(jsonEncode(entry.metaJson()), flush: true);
    await _trim();
  }

  Future<void> _trim() async {
    final dir = await _folder();
    final bodies = <(File, FileStat)>[];
    var total = 0;
    await for (final f in dir.list()) {
      if (f is File && f.path.endsWith('.body')) {
        final stat = await f.stat();
        bodies.add((f, stat));
        total += stat.size;
      }
    }
    if (total <= maxBytes) return;
    bodies.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final (file, stat) in bodies) {
      if (total <= maxBytes) break;
      total -= stat.size;
      await _delete(file);
      await _delete(File(file.path.replaceFirst(RegExp(r'\.body$'), '.json')));
    }
  }

  static Future<void> _delete(File f) async {
    try {
      await f.delete();
    } on FileSystemException {
      // Already gone.
    }
  }

  @override
  Future<void> remove(String key) async {
    final (body, meta) = await _files(key);
    await _delete(meta);
    await _delete(body);
  }

  @override
  Future<void> clear() async {
    final dir = await _folder();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
