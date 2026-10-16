import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../l10n/language.dart';
import 'auth_service.dart';
import 'jwt.dart';
import 'saved_session.dart';

/// What Apple returns from a sign-in.
class AppleCredential {
  const AppleCredential({
    required this.userId,
    required this.identityToken,
    this.email,
    this.givenName,
    this.familyName,
  });

  /// Apple's stable user ID for this app (the token's `sub`).
  final String userId;
  final String identityToken;

  /// Only on the first sign-in to the app (Apple sends them once).
  final String? email;
  final String? givenName;
  final String? familyName;
}

/// Sign in with Apple itself: [PackageAppleSignIn], or a fake in tests.
abstract interface class AppleSignIn {
  Future<bool> isAvailable();

  /// Apple's sign-in sheet, asking for the name and email, with [nonce] put
  /// in the ID token. Null when the user cancels.
  Future<AppleCredential?> signIn({required String nonce});

  /// False once the user has stopped using Apple ID with the app (Settings
  /// → Apple ID → Sign in with Apple), or it was never set up.
  Future<bool> stillAuthorized(String userId);
}

/// [AppleSignIn] with the `sign_in_with_apple` package
/// (AuthenticationServices on iOS).
class PackageAppleSignIn implements AppleSignIn {
  const PackageAppleSignIn();

  @override
  Future<bool> isAvailable() => SignInWithApple.isAvailable();

  @override
  Future<AppleCredential?> signIn({required String nonce}) async {
    final AuthorizationCredentialAppleID c;
    try {
      c = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }
    final userId = c.userIdentifier;
    final token = c.identityToken;
    if (userId == null || token == null) {
      throw StateError('Apple returned no identity token');
    }
    return AppleCredential(
      userId: userId,
      identityToken: token,
      email: c.email,
      givenName: c.givenName,
      familyName: c.familyName,
    );
  }

  @override
  Future<bool> stillAuthorized(String userId) async =>
      await SignInWithApple.getCredentialState(userId) ==
      CredentialState.authorized;
}

/// Where the Apple session is kept: [FileAppleStore], or memory in tests.
abstract interface class AppleStore {
  Future<String?> load();
  Future<void> save(String data);
}

/// A file in the app's private Application Support folder (never shared,
/// not in the Files app). Apple's SDK keeps no session, as Google's does.
class FileAppleStore implements AppleStore {
  const FileAppleStore();

  Future<File> get _file async => File(
    '${(await getApplicationSupportDirectory()).path}/apple_sign_in.json',
  );

  @override
  Future<String?> load() async {
    try {
      final f = await _file;
      return await f.exists() ? await f.readAsString() : null;
    } catch (e) {
      debugPrint('TabCam: reading the Apple session failed: $e');
      return null;
    }
  }

  @override
  Future<void> save(String data) async {
    try {
      final f = await _file;
      await f.parent.create(recursive: true);
      await f.writeAsString(data, flush: true);
    } catch (e) {
      debugPrint('TabCam: saving the Apple session failed: $e');
    }
  }
}

/// Sign in with Apple (iOS), the privacy-focused sign-in the App Store asks
/// for beside Google's (guideline 4.8).
///
/// - Apple's sheet asks for the name and email. It sends them only the
///   first time the user signs in to the app, so they're kept (by Apple's
///   user ID) for the next sign-ins; the email is in each ID token anyway.
///   The user may hide their email: then it's an address at
///   `privaterelay.appleid.com` ([AuthUser.privateEmail]).
/// - Each sign-in sends the SHA-256 of a fresh random nonce, and the ID
///   token must carry it back (and be Apple's, for that user), so a token
///   from elsewhere isn't taken.
/// - Apple keeps no session and can't refresh the ID token without a server
///   of TabCam's own, so the session (user and token) is kept in
///   [AppleStore] and lasts until the token expires; then the user is
///   signed out, and asked to sign in again. At launch, a user who stopped
///   using Apple ID with the app is signed out.
class AppleAuthService extends AuthService {
  AppleAuthService({
    this._apple = const PackageAppleSignIn(),
    this._store = const FileAppleStore(),
    DateTime Function()? now,
    Random? random,
  }) : _now = now ?? DateTime.now,
       _random = random ?? Random.secure();

  final AppleSignIn _apple;
  final AppleStore _store;
  final DateTime Function() _now;
  final Random _random;

  AuthUser? _user;
  String? _idToken;
  bool _checking = true;
  String? _error;
  String? _unavailable;
  Timer? _expiry;

  /// What Apple sent once, by Apple user ID: `{name, email}`.
  Map<String, Object?> _profiles = {};

  @override
  AuthUser? get user => _user;

  @override
  String? get idToken => _idToken;

  @override
  List<AuthProvider> get providers => const [AuthProvider.apple];

