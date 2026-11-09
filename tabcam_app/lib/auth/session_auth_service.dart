import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../cloud/share_api.dart';
import '../l10n/language.dart';
import 'auth_service.dart';
import 'jwt.dart';
import 'session_keeper.dart';

/// What the share API answers when a session starts or renews: TabCam's ID
/// token (an hour), and, when it starts, the refresh token.
class SessionTokens {
  const SessionTokens({
    required this.idToken,
    this.refreshToken,
    this.sessionExpiresAt,
  });

  factory SessionTokens.fromJson(Map<String, Object?> json) {
    final ends = json['sessionExpiresAt'];
    return SessionTokens(
      idToken: json['idToken']! as String,
      refreshToken: json['refreshToken'] as String?,
      sessionExpiresAt: ends is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (ends * 1000).round(),
              isUtc: true,
            )
          : null,
    );
  }

  final String idToken;
  final String? refreshToken;

  /// When the session ends if it isn't used again.
  final DateTime? sessionExpiresAt;
}

/// TabCam's sessions at the share API ([ShareApi], or a fake in tests).
abstract interface class SessionApi {
  /// A new session for the sign-in of [providerToken] (Google's, Apple's,
  /// email's).
  Future<SessionTokens> startSession(String providerToken);

  /// A new ID token; a [ShareApiException] of 401 when the session is over.
  Future<SessionTokens> refreshSession(String refreshToken);

  /// Signs out: the refresh token stops working.
  Future<void> endSession(String refreshToken);
}

