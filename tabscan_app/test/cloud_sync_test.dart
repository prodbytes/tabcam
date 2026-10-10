import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabscan_app/cloud/cloud_sync.dart';
import 'package:tabscan_app/cloud/cognito.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/library/scan.dart';
import 'package:tabscan_app/library/scan_store_memory.dart';

import 'fakes.dart';

/// One device: its library, signed in, syncing with [bucket].
class Device {
  Device(this.bucket, {String identity = 'us-east-1:me'})
    : credentials = FakeCredentials(identity) {
    library = Library(PlatformScanStore(), () => now);
    sync = CloudSync(
      library: library,
      auth: auth,
      bucket: bucket,
      credentials: credentials,
      period: const Duration(days: 1),
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
  late FakeBucket bucket;
  setUp(() => bucket = FakeBucket());

  const folder = 'us-east-1:me/scans';

  test("a scan goes up: its pages, then scan.json, without owner", () async {
    final phone = Device(bucket);
    await phone.start();
    final scan = await phone.library.create([
      bytes([1, 2, 3]),
    ]);
    await phone.sync.syncNow();

    final page = scan.pages.single;
    expect(bucket.objects['$folder/${scan.id}/${page.fileName}'], [1, 2, 3]);
    final json = bucket.json('$folder/${scan.id}/scan.json');
    expect(json['title'], scan.title);
    expect(json.containsKey('owner'), isFalse);
    expect(
      bucket.requests.indexWhere((r) => r.endsWith(page.fileName)),
      lessThan(bucket.requests.indexWhere((r) => r.endsWith('scan.json'))),
    );
    expect(phone.library.all.single.owner, 'us-east-1:me');
    expect(phone.sync.state, SyncState.synced);
  });

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

  test("another device's scans come down, pages and all", () async {
    final phone = Device(bucket);
    await phone.start();
    final scan = await phone.library.create([
      bytes([1, 2]),
    ]);
    await phone.library.update(scan.copyWith(tabText: 'e|--0--|'));
    await phone.sync.syncNow();

    final tablet = Device(bucket);
    await tablet.start();
    final copy = tablet.library.scans.single;
    expect(copy.id, scan.id);
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
    final scan = await phone.library.create([
      bytes([1]),
    ]);
    await phone.sync.syncNow();
    await tablet.start();

    phone.later();
    await phone.library.update(
      phone.library.byId(scan.id)!.copyWith(title: 'Riff in A'),
    );
    await phone.sync.syncNow();
    await tablet.sync.syncNow();
    expect(tablet.library.byId(scan.id)!.title, 'Riff in A');
  });

  test('changed on both: the later change wins', () async {
    final phone = Device(bucket);
    final tablet = Device(bucket);
    await phone.start();
    final scan = await phone.library.create([
      bytes([1]),
    ]);
    await phone.sync.syncNow();
    await tablet.start();

    phone.later();
    await phone.library.update(
      phone.library.byId(scan.id)!.copyWith(title: 'Phone'),
    );
    tablet.now = phone.now.add(const Duration(minutes: 1));
    await tablet.library.update(
      tablet.library.byId(scan.id)!.copyWith(title: 'Tablet'),
    );
    await phone.sync.syncNow();
    await tablet.sync.syncNow(); // newer: goes up over the phone's
    await phone.sync.syncNow();
    expect(phone.library.byId(scan.id)!.title, 'Tablet');
    expect(tablet.library.byId(scan.id)!.title, 'Tablet');
  });

  test('pages removed or rotated are removed from the folder too', () async {
    final phone = Device(bucket);
    final tablet = Device(bucket);
    await phone.start();
    var scan = await phone.library.create([
      bytes([1]),
      bytes([2]),
    ]);
    await phone.sync.syncNow();
    await tablet.start();
    final gone = scan.pages.first;
    phone.later();
    scan = await phone.library.deletePage(phone.library.byId(scan.id)!, gone);
    await phone.sync.syncNow();
    expect(
      bucket.objects.containsKey('$folder/${scan.id}/${gone.fileName}'),
      isFalse,
    );
    await tablet.sync.syncNow();
    final copy = tablet.library.byId(scan.id)!;
    expect(copy.pages.map((p) => p.id), [scan.pages.single.id]);
    expect(await tablet.library.hasPage(scan.id, gone), isFalse);
  });

  test('a deletion reaches the other devices', () async {
    final phone = Device(bucket);
    final tablet = Device(bucket);
    await phone.start();
    final scan = await phone.library.create([
      bytes([1]),
    ]);
    await phone.sync.syncNow();
    await tablet.start();
    expect(tablet.library.scans, hasLength(1));

    phone.later();
    await phone.library.delete(phone.library.byId(scan.id)!);
    await phone.sync.syncNow();
    final keys = bucket.objects.keys.toList();
    expect(keys, ['$folder/${scan.id}/scan.json']);
    expect(bucket.json(keys.single)['deleted'], isNotNull);

    await tablet.sync.syncNow();
    expect(tablet.library.scans, isEmpty);
    expect(await tablet.library.hasPage(scan.id, scan.pages.single), isFalse);

    // A new device doesn't get the deleted scan at all.
    final laptop = Device(bucket);
    await laptop.start();
    expect(laptop.library.all, isEmpty);
  });

  test("another account's scans stay on the device, unsynced", () async {
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

  test('pages are uploaded with their type', () {
    expect(CloudSync.contentTypeOf(const ScanPage(id: 'a')), 'image/jpeg');
    expect(
      CloudSync.contentTypeOf(
        const ScanPage(id: 'a', kind: PageKind.video, extension: 'mp4'),
      ),
      'video/mp4',
    );
  });
}
