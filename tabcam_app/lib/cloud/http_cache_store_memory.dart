import 'http_cache.dart';

/// Platforms with neither files nor IndexedDB keep cached responses in
/// memory.
class PlatformHttpCacheStore extends MemoryHttpCacheStore {}
