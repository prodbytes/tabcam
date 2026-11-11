import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'place.dart';

/// The browser's address bar.
PlaceAddress? browserAddress() => _BrowserAddress();

class _BrowserAddress implements PlaceAddress {
  VoidCallback? _moved;
  bool _listening = false;

  @override
  Uri get current => Uri.parse(web.window.location.href);

  @override
  void replace(Uri address) {
    final href = address.toString();
    if (href == web.window.location.href) return;
    try {
      // Flutter's own history state (how it handles the back button) is
      // kept: only the address changes, and no entry is added.
      web.window.history.replaceState(web.window.history.state, '', href);
    } on Object catch (e) {
      debugPrint('TabCam: address not updated: $e');
    }
  }

  @override
  set onMoved(VoidCallback? moved) {
    _moved = moved;
    if (_listening) return;
    _listening = true;
    // Before or after Flutter's own listener, the entry it ends on gets
    // the place's address: Flutter puts its entry back at the address
    // shown, and the place is rewritten over the one it brought back.
    web.window.addEventListener(
      'popstate',
      ((web.Event _) => _moved?.call()).toJS,
    );
  }
}
