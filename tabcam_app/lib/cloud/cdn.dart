import 'package:flutter/foundation.dart';

/// Leave to GET one folder of the user-data bucket through the site's
/// CloudFront distribution: a signed policy for every key under [prefix]
/// until [expiration], one query string per site ([hosts]). The share API
/// hands one out with each set of folder credentials
/// (tabcam_api/shares/cdn.py).
class CdnGrant {
  const CdnGrant({
    required this.prefix,
    required this.expiration,
    required this.hosts,
  });

  /// `{prefix, expiration (epoch seconds), hosts: {host: query}}`; null for
  /// anything else (an API without a signer sends none).
  static CdnGrant? fromJson(Object? json) {
    if (json is! Map) return null;
    final prefix = json['prefix'];
    final expiration = json['expiration'];
    final hosts = json['hosts'];
    if (prefix is! String || !prefix.endsWith('/')) return null;
    if (expiration is! num || hosts is! Map) return null;
    return CdnGrant(
      prefix: prefix,
      expiration: DateTime.fromMillisecondsSinceEpoch(
        expiration.toInt() * 1000,
        isUtc: true,
      ),
      hosts: {
        for (final e in hosts.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      },
    );
  }

  final String prefix;
  final DateTime expiration;
  final Map<String, String> hosts;

  /// The signed URL of [key] on [site], if this grant covers it there and
  /// has more than [margin] left at [now]; otherwise null (read S3).
  Uri? urlOf(
    String key,
    Uri site,
    DateTime now, {
    Duration margin = const Duration(minutes: 1),
  }) {
    final query = hosts[site.host];
    if (query == null || !key.startsWith(prefix)) return null;
    if (!now.add(margin).isBefore(expiration)) return null;
    // The key as it is: the policy's resource and the site's path pattern
    // (`/us-east-1:*`) match it unencoded, so a key that would need
    // encoding is read from S3 instead. Then the policy, as signed (already
    // URL-safe).
    if (!_plainKey.hasMatch(key)) return null;
    return Uri.parse('${site.origin}/$key?$query');
  }

  static final _plainKey = RegExp(r'^[A-Za-z0-9:._-]+(/[A-Za-z0-9:._-]+)*$');
}

/// Where this build reads users' folders through CloudFront.
abstract final class CdnConfig {
  /// `TABCAM_CDN_URL`: the site the Android and iOS apps read from.
  static const String _url = String.fromEnvironment('TABCAM_CDN_URL');

  /// The site to read from: the web app's own (same origin, so no CORS),
  /// when it runs on one of TabCam's sites; the configured one elsewhere;
  /// null to read S3 directly (local builds, or none set).
  static Uri? get site {
    if (kIsWeb) {
      final here = Uri.base;
      final ours =
          here.scheme == 'https' &&
          (here.host == 'tabcam.nu01.com' || here.host == 'rc.tabcam.nu01.com');
      return ours ? Uri.parse(here.origin) : null;
    }
    return _url.isEmpty ? null : Uri.parse(_url);
  }
}
