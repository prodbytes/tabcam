import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'capture_link.dart';

/// Capture links the app is opened with: on the web, the page's own
/// address; on Android, an App Link (https://tabs.cam/s/… or
/// https://tabs.cam/app/…) that launched the app or reached it while
/// running. A short link is resolved to the full one first
/// ([CaptureLink.resolve]); on the web the site's redirect does that.
///
/// It's a binding observer added before runApp, so it sees a pushed link
/// before the app's Navigator, which would take it for a named route.
class IncomingLinks extends ChangeNotifier with WidgetsBindingObserver {
  IncomingLinks._();

  static final IncomingLinks instance = IncomingLinks._();

  Uri? _pending;

  /// Turns a short link into the full one (tests swap it).
  @visibleForTesting
  Future<Uri?> Function(Uri short) resolve = CaptureLink.resolve;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    final launch = kIsWeb
        ? Uri.base
        : Uri.tryParse(PlatformDispatcher.instance.defaultRouteName);
    if (launch == null) return;
    if (CaptureLink.idIn(launch) != null) _pending = launch;
    if (!kIsWeb && CaptureLink.isShort(launch)) unawaited(_resolve(launch));
    _signInCode = signInCodeIn(launch);
  }

  /// Keeps the full link [short] stands for waiting, once the site has
  /// said which it is; nothing when it can't (offline, an unknown link).
  Future<void> _resolve(Uri short) async {
    final link = await resolve(short);
    if (link == null) return;
    _pending = link;
    notifyListeners();
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
    if (CaptureLink.isShort(link)) {
      unawaited(_resolve(link));
      return true;
    }
    if (CaptureLink.idIn(link) == null) return false;
    _pending = link;
    notifyListeners();
    return true;
  }
}
