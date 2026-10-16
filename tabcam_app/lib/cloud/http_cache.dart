import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'http_cache_store_memory.dart'
    if (dart.library.io) 'http_cache_store_io.dart'
    if (dart.library.js_interop) 'http_cache_store_web.dart'
    as platform;

/// The parts of a response's `Cache-Control` a private cache acts on.
class CacheControl {
  const CacheControl({
    this.noStore = false,
    this.noCache = false,
    this.maxAge,
    this.immutable = false,
  });

  factory CacheControl.parse(String? header) {
    var noStore = false, noCache = false, immutable = false;
    Duration? maxAge;
    for (final part in (header ?? '').toLowerCase().split(',')) {
      final directive = part.trim();
      if (directive == 'no-store') noStore = true;
      if (directive == 'no-cache') noCache = true;
      if (directive == 'immutable') immutable = true;
      if (directive.startsWith('max-age=')) {
        final seconds = int.tryParse(
          directive.substring(8).replaceAll('"', ''),
        );
        if (seconds != null && seconds >= 0) {
          maxAge = Duration(seconds: seconds);
        }
      }
    }
    return CacheControl(
      noStore: noStore,
      noCache: noCache,
      maxAge: maxAge,
      immutable: immutable,
    );
  }

  /// Never kept (`no-store`).
  final bool noStore;

  /// Kept, but checked with the server every time (`no-cache`).
  final bool noCache;

  /// How long a copy is fresh (`max-age`); null: not at all, revalidated.
  final Duration? maxAge;
  final bool immutable;

  /// How long a stored copy may be used without asking: none for
  /// `no-cache`, or without a `max-age` (no heuristic freshness: these are
  /// a user's own files, and a stale one would hide another device's edit).
  Duration get freshFor => noCache ? Duration.zero : (maxAge ?? Duration.zero);
}

/// A stored response: its body and the headers that say how to reuse it.
class CachedResponse {
  const CachedResponse({
    required this.body,
    required this.storedAt,
    this.etag,
    this.lastModified,
    this.cacheControl,
    this.contentType,
    this.ageAtStore = Duration.zero,
  });

  final Uint8List body;

  /// When it was stored, or last revalidated.
  final DateTime storedAt;
  final String? etag;
  final String? lastModified;
  final String? cacheControl;
  final String? contentType;

  /// Its `Age` when it came (time spent in CloudFront's cache).
  final Duration ageAtStore;

  CacheControl get control => CacheControl.parse(cacheControl);

  Duration ageAt(DateTime now) => ageAtStore + now.difference(storedAt);

  bool isFreshAt(DateTime now) => ageAt(now) < control.freshFor;

  /// The headers, as stored beside the body.
  Map<String, Object?> metaJson() => {
    'storedAt': storedAt.toUtc().millisecondsSinceEpoch,
    'etag': etag,
    'lastModified': lastModified,
    'cacheControl': cacheControl,
    'contentType': contentType,
    'age': ageAtStore.inSeconds,
    'size': body.length,
  };

  static CachedResponse fromMeta(Map<String, Object?> meta, Uint8List body) =>
      CachedResponse(
        body: body,
        storedAt: DateTime.fromMillisecondsSinceEpoch(
          (meta['storedAt'] as num?)?.toInt() ?? 0,
          isUtc: true,
        ),
        etag: meta['etag'] as String?,
        lastModified: meta['lastModified'] as String?,
        cacheControl: meta['cacheControl'] as String?,
        contentType: meta['contentType'] as String?,
        ageAtStore: Duration(seconds: (meta['age'] as num?)?.toInt() ?? 0),
      );

  static CachedResponse fromHeaders(
    Map<String, String> headers,
    Uint8List body,
    DateTime now,
  ) => CachedResponse(
    body: body,
    storedAt: now,
    etag: headers['etag'],
    lastModified: headers['last-modified'],
    cacheControl: headers['cache-control'],
    contentType: headers['content-type'],
    ageAtStore: Duration(seconds: int.tryParse(headers['age'] ?? '') ?? 0),
  );

  /// This copy, revalidated by a 304 now: its body, the 304's headers.
  CachedResponse revalidated(Map<String, String> headers, DateTime now) =>
      CachedResponse(
        body: body,
        storedAt: now,
        etag: headers['etag'] ?? etag,
        lastModified: headers['last-modified'] ?? lastModified,
        cacheControl: headers['cache-control'] ?? cacheControl,
        contentType: contentType,
        ageAtStore: Duration(seconds: int.tryParse(headers['age'] ?? '') ?? 0),
      );
}

/// Where cached responses are kept: files in the app's cache folder on
/// Android and iOS, IndexedDB on the web, memory in tests.
abstract interface class HttpCacheStore {
  factory HttpCacheStore() = platform.PlatformHttpCacheStore;

  Future<CachedResponse?> read(String key);

  /// Stores [entry], making room under the store's limit if needed.
  Future<void> write(String key, CachedResponse entry);

  Future<void> remove(String key);

  /// Forgets everything (signing out, deleting the account).
  Future<void> clear();
}

