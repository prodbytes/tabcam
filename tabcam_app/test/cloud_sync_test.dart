import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/media.dart';
import 'package:tabcam_app/cloud/cloud_sync.dart';
import 'package:tabcam_app/cloud/cognito.dart';
import 'package:tabcam_app/cloud/share_api.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';

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

  test('a new device lists the captures first, their files after', () async {
    final phone = Device(bucket);
    await phone.start();
    for (var i = 0; i < 3; i++) {
      phone.later();
      await phone.library.create([
        bytes([i, i]),
      ]);
    }
    await phone.sync.syncNow();

    final hold = bucket.holdFiles = Completer<void>();
    final tablet = Device(bucket);
    await tablet.start();
    // Listed at once, every file still loading.
    final events = tablet.library.events;
    expect(events, hasLength(3));
    for (final e in events) {
      expect(tablet.library.isArriving(e.id, e.pages.single), isTrue);
    }
    // What needs a file waits for it.
    final first = events.first;
    var got = <int>[];
    final waiting = tablet.library
        .original(first, first.pages.single)
        .then((b) => got = b);
    await Future<void>.delayed(Duration.zero);
    expect(got, isEmpty);

    hold.complete();
    await waiting;
    await tablet.settle();
    for (final e in tablet.library.events) {
      expect(tablet.library.isArriving(e.id, e.pages.single), isFalse);
    }
    expect(got, isNotEmpty);
  });

  test('a file that failed to come is asked for again', () async {
    final phone = Device(bucket);
    await phone.start();
    await phone.library.create([
      bytes([4, 2]),
    ]);
    await phone.sync.syncNow();

    bucket.failFiles = 1;
    final tablet = Device(bucket);
    await tablet.start();
    final copy = tablet.library.events.single;
    expect(tablet.library.isArriving(copy.id, copy.pages.single), isTrue);
    // The next pass asks again.
    await tablet.sync.syncNow();
    await tablet.settle();
    expect(tablet.library.isArriving(copy.id, copy.pages.single), isFalse);
    expect(await tablet.library.original(copy, copy.pages.single), [4, 2]);
  });

  test('pictures come before videos', () async {
    final phone = Device(bucket);
    await phone.start();
    var event = await phone.library.create(const []);
    event = await phone.library.addMedia(event, [
      Media(
        XFile.fromData(bytes([9]), path: 'riff.mp4'),
        PageKind.video,
        'mp4',
      ),
    ]);
    await phone.library.addPages(event, [
      bytes([1]),
    ]);
    await phone.sync.syncNow();

    bucket.requests.clear();
    final tablet = Device(bucket);
    await tablet.start();
    final files = [
      for (final r in bucket.requests)
        if (r.startsWith('GET') && !r.endsWith('event.json')) r,
    ];
    expect(files, hasLength(2));
    expect(files.first, isNot(endsWith('.mp4')));
    expect(files.last, endsWith('.mp4'));
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

  test('in front, a device looks for changes every 5 minutes', () {
    final device = Device(bucket);
    final sync = CloudSync(
      library: device.library,
      auth: device.auth,
      bucket: bucket,
      credentials: device.credentials,
    );
    expect(sync.period, const Duration(minutes: 5));
  });

  test('contributions are listed only when a capture can have them', () async {
    final phone = Device(
      bucket,
      shares: FakeShareApi(
        {},
        email: 'me@example.com',
        identity: 'us-east-1:me',
      ),
    );
    await phone.start();
    final event = await phone.library.create(const []);
    await phone.settle();
    expect(bucket.requests, isNot(contains('LIST us-east-1:me/contrib/')));

    // Shared by its link: people may add to it, so it's listed.
    await phone.library.patch(
      event.id,
      (e) => e.copyWith(linkKey: newLinkKey()),
    );
    bucket.requests.clear();
    await phone.settle();
    expect(bucket.requests, contains('LIST us-east-1:me/contrib/'));
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

  // The teacher shares a capture; students see the teacher's files, add
  // their own, and never see each other's; the teacher sees them all and
  // publishes the ones they like.
  group('contributions', () {
    const teacher = 'us-east-1:teacher';
    const ana = 'us-east-1:ana';
    const bo = 'us-east-1:bo';
    late Map<String, Map<String, ShareRole>> grants;
    late Device julio;
    late Device anaPhone;
    late Device boPhone;
    late CaptureEvent lesson;

    Device device(String identity, String email) => Device(
      bucket,
      identity: identity,
      shares: FakeShareApi(grants, email: email, identity: identity),
    );

    setUp(() async {
      grants = {};
      FakeShareApi.identities.clear();
      julio = device(teacher, 'julio@example.com');
      anaPhone = device(ana, 'ana@example.com');
      boPhone = device(bo, 'bo@example.com');
      for (final d in [julio, anaPhone, boPhone]) {
        await d.start();
      }
      lesson = await julio.library.create([
        bytes([1, 2]),
      ]);
      await julio.sync.syncNow();
      for (final email in ['ana@example.com', 'bo@example.com']) {
        await julio.sync.grant(
          julio.library.byId(lesson.id)!,
          email,
          ShareRole.read,
        );
      }
      await julio.sync.syncNow();
      await anaPhone.sync.syncNow();
      await boPhone.sync.syncNow();
    });

    Future<CaptureEvent> anaAddsATake() async {
      final copy = anaPhone.library.byId(lesson.id)!;
      expect(copy.contributes, isTrue);
      anaPhone.later();
      await anaPhone.library.addMedia(copy, [
        Media(
          XFile.fromData(bytes([7, 7, 7]), name: 'take.mp4'),
          PageKind.video,
          'mp4',
        ),
      ]);
      final now = anaPhone.library.byId(lesson.id)!;
      await anaPhone.library.addLink(
        now,
        Uri.parse('https://example.com/ana-cover'),
      );
      await anaPhone.sync.syncNow();
      return anaPhone.library.byId(lesson.id)!;
    }

    test("a student's files go to their own folder, not the capture", () async {
      final before = bucket.json('$teacher/events/${lesson.id}/event.json');
      final copy = await anaAddsATake();
      expect(copy.pages, hasLength(1));
      final mine = copy.myContribution!;
      expect(mine.by, ana);
      expect(mine.pages, hasLength(2));
      final folder = '$teacher/contrib/${lesson.id}/$ana/';
      expect(bucket.objects.keys.where((k) => k.startsWith(folder)).toSet(), {
        '${folder}contrib.json',
        '$folder${mine.pages.first.fileName}',
      });
      // Whose it is is its folder's name: the cloud copy doesn't say.
      expect(bucket.json('${folder}contrib.json'), isNot(contains('by')));
      expect(bucket.json('$teacher/events/${lesson.id}/event.json'), before);
    });

    test("students never see each other's files", () async {
      await anaAddsATake();
      bucket.requests.clear();
      await boPhone.sync.syncNow();
      expect(boPhone.library.byId(lesson.id)!.contributions, isEmpty);
      // Bo's device never asks for anything of Ana's.
      expect(bucket.requests.where((r) => r.contains(ana)), isEmpty);
    });

    test('the teacher sees every student\'s files, by name', () async {
      final copy = await anaAddsATake();
      boPhone.later();
      await boPhone.library.addLink(
        boPhone.library.byId(lesson.id)!,
        Uri.parse('https://example.com/bo-cover'),
      );
      await boPhone.sync.syncNow();
      await julio.sync.syncNow();
      final event = julio.library.byId(lesson.id)!;
      expect(
        {for (final c in event.contributions) c.by: c.email},
        {ana: 'ana@example.com', bo: 'bo@example.com'},
      );
      final take = copy.myContribution!.pages.first;
      expect(await julio.library.original(event, take), [7, 7, 7]);
      // Nothing of theirs is the capture's until it's published.
      expect(event.pages, hasLength(1));
    });

    test('the teacher publishes a file: everyone sees it', () async {
      final copy = await anaAddsATake();
      await julio.sync.syncNow();
      final take = copy.myContribution!.pages.first;
      final event = julio.library.byId(lesson.id)!;
      final theirs = event.contributions.single.pages.first;
      await julio.library.original(event, theirs);
      julio.later();
      await julio.library.publish(event, theirs);
      expect(julio.library.byId(lesson.id)!.isPublished(theirs), isTrue);
      await julio.sync.syncNow();
      // A copy in the capture's own folder, so its link's holders see it.
      final published = julio.library.byId(lesson.id)!.pages.last;
      expect(published.from, take.id);
      expect(published.id, isNot(take.id));
      final copied = '$teacher/events/${lesson.id}/${published.fileName}';
      expect(bucket.objects[copied], [7, 7, 7]);
      await boPhone.sync.syncNow();
      final bos = boPhone.library.byId(lesson.id)!;
      expect(bos.pages.last.from, take.id);
      expect(await boPhone.library.original(bos, bos.pages.last), [7, 7, 7]);
      expect(bos.contributions, isEmpty);
      // Ana sees it's published.
      await anaPhone.sync.syncNow();
      expect(anaPhone.library.byId(lesson.id)!.isPublished(take), isTrue);

      // Taken back, it's Ana's alone again; her file stays with her.
      julio.later();
      await julio.library.unpublish(julio.library.byId(lesson.id)!, theirs);
      await julio.sync.syncNow();
      final after = julio.library.byId(lesson.id)!;
      expect(after.isPublished(theirs), isFalse);
      expect(await julio.library.original(after, theirs), [7, 7, 7]);
      await anaPhone.sync.syncNow();
      final anas = anaPhone.library.byId(lesson.id)!;
      expect(await anaPhone.library.original(anas, take), [7, 7, 7]);
    });

    test('a student deletes a file: it goes from the teacher too', () async {
      final copy = await anaAddsATake();
      await julio.sync.syncNow();
      final link = copy.myContribution!.pages.last;
      anaPhone.later();
      await anaPhone.library.deleteContributionPage(copy, link);
      await anaPhone.sync.syncNow();
      await julio.sync.syncNow();
      expect(
        julio.library.byId(lesson.id)!.contributions.single.pages,
        hasLength(1),
      );
    });

    test("a student's files reach their other devices", () async {
      await anaAddsATake();
      final tablet = device(ana, 'ana@example.com');
      await tablet.start();
      final copy = tablet.library.byId(lesson.id)!;
      expect(copy.myContribution?.pages, hasLength(2));
      expect(
        await tablet.library.original(copy, copy.myContribution!.pages.first),
        [7, 7, 7],
      );
    });

    test("a contribution can't pass a page off as the capture's", () async {
      final folder = '$teacher/contrib/${lesson.id}/$ana/';
      final own = julio.library.byId(lesson.id)!.pages.single;
      bucket.objects['${folder}contrib.json'] = bytes(
        utf8.encode(
          jsonEncode({
            'updated': '2026-10-16T12:00:00Z',
            'pages': [
              own.toJson(),
              {'id': 'fake1', 'kind': 'link', 'url': 'https://example.com/x'},
            ],
          }),
        ),
      );
      await julio.sync.syncNow();
      final event = julio.library.byId(lesson.id)!;
      final theirs = event.contributions.single.pages;
      expect(theirs.map((p) => p.id), ['fake1']);
      expect(event.isPublished(theirs.single), isFalse);
    });

    test('signed in, opening the link joins it as a student', () async {
      const key = 'riffkey-0123456789abcdefghijklmnopqrstu';
      FakeShareApi.links[key] = '$teacher/${lesson.id}';
      final kim = device('us-east-1:kim', 'kim@example.com');
      await kim.start();
      expect(kim.library.byId(lesson.id), isNull);
      expect(await kim.sync.joinLink(lesson.id, key), isTrue);
      await kim.sync.syncNow();
      final copy = kim.library.byId(lesson.id)!;
      expect(copy.contributes, isTrue);
      expect(copy.sharedBy, 'julio@example.com');
      // The teacher's own link joins nothing.
      expect(await julio.sync.joinLink(lesson.id, key), isFalse);
    });
  });
}
