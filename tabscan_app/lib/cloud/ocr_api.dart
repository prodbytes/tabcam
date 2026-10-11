import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Whether the signed-in user has TabScan Premium, as the cloud OCR service
/// says (it asks rbacr), and where to get it.
class PremiumStatus {
  const PremiumStatus({
    required this.premium,
    this.expiresAt,
    this.checked = true,
    this.upgradeUrl,
    this.voucherUrl,
  });

  final bool premium;

  /// When the current grant ends (the paid period); null: no end, or free.
  final DateTime? expiresAt;

  /// False when the service couldn't reach rbacr: not premium for now.
  final bool checked;
  final Uri? upgradeUrl;
  final Uri? voucherUrl;

  factory PremiumStatus.fromJson(Map<String, Object?> json) {
    Uri? url(String key) => switch (json[key]) {
      final String s when s.startsWith('https://') => Uri.parse(s),
      _ => null,
    };
    return PremiumStatus(
      premium: json['premium'] == true,
      expiresAt: switch (json['expiresAt']) {
        final String t => DateTime.tryParse(t)?.toLocal(),
        _ => null,
      },
      checked: json['checked'] != false,
      upgradeUrl: url('upgradeUrl'),
      voucherUrl: url('voucherUrl'),
    );
  }
}

/// One correction auto-correct proposes, to one note of the text tab:
/// [old] at [line], [column] (0-based) becomes [replacement]. An empty
/// [old] adds a note on dashes; an empty [replacement] removes one.
class TabCorrection {
  const TabCorrection({
    required this.id,
    required this.line,
    required this.column,
    required this.old,
    required this.replacement,
    this.reason = '',
  });

  final String id;
  final int line;
  final int column;
  final String old;
  final String replacement;
  final String reason;

  static TabCorrection? fromJson(Object? json) {
    if (json is! Map) return null;
    final (id, line, column, old, replacement) = (
      json['id'],
      json['line'],
      json['column'],
      json['old'],
      json['new'],
    );
    if (id is! String ||
        line is! int ||
        column is! int ||
        old is! String ||
        replacement is! String ||
        line < 0 ||
        column < 0) {
      return null;
    }
    return TabCorrection(
      id: id,
      line: line,
      column: column,
      old: old,
      replacement: replacement,
      reason: json['reason'] as String? ?? '',
    );
  }
}

/// What auto-correct found: the song's tab online, and the corrections.
class AutocorrectResult {
  const AutocorrectResult({
    required this.found,
    this.title = '',
    this.artist = '',
    this.summary = '',
    this.sources = const [],
    this.corrections = const [],
  });

  final bool found;
  final String title;
  final String artist;
  final String summary;
  final List<Uri> sources;
  final List<TabCorrection> corrections;

  factory AutocorrectResult.fromJson(Map<String, Object?> json) {
    String text(String key) => json[key] as String? ?? '';
    return AutocorrectResult(
      found: json['found'] == true,
      title: text('title'),
      artist: text('artist'),
      summary: text('summary'),
      sources: [
        for (final s in json['sources'] as List? ?? const [])
          if (s is String && s.startsWith('https://')) Uri.parse(s),
      ],
      corrections: [
        for (final c in json['corrections'] as List? ?? const [])
          ?TabCorrection.fromJson(c),
      ],
    );
  }
}

class OcrApiException implements Exception {
  OcrApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get needsSignIn => statusCode == 401;
  bool get needsPremium => statusCode == 402;

  /// The service doesn't take this provider's tokens (Apple's, before it's
  /// set up for them): Premium needs Google sign-in.
  bool get needsGoogle =>
      statusCode == 403 && message == 'google sign-in needed';

  @override
  String toString() => 'Cloud OCR HTTP $statusCode: $message';
}

/// The cloud OCR service's requests (tabscan_locr), each with the user's
/// ID token (Google's or Apple's): [HttpOcrApi], or a fake in tests.
abstract interface class OcrApi {
  /// Records who this is for the service, and says whether they're premium.
  Future<PremiumStatus> account(String idToken);

  /// Transcribes [eventId]'s synced pages that have no transcription yet;
  /// how many were queued.
  Future<int> transcribe(String idToken, String eventId);

  /// Checks [text], [eventId]'s text tab, against [song]'s tab found
  /// online; the corrections, per note. Premium only.
  Future<AutocorrectResult> autocorrect(
    String idToken, {
    required String eventId,
    required String song,
    required String text,
  });
}

class HttpOcrApi implements OcrApi {
  HttpOcrApi(this.baseUrl, {http.Client? client})
    : _client = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _client;

  Future<Map<String, Object?>> _post(
    String path,
    String idToken, [
    Map<String, Object?>? body,
    Duration timeout = const Duration(seconds: 30),
  ]) async {
    final watch = Stopwatch()..start();
    final url = baseUrl.resolve(path);
    debugPrint(
      'TabScan: OCR API: POST $url '
      '${jsonEncode({...?body}..remove('text'))}',
    );
    final http.Response r;
    try {
      r = await _client
          .post(
            url,
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body ?? const {}),
          )
          .timeout(timeout);
    } on Object catch (e) {
      debugPrint(
        'TabScan: OCR API: POST $path failed after '
        '${watch.elapsedMilliseconds} ms: $e',
      );
      rethrow;
    }
    debugPrint(
      'TabScan: OCR API: POST $path -> ${r.statusCode} in '
      '${watch.elapsedMilliseconds} ms: ${r.body}',
    );
    Map<String, Object?> json;
    try {
      json = (jsonDecode(r.body) as Map).cast();
    } on Object {
      json = const {};
    }
    if (r.statusCode != 200) {
      throw OcrApiException(
        r.statusCode,
        json['error'] as String? ?? r.reasonPhrase ?? '',
      );
    }
    return json;
  }

  @override
  Future<PremiumStatus> account(String idToken) async =>
      PremiumStatus.fromJson(await _post('/account', idToken));

  @override
  Future<int> transcribe(String idToken, String eventId) async =>
      (await _post('/transcribe', idToken, {'eventId': eventId}))['queued']
          as int? ??
      0;

  @override
  Future<AutocorrectResult> autocorrect(
    String idToken, {
    required String eventId,
    required String song,
    required String text,
  }) async => AutocorrectResult.fromJson(
    await _post(
      '/autocorrect',
      idToken,
      {'eventId': eventId, 'song': song, 'text': text},
      // Claude searches the web: the service gives it up to 270 s.
      const Duration(minutes: 5),
    ),
  );
}
