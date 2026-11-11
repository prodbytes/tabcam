import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'place.dart';

/// The browser's address bar.
PlaceAddress? browserAddress() => const _BrowserAddress();

class _BrowserAddress implements PlaceAddress {
  const _BrowserAddress();

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
}
