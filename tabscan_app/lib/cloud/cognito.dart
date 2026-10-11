import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_service.dart';
import 'sigv4.dart';

/// A Cognito identity (its ID is the user's folder in the bucket) with its
/// temporary AWS credentials.
class CognitoSession {
  const CognitoSession({required this.identityId, required this.credentials});

  final String identityId;
  final AwsCredentials credentials;
}

/// Why Cognito refused (for example, an expired ID token).
class CognitoException implements Exception {
  CognitoException(this.type, this.message);

  final String type;
  final String message;

  /// The ID token was rejected: signing in again gets a fresh one.
  bool get needsSignIn => type.endsWith('NotAuthorizedException');

  @override
  String toString() => 'Cognito $type: $message';
}

/// Credentials for a signed-in user's folder: [CognitoCredentials], or a
/// fake in tests.
abstract interface class CredentialSource {
  Future<CognitoSession> session(String idToken);

  /// Forgets the credentials (rejected, or signed out).
  void clear();
}

/// Exchanges an ID token (Google's, or Apple's) for temporary AWS
/// credentials through a Cognito identity pool (the enhanced flow: GetId,
/// then GetCredentialsForIdentity). Neither call is signed; the token is
/// the proof. It goes in `Logins` under its issuer's key
/// ([AuthProvider.loginsKey]): each provider is its own identity, so the
/// same person signed in with Google and with Apple has two folders.
class CognitoCredentials implements CredentialSource {
  CognitoCredentials({
    required this.region,
    required this.identityPoolId,
    http.Client? client,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now;

  final String region;
  final String identityPoolId;
  final http.Client _client;
  final DateTime Function() _now;

  CognitoSession? _session;
  String? _sessionToken;
  AuthProvider? _sessionProvider;

  /// A session for [idToken], reused until its credentials expire soon or
  /// the token changes.
  @override
  Future<CognitoSession> session(String idToken) async {
    final current = _session;
    if (current != null &&
        _sessionToken == idToken &&
        !current.credentials.expiresSoon(_now())) {
      return current;
    }
    final provider = AuthProvider.ofToken(idToken);
    final logins = {provider.loginsKey: idToken};
    // The identity ID is stable per user, provider and pool, so keep it
    // across tokens of the same provider.
    final identityId =
        current != null && _sessionToken != null && _sessionProvider == provider
        ? current.identityId
        : (await _call('GetId', {
                'IdentityPoolId': identityPoolId,
                'Logins': logins,
              }))['IdentityId']
              as String;
    final result = await _call('GetCredentialsForIdentity', {
      'IdentityId': identityId,
      'Logins': logins,
    });
    final c = (result['Credentials'] as Map).cast<String, Object?>();
    final expiration = c['Expiration'];
    final session = CognitoSession(
      identityId: result['IdentityId'] as String? ?? identityId,
      credentials: AwsCredentials(
        accessKeyId: c['AccessKeyId']! as String,
        secretAccessKey: c['SecretKey']! as String,
        sessionToken: c['SessionToken'] as String?,
        expiration: expiration is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (expiration * 1000).round(),
                isUtc: true,
              )
            : null,
      ),
    );
    _session = session;
    _sessionToken = idToken;
    _sessionProvider = provider;
    return session;
  }

  /// Forgets the session (on sign-out, or rejected credentials).
  @override
  void clear() {
    _session = null;
    _sessionToken = null;
    _sessionProvider = null;
  }

  Future<Map<String, Object?>> _call(
    String action,
    Map<String, Object?> body,
  ) async {
    final response = await _client.post(
      Uri.https('cognito-identity.$region.amazonaws.com', '/'),
      headers: {
        'content-type': 'application/x-amz-json-1.1',
        'x-amz-target': 'AWSCognitoIdentityService.$action',
      },
      body: jsonEncode(body),
    );
    final decoded = response.body.isEmpty
        ? <String, Object?>{}
        : (jsonDecode(response.body) as Map).cast<String, Object?>();
    if (response.statusCode != 200) {
      throw CognitoException(
        (decoded['__type'] as String?) ?? 'HTTP ${response.statusCode}',
        (decoded['message'] ?? decoded['Message'] ?? response.body).toString(),
      );
    }
    return decoded;
  }
}