/// Keeps the user signed in for days, over [inner]'s sign-in (Google,
/// Apple, email, or several): once [inner] signs someone in, the share API
/// starts a TabCam session with the provider's token, and from then on this
/// gives TabCam's ID tokens, renewed with the session's refresh token five
/// minutes before each expires (and when the app comes back to the front).
///
/// The session lasts a week past its last use (90 days at most), and is
/// kept on the device ([SessionKeeper]), so the user stays signed in across
/// reloads and restarts even when the provider can't renew its own token
/// quietly (Google on the web, Apple). It ends only when the user signs
/// out, the share API refuses it (a week unused, 90 days, the account
/// deleted or the sign-in unlinked), or, at launch, the provider says the
/// sign-in no longer stands (Apple ID stopped being used with TabCam).
///
/// Until a session starts (offline, or a share API without sessions),
/// [inner]'s own token is used, as before.
class SessionAuthService extends AuthService with WidgetsBindingObserver {
  SessionAuthService({
    required this.inner,
    required this._api,
    this._keeper = const SessionKeeper(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    inner.addListener(_onInner);
  }

  final AuthService inner;
  final SessionApi _api;
  final SessionKeeper _keeper;
  final DateTime Function() _now;

  _Session? _session;
  bool _restoring = true;
  String? _error;
  Timer? _refresh;
  bool _renewing = false;
  DateTime? _renewedAt;

  /// The refresh token this one last kept on the device: another there
  /// (another tab's newer session) isn't overwritten.
  String? _owned;

  /// The provider token a session is being started with.
  String? _starting;

  /// The provider token a session last failed to start with (not tried
  /// again until [inner] has another).
  String? _failed;

  @override
  AuthUser? get user => _session?.user ?? inner.user;

  @override
  String? get idToken {
    final session = _session;
    if (session == null) return inner.idToken;
    // Behind (a throttled tab, a phone app in the background), the timer
    // may be late: renewed now, and the listeners told.
    if (_expiresSoon(session) && !_renewedRecently) {
      scheduleMicrotask(_renew);
    }
    return session.idToken;
  }

  @override
  List<AuthProvider> get providers => inner.providers;

  @override
  bool get checking => _restoring || (_session == null && inner.checking);

  @override
  bool get available => inner.available;

  @override
  String? get unavailableReason => inner.unavailableReason;

  /// Signed in, [inner]'s errors (its own token expiring) don't matter.
  @override
  String? get error => _error ?? (_session == null ? inner.error : null);

  @override
  Future<void> init() async {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {} // no binding (unit tests)
    final restored = _Session.decode(await _keeper.load());
    if (restored != null) {
      _session = restored;
      _owned = restored.refreshToken;
      debugPrint(
        'TabCam: session restored (${restored.user.provider.name}), '
        'renewal due in ${restored.renewAt.difference(_now()).inMinutes} min',
      );
      // An expired token is renewed before anyone uses it (offline, the
      // session stays, and is renewed a minute later).
      if (_expiresSoon(restored)) {
        await _renew();
      } else {
        _schedule();
      }
    }
    _restoring = false;
    notifyListeners();
    inner.skipQuietSignIn = _session != null;
    await inner.init();
    final session = _session;
    if (session != null && !await inner.stillValid(session.user)) {
      // Stopped using Apple ID with TabCam, in Settings.
      await _end(session);
      _endQuietly(session.refreshToken);
    }
    _onInner();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final session = _session;
    if (session == null) {
      // A session that couldn't start (offline): tried again.
      _failed = null;
      _onInner();
    } else if (_expiresSoon(session)) {
      unawaited(_renew());
    }
  }

  /// A renewal was tried in the last 20 seconds: not again yet (offline,
  /// every read of [idToken] would try).
  bool get _renewedRecently {
    final at = _renewedAt;
    return at != null && _now().difference(at) < const Duration(seconds: 20);
  }

  void _onInner() {
    final user = inner.user;
    final token = inner.idToken;
    final session = _session;
    if (!_restoring && user != null && token != null) {
      if (session == null || !_same(session.user, user)) {
        unawaited(_start(user, token));
      } else {
        final merged = _merge(session.user, user);
        if (!_sameDetails(merged, session.user)) {
          // The same sign-in, its name or photo changed.
          _session = session.withUser(merged);
          unawaited(_save());
        }
      }
    }
    notifyListeners();
  }

  /// [inner] signed [user] in: a session for them, replacing another's.
  Future<void> _start(AuthUser user, String providerToken) async {
    if (_starting == providerToken || _failed == providerToken) return;
    // A TabCam token can't start a session (never [inner]'s, but safe).
    if (isSessionToken(providerToken)) return;
    _starting = providerToken;
    try {
      final tokens = await _api.startSession(providerToken);
      final refresh = tokens.refreshToken;
      if (refresh == null) throw StateError('no refresh token');
      // Someone else signed in meanwhile: theirs is started next.
      if (inner.user == null || !_same(inner.user!, user)) return;
      final previous = _session;
      _session = _Session.received(
        user: user,
        refreshToken: refresh,
        idToken: tokens.idToken,
        now: _now(),
      );
      _error = null;
      _failed = null;
      debugPrint('TabCam: session started (${user.provider.name})');
      _schedule();
      // Signed in here: kept, over another tab's session.
      await _save(force: true);
      if (previous != null && previous.refreshToken != refresh) {
        _endQuietly(previous.refreshToken);
      }
      notifyListeners();
    } catch (e) {
      // Offline, or a share API without sessions: the provider's own token
      // until it has another.
      debugPrint('TabCam: starting a session failed: $e');
      _failed = providerToken;
    } finally {
      if (_starting == providerToken) _starting = null;
    }
  }

  /// A new ID token from the refresh token. Refused: the session is over.
  Future<void> _renew() async {
    final session = _session;
    if (session == null || _renewing || _renewedRecently) return;
    _renewing = true;
    _renewedAt = _now();
    try {
      final tokens = await _api.refreshSession(session.refreshToken);
      if (_session != session) return; // signed out (or in) meanwhile
      _session = session.withToken(tokens.idToken, _now());
      debugPrint('TabCam: session renewed');
      _schedule();
      await _save();
      notifyListeners();
    } on ShareApiException catch (e) {
      if (_session != session) return;
      // Only a refusal ends it: anything else (a deploy gone wrong, 404 or
      // 5xx) is tried again.
      if (e.statusCode == 401) {
        debugPrint('TabCam: the session ended: $e');
        // Another tab signed in again (ending this one): theirs, then.
        final kept = _Session.decode(await _keeper.load());
        if (kept != null && kept.refreshToken != session.refreshToken) {
          _session = kept;
          _owned = kept.refreshToken;
          _renewedAt = null;
          if (_expiresSoon(kept)) {
            scheduleMicrotask(_renew);
          } else {
            _schedule();
          }
          notifyListeners();
          return;
        }
        await _end(session);
        // Still signed in with the provider: a new session from that.
        if (inner.user == null) _error = appL10n.accountSessionEnded;
        _failed = null;
        _onInner();
      } else {
        _retrySoon();
      }
    } catch (e) {
      // Offline: again in a minute; the token may still be good.
      debugPrint('TabCam: renewing the session failed: $e');
      if (_session == session) _retrySoon();
    } finally {
      _renewing = false;
    }
  }

  void _retrySoon() {
    _refresh?.cancel();
    _refresh = Timer(const Duration(minutes: 1), _renew);
  }

  /// The renewal, at [_Session.renewAt]: never sooner than 30 seconds,
  /// whatever the token says.
  void _schedule() {
    _refresh?.cancel();
    final session = _session;
    if (session == null) return;
    var wait = session.renewAt.difference(_now());
    if (wait < const Duration(seconds: 30)) wait = const Duration(seconds: 30);
    _refresh = Timer(wait, _renew);
  }

  bool _expiresSoon(_Session session) => !_now().isBefore(session.renewAt);

  /// Forgets [session] here (the share API has ended it, or will). [force]:
  /// off the device even if another tab has kept its own there since.
  Future<void> _end(_Session session, {bool force = false}) async {
    if (_session != session) return;
    _refresh?.cancel();
    _session = null;
    await _save(force: force);
    notifyListeners();
  }

  void _endQuietly(String refreshToken) {
    unawaited(
      _api
          .endSession(refreshToken)
          .then(
            (_) {},
            onError: (Object e) =>
                debugPrint('TabCam: ending the session failed: $e'),
          ),
    );
  }

  @override
  Future<void> signIn([AuthProvider provider = AuthProvider.google]) {
    _error = null;
    return inner.signIn(provider);
  }

  @override
  Future<void> signOut() async {
    final session = _session;
    _error = null;
    if (session != null) {
      await _end(session, force: true);
      _endQuietly(session.refreshToken);
    }
    _failed = null;
    await inner.signOut();
    notifyListeners();
  }

  @override
  Future<String?> deletionAuthorization([AuthUser? user]) =>
      inner.deletionAuthorization(user ?? this.user);

  @override
  Future<bool> stillValid(AuthUser user) => inner.stillValid(user);

  @override
  Widget? buildSignInButton([AuthProvider provider = AuthProvider.google]) =>
      inner.buildSignInButton(provider);

  /// Keeps the session on the device (none: forgets it). Unless [force]d,
  /// another session kept there since (another tab's) is left alone.
  Future<void> _save({bool force = false}) async {
    final session = _session;
    if (!force) {
      final kept = _Session.decode(await _keeper.load());
      if (kept != null &&
          kept.refreshToken != _owned &&
          kept.refreshToken != session?.refreshToken) {
        return;
      }
    }
    _owned = session?.refreshToken;
    await _keeper.save(session?.encode());
  }

  static bool _same(AuthUser a, AuthUser b) =>
      a.id == b.id && a.provider == b.provider;

  static bool _sameDetails(AuthUser a, AuthUser b) =>
      _same(a, b) &&
      a.email == b.email &&
      a.name == b.name &&
      a.photoUrl == b.photoUrl &&
      a.privateEmail == b.privateEmail;

  /// [fresh]'s details, but what [kept] knows that it doesn't (Apple sends
  /// the name only once).
  static AuthUser _merge(AuthUser kept, AuthUser fresh) => AuthUser(
    id: fresh.id,
    email: fresh.email.isNotEmpty ? fresh.email : kept.email,
    name: fresh.name ?? kept.name,
    photoUrl: fresh.photoUrl ?? kept.photoUrl,
    provider: fresh.provider,
    privateEmail: fresh.privateEmail,
  );

  @override
  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    _refresh?.cancel();
    inner.removeListener(_onInner);
    inner.dispose();
    super.dispose();
  }
}

/// A session as kept on the device: who, the refresh token, the last ID
/// token (restored even when expired: it's renewed at once), and when to
/// renew it.
@immutable
class _Session {
  const _Session({
    required this.user,
    required this.refreshToken,
    required this.idToken,
    required this.renewAt,
  });

