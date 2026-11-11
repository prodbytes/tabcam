import 'meta_storage_stub.dart'
    if (dart.library.js_interop) 'meta_storage_web.dart'
    as platform;

/// Where the web keeps the device's settings ([MetaNames.deviceSettings])
/// across reloads: the browser's localStorage. Either call may throw
/// (storage disabled, a private window, over quota).
abstract interface class MetaStorage {
  String? getItem(String key);

  void setItem(String key, String value);
}

/// The browser's localStorage on the web; null on Android, iOS and the
/// desktop, whose store keeps metas as files.
MetaStorage? browserMetaStorage() => platform.browserMetaStorage();
