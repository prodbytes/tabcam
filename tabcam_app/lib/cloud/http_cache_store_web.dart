import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'http_cache.dart';

/// Cached responses in the browser's IndexedDB (`tabcam-http-cache`): the
/// headers in `meta` (with when each was last used), the bodies in `body`,
/// both by the key's [cacheName]. Over [maxBytes], the least recently used
/// go first. Without IndexedDB (a private window may refuse it), memory.
class PlatformHttpCacheStore implements HttpCacheStore {
  PlatformHttpCacheStore({this.maxBytes = 512 * 1024 * 1024});

  final int maxBytes;
  Future<web.IDBDatabase?>? _db;
  final _memory = MemoryHttpCacheStore();

  static const _name = 'tabcam-http-cache';
  static const _meta = 'meta';
  static const _body = 'body';

  Future<web.IDBDatabase?> _open() => _db ??= () async {
    try {
      final request = web.window.indexedDB.open(_name, 1);
      request.onupgradeneeded = ((web.Event _) {
        final db = request.result as web.IDBDatabase;
        if (!db.objectStoreNames.contains(_meta)) db.createObjectStore(_meta);
        if (!db.objectStoreNames.contains(_body)) db.createObjectStore(_body);
      }).toJS;
      return await _done(request) as web.IDBDatabase;
    } on Object {
      return null;
    }
  }();

  static Future<JSAny?> _done(web.IDBRequest request) {
    final done = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) => done.complete(request.result)).toJS;
    request.onerror = ((web.Event _) => done.completeError(
      StateError('IndexedDB: ${request.error?.message}'),
    )).toJS;
    return done.future;
  }

  static Future<void> _committed(web.IDBTransaction t) {
    final done = Completer<void>();
    t.oncomplete = ((web.Event _) => done.complete()).toJS;
    t.onerror = ((web.Event _) => done.completeError(
      StateError('IndexedDB: ${t.error?.message}'),
    )).toJS;
    t.onabort = ((web.Event _) => done.completeError(
      StateError('IndexedDB aborted'),
    )).toJS;
    return done.future;
  }

  @override
  Future<CachedResponse?> read(String key) async {
    final db = await _open();
    if (db == null) return _memory.read(key);
    final name = cacheName(key);
    final t = db.transaction([_meta.toJS, _body.toJS].toJS, 'readwrite');
    final metaStore = t.objectStore(_meta);
    final meta = await _done(metaStore.get(name.toJS));
    final body = await _done(t.objectStore(_body).get(name.toJS));
    if (meta == null || body == null) return null;
    final json = (jsonDecode((meta as JSString).toDart) as Map)
        .cast<String, Object?>();
    // Most recently used: kept the longest.
    metaStore.put(
      jsonEncode({...json, 'used': DateTime.now().millisecondsSinceEpoch}).toJS,
      name.toJS,
    );
    await _committed(t);
    return CachedResponse.fromMeta(json, (body as JSUint8Array).toDart);
  }

  @override
  Future<void> write(String key, CachedResponse entry) async {
    final db = await _open();
    if (db == null) return _memory.write(key, entry);
    final name = cacheName(key);
    final t = db.transaction([_meta.toJS, _body.toJS].toJS, 'readwrite');
    t.objectStore(_body).put(entry.body.toJS, name.toJS);
    t
        .objectStore(_meta)
        .put(
          jsonEncode({
            ...entry.metaJson(),
            'used': DateTime.now().millisecondsSinceEpoch,
          }).toJS,
          name.toJS,
        );
    await _committed(t);
    await _trim(db);
  }

  Future<void> _trim(web.IDBDatabase db) async {
    final t = db.transaction([_meta.toJS, _body.toJS].toJS, 'readwrite');
    final metaStore = t.objectStore(_meta);
    final keys =
        (await _done(metaStore.getAllKeys()) as JSArray<JSString>).toDart;
    final metas = (await _done(metaStore.getAll()) as JSArray<JSString>).toDart;
    final entries = <(String, int, int)>[];
    var total = 0;
    for (var i = 0; i < keys.length; i++) {
      final m = jsonDecode(metas[i].toDart) as Map;
      final size = (m['size'] as num?)?.toInt() ?? 0;
      entries.add((keys[i].toDart, size, (m['used'] as num?)?.toInt() ?? 0));
      total += size;
    }
    if (total > maxBytes) {
      entries.sort((a, b) => a.$3.compareTo(b.$3));
      for (final (name, size, _) in entries) {
        if (total <= maxBytes) break;
        total -= size;
        metaStore.delete(name.toJS);
        t.objectStore(_body).delete(name.toJS);
      }
    }
    await _committed(t);
  }

  @override
  Future<void> remove(String key) async {
    final db = await _open();
    if (db == null) return _memory.remove(key);
    final name = cacheName(key);
    final t = db.transaction([_meta.toJS, _body.toJS].toJS, 'readwrite');
    t.objectStore(_meta).delete(name.toJS);
    t.objectStore(_body).delete(name.toJS);
    await _committed(t);
  }

  @override
  Future<void> clear() async {
    await _memory.clear();
    final db = await _open();
    if (db == null) return;
    final t = db.transaction([_meta.toJS, _body.toJS].toJS, 'readwrite');
    t.objectStore(_meta).clear();
    t.objectStore(_body).clear();
    await _committed(t);
  }
}
