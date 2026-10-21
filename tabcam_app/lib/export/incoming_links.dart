import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'capture_link.dart';

/// Capture links the app is opened with: on the web, the page's own
/// address; on Android, an App Link (https://tabcam.nu01.com/app/…) that
/// launched the app or reached it while running.
///
/// It's a binding observer added before runApp, so it sees a pushed link
/// before the app's Navigator, which would take it for a named route.
class IncomingLinks extends ChangeNotifier with WidgetsBindingObserver {
  IncomingLinks._();

  static final IncomingLinks instance = IncomingLinks._();

  Uri? _pending;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    final launch = kIsWeb
        ? Uri.base
        : Uri.tryParse(PlatformDispatcher.instance.defaultRouteName);
    if (launch != null && CaptureLink.idIn(launch) != null) _pending = launch;
    if (launch != null) _signInCode = signInCodeIn(launch);
  }

  String? _signInCode;

  /// A sign-in email's code (its link, `…/app/?signin-code=<code>`), if the
  /// app was opened with one; it's then no longer waiting.
  String? takeSignInCode() {
    final code = _signInCode;
    _signInCode = null;
    return code;
  }

  /// The code in a sign-in email's link, or null.
  static String? signInCodeIn(Uri link) {
    final code = link.queryParameters['signin-code'];
    return code != null && RegExp(r'^\d{6,8}$').hasMatch(code) ? code : null;
  }

  /// The link waiting to be opened, if any, left waiting.
  Uri? get pending => _pending;

  /// The link waiting to be opened, if any; it's then no longer waiting.
  Uri? take() {
    final link = _pending;
    _pending = null;
    return link;
  }

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final link = routeInformation.uri;
    if (signInCodeIn(link) case final code?) {
      _signInCode = code;
      notifyListeners();
      return true;
    }
    if (CaptureLink.idIn(link) == null) return false;
    _pending = link;
    notifyListeners();
    return true;
  }
}
