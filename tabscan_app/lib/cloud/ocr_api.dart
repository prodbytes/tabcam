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

class OcrApiException implements Exception {
  OcrApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get needsSignIn => statusCode == 401;

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
  ]) async {
    final watch = Stopwatch()..start();
    final url = baseUrl.resolve(path);
    debugPrint('TabScan: OCR API: POST $url ${jsonEncode(body ?? const {})}');
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
          .timeout(const Duration(seconds: 30));
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
}
