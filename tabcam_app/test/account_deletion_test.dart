import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/cloud/account_deletion.dart';
import 'package:tabcam_app/cloud/cloud_sync.dart';
import 'package:tabcam_app/cloud/share_api.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/main.dart';

import 'fakes.dart';

const me = 'us-east-1:me';
const olga = 'us-east-1:olga';

/// A signed-in device syncing with [bucket], its passes run by hand.
class Phone {
  Phone(this.bucket, this.identity, this.user, this.grants)
    : credentials = FakeCredentials(identity),
      shares = FakeShareApi(
        grants,
        email: '$user@example.com',
        identity: identity,
      ) {
    sync = CloudSync(
      library: library,
      auth: auth,
      bucket: bucket,
      credentials: credentials,
      shares: shares,
      period: const Duration(days: 1),
      debounce: const Duration(days: 1),
    );
  }

  final FakeBucket bucket;
  final String identity;
  final String user;
  final Map<String, Map<String, ShareRole>> grants;
  final FakeCredentials credentials;
  final FakeShareApi shares;
  final auth = FakeAuth();
  final library = Library(PlatformEventStore());
  late final CloudSync sync;

  Future<void> start() async {
    await library.load();
    sync.start();
    auth.signInAs(user);
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await sync.syncNow();
  }
}

Uint8List bytes(List<int> b) => Uint8List.fromList(b);

