import 'package:web/web.dart' as web;

import 'meta_storage.dart';

MetaStorage? browserMetaStorage() => const _LocalStorage();

/// The browser's localStorage, reached at each call: merely reading
/// `window.localStorage` throws where storage is blocked.
class _LocalStorage implements MetaStorage {
  const _LocalStorage();

  @override
  String? getItem(String key) => web.window.localStorage.getItem(key);

  @override
  void setItem(String key, String value) =>
      web.window.localStorage.setItem(key, value);
}
