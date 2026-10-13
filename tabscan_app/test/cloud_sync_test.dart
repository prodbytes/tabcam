import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabscan_app/cloud/cloud_sync.dart';
import 'package:tabscan_app/cloud/cognito.dart';
import 'package:tabscan_app/cloud/share_api.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/library/capture_event.dart';
import 'package:tabscan_app/library/event_store_memory.dart';

import 'fakes.dart';

/// One device: its library, signed in, syncing with [bucket].
class Device {
  Device(
    this.bucket, {
    String identity = 'us-east-1:me',
    ShareApi? shares,
    Duration period = const Duration(days: 1),
  }) : credentials = FakeCredentials(identity) {
    library = Library(PlatformEventStore(), () => now);
    sync = CloudSync(
      library: library,
      auth: auth,
      bucket: bucket,
      credentials: credentials,
      shares: shares,
      period: period,
      debounce: const Duration(days: 1),
    );
  }

  final FakeBucket bucket;
  final FakeCredentials credentials;
  final auth = FakeAuth();
  late final Library library;
  late final CloudSync sync;
  DateTime now = DateTime(2026, 10, 10, 12);

  Future<void> start() async {
    await library.load();
    sync.start();
    auth.signInAs('me');
    await settle();
  }

  /// Lets the pass that sign-in started finish.
  Future<void> settle() async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await sync.syncNow();
  }

  void later() => now = now.add(const Duration(minutes: 1));
}

Uint8List bytes(List<int> b) => Uint8List.fromList(b);

