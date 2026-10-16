import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:tabcam_app/auth/apple_auth_service.dart';
import 'package:tabcam_app/auth/auth_service.dart';
import 'package:tabcam_app/auth/multi_auth_service.dart';
import 'package:tabcam_app/auth/saved_session.dart';
import 'package:tabcam_app/cloud/cognito.dart';
import 'package:tabcam_app/cloud/share_api.dart';
import 'package:tabcam_app/screens/sign_in_buttons.dart';

import 'fakes.dart';

final _now = DateTime.utc(2026, 10, 11, 12);

/// A JWT with [claims] (unsigned: the app never checks signatures).
String jwt(Map<String, Object?> claims) =>
    'eyJhbGciOiJub25lIn0.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.sig';

int _in(Duration d) => _now.add(d).millisecondsSinceEpoch ~/ 1000;

String appleToken({
  String sub = 'apple.user.1',
  String? nonce,
  String? email = 'riff@example.com',
  Object? privateEmail,
  Duration life = const Duration(hours: 24),
}) => jwt({
  'iss': 'https://appleid.apple.com',
  'aud': 'com.nu01.tabcam',
  'sub': sub,
  'exp': _in(life),
  'nonce': ?nonce,
  'email': ?email,
  'email_verified': 'true',
  'is_private_email': ?privateEmail,
});

String googleToken() => jwt({
  'iss': 'https://accounts.google.com',
  'sub': 'g1',
  'exp': _in(const Duration(hours: 1)),
});

/// Apple's sheet: answers with [answer] for the nonce it's given.
class FakeApple implements AppleSignIn {
  FakeApple(this.answer);

  AppleCredential? Function(String nonce) answer;
  bool authorized = true;
  bool available = true;
  final List<String> nonces = [];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<AppleCredential?> signIn({required String nonce}) async {
    nonces.add(nonce);
    return answer(nonce);
  }

  @override
  Future<bool> stillAuthorized(String userId) async => authorized;

  /// What Apple's sheet answers when the account is being deleted (null:
  /// canceled).
  ({String userId, String code})? authorization = (
    userId: 'apple.user.1',
    code: 'c0de',
  );

  @override
  Future<({String userId, String code})?> authorize() async => authorization;
}

class MemoryAppleStore implements AppleStore {
  String? data;

  @override
  Future<String?> load() async => data;

  @override
  Future<void> save(String data) async => this.data = data;
}

AppleAuthService apple(FakeApple fake, MemoryAppleStore store) =>
    AppleAuthService(apple: fake, store: store, now: () => _now);

