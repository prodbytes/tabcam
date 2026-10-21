import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tabcam_app/auth/auth_service.dart';
import 'package:tabcam_app/auth/email_auth_service.dart';
import 'package:tabcam_app/auth/email_config.dart';
import 'package:tabcam_app/auth/email_store.dart';
import 'package:tabcam_app/cloud/share_api.dart';
import 'package:tabcam_app/export/incoming_links.dart';
import 'package:tabcam_app/l10n/language.dart';
import 'package:tabcam_app/screens/sign_in_buttons.dart';

final _now = DateTime.utc(2026, 10, 21, 12);

String _jwt(Map<String, Object?> claims) =>
    'eyJhbGciOiJub25lIn0.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.sig';

/// An ID token from the email user pool for [email].
String emailToken({
  String email = 'riff@example.com',
  Duration life = const Duration(hours: 1),
  DateTime? at,
}) => _jwt({
  'iss': EmailConfig.issuer,
  'sub': 'sub-$email',
  'email': email,
  'email_verified': true,
  'exp': (at ?? _now).add(life).millisecondsSinceEpoch ~/ 1000,
});

/// The user pool: answers each call with [answer]; records them.
class FakeIdp implements EmailIdp {
  FakeIdp(this.answer);

  Map<String, Object?> Function(String operation, Map<String, Object?> body)
  answer;
  final List<String> calls = [];
  final List<Map<String, Object?>> bodies = [];

  @override
  Future<Map<String, Object?>> call(
    String operation,
    Map<String, Object?> body,
  ) async {
    calls.add(operation);
    bodies.add(body);
    return answer(operation, body);
  }
}

class MemoryStore implements EmailStore {
  String? data;

  @override
  Future<String?> load() async => data;

  @override
  Future<void> save(String? data) async => this.data = data;
}

Map<String, Object?> _tokens({String email = 'riff@example.com'}) => {
  'AuthenticationResult': {
    'IdToken': emailToken(email: email),
    'RefreshToken': 'refresh-1',
  },
};