  /// A session whose [idToken] arrived [now]: renewed five minutes before
  /// it expires, by its own lifetime (`exp - iat`, set by the server), so a
  /// device clock that's off doesn't matter.
  factory _Session.received({
    required AuthUser user,
    required String refreshToken,
    required String idToken,
    required DateTime now,
  }) => _Session(
    user: user,
    refreshToken: refreshToken,
    idToken: idToken,
    renewAt: now.add(_life(idToken) - _lead),
  );

  static const _lead = Duration(minutes: 5);

  /// How long [token] is good for, by its claims; an hour if they don't
  /// say, never less than [_lead] and a minute.
  static Duration _life(String token) {
    final claims = jwtClaims(token);
    final (exp, iat) = (claims?['exp'], claims?['iat']);
    final life = exp is num && iat is num
        ? Duration(seconds: (exp - iat).round())
        : const Duration(hours: 1);
    const least = Duration(minutes: 6);
    return life < least ? least : life;
  }

  final AuthUser user;
  final String refreshToken;
  final String idToken;

  /// When to renew [idToken], by this device's clock.
  final DateTime renewAt;

  _Session withToken(String token, DateTime now) => _Session.received(
    user: user,
    refreshToken: refreshToken,
    idToken: token,
    now: now,
  );

  _Session withUser(AuthUser user) => _Session(
    user: user,
    refreshToken: refreshToken,
    idToken: idToken,
    renewAt: renewAt,
  );

  String encode() => jsonEncode({
    'v': 1,
    'id': user.id,
    'email': user.email,
    'name': user.name,
    'photoUrl': user.photoUrl,
    'provider': user.provider.name,
    if (user.privateEmail) 'privateEmail': true,
    'refreshToken': refreshToken,
    'idToken': idToken,
    'renewAt': renewAt.millisecondsSinceEpoch,
  });

  static _Session? decode(String? json) {
    if (json == null) return null;
    try {
      final m = (jsonDecode(json) as Map).cast<String, Object?>();
      final (id, email, refresh, token, renew) = (
        m['id'],
        m['email'],
        m['refreshToken'],
        m['idToken'],
        m['renewAt'],
      );
      if (id is! String ||
          email is! String ||
          refresh is! String ||
          token is! String ||
          renew is! int) {
        return null;
      }
      return _Session(
        user: AuthUser(
          id: id,
          email: email,
          name: m['name'] as String?,
          photoUrl: m['photoUrl'] as String?,
          provider: AuthProvider.byName(m['provider'] as String?),
          privateEmail: m['privateEmail'] == true,
        ),
        refreshToken: refresh,
        idToken: token,
        renewAt: DateTime.fromMillisecondsSinceEpoch(renew),
      );
    } catch (_) {
      return null;
    }
  }
}
