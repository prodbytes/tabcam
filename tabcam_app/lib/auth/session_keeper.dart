/// Where a TabCam session is kept on the device ([SessionAuthService]): a
/// file in the app's private folder on Android and iOS, the browser's
/// localStorage on the web.
library;

export 'session_keeper_io.dart'
    if (dart.library.js_interop) 'session_keeper_web.dart';
