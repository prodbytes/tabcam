/// tabs.cam's own search: the public captures (those their owners made
/// Public in Share) whose title or artist has every word typed, which the
/// dictionary's sidebar shows over YouTube's videos for anything that's
/// not a chord or a scale. Asked of the share API (`GET /public?q=`, no
/// sign-in), the one search of the dictionary's that goes to tabs.cam's
/// servers: nobody else knows which captures are public.
library;

import 'package:flutter/foundation.dart';

import '../cloud/share_api.dart';
import '../cloud/share_config.dart';

/// tabs.cam's search failed (no network, the API down).
class PublicSearchFailed implements Exception {
  const PublicSearchFailed(this.message);

  final String message;

  @override
  String toString() => 'PublicSearchFailed: $message';
}

/// Searches the public captures, keeping the last searches' results so
/// the same search isn't asked twice.
class PublicSearch {
  PublicSearch({this.api});

  /// The app's: none in a build without the share API.
  static PublicSearch instance = PublicSearch(
    api: ShareConfig.apiUrl.isEmpty
        ? null
        : ShareApi(baseUrl: Uri.parse(ShareConfig.apiUrl)),
  );

  final ShareApi? api;

  /// Whether it searches at all (a build with the share API).
  bool get available => api != null;

  /// How many captures a search shows.
  static const count = 5;

  /// The most searches kept.
  static const _kept = 50;

  final _results = <String, List<PublicCapture>>{};

  @visibleForTesting
  static String keyOf(String query) =>
      query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Whether [query] is long enough to search (the API answers nothing
  /// for less than two letters or digits).
  static bool searches(String query) =>
      query.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '').length >= 2;

  /// [query]'s results, if it was searched already.
  List<PublicCapture>? cached(String query) => _results[keyOf(query)];

  /// The public captures tabs.cam finds for [query], [count] at most;
  /// throws [PublicSearchFailed].
  Future<List<PublicCapture>> search(String query) async {
    final key = keyOf(query);
    final kept = _results[key];
    if (kept != null) return kept;
    final api = this.api;
    if (api == null) throw const PublicSearchFailed('no share API');
    final List<PublicCapture> found;
    try {
      found = (await api.searchPublic(query)).take(count).toList();
    } on Object catch (e) {
      throw PublicSearchFailed('$e');
    }
    if (_results.length >= _kept) _results.remove(_results.keys.first);
    _results[key] = found;
    return found;
  }
}
