import 'package:flutter/widgets.dart';

import 'jwt.dart';

/// Who vouches for the user: the OpenID Connect provider whose ID token the
/// app holds, and the key Cognito (and the share API) know it by.
enum AuthProvider {
  /// Sign in with Google: every platform.
  google('Google', 'https://accounts.google.com', 'accounts.google.com'),

  /// Sign in with Apple: iOS, where the App Store asks for it next to
  /// Google (guideline 4.8).
  apple('Apple', 'https://appleid.apple.com', 'appleid.apple.com');

  const AuthProvider(this.label, this.issuer, this.loginsKey);

  /// "Google", "Apple".
  final String label;

  /// The ID tokens' `iss` claim.
  final String issuer;

  /// The key of the token in Cognito's `Logins`.
  final String loginsKey;

  /// The provider named [name] (as saved), Google for anything else.
  static AuthProvider byName(String? name) =>
      name == apple.name ? apple : google;

  /// Who issued [idToken] (its `iss` claim, unverified: only to pick where
  /// to send it, and the services check it). Google when it can't be read.
  static AuthProvider ofToken(String idToken) =>
      jwtClaims(idToken)?['iss'] == apple.issuer ? apple : google;
}

/// Who is signed in.
@immutable
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.name,
    this.photoUrl,
    this.provider = AuthProvider.google,
    this.privateEmail = false,
  });

  final String id;
  final String email;
  final String? name;
  final String? photoUrl;

  /// Who they signed in with.
  final AuthProvider provider;

  /// [email] is Apple's private relay address (Hide My Email), not the
  /// user's own.
  final bool privateEmail;

  /// A name to show: the display name, or else the email (or, for a private
  /// relay address, which means nothing to anyone, the provider).
  String get label => (name?.trim().isNotEmpty ?? false)
      ? name!
      : privateEmail
      ? '${provider.label} ID (private email)'
      : email;

  /// Who is signed in, for tooltips: "Ana · ana@example.com".
  String get identity => label == email ? email : '$label · $email';
}

/// Signing in and out. The app owns one; the account sheet and cloud sync
/// read it.
abstract class AuthService extends ChangeNotifier {
  /// The signed-in user, or null.
  AuthUser? get user;

  /// The signed-in user's OpenID Connect ID token (a JWT), exchanged with
  /// Cognito for AWS credentials by `CloudSync`. Null when signed out, or
  /// when the provider didn't return one.
  String? get idToken;

  /// The providers the user can sign in with here, in the order their
  /// buttons show.
  List<AuthProvider> get providers => const [AuthProvider.google];

  /// True while checking at launch whether a previous session can be
  /// restored silently.
  bool get checking;

  /// False when sign-in can't work here (e.g. no client ID configured);
  /// [unavailableReason] says why.
  bool get available;
  String? get unavailableReason;

  /// The last sign-in error, shown in the account sheet.
  String? get error;

  /// Sets up the provider and restores a previous session if possible.
  Future<void> init();

  /// Starts an interactive sign-in with [provider] (one of [providers]).
  /// Not used for Google on web, where Google's own button
  /// ([buildSignInButton]) signs in.
  Future<void> signIn([AuthProvider provider = AuthProvider.google]);

  Future<void> signOut();

  /// [provider]'s own sign-in button, where the platform requires one
  /// (Google on web); null to use the app's button, which calls [signIn].
  Widget? buildSignInButton([AuthProvider provider = AuthProvider.google]);
}
