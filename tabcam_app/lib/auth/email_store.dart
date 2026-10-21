/// Where sign in with email remembers its session (and a sign-in waiting
/// for its code): a file in the app's private folder on Android and iOS,
/// the browser's localStorage on the web.
library;

export 'email_store_io.dart'
    if (dart.library.js_interop) 'email_store_web.dart';
