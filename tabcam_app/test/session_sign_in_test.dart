import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tabcam_app/auth/auth_service.dart';
import 'package:tabcam_app/auth/session_auth_service.dart';
import 'package:tabcam_app/auth/session_keeper.dart';
import 'package:tabcam_app/cloud/share_api.dart';
import 'package:tabcam_app/l10n/language.dart';

import 'fakes.dart';

final _now = DateTime.utc(2026, 11, 9, 12);

String _jwt(Map<String, Object?> claims) =>
    'eyJhbGciOiJub25lIn0.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.sig';

/// TabCam's ID token for Google's `riff`, number [n], expiring [life] after
/// [at].
String sessionToken({
  int n = 1,
  DateTime? at,
  Duration life = const Duration(hours: 1),
  String idp = 'https://accounts.google.com',
}) => _jwt({
  'iss': 'https://api.example.com/session',
  'aud': sessionAudience,
  'sub': 'riff',
  'idp': idp,
  'n': n,
  'iat': (at ?? _now).millisecondsSinceEpoch ~/ 1000,
  'exp': (at ?? _now).add(life).millisecondsSinceEpoch ~/ 1000,
});

/// The share API's session routes, in memory.
class FakeSessionApi implements SessionApi {
  final List<String> started = [];
  final List<String> refreshed = [];
  final List<String> ended = [];
  DateTime Function() now = () => _now;

  /// Throws instead of answering, when set.
  Object? startError;
  Object? refreshError;
  int _n = 0;

  @override
  Future<SessionTokens> startSession(String providerToken) async {
    started.add(providerToken);
    if (startError case final e?) throw e;
    _n++;
    return SessionTokens(
      idToken: sessionToken(n: _n, at: now()),
      refreshToken: 'tcs1.refresh-$_n',
    );
  }

  @override
  Future<SessionTokens> refreshSession(String refreshToken) async {
    refreshed.add(refreshToken);
    if (refreshError case final e?) throw e;
    _n++;
    return SessionTokens(
      idToken: sessionToken(n: _n, at: now()),
    );
  }

  @override
  Future<void> endSession(String refreshToken) async => ended.add(refreshToken);
}

class MemoryKeeper implements SessionKeeper {
  String? data;

  @override
  Future<String?> load() async => data;

  @override
  Future<void> save(String? data) async => this.data = data;
}

/// A provider sign-in whose user may have stopped using it (Apple).
class RevokableAuth extends FakeAuth {
  bool valid = true;

  @override
  Future<bool> stillValid(AuthUser user) async => valid;
}

const _riff = AuthUser(id: 'riff', email: 'riff@example.com', name: 'Riff');

/// A session kept on the device: [_riff]'s, with [token], to be renewed
/// five minutes before it expires.
String _kept(String token, {String refresh = 'tcs1.kept'}) => jsonEncode({
  'v': 1,
  'id': 'riff',
  'email': 'riff@example.com',
  'name': 'Riff',
  'provider': 'google',
  'refreshToken': refresh,
  'idToken': token,
  'renewAt': (_claim(token, 'exp') - 300) * 1000,
});

int _claim(String token, String name) =>
    (jsonDecode(
          utf8.decode(
            base64Url.decode(base64Url.normalize(token.split('.')[1])),
          ),
        ) as Map)[name]
        as int;

int _n(String? token) {
  final payload = token!.split('.')[1];
  return (jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(payload))),
      ) as Map)['n']
      as int;
}

