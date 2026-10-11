import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_service.dart';
import 'sigv4.dart';

/// What a person may do with a capture shared with them.
enum ShareRole {
  /// Change it, as its owner can (the default).
  edit,

  /// Only see it.
  read;

  static ShareRole byName(String? name) => name == 'read' ? read : edit;

  String get label => this == edit ? 'Can edit' : 'Read only';
}

/// One person a capture is shared with.
class Grant {
  const Grant(this.email, this.role);

  final String email;
  final ShareRole role;
}

/// A capture someone shared with the signed-in user.
class SharedCapture {
  const SharedCapture({
    required this.owner,
    required this.captureId,
    required this.ownerEmail,
    required this.role,
  });

  /// The owner's Cognito identity: the folder the capture is in.
  final String owner;
  final String captureId;
  final String ownerEmail;
  final ShareRole role;
}

/// Credentials for one shared capture's folder, and what they allow.
class ShareCredentials {
  const ShareCredentials(this.credentials, this.role);

  final AwsCredentials credentials;
  final ShareRole role;
}

/// Why the share API refused.
class ShareApiException implements Exception {
  ShareApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  /// Not shared with the user (any more).
  bool get notShared => statusCode == 404;

  @override
  String toString() => message;
}

/// The share API (tabscan_api/shares): grants of the user's own captures,
/// what's shared with them, and credentials for it. Every request carries
/// the user's ID token: Google's at the API's root, Apple's under `/apple`
/// (each path has its own authorizer, for its issuer).
class ShareApi {
  ShareApi({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _client;

  Future<List<Grant>> grants(String token, String captureId) async =>
      _grants(await _call(token, 'GET', ['shares', captureId]));

  /// Shares [captureId] with [email] as [role] (a new grant, or a changed
  /// one); the capture's grants after.
  Future<List<Grant>> grant(
    String token,
    String captureId,
    String email, {
    ShareRole role = ShareRole.edit,
  }) async => _grants(
    await _call(
      token,
      'PUT',
      ['shares', captureId],
      body: {'email': email, 'role': role.name},
    ),
  );

  Future<List<Grant>> revoke(
    String token,
    String captureId,
    String email,
  ) async => _grants(
    await _call(
      token,
      'DELETE',
      ['shares', captureId],
      query: {'email': email},
    ),
  );

  Future<List<SharedCapture>> shared(String token) async {
    final body = await _call(token, 'GET', ['shared']);
    return [
      for (final s in body['shared'] as List)
        SharedCapture(
          owner: (s as Map)['owner'] as String,
          captureId: s['captureId'] as String,
          ownerEmail: s['ownerEmail'] as String,
          role: ShareRole.byName(s['role'] as String?),
        ),
    ];
  }

  /// Stops [captureId] of [owner] being shared with the user.
  Future<void> leave(String token, String owner, String captureId) =>
      _call(token, 'DELETE', ['shared', owner, captureId]);

  Future<ShareCredentials> credentials(
    String token,
    String owner,
    String captureId,
  ) async {
    final c = await _call(token, 'POST', [
      'shared',
      owner,
      captureId,
      'credentials',
    ]);
    return ShareCredentials(
      AwsCredentials(
        accessKeyId: c['accessKeyId'] as String,
        secretAccessKey: c['secretAccessKey'] as String,
        sessionToken: c['sessionToken'] as String,
        expiration: DateTime.fromMillisecondsSinceEpoch(
          (c['expiration'] as num).toInt() * 1000,
          isUtc: true,
        ),
      ),
      ShareRole.byName(c['role'] as String?),
    );
  }

  static List<Grant> _grants(Map<String, Object?> body) => [
    for (final g in body['grants'] as List)
      Grant(
        (g as Map)['email'] as String,
        ShareRole.byName(g['role'] as String?),
      ),
  ];

  Future<Map<String, Object?>> _call(
    String token,
    String method,
    List<String> path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    final uri = baseUrl.replace(
      pathSegments: [
        ...baseUrl.pathSegments.where((s) => s.isNotEmpty),
        if (AuthProvider.ofToken(token) == AuthProvider.apple) 'apple',
        ...path,
      ],
      queryParameters: query,
    );
    final request = http.Request(method, uri)
      ..headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    Map<String, Object?> decoded;
    try {
      decoded = (jsonDecode(response.body) as Map).cast<String, Object?>();
    } on Object {
      decoded = {};
    }
    if (response.statusCode != 200) {
      throw ShareApiException(
        response.statusCode,
        decoded['message'] as String? ??
            (response.statusCode == 401
                ? 'Sign in again to share'
                : 'Sharing failed (HTTP ${response.statusCode})'),
      );
    }
    return decoded;
  }
}
