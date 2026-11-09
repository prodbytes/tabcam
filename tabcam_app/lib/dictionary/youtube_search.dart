/// YouTube's search, from the device: what the dictionary's sidebar shows
/// for anything that's not a chord or a scale. The device asks the YouTube
/// Data API itself (`search.list`, with the build's public API key,
/// TABCAM_YOUTUBE_API_KEY); nothing goes through TabCam's servers.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A video YouTube found.
@immutable
class YouTubeVideo {
  const YouTubeVideo({
    required this.id,
    required this.title,
    required this.channel,
    this.thumbnail,
  });

  final String id;
  final String title;
  final String channel;
  final Uri? thumbnail;

  /// Its page on YouTube.
  Uri get url => Uri.https('www.youtube.com', '/watch', {'v': id});
}

/// YouTube's search failed (no network, the API's quota spent, a bad key).
class YouTubeSearchFailed implements Exception {
  const YouTubeSearchFailed(this.message);

  final String message;

  @override
  String toString() => 'YouTubeSearchFailed: $message';
}

/// Searches YouTube from the device, keeping the last searches' results
/// so the same search isn't asked twice (each costs the API's quota).
class YouTubeSearch {
  YouTubeSearch({required this.apiKey, http.Client? client}) : _given = client;

  static const _buildKey = String.fromEnvironment('TABCAM_YOUTUBE_API_KEY');

  /// The app's: the build's key; with none, there are no results to show,
  /// only the link to YouTube's search.
  static YouTubeSearch instance = YouTubeSearch(apiKey: _buildKey);

  /// How long the dictionary waits, once typing stops, before it searches.
  static const wait = Duration(seconds: 2);

  /// How many videos a search shows.
  static const count = 8;

  /// The most searches kept.
  static const _kept = 50;

  final String apiKey;
  final http.Client? _given;

  /// Made on the first search.
  late final http.Client _client = _given ?? http.Client();
  final _results = <String, List<YouTubeVideo>>{};

  /// Whether this build can search (it has a key).
  bool get available => apiKey.isNotEmpty;

  static String _keyOf(String query) =>
      query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// [query]'s results, if it was searched already.
  List<YouTubeVideo>? cached(String query) => _results[_keyOf(query)];

  /// The videos YouTube finds for [query]; throws [YouTubeSearchFailed].
  Future<List<YouTubeVideo>> search(String query) async {
    final key = _keyOf(query);
    final kept = _results[key];
    if (kept != null) return kept;
    final url = Uri.https('www.googleapis.com', '/youtube/v3/search', {
      'part': 'snippet',
      'type': 'video',
      'maxResults': '$count',
      'q': query.trim(),
      'fields':
          'items(id/videoId,snippet(title,channelTitle,thumbnails/medium/url))',
      'key': apiKey,
    });
    final http.Response response;
    try {
      response = await _client.get(url);
    } catch (e) {
      throw YouTubeSearchFailed('$e');
    }
    if (response.statusCode != 200) {
      throw YouTubeSearchFailed('HTTP ${response.statusCode}');
    }
    final List<YouTubeVideo> videos;
    try {
      videos = parse(jsonDecode(response.body));
    } on FormatException catch (e) {
      throw YouTubeSearchFailed('$e');
    }
    if (_results.length >= _kept) _results.remove(_results.keys.first);
    _results[key] = videos;
    return videos;
  }

  /// The videos in a `search.list` response.
  @visibleForTesting
  static List<YouTubeVideo> parse(Object? json) {
    if (json is! Map || json['items'] is! List) {
      throw const FormatException('no items');
    }
    return [
      for (final item in json['items'] as List)
        if (item is Map &&
            item['id'] is Map &&
            item['id']['videoId'] is String &&
            item['snippet'] is Map)
          YouTubeVideo(
            id: item['id']['videoId'] as String,
            title: unescape('${item['snippet']['title'] ?? ''}'),
            channel: unescape('${item['snippet']['channelTitle'] ?? ''}'),
            thumbnail: switch (item['snippet']['thumbnails']) {
              {'medium': {'url': final String url}} => Uri.tryParse(url),
              _ => null,
            },
          ),
    ];
  }

  /// [text] without the HTML entities the API writes in titles
  /// (`&amp;`, `&quot;`, `&#39;`).
  @visibleForTesting
  static String unescape(String text) => text.replaceAllMapped(
    RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);'),
    (m) {
      final name = m[1]!;
      if (name.startsWith('#')) {
        final code = name.startsWith('#x')
            ? int.tryParse(name.substring(2), radix: 16)
            : int.tryParse(name.substring(1));
        return code != null && code > 0 && code <= 0x10FFFF
            ? String.fromCharCode(code)
            : m[0]!;
      }
      return const {
        'amp': '&',
        'lt': '<',
        'gt': '>',
        'quot': '"',
        'apos': "'",
      }[name]!;
    },
  );
}