  @override
  bool get checking => _checking;

  @override
  bool get available => _unavailable == null;

  @override
  String? get unavailableReason => _unavailable;

  @override
  String? get error => _error;

  @override
  Future<void> init() async {
    final data = _decode(await _store.load());
    final profiles = data['profiles'];
    _profiles = profiles is Map ? profiles.cast<String, Object?>() : {};
    final session = data['session'];
    final saved = session is String
        ? SavedSession.decode(session, now: _now())
        : null;
    if (saved != null && saved.user.provider == AuthProvider.apple) {
      _user = saved.user;
      _idToken = saved.idToken;
      _scheduleExpiry(saved.idToken);
      notifyListeners();
    }
    try {
      if (!await _apple.isAvailable()) {
        _unavailable = appL10n.accountAppleUnavailable;
      } else if (_user case final user?
          when !await _apple.stillAuthorized(user.id)) {
        // Stopped using Apple ID with TabCam, in Settings.
        await _forget();
      }
    } catch (e) {
      // Can't tell: keep a restored session, which expires by itself.
      debugPrint('TabCam: Sign in with Apple check failed: $e');
    }
    _checking = false;
    notifyListeners();
  }

  @override
  Future<void> signIn([AuthProvider provider = AuthProvider.apple]) async {
    _error = null;
    notifyListeners();
    final raw = base64UrlEncode(
      List<int>.generate(32, (_) => _random.nextInt(256)),
    );
    final nonce = sha256.convert(utf8.encode(raw)).toString();
    try {
      final c = await _apple.signIn(nonce: nonce);
      if (c == null) return; // Canceled.
      final claims = jwtClaims(c.identityToken);
      if (claims == null ||
          claims['iss'] != AuthProvider.apple.issuer ||
          claims['sub'] != c.userId ||
          claims['nonce'] != nonce) {
        throw StateError("Apple's sign-in reply doesn't match the request");
      }
      final profile = _profiles[c.userId];
      final known = profile is Map ? profile.cast<String, Object?>() : {};
      final name = [
        c.givenName,
        c.familyName,
      ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
      final email =
          _nonEmpty(c.email) ??
          _nonEmpty(claims['email']) ??
          _nonEmpty(known['email']);
      if (email == null) {
        throw StateError(
          "Apple didn't share an email address, which TabCam needs",
        );
      }
      final user = AuthUser(
        id: c.userId,
        email: email.toLowerCase(),
        name: name.isNotEmpty ? name : _nonEmpty(known['name']),
        provider: AuthProvider.apple,
        privateEmail:
            claimIsTrue(claims['is_private_email']) ||
            email.toLowerCase().endsWith('@privaterelay.appleid.com'),
      );
      _profiles[c.userId] = {'name': user.name, 'email': user.email};
      _user = user;
      _idToken = c.identityToken;
      _scheduleExpiry(c.identityToken);
      await _save();
    } catch (e) {
      debugPrint('TabCam: Sign in with Apple failed: $e');
      _error = switch (e) {
        SignInWithAppleAuthorizationException(:final message)
            when message.isNotEmpty =>
          message,
        StateError(:final message) => message,
        _ => appL10n.accountAppleSignInFailed,
      };
    }
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    // Apple has no sign-out: forgetting the session is all there is. The
    // name and email Apple sent once are kept, for the next sign-in.
    await _forget();
    notifyListeners();
  }

  /// Signs out when [token] expires: Apple can't renew it quietly.
  void _scheduleExpiry(String token) {
    _expiry?.cancel();
    final expiry = SavedSession.tokenExpiry(token);
    if (expiry == null) return;
    final left = expiry.difference(_now());
    _expiry = Timer(left.isNegative ? Duration.zero : left, () async {
      if (_idToken != token) return;
      await _forget();
      _error = appL10n.accountAppleSignInExpired;
      notifyListeners();
    });
  }

  Future<void> _forget() async {
    _expiry?.cancel();
    _user = null;
    _idToken = null;
    await _save();
  }

  Future<void> _save() {
    final user = _user;
    final token = _idToken;
    return _store.save(
      jsonEncode({
        'profiles': _profiles,
        if (user != null && token != null)
          'session': SavedSession(user: user, idToken: token).encode(),
      }),
    );
  }

  static Map<String, Object?> _decode(String? data) {
    if (data == null) return {};
    try {
      final m = jsonDecode(data);
      return m is Map ? m.cast<String, Object?>() : {};
    } catch (_) {
      return {};
    }
  }

  static String? _nonEmpty(Object? s) =>
      s is String && s.trim().isNotEmpty ? s.trim() : null;

  /// Apple's button, drawn by the app (`SignInWithAppleButton`).
  @override
  Widget? buildSignInButton([AuthProvider provider = AuthProvider.apple]) =>
      null;

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }
}
