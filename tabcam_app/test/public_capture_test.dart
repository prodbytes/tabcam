import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/cloud/cloud_sync.dart';
import 'package:tabcam_app/cloud/public_capture.dart';
import 'package:tabcam_app/export/capture_link.dart';
import 'package:tabcam_app/export/incoming_links.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/main.dart';
import 'package:tabcam_app/screens/public_capture_screen.dart';

import 'fakes.dart';

const owner = 'us-east-1:00000000-0000-0000-0000-00000000000a';
const riff = 'e|--3--5--7--|\nB|--------8--|';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late FakeBucket bucket;
  late Uri link;
  late String id;

  /// The owner's device: a capture with a page and a tab, its link copied
  /// (a key, recorded) and synced to the cloud.
  Future<void> ownerShares() async {
    bucket = FakeBucket();
    final library = Library(PlatformEventStore(), null, (_) async => null);
    await library.load();
    final auth = FakeAuth()..signInAs('julio');
    final api = FakeShareApi({}, email: 'julio@example.com', identity: owner);
    final sync = CloudSync(
      library: library,
      auth: auth,
      bucket: bucket,
      credentials: FakeCredentials(owner),
      shares: api,
      period: const Duration(days: 1),
    );
    final made = await library.create([
      img.encodeJpg(img.Image(width: 8, height: 8)),
    ]);
    id = made.id;
    final keyed = await library.patch(
      id,
      (e) => e.copyWith(tabText: riff, linkKey: newLinkKey()),
    );
    sync.start(); // signed in: a pass starts
    while (sync.state != SyncState.synced) {
      expect(sync.state, isNot(SyncState.failed));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(bucket.objects.keys, contains('$owner/events/$id/event.json'));
    await sync.publishLink(keyed!);
    link = CaptureLink.of(keyed);
    sync.dispose();
  }

  PublicCaptures captures() => PublicCaptures(
    api: FakeShareApi({}, email: 'nobody@example.com'),
    bucket: bucket,
  );

  tearDown(() => IncomingLinks.instance.take());

  test('a link with its key brings the capture, read only', () async {
    await ownerShares();
    expect(PublicCaptures.opens(link), isTrue);
    final library = Library(PlatformEventStore());
    await library.load();
    final event = await captures().open(link, library);
    expect(event.id, id);
    expect(event.readOnly, isTrue);
    expect(event.isShared, isFalse);
    expect(event.tabText, riff);
    expect(event.owner, owner);
    expect(await library.hasPage(id, event.pages.single), isTrue);
    // Its Share copies the same link.
    expect(CaptureLink.of(library.byId(id)!), link);
  });

  test(
    'refreshing brings the owner\'s rename, and nothing when unchanged',
    () async {
      await ownerShares();
      final library = Library(PlatformEventStore());
      await library.load();
      final opened = captures();
      await opened.open(link, library);
      expect(await opened.refresh(link, library), isNull);

      // The owner renames the file; their device syncs it up.
      final key = '$owner/events/$id/event.json';
      final json = (jsonDecode(utf8.decode(bucket.objects[key]!)) as Map)
          .cast<String, Object?>();
      final renamed = CaptureEvent.fromJson(json);
      bucket.objects[key] = utf8.encode(
        jsonEncode(
          renamed
              .copyWith(
                pages: [
                  renamed.pages.single.copyWith(title: () => 'Tablature'),
                ],
              )
              .toJson(local: false),
        ),
      );

      final event = await opened.refresh(link, library);
      expect(event?.pages.single.title, 'Tablature');
      expect(library.byId(id)!.pages.single.title, 'Tablature');
      expect(library.byId(id)!.readOnly, isTrue);
      expect(await opened.refresh(link, library), isNull);
    },
  );

  test('a wrong key, or none, opens nothing', () async {
    await ownerShares();
    final library = Library(PlatformEventStore());
    await library.load();
    final wrong = link.replace(queryParameters: {'c': id, 'k': newLinkKey()});
    await expectLater(
      captures().open(wrong, library),
      throwsA(isA<LinkUnavailable>()),
    );
    final bare = link.replace(queryParameters: {'c': id});
    expect(PublicCaptures.opens(bare), isFalse);
    expect(library.all, isEmpty);
  });

  testWidgets('signed out, the link opens the capture instead of the welcome', (
    tester,
  ) async {
    await tester.runAsync(ownerShares);
    final mine = Library(PlatformEventStore());
    await tester.runAsync(mine.load);
    await IncomingLinks.instance.didPushRouteInformation(
      RouteInformation(uri: link),
    );
    await tester.pumpWidget(
      TabCamApp(library: mine, auth: FakeAuth(), captures: captures()),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await frames(tester);
    expect(find.byKey(const Key('welcome')), findsNothing);
    expect(find.byKey(const Key('link-banner')), findsOneWidget);
    expect(find.text('Opened by its link · Read only'), findsOneWidget);
    // Read only, and not theirs to clone.
    expect(find.byTooltip('Rename'), findsNothing);
    expect(find.byTooltip('Clone'), findsNothing);
    expect(find.byTooltip('Share'), findsOneWidget);
    await tester.tap(find.byKey(const Key('text')));
    await frames(tester);
    expect(
      find.textContaining('--3--5--7--', findRichText: true),
      findsWidgets,
    );
    // Nothing of it in the user's own library.
    expect(mine.all, isEmpty);

    await tester.tap(find.text('Sign in'));
    await frames(tester);
    expect(find.byKey(const Key('welcome')), findsOneWidget);
    // Still waiting: once signed in, Home opens it.
    expect(IncomingLinks.instance.pending, link);
  });

  testWidgets('a wrong key says so, signed out', (tester) async {
    await tester.runAsync(ownerShares);
    final mine = Library(PlatformEventStore());
    await tester.runAsync(mine.load);
    await IncomingLinks.instance.didPushRouteInformation(
      RouteInformation(
        uri: link.replace(queryParameters: {'c': id, 'k': newLinkKey()}),
      ),
    );
    await tester.pumpWidget(
      TabCamApp(library: mine, auth: FakeAuth(), captures: captures()),
    );
    await frames(tester);
    expect(find.byType(PublicCaptureScreen), findsOneWidget);
    expect(find.textContaining("can't be opened"), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    await frames(tester);
    expect(find.byKey(const Key('welcome')), findsOneWidget);
  });

  testWidgets('signed in, not shared with them: the link opens it read only', (
    tester,
  ) async {
    await tester.runAsync(ownerShares);
    final mine = Library(PlatformEventStore(), null, (_) async => null);
    await tester.runAsync(mine.load);
    final auth = FakeAuth();
    final sync = CloudSync(
      library: mine,
      auth: auth,
      bucket: bucket,
      credentials: FakeCredentials('us-east-1:ana'),
      shares: FakeShareApi({}, email: 'ana@example.com', identity: 'ana'),
      period: const Duration(days: 1),
    );
    addTearDown(sync.dispose);
    await tester.runAsync(() async {
      sync.start();
      auth.signInAs('ana');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await IncomingLinks.instance.didPushRouteInformation(
      RouteInformation(uri: link),
    );
    await tester.pumpWidget(
      TabCamApp(library: mine, auth: auth, sync: sync, captures: captures()),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await frames(tester);
    }
    expect(find.byType(PublicCaptureScreen), findsOneWidget);
    expect(find.byKey(const Key('link-banner')), findsOneWidget);
    // Signed in: no Sign in, and Back goes Home.
    expect(find.text('Sign in'), findsNothing);
    expect(mine.all, isEmpty);
    await tester.pageBack();
    await frames(tester);
    expect(find.byType(PublicCaptureScreen), findsNothing);
  });
}
