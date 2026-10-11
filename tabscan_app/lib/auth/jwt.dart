import 'dart:convert';

/// The claims of a JWT, read without checking its signature, or null if it
/// isn't one. Only for the app's own decisions (when a token expires, which
/// provider issued it): the services that take the token verify it.
Map<String, Object?>? jwtClaims(String jwt) {
  final parts = jwt.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final claims = jsonDecode(payload);
    return claims is Map ? claims.cast<String, Object?>() : null;
  } catch (_) {
    return null;
  }
}

/// A claim that is true: Apple sends some booleans as strings ("true").
bool claimIsTrue(Object? value) =>
    value == true || (value is String && value.toLowerCase() == 'true');
