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
    if (CaptureLink.idIn(link) == null) return false;
    _pending = link;
    notifyListeners();
    return true;
  }
}
