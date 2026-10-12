import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tabscan_app/cloud/cloud_sync.dart';
import 'package:tabscan_app/cloud/cognito.dart';
import 'package:tabscan_app/cloud/profile_service.dart';
import 'package:tabscan_app/cloud/share_api.dart';
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/screens/account_panel.dart';

import 'fakes.dart';

const _julio = ProfileAccount(
  id: 'a1',
  email: 'julio@example.com',
  provider: 'google',
  owner: true,
  you: true,
);
const _apple = ProfileAccount(
  id: 'a2',
  email: 'x7k2@privaterelay.appleid.com',
  provider: 'apple',
  owner: false,
  you: false,
);

class _Setup {
  _Setup({String identity = 'us-east-1:me'})
    : credentials = FakeCredentials(identity),
      shares = FakeShareApi({}, email: 'julio@example.com', identity: identity);

  final library = Library(PlatformEventStore());
  final auth = FakeAuth();
  final bucket = FakeBucket();
  final FakeCredentials credentials;
  final FakeShareApi shares;
  late final CloudSync sync;
  late final ProfileService profiles;
  int changed = 0;

  Future<void> start() async {
    await library.load();
    sync = CloudSync(
      library: library,
      auth: auth,
      bucket: bucket,
      credentials: credentials,
      shares: shares,
      period: const Duration(days: 1),
      debounce: const Duration(days: 1),
    );
    sync.profiles = profiles = ProfileService(
      sync: sync,
      onChanged: () => changed++,
    );
    sync.start();
    profiles.start();
  }

  Future<void> settle() async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await sync.syncNow();
  }

  void dispose() {
    profiles.dispose();
    sync.dispose();
  }
}

