import 'package:flutter/foundation.dart';

import '../app_version.dart';
import '../library/capture_event.dart';

/// A capture's link, `https://tabscan.nu01.com/app/?c=<capture id>`: it
/// opens the capture in TabScan for whoever has it (its owner, and the
/// people it's shared with), found by its ID alone.
abstract final class CaptureLink {
  /// The web app the link opens: the site this web build runs on, else
  /// the stage's site.
  static Uri get app {
    if (kIsWeb) {
      final here = Uri.base;
      return Uri(
        scheme: here.scheme,
        host: here.host,
        port: here.port,
        path: '/app/',
      );
    }
    return Uri.https(
      AppVersion.stage == 'rc' ? 'rc.tabscan.nu01.com' : 'tabscan.nu01.com',
      '/app/',
    );
  }

  static Uri of(CaptureEvent event, {Uri? app}) =>
      (app ?? CaptureLink.app).replace(queryParameters: {'c': event.id});

  /// The capture ID in [link], or null when it holds none (or a bad one).
  static String? idIn(Uri link) {
    final id = link.queryParameters['c'];
    if (id == null) return null;
    try {
      return checkId(id);
    } on FormatException {
      return null;
    }
  }
}
