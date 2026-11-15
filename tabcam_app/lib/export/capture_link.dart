import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_version.dart';
import '../library/capture_event.dart';

/// A capture's link. With its key ([CaptureEvent.linkKey]) it's a short
/// link, `https://tabs.cam/s/<key>`: the site answers it with a redirect
/// to the full one, `https://tabs.cam/app/?c=<capture id>&k=<key>`, which
/// opens the capture for anyone holding it, read only, signed in or not.
/// Without a key yet it's the full one without it, `…/app/?c=<capture id>`,
/// which opens the capture for its owner and the people it's shared with,
/// found by its ID. A file's link adds `f=<file id>`: it opens the capture
/// with that file open.
abstract final class CaptureLink {
  /// The sites that answer short links (the share API's redirect behind
  /// their CloudFront): production's and the RC's.
  static const shortLinkHosts = {'tabs.cam', 'rc.tabs.cam'};

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
      AppVersion.stage == 'rc' ? 'rc.tabs.cam' : 'tabs.cam',
      '/app/',
    );
  }

  /// The link to copy: the short one when the capture has its key and the
  /// site answers short links (not a local build's), else the full one.
  static Uri of(CaptureEvent event, {EventPage? file, Uri? app}) {
    final site = app ?? CaptureLink.app;
    final key = event.linkKey;
    if (key == null || !shortLinkHosts.contains(site.host)) {
      return full(event, file: file, app: site);
    }
    return site.replace(
      path: '/s/$key',
      queryParameters: file == null ? null : {'f': file.id},
    );
  }

  /// The full link, what a short one redirects to.
  static Uri full(CaptureEvent event, {EventPage? file, Uri? app}) =>
      (app ?? CaptureLink.app).replace(
        queryParameters: {'c': event.id, 'k': ?event.linkKey, 'f': ?file?.id},
      );

  static final RegExp _short = RegExp(r'^/s/([A-Za-z0-9_-]{12,64})$');

  /// Whether [link] is a short one (`…/s/<key>`), to [resolve] before it
  /// opens anything.
  static bool isShort(Uri link) => _short.hasMatch(link.path);

  /// The full link a short one stands for, from the site's redirect (not
  /// followed), with [short]'s host, or the stage's site when it has none
  /// (Android hands the app a link's path alone); null when the site
  /// doesn't know it, or can't be reached. Only for the apps: in the
  /// browser the site's redirect brings the app the full link itself.
  static Future<Uri?> resolve(Uri short, {http.Client? client}) async {
    if (!isShort(short)) return null;
    final link = short.hasAuthority ? short : app.resolveUri(short);
    final http.Client c = client ?? http.Client();
    try {
      final request = http.Request('GET', link)..followRedirects = false;
      final response = await c
          .send(request)
          .timeout(const Duration(seconds: 15));
      await response.stream.drain<void>();
      final location = response.headers['location'];
      if (response.statusCode < 300 ||
          response.statusCode >= 400 ||
          location == null) {
        return null;
      }
      final target = link.resolve(location);
      return idIn(target) != null ? target : null;
    } on Object catch (e) {
      debugPrint('TabCam: the short link $link failed: $e');
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

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