void main() {
  test('profile credentials: the share API vouches, Cognito answers', () async {
    final requests = <Map<String, Object?>>[];
    final cognito = MockClient((r) async {
      requests.add({
        'target': r.headers['x-amz-target'],
        ...jsonDecode(r.body),
      });
      return http.Response(
        jsonEncode({
          'IdentityId': 'us-east-1:profile',
          'Credentials': {
            'AccessKeyId': 'AKID',
            'SecretKey': 's',
            'SessionToken': 't',
            'Expiration': 4102444800,
          },
        }),
        200,
      );
    });
    final shares = FakeShareApi(
      {},
      email: 'julio@example.com',
      identity: 'us-east-1:profile',
    );
    final creds = ProfileCredentials(
      region: 'us-east-1',
      identityPoolId: 'us-east-1:pool',
      shares: shares,
      client: cognito,
    );
    final session = await creds.session('google-token');
    expect(session.identityId, 'us-east-1:profile');
    expect(requests.single, {
      'target': 'AWSCognitoIdentityService.GetCredentialsForIdentity',
      'IdentityId': 'us-east-1:profile',
      'Logins': {'cognito-identity.amazonaws.com': 'openid-brave_calm_otter'},
    });
    // Reused until it expires or the token changes.
    await creds.session('google-token');
    expect(shares.calls, ['credentials']);
  });

  test('the profile is asked for at sign-in', () async {
    final s = _Setup();
    await s.start();
    s.auth.signInAs('me');
    await s.settle();
    expect(s.profiles.profile?.id, 'brave_calm_otter');
    await s.auth.signOut();
    expect(s.profiles.profile, isNull);
    s.dispose();
  });

  test('linking moves this sign-in: new credentials, Premium again', () async {
    final s = _Setup();
    await s.start();
    s.auth.signInAs('me');
    await s.settle();
    s.shares.linkTo = const Profile(
      id: 'huge_wavy_darter',
      accounts: [_julio, _apple],
      roles: ['free', 'premium'],
    );
    final clears = s.credentials.clears;
    await s.profiles.link('abcd-efgh');
    expect(s.profiles.profile?.id, 'huge_wavy_darter');
    expect(s.profiles.profile!.premium, isTrue);
    expect(s.credentials.clears, greaterThan(clears));
    expect(s.changed, 1);

    s.shares.linkError = ShareApiException(404, 'wrong');
    await expectLater(
      s.profiles.link('nope'),
      throwsA(isA<ShareApiException>()),
    );
    expect(s.profiles.error, 'wrong');
    s.dispose();
  });

  test("the same user's folder moving takes their captures along", () async {
    final s = _Setup();
    await s.start();
    s.auth.signInAs('me');
    await s.settle();
    final event = await s.library.create([
      Uint8List.fromList([1, 2, 3]),
    ]);
    await s.sync.syncNow();
    expect(
      s.bucket.objects.keys,
      contains('us-east-1:me/events/${event.id}/event.json'),
    );

    // The sign-in joined a profile: another folder.
    s.credentials.identityId = 'us-east-1:profile';
    s.credentials.clear();
    await s.sync.syncNow();
    expect(s.library.byId(event.id)!.owner, 'us-east-1:profile');
    expect(
      s.bucket.objects.keys,
      contains('us-east-1:profile/events/${event.id}/event.json'),
    );
    s.dispose();
  });

  test("another user's captures stay theirs", () async {
    final s = _Setup();
    await s.start();
    s.auth.signInAs('me');
    await s.settle();
    final event = await s.library.create([
      Uint8List.fromList([1, 2, 3]),
    ]);
    await s.sync.syncNow();
    await s.auth.signOut();
    s.credentials.identityId = 'us-east-1:other';
    s.auth.signInAs('other');
    await s.settle();
    expect(s.library.byId(event.id)!.owner, 'us-east-1:me');
    expect(
      s.bucket.objects.keys.where((k) => k.startsWith('us-east-1:other/')),
      isEmpty,
    );
    s.dispose();
  });

  testWidgets('Profile shows the profile, its roles and linked accounts', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(() async {
      s.shares.profileNow = const Profile(
        id: 'huge_wavy_darter',
        accounts: [_julio, _apple],
        roles: ['admin', 'free', 'premium'],
      );
      await s.start();
      s.auth.signInAs('me');
      await s.settle();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountPanel(auth: s.auth, sync: s.sync),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Profile: huge_wavy_darter'), findsOneWidget);
    expect(find.text('Roles: admin, free, premium'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);

    await tester.tap(find.text('Linked accounts (2)'));
    await tester.pumpAndSettle();
    expect(find.text('x7k2@privaterelay.appleid.com'), findsOneWidget);
    expect(find.text('Unlink'), findsOneWidget); // not the owner's
    await tester.tap(find.text('Get a link code'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SelectableText>(find.byKey(const Key('link-code'))).data,
      'ABCD-EFGH',
    );

    s.shares.linkError = ShareApiException(404, 'wrong');
    await tester.enterText(find.byKey(const Key('enter-code')), 'zzzz-zzzz');
    await tester.ensureVisible(find.text('Link this account'));
    await tester.tap(find.text('Link this account'));
    await tester.pumpAndSettle();
    expect(s.shares.calls, contains('link zzzz-zzzz'));
    expect(
      find.text('That code is wrong, already used or expired.'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Unlink'));
    await tester.tap(find.text('Unlink'));
    await tester.pumpAndSettle();
    expect(find.text('x7k2@privaterelay.appleid.com'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });

  testWidgets('a linked account that is not the owner can not delete', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(() async {
      s.shares.profileNow = const Profile(
        id: 'huge_wavy_darter',
        accounts: [
          ProfileAccount(
            id: 'a1',
            email: 'julio@example.com',
            provider: 'google',
            owner: true,
            you: false,
          ),
          ProfileAccount(
            id: 'a2',
            email: 'ana@example.com',
            provider: 'google',
            owner: false,
            you: true,
          ),
        ],
        roles: ['free'],
      );
      await s.start();
      s.auth.signInAs('me');
      await s.settle();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountPanel(auth: s.auth, sync: s.sync),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Delete account'), findsNothing);
    expect(find.textContaining("Only the profile's owner"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
}