void main() {
  // Sync follows the app coming to the front, through the binding.
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeBucket bucket;
  setUp(() => bucket = FakeBucket());

  const folder = 'us-east-1:me/events';

  test("the periodic pass runs again after signing out and back in", () async {
    final phone = Device(bucket, period: const Duration(milliseconds: 20));
    await phone.start();
    await phone.auth.signOut();
    phone.auth.signInAs('me');
    await phone.settle();
    // The change waits for the debounce (a day): only the periodic pass
    // can take it up.
    final event = await phone.library.create([
      bytes([4, 5, 6]),
    ]);
    for (var i = 0; i < 50; i++) {
      if (bucket.objects.containsKey('$folder/${event.id}/event.json')) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(
      bucket.objects.containsKey('$folder/${event.id}/event.json'),
      isTrue,
    );
    phone.sync.dispose();
  });

  test(
    "an event goes up: its pages, then event.json, naming its owner",
    () async {
      final phone = Device(bucket);
      await phone.start();
      final event = await phone.library.create([
        bytes([1, 2, 3]),
      ]);
      await phone.sync.syncNow();

      final page = event.pages.single;
      expect(bucket.objects['$folder/${event.id}/${page.fileName}'], [1, 2, 3]);
      final json = bucket.json('$folder/${event.id}/event.json');
      expect(json['title'], event.title);
      expect(json['owner'], 'us-east-1:me');
      expect(
        bucket.requests.indexWhere((r) => r.endsWith(page.fileName)),
        lessThan(bucket.requests.indexWhere((r) => r.endsWith('event.json'))),
      );
      expect(phone.library.all.single.owner, 'us-east-1:me');
      expect(phone.sync.state, SyncState.synced);
    },
  );

  test('nothing changed: a pass is one listing', () async {
    final phone = Device(bucket);
    await phone.start();
    await phone.library.create([
      bytes([1]),
    ]);
    await phone.sync.syncNow();
    bucket.requests.clear();
    await phone.sync.syncNow();
    expect(bucket.requests, ['LIST $folder/']);
  });

  test("another device's events come down, pages and all", () async {
    final phone = Device(bucket);
    await phone.start();
    final event = await phone.library.create([
      bytes([1, 2]),
    ]);
    await phone.library.update(event.copyWith(tabText: 'e|--0--|'));
    await phone.sync.syncNow();

    final tablet = Device(bucket);
    await tablet.start();
    final copy = tablet.library.events.single;
    expect(copy.id, event.id);
    expect(copy.tabText, 'e|--0--|');
    expect(copy.owner, 'us-east-1:me');
    expect(await tablet.library.original(copy, copy.pages.single), [1, 2]);
    // What came down doesn't go back up.
    bucket.requests.clear();
    await tablet.sync.syncNow();
    expect(bucket.requests, ['LIST $folder/']);
  });

  test('a change on one device reaches the other', () async {
    final phone = Device(bucket);
    final tablet = Device(bucket);
    await phone.start();
    final event = await phone.library.create([
      bytes([1]),
    ]);
    await phone.sync.syncNow();
    await tablet.start();

    phone.later();
    await phone.library.update(
      phone.library.byId(event.id)!.copyWith(title: 'Riff in A'),
    );
    await phone.sync.syncNow();
    await tablet.sync.syncNow();
    expect(tablet.library.byId(event.id)!.title, 'Riff in A');
  });

  test('a file renamed on one device reaches the other as it comes to '
      'the front', () async {
    final phone = Device(bucket);
    final tablet = Device(bucket);
    await phone.start();
    final event = await phone.library.create([
      bytes([1]),
    ]);
    await phone.sync.syncNow();
    await tablet.start();
    tablet.sync.didChangeAppLifecycleState(AppLifecycleState.hidden);

    phone.later();
    final page = phone.library.byId(event.id)!.pages.single;
    await phone.library.update(
      phone.library
          .byId(event.id)!
          .copyWith(pages: [page.copyWith(title: () => 'Tablature')]),
    );
    await phone.sync.syncNow();
    // No pass of the tablet's own: back in front, it looks at once.
    tablet.sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tablet.settle();
    expect(tablet.library.byId(event.id)!.pages.single.title, 'Tablature');
  });

  test('in front, a device looks for changes every few seconds', () {
    final device = Device(bucket);
    final sync = CloudSync(
      library: device.library,
      auth: device.auth,
      bucket: bucket,
      credentials: device.credentials,
    );
    expect(sync.period, lessThanOrEqualTo(const Duration(seconds: 10)));
    expect(sync.backgroundPeriod, greaterThan(sync.period));
  });

  test('changed on both: the later change wins', () async {
    final phone = Device(bucket);
    final tablet = Device(bucket);
    await phone.start();
    final event = await phone.library.create([
      bytes([1]),
    ]);
    await phone.sync.syncNow();
    await tablet.start();

    phone.later();
    await phone.library.update(
      phone.library.byId(event.id)!.copyWith(title: 'Phone'),
    );
    tablet.now = phone.now.add(const Duration(minutes: 1));
    await tablet.library.update(
      tablet.library.byId(event.id)!.copyWith(title: 'Tablet'),
    );
    await phone.sync.syncNow();
    await tablet.sync.syncNow(); // newer: goes up over the phone's
    await phone.sync.syncNow();
    expect(phone.library.byId(event.id)!.title, 'Tablet');
    expect(tablet.library.byId(event.id)!.title, 'Tablet');
  });

  test('pages removed or rotated are removed from the folder too', () async {
    final phone = Device(bucket);
    final tablet = Device(bucket);
    await phone.start();
    var event = await phone.library.create([
      bytes([1]),
      bytes([2]),
    ]);
    await phone.sync.syncNow();
    await tablet.start();
    final gone = event.pages.first;
    phone.later();
    event = await phone.library.deletePage(phone.library.byId(event.id)!, gone);
    await phone.sync.syncNow();
    expect(
      bucket.objects.containsKey('$folder/${event.id}/${gone.fileName}'),
      isFalse,
    );
    await tablet.sync.syncNow();
    final copy = tablet.library.byId(event.id)!;
    expect(copy.pages.map((p) => p.id), [event.pages.single.id]);
    expect(await tablet.library.hasPage(event.id, gone), isFalse);
  });

  test('a deletion reaches the other devices', () async {
    final phone = Device(bucket);
    final tablet = Device(bucket);
    await phone.start();
    final event = await phone.library.create([
      bytes([1]),
    ]);
    await phone.sync.syncNow();
    await tablet.start();
    expect(tablet.library.events, hasLength(1));

    phone.later();
    await phone.library.delete(phone.library.byId(event.id)!);
    await phone.sync.syncNow();
    final keys = bucket.objects.keys.toList();
    expect(keys, ['$folder/${event.id}/event.json']);
    expect(bucket.json(keys.single)['deleted'], isNotNull);

    await tablet.sync.syncNow();
    expect(tablet.library.events, isEmpty);
    expect(await tablet.library.hasPage(event.id, event.pages.single), isFalse);

    // A new device doesn't get the deleted event at all.
    final laptop = Device(bucket);
    await laptop.start();
    expect(laptop.library.all, isEmpty);
  });

  test("another account's events stay on the device, unsynced", () async {
    final phone = Device(bucket);
    await phone.start();
    await phone.library.create([
      bytes([1]),
    ]);
    await phone.sync.syncNow();
    await phone.library.setOwner(phone.library.all.single, 'us-east-1:other');
    bucket.objects.clear();
    phone.later();
    await phone.library.update(phone.library.all.single.copyWith(title: 'X'));
    await phone.sync.syncNow();
    expect(bucket.objects, isEmpty);
  });

  test('expired credentials are renewed once, and the pass goes on', () async {
    final phone = Device(bucket);
    await phone.start();
    await phone.library.create([
      bytes([1]),
    ]);
    bucket.failNext = 1;
    await phone.sync.syncNow();
    expect(phone.credentials.clears, greaterThanOrEqualTo(1));
    expect(phone.sync.state, SyncState.synced);
    expect(bucket.objects, hasLength(2));
  });

  test('a rejected Google token asks to sign in again', () async {
    final phone = Device(bucket);
    phone.credentials.error = CognitoException(
      'NotAuthorizedException',
      'Token expired',
    );
    await phone.start();
    expect(phone.sync.state, SyncState.failed);
    expect(phone.sync.message, 'Sign in again to sync');
  });

  test('signed out, nothing syncs', () async {
    final phone = Device(bucket);
    await phone.start();
    await phone.auth.signOut();
    await phone.library.create([
      bytes([1]),
    ]);
    await phone.sync.syncNow();
    expect(bucket.objects, isEmpty);
    expect(phone.sync.state, SyncState.signedOut);
  });

  test('links sync as part of event.json, with no file', () async {
    final phone = Device(bucket);
    final tablet = Device(bucket);
    await phone.start();
    var event = await phone.library.create([
      bytes([1]),
    ]);
    event = await phone.library.addLink(
      event,
      Uri.parse('https://example.com/lesson'),
      title: 'Lesson',
    );
    await phone.sync.syncNow();
    // The page's file and event.json: nothing for the link.
    expect(bucket.objects, hasLength(2));
    await tablet.start();
    final link = tablet.library.events.single.pages.last;
    expect(link.isLink, isTrue);
    expect(link.title, 'Lesson');
    expect(link.url.toString(), 'https://example.com/lesson');
  });

  test('pages are uploaded with their type', () {
    expect(CloudSync.contentTypeOf(const EventPage(id: 'a')), 'image/jpeg');
    expect(
      CloudSync.contentTypeOf(
        const EventPage(id: 'a', kind: PageKind.video, extension: 'mp4'),
      ),
      'video/mp4',
    );
  });

  group('shared captures', () {
    const owner = 'us-east-1:owner';
    const ana = 'us-east-1:ana';
    late Map<String, Map<String, ShareRole>> grants;
    late Device julio;
    late Device anaPhone;

    setUp(() async {
      grants = {};
      julio = Device(
        bucket,
        identity: owner,
        shares: FakeShareApi(
          grants,
          email: 'julio@example.com',
          identity: owner,
        ),
      );
      anaPhone = Device(
        bucket,
        identity: ana,
        shares: FakeShareApi(grants, email: 'ana@example.com', identity: ana),
      );
      await julio.start();
      await anaPhone.start();
    });

    Future<CaptureEvent> shareOne(ShareRole role) async {
      final event = await julio.library.create([
        bytes([1, 2]),
      ]);
      await julio.sync.syncNow();
      await julio.sync.grant(
        julio.library.byId(event.id)!,
        'ana@example.com',
        role,
      );
      await julio.sync.syncNow();
      await anaPhone.sync.syncNow();
      return julio.library.byId(event.id)!;
    }

    test('the owner records the shares on the event, which syncs', () async {
      final created = await julio.library.create([
        bytes([1, 2]),
      ]);
      await julio.sync.syncNow();
      julio.now = julio.now.add(const Duration(minutes: 1));
      await julio.sync.grant(
        julio.library.byId(created.id)!,
        'ana@example.com',
        ShareRole.read,
      );
      // grant started the pass that sends the shares.
      while (julio.sync.state == SyncState.syncing) {
        await Future<void>.delayed(Duration.zero);
      }
      final event = julio.library.byId(created.id)!;
      expect(event.shares, [
        const EventShare('ana@example.com', readOnly: true),
      ]);
      final json = bucket.json('$owner/events/${event.id}/event.json');
      expect(json['owner'], owner);
      expect(json['shares'], [
        {'email': 'ana@example.com', 'role': 'read'},
      ]);
      await anaPhone.sync.syncNow();
      expect(anaPhone.library.byId(event.id)!.shares, event.shares);

      await julio.sync.revoke(event, 'ana@example.com');
      expect(julio.library.byId(event.id)!.shares, isEmpty);
    });

    test('a capture shared to edit comes down, and edits go back', () async {
      final event = await shareOne(ShareRole.edit);
      final copy = anaPhone.library.byId(event.id)!;
      expect(copy.sharedBy, 'julio@example.com');
      expect(copy.readOnly, isFalse);
      expect(copy.owner, owner);
      expect(await anaPhone.library.original(copy, copy.pages.single), [1, 2]);

      anaPhone.now = julio.now.add(const Duration(minutes: 5));
      await anaPhone.library.update(copy.copyWith(title: 'Riff, by Ana'));
      await anaPhone.sync.syncNow();
      expect(
        bucket.json('$owner/events/${event.id}/event.json')['title'],
        'Riff, by Ana',
      );
      // Sharing stays on Ana's device: the cloud copy doesn't say.
      expect(
        bucket.json('$owner/events/${event.id}/event.json'),
        isNot(contains('sharedBy')),
      );
      await julio.sync.syncNow();
      expect(julio.library.byId(event.id)!.title, 'Riff, by Ana');
      expect(julio.library.byId(event.id)!.isShared, isFalse);
    });

    test('read only: it comes down, and nothing goes up', () async {
      final event = await shareOne(ShareRole.read);
      final copy = anaPhone.library.byId(event.id)!;
      expect(copy.readOnly, isTrue);
      final before = Map.of(bucket.objects);
      anaPhone.later();
      await anaPhone.library.update(copy.copyWith(title: 'Mine now'));
      bucket.requests.clear();
      await anaPhone.sync.syncNow();
      expect(bucket.requests.where((r) => r.startsWith('PUT')), isEmpty);
      expect(bucket.objects.keys, before.keys);
    });

    test("Ana's own events don't go to Julio's folder", () async {
      await shareOne(ShareRole.edit);
      await anaPhone.library.create([
        bytes([9]),
      ]);
      await anaPhone.sync.syncNow();
      expect(
        bucket.objects.keys.where((k) => k.startsWith('$ana/')),
        hasLength(2),
      );
      expect(
        bucket.objects.keys.where((k) => k.startsWith('$owner/')),
        hasLength(2),
      );
    });

    test(
      'revoked, it goes from her device; shared again, it comes back',
      () async {
        final event = await shareOne(ShareRole.edit);
        await julio.sync.revoke(event, 'ana@example.com');
        await anaPhone.sync.syncNow();
        expect(anaPhone.library.byIdAll(event.id), isNull);
        // Julio's stays.
        expect(julio.library.byId(event.id), isNotNull);
        expect(
          bucket.objects.containsKey('$owner/events/${event.id}/event.json'),
          isTrue,
        );

        await julio.sync.grant(event, 'ana@example.com', ShareRole.read);
        await anaPhone.sync.syncNow();
        expect(anaPhone.library.byId(event.id)!.readOnly, isTrue);
      },
    );

    test('Ana removes it: she leaves the share', () async {
      final event = await shareOne(ShareRole.edit);
      await anaPhone.sync.leave(anaPhone.library.byId(event.id)!);
      expect(anaPhone.library.byIdAll(event.id), isNull);
      expect(grants['$owner/${event.id}'], isEmpty);
      await anaPhone.sync.syncNow();
      expect(anaPhone.library.byIdAll(event.id), isNull);
      expect(julio.library.byId(event.id), isNotNull);
    });

    test('the owner deletes it: it goes from her device too', () async {
      final event = await shareOne(ShareRole.edit);
      julio.later();
      await julio.library.delete(event);
      await julio.sync.syncNow();
      await anaPhone.sync.syncNow();
      expect(anaPhone.library.events, isEmpty);
      expect(grants['$owner/${event.id}'], isEmpty);
    });

    test('a role change reaches her copy', () async {
      final event = await shareOne(ShareRole.edit);
      await julio.sync.grant(event, 'ana@example.com', ShareRole.read);
      await anaPhone.sync.syncNow();
      expect(anaPhone.library.byId(event.id)!.readOnly, isTrue);
    });

    test('a clone of a shared capture is her own, to share apart', () async {
      final event = await shareOne(ShareRole.read);
      final copy = await anaPhone.library.clone(
        anaPhone.library.byId(event.id)!,
      );
      expect(copy.isShared, isFalse);
      expect(copy.readOnly, isFalse);
      await anaPhone.sync.syncNow();
      expect(
        bucket.objects.containsKey('$ana/events/${copy.id}/event.json'),
        isTrue,
      );
    });
  });
}
