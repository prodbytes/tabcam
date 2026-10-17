import 'package:flutter/foundation.dart';

import '../app_version.dart';
import '../library/capture_event.dart';

/// A capture's link, `https://tabcam.nu01.com/app/?c=<capture id>&k=<key>`:
/// it opens the capture in TabCam for whoever has it (its owner, and the
/// people it's shared with), found by its ID; and, with its key
/// ([CaptureEvent.linkKey]), for anyone else too, read only, signed in or
/// not. A capture without a key yet has a link without one. A file's link
/// adds `&f=<file id>`: it opens the capture with that file open.
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
      AppVersion.stage == 'rc' ? 'rc.tabcam.nu01.com' : 'tabcam.nu01.com',
      '/app/',
    );
  }

  static Uri of(CaptureEvent event, {EventPage? file, Uri? app}) =>
      (app ?? CaptureLink.app).replace(
        queryParameters: {'c': event.id, 'k': ?event.linkKey, 'f': ?file?.id},
      );

  /// The file ID in [link], or null when it holds none (or a bad one).
  static String? fileIn(Uri link) {
    final id = link.queryParameters['f'];
    if (id == null) return null;
    try {
      return checkId(id);
    } on FormatException {
      return null;
    }
  }

  /// The key in [link], or null when it has none (or a bad one).
  static String? keyIn(Uri link) => switch (link.queryParameters['k']) {
    final String key when isLinkKey(key) => key,
    _ => null,
  };

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