void main() {
  test('a new address signs up, confirms with its code and is signed in '
      'at once', () async {
    final idp = FakeIdp(
      (op, body) => switch (op) {
        'SignUp' => {'UserConfirmed': false, 'Session': 's-up'},
        'ConfirmSignUp' => {'Session': 's-confirmed'},
        'InitiateAuth' => _tokens(),
        _ => throw StateError(op),
      },
    );
    final store = MemoryStore();
    final auth = EmailAuthService(
      idp: idp,
      store: store,
      now: () => _now,
      site: 'https://rc.tabcam.nu01.com',
    );
    await auth.init();
    expect(await auth.sendCode('  Riff@Example.com '), isTrue);
    expect(auth.step, EmailStep.code);
    expect(auth.pendingEmail, 'riff@example.com');
    expect(idp.bodies.first['Username'], 'riff@example.com');
    expect(idp.bodies.first['ClientMetadata'], {
      'lang': 'en',
      'site': 'https://rc.tabcam.nu01.com',
    });
    expect(await auth.verify('123 456'), isTrue);
    expect(idp.calls, ['SignUp', 'ConfirmSignUp', 'InitiateAuth']);
    expect(idp.bodies[1]['ConfirmationCode'], '123456');
    expect(idp.bodies[2]['Session'], 's-confirmed');
    expect(auth.user?.email, 'riff@example.com');
    expect(auth.user?.id, 'sub-riff@example.com');
    expect(auth.user?.provider, AuthProvider.email);
    expect(AuthProvider.ofToken(auth.idToken!), AuthProvider.email);
    expect(auth.step, EmailStep.address);

    // Kept: a new launch is still signed in.
    final again = EmailAuthService(idp: idp, store: store, now: () => _now);
    await again.init();
    expect(again.user?.email, 'riff@example.com');
    auth.dispose();
    again.dispose();
  });

  test('a known address gets a sign-in code', () async {
    final idp = FakeIdp(
      (op, body) => switch (op) {
        'SignUp' => throw const EmailIdpException(
          'UsernameExistsException',
          'exists',
        ),
        'InitiateAuth' => {'ChallengeName': 'EMAIL_OTP', 'Session': 's-otp'},
        'RespondToAuthChallenge' => _tokens(),
        _ => throw StateError(op),
      },
    );
    final auth = EmailAuthService(
      idp: idp,
      store: MemoryStore(),
      now: () => _now,
    );
    await auth.init();
    expect(await auth.sendCode('riff@example.com'), isTrue);
    expect(
      (idp.bodies[1]['AuthParameters']! as Map)['PREFERRED_CHALLENGE'],
      'EMAIL_OTP',
    );
    expect(await auth.verify('654321'), isTrue);
    expect(idp.calls.last, 'RespondToAuthChallenge');
    expect(idp.bodies.last['Session'], 's-otp');
    expect(
      (idp.bodies.last['ChallengeResponses']! as Map)['EMAIL_OTP_CODE'],
      '654321',
    );
    expect(auth.user?.email, 'riff@example.com');
    auth.dispose();
  });

  test('a bad address or code is said, and the code can be tried '
      'again', () async {
    var wrong = true;
    final idp = FakeIdp(
      (op, body) => switch (op) {
        'SignUp' => {'Session': 's'},
        'ConfirmSignUp' when wrong => throw const EmailIdpException(
          'CodeMismatchException',
          'Invalid code',
        ),
        'ConfirmSignUp' => {'Session': 's2'},
        'InitiateAuth' => _tokens(),
        _ => throw StateError(op),
      },
    );
    final auth = EmailAuthService(
      idp: idp,
      store: MemoryStore(),
      now: () => _now,
    );
    await auth.init();
    expect(await auth.sendCode('not an address'), isFalse);
    expect(auth.error, appL10n.emailSignInBadAddress);
    expect(idp.calls, isEmpty);
    expect(await auth.sendCode('riff@example.com'), isTrue);
    expect(await auth.verify('12'), isFalse);
    expect(auth.error, appL10n.emailSignInBadCode);
    expect(await auth.verify('111111'), isFalse);
    expect(auth.error, appL10n.emailSignInBadCode);
    expect(auth.user, isNull);
    expect(auth.step, EmailStep.code);
    wrong = false;
    expect(await auth.verify('222222'), isTrue);
    expect(auth.error, isNull);
    expect(auth.user, isNotNull);
    auth.dispose();
  });

  test('the link finishes a sign-in waiting here, even after the app was '
      'closed', () async {
    final idp = FakeIdp(
      (op, body) => switch (op) {
        'SignUp' => throw const EmailIdpException(
          'UsernameExistsException',
          '',
        ),
        'InitiateAuth' => {'ChallengeName': 'EMAIL_OTP', 'Session': 's-otp'},
        'RespondToAuthChallenge' => _tokens(),
        _ => throw StateError(op),
      },
    );
    final store = MemoryStore();
    final first = EmailAuthService(idp: idp, store: store, now: () => _now);
    await first.init();
    await first.sendCode('riff@example.com');
    first.dispose();

    final later = EmailAuthService(
      idp: idp,
      store: store,
      now: () => _now.add(const Duration(minutes: 5)),
    );
    await later.init();
    expect(later.step, EmailStep.code);
    expect(await later.completeWithLink('765432'), isTrue);
    expect(later.user?.email, 'riff@example.com');
    // Signed in: another link does nothing.
    expect(await later.completeWithLink('765432'), isFalse);
    later.dispose();

    // A link without a sign-in waiting (too late, or another device's).
    final stale = EmailAuthService(
      idp: idp,
      store: MemoryStore(),
      now: () => _now,
    );
    await stale.init();
    expect(await stale.completeWithLink('765432'), isFalse);
    stale.dispose();
  });

  test('a waiting sign-in is forgotten after 15 minutes', () async {
    final idp = FakeIdp((op, body) => {'Session': 's'});
    final store = MemoryStore();
    final first = EmailAuthService(idp: idp, store: store, now: () => _now);
    await first.init();
    await first.sendCode('riff@example.com');
    first.dispose();
    final late = EmailAuthService(
      idp: idp,
      store: store,
      now: () => _now.add(const Duration(minutes: 16)),
    );
    await late.init();
    expect(late.step, EmailStep.address);
    late.dispose();
  });

  test('the ID token is renewed before it expires', () {
    fakeAsync((async) {
      var renewals = 0;
      final idp = FakeIdp(
        (op, body) => switch (op) {
          'SignUp' => {'Session': 's'},
          'ConfirmSignUp' => {'Session': 's2'},
          'InitiateAuth' when (body['AuthFlow'] == 'REFRESH_TOKEN_AUTH') => () {
            renewals++;
            return {
              'AuthenticationResult': {
                'IdToken': emailToken(
                  at: _now.add(async.elapsed),
                  life: const Duration(hours: 1),
                ),
              },
            };
          }(),
          'InitiateAuth' => _tokens(),
          _ => throw StateError(op),
        },
      );
      final auth = EmailAuthService(
        idp: idp,
        store: MemoryStore(),
        now: () => _now.add(async.elapsed),
      );
      auth.init();
      async.flushMicrotasks();
      auth.sendCode('riff@example.com');
      async.flushMicrotasks();
      auth.verify('123456');
      async.flushMicrotasks();
      expect(auth.user, isNotNull);
      async.elapse(const Duration(minutes: 50));
      expect(renewals, 0);
      async.elapse(const Duration(minutes: 6));
      expect(renewals, 1);
      expect(
        (idp.bodies.last['AuthParameters']! as Map)['REFRESH_TOKEN'],
        'refresh-1',
      );
      expect(auth.user?.email, 'riff@example.com');
      auth.dispose();
    });
  });

  test('a refused refresh signs out', () async {
    final idp = FakeIdp(
      (op, body) => switch (op) {
        'SignUp' => {'Session': 's'},
        'ConfirmSignUp' => {'Session': 's2'},
        'InitiateAuth' when body['AuthFlow'] == 'REFRESH_TOKEN_AUTH' =>
          throw const EmailIdpException('NotAuthorizedException', 'revoked'),
        'InitiateAuth' => _tokens(),
        _ => throw StateError(op),
      },
    );
    final store = MemoryStore();
    final auth = EmailAuthService(idp: idp, store: store, now: () => _now);
    await auth.init();
    await auth.sendCode('riff@example.com');
    await auth.verify('123456');
    auth.dispose();
    // Two hours on: the ID token has expired, and the refresh is refused.
    final later = EmailAuthService(
      idp: idp,
      store: store,
      now: () => _now.add(const Duration(hours: 2)),
    );
    await later.init();
    expect(later.user, isNull);
    expect(later.checking, isFalse);
    expect(store.data, isNull);
    later.dispose();
  });

  test('signing out forgets the session and revokes it', () async {
    final idp = FakeIdp(
      (op, body) => switch (op) {
        'SignUp' => {'Session': 's'},
        'ConfirmSignUp' => {'Session': 's2'},
        'InitiateAuth' => _tokens(),
        'RevokeToken' => {},
        _ => throw StateError(op),
      },
    );
    final store = MemoryStore();
    final auth = EmailAuthService(idp: idp, store: store, now: () => _now);
    await auth.init();
    await auth.sendCode('riff@example.com');
    await auth.verify('123456');
    await auth.signOut();
    await pumpEventQueue();
    expect(auth.user, isNull);
    expect(auth.idToken, isNull);
    expect(store.data, isNull);
    expect(idp.calls.last, 'RevokeToken');
    expect(idp.bodies.last['Token'], 'refresh-1');
    auth.dispose();
  });

  test('the share API is asked under /email', () async {
    final sent = <http.Request>[];
    final api = ShareApi(
      baseUrl: Uri.parse('https://api.example'),
      client: MockClient((request) async {
        sent.add(request);
        return http.Response(jsonEncode({'shared': []}), 200);
      }),
    );
    await api.shared(emailToken());
    expect(sent.single.url.path, '/email/shared');
  });

  test("a sign-in link's code is read; anything else isn't", () {
    expect(
      IncomingLinks.signInCodeIn(
        Uri.parse('https://tabcam.nu01.com/app/?signin-code=123456'),
      ),
      '123456',
    );
    expect(
      IncomingLinks.signInCodeIn(
        Uri.parse('https://tabcam.nu01.com/app/?signin-code=12ab56'),
      ),
      isNull,
    );
    expect(
      IncomingLinks.signInCodeIn(Uri.parse('https://tabcam.nu01.com/app/')),
      isNull,
    );
  });

  testWidgets('the dialog asks for the address, then the code, and closes '
      'signed in', (tester) async {
    final idp = FakeIdp(
      (op, body) => switch (op) {
        'SignUp' => {'Session': 's'},
        'ConfirmSignUp' => {'Session': 's2'},
        'InitiateAuth' => _tokens(),
        _ => throw StateError(op),
      },
    );
    final auth = EmailAuthService(
      idp: idp,
      store: MemoryStore(),
      now: () => _now,
    );
    await auth.init();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SignInButtons(auth: auth)),
      ),
    );
    await tester.tap(find.byKey(const Key('sign-in-email')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('email-sign-in-address')),
      'riff@example.com',
    );
    await tester.tap(find.byKey(const Key('email-sign-in-go')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('email-sign-in-code')), findsOneWidget);
    expect(find.textContaining('riff@example.com'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('email-sign-in-code')),
      '123456',
    );
    await tester.tap(find.byKey(const Key('email-sign-in-go')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(auth.user?.email, 'riff@example.com');
    auth.dispose();
  });
}