/// Lets dialogs and messages animate (Home's thumbnails, loading, never
/// settle).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakeBucket bucket;
  late Map<String, Map<String, ShareRole>> grants;
  late Phone phone;
  late Phone olgaPhone;

  setUp(() async {
    bucket = FakeBucket();
    grants = {};
    phone = Phone(bucket, me, 'me', grants);
    olgaPhone = Phone(bucket, olga, 'olga', grants);
    // An event of another account that used this phone: it stays.
    await phone.library.load();
    final theirs = await phone.library.create([
      bytes([9]),
    ]);
    await phone.library.setOwner(theirs, 'us-east-1:someone');
    await phone.start();
    await olgaPhone.start();
  });

  /// Two events of mine (one shared with Olga), one of Olga's shared with
  /// me, a transcription, and an event made since the last pass.
  Future<void> fill() async {
    final riff = await phone.library.create([
      bytes([1, 2]),
    ]);
    await phone.library.create([
      bytes([3]),
    ]);
    await phone.sync.syncNow();
    await phone.sync.grant(
      phone.library.byId(riff.id)!,
      'olga@example.com',
      ShareRole.edit,
    );
    final hers = await olgaPhone.library.create([
      bytes([4]),
    ]);
    await olgaPhone.sync.syncNow();
    await olgaPhone.sync.grant(
      olgaPhone.library.byId(hers.id)!,
      'me@example.com',
      ShareRole.read,
    );
    await phone.sync.syncNow();
    await olgaPhone.sync.syncNow();
    bucket.objects['$me/ocr/${riff.id}/p.json'] = utf8.encode('{}');
    await phone.library.create([
      bytes([5]),
    ]);
    expect(phone.library.all.where((e) => e.isShared), hasLength(1));
    expect(olgaPhone.library.all.where((e) => e.isShared), hasLength(1));
  }

  Iterable<String> keysOf(String identity) =>
      bucket.objects.keys.where((k) => k.startsWith('$identity/'));

  test('deletes the folder, the shares both ways, the events here, then '
      'signs out', () async {
    await fill();
    expect(keysOf(me), isNotEmpty);
    final steps = <DeletionStep>[];
    await AccountDeletion(phone.sync).run(onProgress: (p) => steps.add(p.step));

    expect(keysOf(me), isEmpty);
    expect(keysOf(olga), isNotEmpty); // Olga's folder is hers
    expect(phone.shares.deletedAccounts, [me]);
    expect(grants.values.expand((g) => g.keys), isEmpty);
    // Only the other account's event stays on the phone.
    expect(phone.library.all.map((e) => e.owner), ['us-east-1:someone']);
    expect(phone.auth.user, isNull);
    expect(phone.sync.state, SyncState.signedOut);
    expect(steps.toSet().toList(), DeletionStep.values);
    expect(await phone.library.readMeta(CloudSync.stateName), '{}');

    // Olga's next pass drops what I shared with her; her own capture stays.
    await olgaPhone.sync.syncNow();
    expect(olgaPhone.library.all.where((e) => e.isShared), isEmpty);
    expect(olgaPhone.library.events, hasLength(1));
  });

  test('a large folder goes in batches of 1000, with progress', () async {
    for (var i = 0; i < 1500; i++) {
      bucket.objects['$me/events/x$i/p.img'] = bytes([i % 256]);
    }
    bucket.requests.clear();
    final progress = <DeletionProgress>[];
    await AccountDeletion(phone.sync).run(onProgress: progress.add);
    expect(bucket.requests.where((r) => r.startsWith('DELETE')), [
      'DELETE 1000',
      'DELETE 500',
    ]);
    expect(
      progress
          .where((p) => p.step == DeletionStep.cloud && p.total > 0)
          .map((p) => p.label()),
      [
        'Deleting your files in the cloud (0 of 1500)…',
        'Deleting your files in the cloud (1000 of 1500)…',
        'Deleting your files in the cloud (1500 of 1500)…',
      ],
    );
    expect(keysOf(me), isEmpty);
  });

  test('files S3 keeps stop it: still signed in, nothing else deleted, and '
      'trying again finishes', () async {
    await fill();
    final stuck = keysOf(me).first;
    bucket.undeletable.add(stuck);
    final events = phone.library.all.length;
    await expectLater(
      AccountDeletion(phone.sync).run(),
      throwsA(
        isA<AccountDeletionException>().having(
          (e) => e.message,
          'message',
          contains("couldn't be deleted"),
        ),
      ),
    );
    expect(phone.auth.user, isNotNull);
    expect(phone.shares.deletedAccounts, isEmpty);
    expect(phone.library.all, hasLength(events));
    expect(grants.values.expand((g) => g.keys), isNotEmpty);
    // Sync goes on: the account is still there.
    bucket.requests.clear();
    await phone.sync.syncNow();
    expect(bucket.requests, contains('LIST $me/events/'));

    bucket.undeletable.clear();
    await AccountDeletion(phone.sync).run();
    expect(keysOf(me), isEmpty);
    expect(phone.auth.user, isNull);
  });

  test('the share API failing stops it before anything here goes', () async {
    await fill();
    phone.shares.failDeleteAccount = ShareApiException(500, 'Internal error');
    final events = phone.library.all.length;
    await expectLater(
      AccountDeletion(phone.sync).run(),
      throwsA(
        isA<AccountDeletionException>().having(
          (e) => e.message,
          'message',
          allOf(contains('not your shares'), contains('Internal error')),
        ),
      ),
    );
    expect(phone.auth.user, isNotNull);
    expect(phone.library.all, hasLength(events));

    await AccountDeletion(phone.sync).run();
    expect(phone.shares.deletedAccounts, [me]);
    expect(phone.auth.user, isNull);
  });

  test('expired credentials are renewed once', () async {
    await fill();
    bucket.failNext = 1; // the listing: ExpiredToken
    await AccountDeletion(phone.sync).run();
    expect(phone.credentials.clears, greaterThan(0));
    expect(keysOf(me), isEmpty);
  });

  test('signed out, it asks to sign in', () async {
    await phone.auth.signOut();
    await expectLater(
      AccountDeletion(phone.sync).run(),
      throwsA(isA<AccountDeletionException>()),
    );
  });

  testWidgets('Profile: Delete account asks, then deletes and says so', (
    tester,
  ) async {
    await tester.runAsync(fill);
    await tester.pumpWidget(
      TabCamApp(library: phone.library, auth: phone.auth, sync: phone.sync),
    );
    await tester.tap(find.text('Profile'));
    await settle(tester);

    await tester.ensureVisible(find.text('Delete account'));
    await tester.tap(find.text('Delete account'));
    await settle(tester);
    expect(find.text('Delete your account?'), findsOneWidget);
    expect(find.textContaining("can't be undone"), findsOneWidget);
    expect(find.textContaining('Google account'), findsOneWidget);
    // Cancelling deletes nothing.
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(keysOf(me), isNotEmpty);

    await tester.tap(find.text('Delete account'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-delete-account')));
    await tester.pump();
    expect(find.text('Deleting your account'), findsOneWidget);
    await tester.runAsync(() async {
      while (phone.auth.user != null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await settle(tester);
    expect(find.text('Your TabCam account was deleted.'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(keysOf(me), isEmpty);
    phone.sync.dispose();
    olgaPhone.sync.dispose();
  });

  testWidgets('a failure shows why, with Try again', (tester) async {
    await tester.runAsync(fill);
    phone.shares.failDeleteAccount = ShareApiException(500, 'Internal error');
    await tester.pumpWidget(
      TabCamApp(library: phone.library, auth: phone.auth, sync: phone.sync),
    );
    await tester.tap(find.text('Profile'));
    await settle(tester);
    await tester.ensureVisible(find.text('Delete account'));
    await tester.tap(find.text('Delete account'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-delete-account')));
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (find.text('Account not deleted').evaluate().isNotEmpty) break;
    }
    await settle(tester);
    expect(find.text('Account not deleted'), findsOneWidget);
    expect(find.textContaining('Internal error'), findsOneWidget);
    expect(phone.auth.user, isNotNull);

    await tester.tap(find.text('Try again'));
    await tester.runAsync(() async {
      while (phone.auth.user != null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await settle(tester);
    expect(find.text('Your TabCam account was deleted.'), findsOneWidget);
    phone.sync.dispose();
    olgaPhone.sync.dispose();
  });
}
