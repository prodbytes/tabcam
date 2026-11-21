/// Cifra Club's search, from the device: the tabs the dictionary's sidebar
/// shows under YouTube's videos for anything that's not a chord or a
/// scale. The device asks Cifra Club's own search index (the site's Solr,
/// at `solr.sscdn.co`, which answers any origin, so the browser can ask it
/// too), with no key; nothing goes through tabs.cam's servers.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A song Cifra Club has a tab (or chords) of.
@immutable
class CifraClubSong {
  const CifraClubSong({
    required this.artistSlug,
    required this.songSlug,
    required this.title,
    required this.artist,
    this.image,
  });

  /// The artist's and the song's parts of its address.
  final String artistSlug;
  final String songSlug;
  final String title;
  final String artist;

  /// The artist's picture, small; null without one.
  final Uri? image;

  /// Its page on Cifra Club.
  Uri get url => Uri.https('www.cifraclub.com.br', '/$artistSlug/$songSlug/');

  /// Names it among results.
  String get id => '$artistSlug/$songSlug';
}

/// Cifra Club's search failed (no network, the index down).
class CifraClubSearchFailed implements Exception {
  const CifraClubSearchFailed(this.message);

  final String message;

  @override
  String toString() => 'CifraClubSearchFailed: $message';
}

/// Searches Cifra Club from the device, keeping the last searches' results
/// so the same search isn't asked twice.
class CifraClubSearch {
  CifraClubSearch({http.Client? client}) : _given = client;

  /// The app's.
  static CifraClubSearch instance = CifraClubSearch();

  /// How many songs a search shows.
  static const count = 3;

  /// How many the index is asked for: artists come among the songs, and
  /// only songs are shown.
  static const rows = 10;

  /// The most searches kept.
  static const _kept = 50;

  final http.Client? _given;

  /// Made on the first search.
  late final http.Client _client = _given ?? http.Client();
  final _results = <String, List<CifraClubSong>>{};

  static String _keyOf(String query) =>
      query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// [query]'s results, if it was searched already.
  List<CifraClubSong>? cached(String query) => _results[_keyOf(query)];

  /// The songs Cifra Club finds for [query], [count] at most; throws
  /// [CifraClubSearchFailed].
  Future<List<CifraClubSong>> search(String query) async {
    final key = _keyOf(query);
    final kept = _results[key];
    if (kept != null) return kept;
    final url = Uri.https('solr.sscdn.co', '/cc/h2/', {
      'q': query.trim(),
      'wt': 'json',
      'rows': '$rows',
    });
    final http.Response response;
    try {
      response = await _client.get(url);
    } catch (e) {
      throw CifraClubSearchFailed('$e');
    }
    if (response.statusCode != 200) {
      throw CifraClubSearchFailed('HTTP ${response.statusCode}');
    }
    final List<CifraClubSong> songs;
    try {
      songs = parse(jsonDecode(unwrap(response.body))).take(count).toList();
    } on FormatException catch (e) {
      throw CifraClubSearchFailed('$e');
    }
    if (_results.length >= _kept) _results.remove(_results.keys.first);
    _results[key] = songs;
    return songs;
  }

  /// [body] without the parentheses the index wraps its JSON in.
  @visibleForTesting
  static String unwrap(String body) {
    final text = body.trim();
    return text.startsWith('(') && text.endsWith(')')
        ? text.substring(1, text.length - 1)
        : text;
  }

  /// The songs in the index's answer: its `docs` of type 2 (songs; type 1
  /// is an artist), each with its artist's and its own address parts.
  @visibleForTesting
  static List<CifraClubSong> parse(Object? json) {
    final docs = switch (json) {
      {'response': {'docs': final List docs}} => docs,
      _ => throw const FormatException('no docs'),
    };
    return [
      for (final doc in docs)
        if (doc is Map &&
            '${doc['t']}' == '2' &&
            doc['d'] is String &&
            doc['u'] is String &&
            _slug.hasMatch(doc['d'] as String) &&
            _slug.hasMatch(doc['u'] as String))
          CifraClubSong(
            artistSlug: doc['d'] as String,
            songSlug: doc['u'] as String,
            title: '${doc['m'] ?? ''}'.trim(),
            artist: '${doc['a'] ?? ''}'.trim(),
            image: switch (doc['i']) {
              final String path when _picture.hasMatch(path) => Uri.https(
                'akamai.sscdn.co',
                '/letras/100x100/fotos/$path',
              ),
              _ => null,
            },
          ),
    ];
  }

  /// An address part as the site writes them.
  static final _slug = RegExp(r'^[a-z0-9][a-z0-9-]*$');

  /// A picture's path as the index writes it (`b/b/e/5/bbe5….jpg`).
  static final _picture = RegExp(
    r'^[a-z0-9]+(/[a-z0-9]+)*(-[a-z0-9]+)?\.jpe?g$',
  );
}
