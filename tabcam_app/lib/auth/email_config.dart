/// Sign in with email, set at build time like the Google client IDs
/// (`.env`, through `scripts/dart-defines.sh`): the tabcam-email user pool
/// and its app client (public identifiers). Empty: no email sign-in.
abstract final class EmailConfig {
  /// `TABCAM_EMAIL_USER_POOL_ID`, e.g. us-east-1_KwBmbR5yh.
  static const String userPoolId = String.fromEnvironment(
    'TABCAM_EMAIL_USER_POOL_ID',
  );

  /// `TABCAM_EMAIL_CLIENT_ID`: the pool's app client (the tokens' audience).
  static const String clientId = String.fromEnvironment(
    'TABCAM_EMAIL_CLIENT_ID',
  );

  static bool get enabled => userPoolId.isNotEmpty && clientId.isNotEmpty;

  /// The pool's region: its ID's prefix.
  static String get region => userPoolId.split('_').first;

  /// The ID tokens' issuer. Constant so [AuthProvider] can name it.
  static const String issuer =
      'https://cognito-idp.us-east-1.amazonaws.com/$userPoolId';

  /// The token's key in Cognito's Logins: the issuer without its scheme.
  static const String loginsKey =
      'cognito-idp.us-east-1.amazonaws.com/$userPoolId';
}
