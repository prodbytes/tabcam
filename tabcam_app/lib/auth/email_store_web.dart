import 'package:web/web.dart' as web;

/// The browser's localStorage, under one key.
class EmailStore {
  const EmailStore();

  static const String _key = 'tabcam.email-session';

  Future<String?> load() async {
    try {
      return web.window.localStorage.getItem(_key);
    } catch (_) {
      return null; // storage disabled (some private modes)
    }
  }

  Future<void> save(String? data) async {
    try {
      if (data == null) {
        web.window.localStorage.removeItem(_key);
      } else {
        web.window.localStorage.setItem(_key, data);
      }
    } catch (_) {}
  }
}
