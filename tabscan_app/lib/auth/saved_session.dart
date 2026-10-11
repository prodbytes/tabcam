import 'dart:convert';

import 'auth_service.dart';
import 'jwt.dart';

/// A signed-in session as remembered across reloads: who, with which
/// provider, and their ID token. Only restored while the token is still
/// valid.
class SavedSession {
  const SavedSession({required this.user, required this.idToken});

  final AuthUser user;
  final String idToken;

  String encode() => jsonEncode({
    'id': user.id,
    'email': user.email,
    'name': user.name,
    'photoUrl': user.photoUrl,
    'provider': user.provider.name,
    if (user.privateEmail) 'privateEmail': true,
    'idToken': idToken,
  });

  /// The session in [json], or null if it's missing, malformed, or its token
  /// expires within [margin] of [now].
  static SavedSession? decode(
    String? json, {
    required DateTime now,
    Duration margin = const Duration(minutes: 1),
  }) {
    if (json == null) return null;
    try {
      final m = (jsonDecode(json) as Map).cast<String, Object?>();
      final token = m['idToken'];
      final id = m['id'];
      final email = m['email'];
      if (token is! String || id is! String || email is! String) return null;
      final expiry = tokenExpiry(token);
      if (expiry == null || !now.add(margin).isBefore(expiry)) return null;
      return SavedSession(
        user: AuthUser(
          id: id,
          email: email,
          name: m['name'] as String?,
          photoUrl: m['photoUrl'] as String?,
          // Sessions saved before Sign in with Apple are Google's.
          provider: AuthProvider.byName(m['provider'] as String?),
          privateEmail: m['privateEmail'] == true,
        ),
        idToken: token,
      );
    } catch (_) {
      return null;
    }
  }

  /// How long until [token] should be refreshed: [lead] before it expires,
  /// or now if that's past. Null if its expiry can't be read.
  static Duration? refreshIn(
    String token, {
    required DateTime now,
    Duration lead = const Duration(minutes: 5),
  }) {
    final expiry = tokenExpiry(token);
    if (expiry == null) return null;
    final left = expiry.subtract(lead).difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// When a JWT expires (its `exp` claim), or null if it can't be read. Only
  /// used to decide whether a saved session is still worth restoring:
  /// Cognito verifies the token itself.
  static DateTime? tokenExpiry(String jwt) {
    final exp = jwtClaims(jwt)?['exp'];
    return exp is num
        ? DateTime.fromMillisecondsSinceEpoch((exp * 1000).round(), isUtc: true)
        : null;
  }
}