/// A GET the cache couldn't answer: the server's status (the caller falls
/// back to another way, S3 directly).
class HttpCacheException implements Exception {
  HttpCacheException(this.statusCode, this.url);

  final int statusCode;
  final Uri url;

  @override
  String toString() => 'HTTP $statusCode from ${url.replace(query: '')}';
}

/// A private HTTP cache for users' files read through CloudFront, keyed by
/// the object's key (its signed URL's query changes every hour), following
/// the objects' own `Cache-Control` as CloudFront does: a fresh copy is
/// used without asking, a stale one revalidated with its `ETag` (a 304
/// keeps it), `no-store` never kept.
class HttpCache {
  HttpCache({
    HttpCacheStore? store,
    http.Client? client,
    DateTime Function()? now,
    this.maxEntryBytes = 64 * 1024 * 1024,
  }) : store = store ?? HttpCacheStore(),
       _client = client ?? http.Client(),
       _now = now ?? DateTime.now;

  final HttpCacheStore store;
  final http.Client _client;
  final DateTime Function() _now;

  /// Bodies larger than this aren't kept (long videos): streamed through.
  final int maxEntryBytes;

  Future<CachedResponse?> _stored(String key) async {
    try {
      return await store.read(key);
    } on Object {
      return null; // A broken entry is a miss.
    }
  }

  void _keep(String key, CachedResponse entry) {
    if (entry.control.noStore || entry.body.length > maxEntryBytes) return;
    unawaited(store.write(key, entry).catchError((Object _) {}));
  }

  Map<String, String> _conditions(CachedResponse? cached) => {
    if (cached?.etag != null) 'if-none-match': cached!.etag!,
    if (cached?.etag == null && cached?.lastModified != null)
      'if-modified-since': cached!.lastModified!,
  };

  /// [url]'s body, for the object [key]: the stored copy while it's
  /// fresh, otherwise the server's (a 304 keeps the stored one).
  Future<Uint8List> get(Uri url, String key) async {
    final cached = await _stored(key);
    final now = _now();
    if (cached != null && cached.isFreshAt(now)) return cached.body;
    final response = await _client.get(url, headers: _conditions(cached));
    if (response.statusCode == 304 && cached != null) {
      _keep(key, cached.revalidated(response.headers, _now()));
      return cached.body;
    }
    if (response.statusCode != 200) {
      throw HttpCacheException(response.statusCode, url);
    }
    _keep(
      key,
      CachedResponse.fromHeaders(response.headers, response.bodyBytes, _now()),
    );
    return response.bodyBytes;
  }

  /// [url]'s body as it arrives, for large files: the stored copy while
  /// it's fresh; otherwise the server's, kept as it passes when it's small
  /// enough.
  Future<Stream<List<int>>> getStream(Uri url, String key) async {
    final cached = await _stored(key);
    if (cached != null && cached.isFreshAt(_now())) {
      return Stream.value(cached.body);
    }
    final request = http.Request('GET', url)
      ..headers.addAll(_conditions(cached));
    final response = await _client.send(request);
    if (response.statusCode == 304 && cached != null) {
      await response.stream.drain<void>();
      _keep(key, cached.revalidated(response.headers, _now()));
      return Stream.value(cached.body);
    }
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw HttpCacheException(response.statusCode, url);
    }
    final length = response.contentLength;
    final keep =
        length != null &&
        length <= maxEntryBytes &&
        !CacheControl.parse(response.headers['cache-control']).noStore;
    if (!keep) return response.stream;
    final bytes = BytesBuilder(copy: false);
    return response.stream.transform(
      StreamTransformer.fromHandlers(
        handleData: (chunk, sink) {
          bytes.add(chunk);
          sink.add(chunk);
        },
        handleDone: (sink) {
          final body = bytes.takeBytes();
          if (body.length == length) {
            _keep(
              key,
              CachedResponse.fromHeaders(response.headers, body, _now()),
            );
          }
          sink.close();
        },
      ),
    );
  }

  Future<void> clear() => store.clear();
}

/// Cached responses in memory: the web without IndexedDB, and tests.
class MemoryHttpCacheStore implements HttpCacheStore {
  MemoryHttpCacheStore({this.maxBytes = 64 * 1024 * 1024});

  final int maxBytes;
  final _entries = <String, CachedResponse>{};

  Map<String, CachedResponse> get entries => Map.unmodifiable(_entries);

  @override
  Future<CachedResponse?> read(String key) async {
    final entry = _entries.remove(key);
    if (entry != null) _entries[key] = entry; // Most recently used last.
    return entry;
  }

  @override
  Future<void> write(String key, CachedResponse entry) async {
    _entries.remove(key);
    _entries[key] = entry;
    var total = _entries.values.fold<int>(0, (n, e) => n + e.body.length);
    while (total > maxBytes && _entries.length > 1) {
      final oldest = _entries.keys.first;
      total -= _entries.remove(oldest)!.body.length;
    }
  }

  @override
  Future<void> remove(String key) async => _entries.remove(key);

  @override
  Future<void> clear() async => _entries.clear();
}

/// The store's name for [key], safe in a file name or an IndexedDB key.
String cacheName(String key) => sha256.convert(utf8.encode(key)).toString();