void main() {
  group('AuthProvider', () {
    test('a token names its provider by its issuer', () {
      expect(AuthProvider.ofToken(appleToken()), AuthProvider.apple);
      expect(AuthProvider.ofToken(googleToken()), AuthProvider.google);
      expect(AuthProvider.ofToken('not a jwt'), AuthProvider.google);
      expect(AuthProvider.apple.loginsKey, 'appleid.apple.com');
      expect(AuthProvider.google.loginsKey, 'accounts.google.com');
    });

    test('a saved session keeps its provider; old ones are Google', () {
      final token = appleToken();
      final saved = SavedSession(
        user: AuthUser(
          id: 'a',
          email: 'x@privaterelay.appleid.com',
          provider: AuthProvider.apple,
          privateEmail: true,
        ),
        idToken: token,
      ).encode();
      final back = SavedSession.decode(saved, now: _now)!;
      expect(back.user.provider, AuthProvider.apple);
      expect(back.user.privateEmail, isTrue);

      final old = jsonEncode({
        'id': 'g',
        'email': 'g@example.com',
        'idToken': token,
      });
      expect(
        SavedSession.decode(old, now: _now)!.user.provider,
        AuthProvider.google,
      );
    });

    test('a private relay address is labelled by the provider', () {
      const user = AuthUser(
        id: 'a',
        email: 'x1@privaterelay.appleid.com',
        provider: AuthProvider.apple,
        privateEmail: true,
      );
      expect(user.label, 'Apple ID (private email)');
      const named = AuthUser(
        id: 'a',
        email: 'x1@privaterelay.appleid.com',
        name: 'Ana Riff',
        provider: AuthProvider.apple,
        privateEmail: true,
      );
      expect(named.label, 'Ana Riff');
    });
  });

  group('AppleAuthService', () {
    test('signs in with a hashed nonce, keeping the name Apple sends once, '
        'and restores the session at launch', () async {
      final store = MemoryAppleStore();
      final fake = FakeApple(
        (nonce) => AppleCredential(
          userId: 'apple.user.1',
          identityToken: appleToken(nonce: nonce),
          email: 'Riff@Example.com',
          givenName: 'Ana',
          familyName: 'Riff',
        ),
      );
      final auth = apple(fake, store);
      await auth.init();
      expect(auth.user, isNull);
      await auth.signIn(AuthProvider.apple);
      expect(auth.error, isNull);
      expect(fake.nonces.single, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(auth.user!.email, 'riff@example.com');
      expect(auth.user!.name, 'Ana Riff');
      expect(auth.user!.provider, AuthProvider.apple);
      expect(AuthProvider.ofToken(auth.idToken!), AuthProvider.apple);

      // The next launch restores it.
      final again = apple(fake, store);
      await again.init();
      expect(again.user!.name, 'Ana Riff');
      expect(again.idToken, auth.idToken);

      // Signed out and in again: Apple sends no name or email this time,
      // but the token has the email, and the name was kept.
      await again.signOut();
      expect(again.user, isNull);
      fake.answer = (nonce) => AppleCredential(
        userId: 'apple.user.1',
        identityToken: appleToken(nonce: nonce),
      );
      await again.signIn(AuthProvider.apple);
      expect(again.user!.name, 'Ana Riff');
      expect(again.user!.email, 'riff@example.com');
      auth.dispose();
      again.dispose();
    });

    test('a hidden email is a private relay address', () async {
      final auth = apple(
        FakeApple(
          (nonce) => AppleCredential(
            userId: 'apple.user.1',
            identityToken: appleToken(
              nonce: nonce,
              email: 'x7k2@privaterelay.appleid.com',
              privateEmail: 'true',
            ),
          ),
        ),
        MemoryAppleStore(),
      );
      await auth.init();
      await auth.signIn(AuthProvider.apple);
      expect(auth.user!.privateEmail, isTrue);
      expect(auth.user!.label, 'Apple ID (private email)');
      auth.dispose();
    });

    test(
      'a token without our nonce, or for another user, is refused',
      () async {
        final fake = FakeApple(
          (_) => AppleCredential(
            userId: 'apple.user.1',
            identityToken: appleToken(nonce: 'someone-elses'),
          ),
        );
        final auth = apple(fake, MemoryAppleStore());
        await auth.init();
        await auth.signIn(AuthProvider.apple);
        expect(auth.user, isNull);
        expect(auth.error, contains("doesn't match"));

        fake.answer = (nonce) => AppleCredential(
          userId: 'apple.user.1',
          identityToken: appleToken(nonce: nonce, sub: 'apple.user.2'),
        );
        await auth.signIn(AuthProvider.apple);
        expect(auth.user, isNull);
        auth.dispose();
      },
    );

    test('canceling is no error', () async {
      final auth = apple(FakeApple((_) => null), MemoryAppleStore());
      await auth.init();
      await auth.signIn(AuthProvider.apple);
      expect(auth.user, isNull);
      expect(auth.error, isNull);
      auth.dispose();
    });

    test('a user who stopped using Apple ID with the app is signed out at '
        'launch; an expired session isn\'t restored', () async {
      final store = MemoryAppleStore();
      final fake = FakeApple(
        (nonce) => AppleCredential(
          userId: 'apple.user.1',
          identityToken: appleToken(nonce: nonce),
        ),
      );
      final auth = apple(fake, store);
      await auth.init();
      await auth.signIn(AuthProvider.apple);
      fake.authorized = false;
      final again = apple(fake, store);
      await again.init();
      expect(again.user, isNull);

      fake
        ..authorized = true
        ..answer = (nonce) => AppleCredential(
          userId: 'apple.user.1',
          identityToken: appleToken(
            nonce: nonce,
            life: const Duration(seconds: 30),
          ),
        );
      await again.signIn(AuthProvider.apple);
      final later = apple(fake, store);
      await later.init();
      expect(later.user, isNull);
      for (final a in [auth, again, later]) {
        a.dispose();
      }
    });

    test('not offered where Apple says it isn\'t available', () async {
      final fake = FakeApple((_) => null)..available = false;
      final auth = apple(fake, MemoryAppleStore());
      await auth.init();
      expect(auth.available, isFalse);
      final both = MultiAuthService([auth, FakeAuth()]);
      expect(both.providers, [AuthProvider.google]);
    });
  });

  group('deleting an Apple account', () {
    FakeApple fake() => FakeApple(
      (nonce) => AppleCredential(
        userId: 'apple.user.1',
        identityToken: appleToken(nonce: nonce),
        email: 'riff@example.com',
      ),
    );

    test('asks Apple for a fresh code, the signed-in Apple ID\'s', () async {
      final f = fake();
      final auth = apple(f, MemoryAppleStore());
      final both = MultiAuthService([auth, FakeAuth()]);
      await both.init();
      await both.signIn(AuthProvider.apple);
      expect(await auth.deletionAuthorization(), 'c0de');
      expect(await both.deletionAuthorization(), 'c0de');

      f.authorization = null;
      await expectLater(
        auth.deletionAuthorization(),
        throwsA(isA<DeletionAuthorizationCanceled>()),
      );
      f.authorization = (userId: 'apple.user.2', code: 'other');
      await expectLater(auth.deletionAuthorization(), throwsStateError);
      both.dispose();
    });

    test('Google has nothing to revoke', () async {
      final google = FakeAuth()..signInAs('ana', googleToken());
      expect(await google.deletionAuthorization(), isNull);
    });

    test('the share API gets the code with DELETE /apple/account', () async {
      final sent = <http.Request>[];
      final api = ShareApi(
        baseUrl: Uri.parse('https://api.example'),
        client: MockClient((request) async {
          sent.add(request);
          return http.Response('{}', 200);
        }),
      );
      await api.deleteAccount(appleToken(), appleAuthorizationCode: 'c0de');
      await api.deleteAccount(googleToken());
      expect(sent.map((r) => '${r.method} ${r.url.path}'), [
        'DELETE /apple/account',
        'DELETE /account',
      ]);
      expect(jsonDecode(sent.first.body), {'appleAuthorizationCode': 'c0de'});
      expect(sent.last.body, isEmpty);
    });
  });

  group('MultiAuthService', () {
    test('offers each provider, and one session at a time', () async {
      final fake = FakeApple(
        (nonce) => AppleCredential(
          userId: 'apple.user.1',
          identityToken: appleToken(nonce: nonce),
          email: 'riff@example.com',
        ),
      );
      final google = FakeAuth();
      final auth = MultiAuthService([apple(fake, MemoryAppleStore()), google]);
      await auth.init();
      expect(auth.providers, [AuthProvider.apple, AuthProvider.google]);

      google.signInAs('ana', googleToken());
      expect(auth.user!.provider, AuthProvider.google);

      await auth.signIn(AuthProvider.apple);
      expect(auth.user!.provider, AuthProvider.apple);
      expect(AuthProvider.ofToken(auth.idToken!), AuthProvider.apple);
      await Future<void>.delayed(Duration.zero);
      expect(google.user, isNull, reason: 'Google signed out');

      await auth.signIn(AuthProvider.google);
      expect(google.signIns, [AuthProvider.google]);

      await auth.signOut();
      expect(auth.user, isNull);
      auth.dispose();
    });
  });

  group('the cloud with an Apple token', () {
    test('Cognito gets it under appleid.apple.com, and a new identity when '
        'the provider changes', () async {
      final logins = <Object?>[];
      final cognito = CognitoCredentials(
        region: 'us-east-1',
        identityPoolId: 'us-east-1:pool',
        now: () => _now,
        client: MockClient((request) async {
          final action = request.headers['x-amz-target']!.split('.').last;
          final body = (jsonDecode(request.body) as Map)
              .cast<String, Object?>();
          logins.add('$action ${jsonEncode(body['Logins'])}');
          final apple = (body['Logins'] as Map).containsKey(
            'appleid.apple.com',
          );
          final id = apple ? 'us-east-1:apple' : 'us-east-1:google';
          return http.Response(
            jsonEncode({
              'IdentityId': id,
              if (action != 'GetId')
                'Credentials': {
                  'AccessKeyId': 'ASIA',
                  'SecretKey': 'secret',
                  'SessionToken': 'session',
                  'Expiration':
                      _now
                          .add(const Duration(hours: 1))
                          .millisecondsSinceEpoch /
                      1000,
                },
            }),
            200,
          );
        }),
      );
      final g = googleToken();
      expect((await cognito.session(g)).identityId, 'us-east-1:google');
      final a = appleToken();
      final session = await cognito.session(a);
      expect(session.identityId, 'us-east-1:apple');
      final apple = jsonEncode({'appleid.apple.com': a});
      expect(logins.sublist(2), [
        'GetId $apple',
        'GetCredentialsForIdentity $apple',
      ]);
    });

    test('the share API is asked under /apple', () async {
      final sent = <http.Request>[];
      final api = ShareApi(
        baseUrl: Uri.parse('https://api.example'),
        client: MockClient((request) async {
          sent.add(request);
          return http.Response(jsonEncode({'shared': []}), 200);
        }),
      );
      await api.shared(appleToken());
      await api.shared(googleToken());
      expect(sent.map((r) => r.url.path), ['/apple/shared', '/shared']);
    });
  });

  group('SignInButtons', () {
    testWidgets('shows Sign in with Apple above Google, and each signs in '
        'with its provider', (tester) async {
      final auth = FakeAuth(
        offered: const [AuthProvider.apple, AuthProvider.google],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SignInButtons(auth: auth)),
        ),
      );
      final appleButton = find.byType(SignInWithAppleButton);
      final googleButton = find.text('Sign in with Google');
      expect(appleButton, findsOneWidget);
      expect(googleButton, findsOneWidget);
      expect(
        tester.getTopLeft(appleButton).dy,
        lessThan(tester.getTopLeft(googleButton).dy),
      );
      expect(
        tester.getSize(appleButton).width,
        tester.getSize(find.byKey(const Key('sign-in-google'))).width,
      );
      await tester.tap(appleButton);
      await tester.tap(googleButton);
      expect(auth.signIns, [AuthProvider.apple, AuthProvider.google]);
    });

    testWidgets('only Google where Apple isn\'t offered', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SignInButtons(auth: FakeAuth())),
        ),
      );
      expect(find.byType(SignInWithAppleButton), findsNothing);
      expect(find.text('Sign in with Google'), findsOneWidget);
    });
  });
}