void main() {
  late FakeAuth inner;
  late FakeSessionApi api;
  late MemoryKeeper keeper;
  late DateTime now;

  SessionAuthService make({FakeAuth? provider}) => SessionAuthService(
    inner: inner = provider ?? FakeAuth(),
    api: api,
    keeper: keeper,
    now: () => now,
  );

  setUp(() {
    api = FakeSessionApi()..now = () => now;
    keeper = MemoryKeeper();
    now = _now;
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('signing in with a provider starts a session, whose token is used '
      'and kept', () async {
    final auth = make();
    await auth.init();
    expect(auth.user, isNull);
    expect(inner.skipQuietSignIn, isFalse);
    inner.signInWith(_riff, 'google-token');
    // Until the session starts, the provider's own token.
    expect(auth.idToken, 'google-token');
    await settle();
    expect(api.started, ['google-token']);
    expect(isSessionToken(auth.idToken!), isTrue);
    expect(auth.user!.id, 'riff');
    expect(keeper.data, contains('tcs1.refresh-1'));
  });

  test('the provider losing its token leaves the user signed in', () async {
    final auth = make();
    await auth.init();
    inner.signInWith(_riff, 'google-token');
    await settle();
    // Apple's token expiring signs its service out; Google's may just
    // fail to renew.
    await inner.signOut();
    expect(auth.user?.email, 'riff@example.com');
    expect(isSessionToken(auth.idToken!), isTrue);
    expect(auth.error, isNull);
  });

  test('at launch the kept session is back at once, even with its token '
      'expired, and renewed', () async {
    keeper.data = _kept(
      sessionToken(at: _now.subtract(const Duration(days: 3))),
    );
    final auth = make();
    await auth.init();
    expect(auth.user?.name, 'Riff');
    expect(auth.checking, isFalse);
    // No provider prompt at launch: already signed in.
    expect(inner.skipQuietSignIn, isTrue);
    await settle();
    expect(api.refreshed, ['tcs1.kept']);
    expect(_n(auth.idToken), 1);
    expect(keeper.data, contains(auth.idToken));
  });

  test('the token is renewed five minutes before it expires', () {
    fakeAsync((async) {
      now = _now;
      final auth = make();
      auth.init();
      async.flushMicrotasks();
      inner.signInWith(_riff, 'google-token');
      async.flushMicrotasks();
      expect(api.refreshed, isEmpty);
      now = _now.add(const Duration(minutes: 54));
      async.elapse(const Duration(minutes: 54));
      expect(api.refreshed, isEmpty);
      now = _now.add(const Duration(minutes: 55));
      async.elapse(const Duration(minutes: 1));
      expect(api.refreshed, ['tcs1.refresh-1']);
      expect(_n(auth.idToken), 2);
      auth.dispose();
    });
  });

  test('offline, renewing is tried again a minute later', () {
    fakeAsync((async) {
      keeper.data = _kept(
        sessionToken(at: _now.subtract(const Duration(hours: 2))),
      );
      api.refreshError = http.ClientException('offline');
      final auth = make();
      auth.init();
      async.elapse(Duration.zero);
      expect(api.refreshed, hasLength(1));
      expect(auth.user, isNotNull);
      api.refreshError = null;
      now = _now.add(const Duration(minutes: 1));
      async.elapse(const Duration(minutes: 1));
      expect(api.refreshed, hasLength(2));
      expect(isSessionToken(auth.idToken!), isTrue);
      expect(_n(auth.idToken), 1);
      auth.dispose();
    });
  });

  test('a refused renewal signs out, and says why', () async {
    keeper.data = _kept(
      sessionToken(at: _now.subtract(const Duration(hours: 2))),
    );
    api.refreshError = ShareApiException(401, 'Sign in again');
    final auth = make();
    await auth.init();
    await settle();
    expect(auth.user, isNull);
    expect(keeper.data, isNull);
    expect(auth.error, appL10n.accountSessionEnded);
  });

  test("a refused renewal while the provider still has the user starts a "
      'new session, quietly', () async {
    final auth = make();
    await auth.init();
    inner.signInWith(_riff, 'google-token');
    await settle();
    api.refreshError = ShareApiException(401, 'Sign in again');
    now = _now.add(const Duration(hours: 2));
    auth.idToken; // expired: renewed
    await settle();
    await settle();
    expect(api.started, ['google-token', 'google-token']);
    expect(auth.user?.id, 'riff');
    expect(auth.error, isNull);
  });

  test('signing out ends the session at the API, here and with the '
      'provider', () async {
    final auth = make();
    await auth.init();
    inner.signInWith(_riff, 'google-token');
    await settle();
    await auth.signOut();
    expect(auth.user, isNull);
    expect(inner.user, isNull);
    expect(keeper.data, isNull);
    expect(api.ended, ['tcs1.refresh-1']);
  });

  test("without sessions at the API, the provider's token is used as "
      'before', () async {
    api.startError = ShareApiException(404, 'No sessions here');
    final auth = make();
    await auth.init();
    inner.signInWith(_riff, 'google-token');
    await settle();
    expect(auth.idToken, 'google-token');
    expect(auth.user?.id, 'riff');
    expect(keeper.data, isNull);
    // Not asked again for the same token.
    inner.signInWith(_riff, 'google-token');
    await settle();
    expect(api.started, hasLength(1));
  });

  test("another account signing in replaces the session, and ends the old "
      'one', () async {
    final auth = make();
    await auth.init();
    inner.signInWith(_riff, 'google-token');
    await settle();
    inner.signInWith(
      const AuthUser(id: 'mia', email: 'mia@example.com'),
      'mia-token',
    );
    await settle();
    expect(auth.user?.id, 'mia');
    expect(api.started, ['google-token', 'mia-token']);
    expect(api.ended, ['tcs1.refresh-1']);
  });

  test('at launch, a sign-in the provider no longer vouches for (Apple ID '
      'stopped) ends the session', () async {
    keeper.data = _kept(sessionToken());
    final provider = RevokableAuth()..valid = false;
    final auth = make(provider: provider);
    await auth.init();
    expect(auth.user, isNull);
    expect(keeper.data, isNull);
    expect(api.ended, ['tcs1.kept']);
  });

  test(
    "deleting the account asks the provider for the session's user",
    () async {
      keeper.data = _kept(sessionToken());
      final auth = make();
      inner.deletionAnswer = () async => 'c0de';
      await auth.init();
      expect(await auth.deletionAuthorization(), 'c0de');
    },
  );

  test('a device clock an hour ahead renews once, an hour later, with no '
      'loop', () {
    fakeAsync((async) {
      now = _now.add(const Duration(hours: 1)); // the device's clock
      api.now = () => _now; // the server's
      final auth = make();
      auth.init();
      async.flushMicrotasks();
      inner.signInWith(_riff, 'google-token'); // the server's tokens: _now
      async.flushMicrotasks();
      expect(isSessionToken(auth.idToken!), isTrue);
      async.elapse(const Duration(minutes: 30));
      expect(api.refreshed, isEmpty);
      now = now.add(const Duration(minutes: 55));
      async.elapse(const Duration(minutes: 25));
      expect(api.refreshed, hasLength(1));
      async.elapse(const Duration(minutes: 10));
      expect(api.refreshed, hasLength(1));
      auth.dispose();
    });
  });

  test('anything but a refusal (a 404, a 5xx) keeps the session, and '
      'tries again', () async {
    keeper.data = _kept(
      sessionToken(at: _now.subtract(const Duration(hours: 2))),
    );
    api.refreshError = ShareApiException(404, 'No sessions here');
    final auth = make();
    await auth.init();
    expect(auth.user?.id, 'riff');
    expect(keeper.data, contains('tcs1.kept'));
    expect(auth.error, isNull);
    auth.dispose();
  });

  test("a refused renewal takes another tab's newer session instead of "
      'signing out', () async {
    final auth = make();
    await auth.init();
    inner.signInWith(_riff, 'google-token');
    await settle();
    // Another tab signed out and in again: its session is on the device,
    // and this tab's was ended.
    api.refreshError = ShareApiException(401, 'Sign in again');
    now = _now.add(const Duration(hours: 2));
    keeper.data = _kept(sessionToken(n: 7, at: now), refresh: 'tcs1.other-tab');
    auth.idToken;
    await settle();
    await settle();
    expect(auth.user?.id, 'riff');
    expect(keeper.data, contains('tcs1.other-tab'));
    expect(auth.error, isNull);
  });

  test("renewing doesn't overwrite another tab's newer session", () async {
    final auth = make();
    await auth.init();
    inner.signInWith(_riff, 'google-token');
    await settle();
    final other = _kept(sessionToken(n: 7), refresh: 'tcs1.other-tab');
    keeper.data = other;
    now = _now.add(const Duration(minutes: 56));
    auth.idToken;
    await settle();
    expect(api.refreshed, ['tcs1.refresh-1']);
    expect(keeper.data, other);
  });

  test("a session's token names its provider, and goes to /tabcam", () async {
    final apple = sessionToken(idp: 'https://appleid.apple.com');
    expect(AuthProvider.ofToken(apple), AuthProvider.apple);
    expect(AuthProvider.ofToken(sessionToken()), AuthProvider.google);
    expect(isSessionToken(apple), isTrue);
    expect(
      isSessionToken(_jwt({'iss': 'https://accounts.google.com'})),
      isFalse,
    );

    final paths = <String>[];
    final bodies = <String>[];
    final shares = ShareApi(
      baseUrl: Uri.parse('https://share.example'),
      client: MockClient((request) async {
        paths.add('${request.method} ${request.url.path}');
        bodies.add(request.body);
        if (request.url.path == '/session/refresh') {
          return http.Response('{"message": "Sign in again"}', 401);
        }
        return http.Response(
          jsonEncode({
            'idToken': sessionToken(),
            'refreshToken': 'tcs1.r',
            'sessionExpiresAt': 1800000000,
            'profileId': 'brave_calm_otter',
            'accounts': [],
            'roles': [],
            'globalRoles': [],
          }),
          200,
        );
      }),
    );
    final started = await shares.startSession(
      _jwt({'iss': 'https://appleid.apple.com'}),
    );
    expect(started.refreshToken, 'tcs1.r');
    await shares.profile(apple);
    await shares.endSession('tcs1.r');
    await expectLater(
      shares.refreshSession('tcs1.r'),
      throwsA(
        isA<ShareApiException>().having((e) => e.statusCode, 'status', 401),
      ),
    );
    expect(paths, [
      'POST /apple/session',
      'GET /tabcam/profile',
      'POST /session/end',
      'POST /session/refresh',
    ]);
    expect(jsonDecode(bodies[2]), {'refreshToken': 'tcs1.r'});
  });
}
