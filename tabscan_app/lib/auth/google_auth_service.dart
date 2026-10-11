import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../l10n/language.dart';
import 'auth_service.dart';
import 'google_button.dart';
import 'google_config.dart';
import 'saved_session.dart';
import 'session_store.dart';

/// Sign in with Google (`google_sign_in`), as Presence does:
///
/// - **Web:** Google Identity Services with FedCM: a quiet, auto-select
///   prompt at launch, and Google's own rendered button. The session is
///   remembered across reloads ([SessionStore]), since GIS keeps none.
/// - **Android:** Credential Manager: a quiet check of the accounts that
///   signed in before, and the "Sign in with Google" sheet for the button.
/// - **iOS:** the Google Sign-In SDK, which restores the previous sign-in.
///
/// Every platform's ID token is issued for the web client (the server
/// client ID on Android and iOS), the one client the Cognito identity pool
/// trusts. Tokens last an hour; each is refreshed quietly five minutes
/// before it expires.
class GoogleAuthService extends AuthService {
  GoogleAuthService({
    this._store = const SessionStore(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SessionStore _store;
  final DateTime Function() _now;

  AuthUser? _user;
  String? _idToken;
  bool _checking = true;
  String? _error;
  String? _unavailable;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _events;
  Timer? _refresh;

  @override
  AuthUser? get user => _user;

  @override
  String? get idToken => _idToken;

  @override
  bool get checking => _checking;

  @override
  bool get available => _unavailable == null;

  @override
  String? get unavailableReason => _unavailable;

  @override
  String? get error => _error;

  /// The client ID this platform needs, and the server client ID (the web
  /// client). Android has no client ID of its own in the app: Google
  /// matches it by package name and signing-key fingerprint.
  static ({String? clientId, String? serverClientId}) get _ids {
    const web = GoogleConfig.webClientId;
    const ios = GoogleConfig.iosClientId;
    String? orNull(String s) => s.isEmpty ? null : s;
    if (kIsWeb) return (clientId: orNull(web), serverClientId: null);
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => (
        clientId: orNull(ios),
        serverClientId: orNull(web),
      ),
      _ => (clientId: null, serverClientId: orNull(web)),
    };
  }

  @override
  Future<void> init() async {
    // Signed in before this reload, with a token still valid: signed in
    // now, before Google's library has loaded.
    final saved = SavedSession.decode(_store.load(), now: _now());
    if (saved != null) {
      _user = saved.user;
      _idToken = saved.idToken;
      notifyListeners();
    } else {
      _store.clear();
    }
    final ids = _ids;
    if (ids.clientId == null && ids.serverClientId == null) {
      _unavailable = appL10n.accountSignInNotSetUp;
      _checking = false;
      notifyListeners();
      return;
    }
    try {
      final google = GoogleSignIn.instance;
      await google.initialize(
        clientId: ids.clientId,
        serverClientId: ids.serverClientId,
      );
      _events = google.authenticationEvents.listen(
        _onEvent,
        onError: (Object e) {
          // "Canceled" is the quiet check finding no session, or the user
          // closing Google's prompt: not an error worth showing.
          if (e is GoogleSignInException &&
              e.code == GoogleSignInExceptionCode.canceled) {
            return;
          }
          _fail(e);
        },
      );
    } catch (e) {
      debugPrint('TabScan: Google sign-in is unavailable: ${_details(e)}');
      _unavailable = appL10n.accountGoogleUnavailable(_describe(e));
      _checking = false;
      notifyListeners();
      return;
    }
    try {
      // A restored session is refreshed shortly before it expires, not
      // now; otherwise check quietly for one. On web this starts the FedCM
      // prompt and returns at once: a sign-in arrives as an event.
      if (_idToken case final token?) {
        _scheduleRefresh(token);
      } else {
        await GoogleSignIn.instance.attemptLightweightAuthentication();
      }
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled && _error == null) {
        _fail(e);
      }
    } catch (e) {
      if (_error == null) _fail(e);
    }
    _checking = false;
    notifyListeners();
  }

  void _onEvent(GoogleSignInAuthenticationEvent event) {
    _error = null;
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn(:final user):
        _user = AuthUser(
          id: user.id,
          email: user.email,
          name: user.displayName,
          photoUrl: user.photoUrl,
        );
        _idToken = user.authentication.idToken;
        _remember();
        if (_idToken case final token?) _scheduleRefresh(token);
      case GoogleSignInAuthenticationEventSignOut():
        _forget();
    }
    notifyListeners();
  }

  @override
  Future<void> signIn() async {
    _error = null;
    notifyListeners();
    try {
      await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) _fail(e);
    } catch (e) {
      _fail(e);
    }
  }

  @override
  Future<void> signOut() async {
    // Forgotten here too: a restored session may not be one the library
    // knows about, so it might not send a sign-out event.
    _forget();
    notifyListeners();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      debugPrint('TabScan: Google sign-out failed: $e');
    }
  }

  void _forget() {
    _refresh?.cancel();
    _user = null;
    _idToken = null;
    _store.clear();
  }

  /// Asks Google quietly for a new token five minutes before [token]
  /// expires. Finding none leaves the session as it is, until it expires
  /// and cloud sync asks to sign in again.
  void _scheduleRefresh(String token) {
    _refresh?.cancel();
    final delay = SavedSession.refreshIn(token, now: _now());
    if (delay == null) return;
    _refresh = Timer(delay, () {
      if (_user == null) return;
      GoogleSignIn.instance.attemptLightweightAuthentication()?.ignore();
    });
  }

  void _remember() {
    final user = _user;
    final token = _idToken;
    if (user == null || token == null) {
      _store.clear();
      return;
    }
    _store.save(SavedSession(user: user, idToken: token).encode());
  }

  @override
  Widget? buildSignInButton() => GoogleSignIn.instance.supportsAuthenticate()
      ? null
      : googleSignInButton();

  /// Shows [e] as the sign-in error; the log gets all of it.
  void _fail(Object e) {
    debugPrint('TabScan: Google sign-in failed: ${_details(e)}');
    _error = _describe(e);
    notifyListeners();
  }

  static String _details(Object e) => switch (e) {
    GoogleSignInException(:final code, :final description, :final details) => [
      code.name,
      ?description,
      if (details != null) 'details: $details',
    ].join('; '),
    _ => e.toString(),
  };

  static String _describe(Object e) => switch (e) {
    GoogleSignInException(:final description?) => description,
    GoogleSignInException(:final code) => code.name,
    _ => e.toString(),
  };

  @override
  void dispose() {
    _events?.cancel();
    _refresh?.cancel();
    super.dispose();
  }
}
