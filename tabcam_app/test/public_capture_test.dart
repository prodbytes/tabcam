import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/auth/auth_service.dart';
import 'package:tabcam_app/cloud/cloud_sync.dart';
import 'package:tabcam_app/cloud/public_capture.dart';
import 'package:tabcam_app/cloud/share_api.dart';
import 'package:tabcam_app/dictionary/dictionary_sidebar.dart';
import 'package:tabcam_app/export/capture_link.dart';
import 'package:tabcam_app/export/incoming_links.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/library/meta_names.dart';
import 'package:tabcam_app/library/meta_storage.dart';
import 'package:tabcam_app/main.dart';
import 'package:tabcam_app/metronome/metronome.dart';
import 'package:tabcam_app/screens/event_screen.dart';
import 'package:tabcam_app/screens/file_screen.dart';
import 'package:tabcam_app/screens/keys_help.dart';
import 'package:tabcam_app/screens/public_capture_screen.dart';

import 'fakes.dart';

/// localStorage, as a map.
class _Storage implements MetaStorage {
  final Map<String, String> items = {};

  @override
  String? getItem(String key) => items[key];

  @override
  void setItem(String key, String value) => items[key] = value;
}

const owner = 'us-east-1:00000000-0000-0000-0000-00000000000a';
const riff = 'e|--3--5--7--|\nB|--------8--|';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// No Dictionary, Metronome or keys' help (the button, or its H key), nor
/// their sidebars: signed out, a link's capture has none.
void expectNoTools() {
  expect(find.byType(DictionaryButton), findsNothing);
  expect(find.byType(MetronomeButton), findsNothing);
  expect(find.byType(KeysHelpButton), findsNothing);
  expect(find.byType(DictionarySidebar), findsNothing);
  expect(find.byType(MetronomeSidebar), findsNothing);
}

void main() {
  late FakeBucket bucket;
  late Uri link;
  late String id;
  late String pageId;

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
    pageId = made.pages.single.id;
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
    link = CaptureLink.full(keyed);
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
    // Its Share copies the same link: the short one.
    expect(
      CaptureLink.of(library.byId(id)!).toString(),
      'https://tabs.cam/s/${CaptureLink.keyIn(link)}',
    );
  });

  test('a video\'s kept render comes with it; one not up yet is left out, '
      'and the capture opens all the same', () async {
    await ownerShares();
    final key = '$owner/events/$id/event.json';
    final event = CaptureEvent.fromJson(
      (jsonDecode(utf8.decode(bucket.objects[key]!)) as Map)
          .cast<String, Object?>(),
    );
    const video = EventPage(
      id: 'v1',
      kind: PageKind.video,
      extension: 'mp4',
      render: PageRender(id: 'r1', extension: 'mp4'),
    );
    const later = EventPage(
      id: 'v2',
      kind: PageKind.video,
      extension: 'mp4',
      render: PageRender(id: 'r2', extension: 'mp4'),
    );
    bucket.objects[key] = utf8.encode(
      jsonEncode(
        event
            .copyWith(pages: [...event.pages, video, later])
            .toJson(local: false),
      ),
    );
    bucket.objects['$owner/events/$id/v1.mp4'] = Uint8List.fromList([1, 2]);
    bucket.objects['$owner/events/$id/r1.mp4'] = Uint8List.fromList([9, 9]);
    bucket.objects['$owner/events/$id/v2.mp4'] = Uint8List.fromList([4]);
    final library = Library(PlatformEventStore());
    await library.load();
    final opened = await captures().open(link, library);
    expect(await library.original(opened, video.render!.file), [9, 9]);
    expect(await library.original(opened, opened.pages.last), [4]);
    expect(await library.hasPage(id, later.render!.file), isFalse);
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

  test('a capture its owner deleted (in their trash) opens nothing', () async {
    await ownerShares();
    final key = '$owner/events/$id/event.json';
    final json = (jsonDecode(utf8.decode(bucket.objects[key]!)) as Map)
        .cast<String, Object?>();
    bucket.objects[key] = utf8.encode(
      jsonEncode(
        CaptureEvent.fromJson(json)
            .copyWith(trashed: () => DateTime.utc(2026, 11, 15))
            .toJson(local: false),
      ),
    );
    final library = Library(PlatformEventStore());
    await library.load();
    await expectLater(
      captures().open(link, library),
      throwsA(isA<LinkUnavailable>()),
    );
  });

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
    // The dictionary left open (app-wide) before signing out: it doesn't
    // show here.
    DictionaryState.instance.toggle();
    addTearDown(DictionaryState.instance.clear);
    await IncomingLinks.instance.didPushRouteInformation(
      RouteInformation(uri: link),
    );
    final auth = FakeAuth();
    await tester.pumpWidget(
      TabCamApp(library: mine, auth: auth, captures: captures()),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await frames(tester);
    expect(find.byKey(const Key('welcome')), findsNothing);
    expect(find.byKey(const Key('link-banner')), findsOneWidget);
    expect(find.text('Opened by its link · Read only'), findsOneWidget);
    // The one-click sign-in, last in the app bar: signs in right here.
    final quick = find.byKey(const Key('quick-sign-in-google'));
    expect(
      find.descendant(of: find.byType(AppBar), matching: quick),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(quick).dx,
      greaterThan(tester.getTopLeft(find.byTooltip('Share')).dx),
    );
    await tester.tap(quick);
    expect(auth.signIns, [AuthProvider.google]);
    // Read only, and not theirs to clone.
    expect(find.byTooltip('Rename'), findsNothing);
    expect(find.byTooltip('Clone'), findsNothing);
    expect(find.byTooltip('Share'), findsOneWidget);
    // The tools are signed-in users'.
    expectNoTools();
    await tester.tap(find.byKey(const Key('text')));
    await frames(tester);
    expect(
      find.textContaining('--3--5--7--', findRichText: true),
      findsWidgets,
    );
    expectNoTools();
    // A phone's Text view: none in its More menu either.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await frames(tester);
    expectNoTools();
    await tester.tap(find.byKey(const Key('event-more')));
    await frames(tester);
    expect(find.byKey(const Key('more-share')), findsOneWidget);
    expect(find.byKey(const Key('more-dictionary')), findsNothing);
    expect(find.byKey(const Key('more-metronome')), findsNothing);
    await tester.tapAt(Offset.zero);
    await frames(tester);
    tester.view.reset();
    await frames(tester);
    // Nothing of it in the user's own library.
    expect(mine.all, isEmpty);

    await tester.tap(find.text('Sign in'));
    await frames(tester);
    expect(find.byKey(const Key('welcome')), findsOneWidget);
    // Still waiting: once signed in, Home opens it.
    expect(IncomingLinks.instance.pending, link);
  });

  testWidgets("the link's capture keeps its settings apart from the "
      "device's", (tester) async {
    // The device's settings, as the web keeps them (localStorage).
    final storage = _Storage()
      ..items['tabcam.meta.playalong'] = '{"countIn":true}';
    final before = PlatformEventStore.defaultStorage;
    PlatformEventStore.defaultStorage = () => storage;
    addTearDown(() => PlatformEventStore.defaultStorage = before);

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
    final opened = tester.widget<EventScreen>(find.byType(EventScreen)).library;
    expect(opened, isNot(same(mine)));
    await tester.runAsync(() async {
      // It neither reads the device's count-in nor changes it.
      expect(await opened.readMeta(MetaNames.playAlong), isNull);
      await opened.writeMeta(MetaNames.playAlong, '{"countIn":false}');
      expect(storage.items, {'tabcam.meta.playalong': '{"countIn":true}'});
      expect(await mine.readMeta(MetaNames.playAlong), '{"countIn":true}');
    });
  });

  testWidgets("signed out, a file's link opens that file over the capture", (
    tester,
  ) async {
    await tester.runAsync(ownerShares);
    final mine = Library(PlatformEventStore());
    await tester.runAsync(mine.load);
    final fileLink = link.replace(
      queryParameters: {...link.queryParameters, 'f': pageId},
    );
    await IncomingLinks.instance.didPushRouteInformation(
      RouteInformation(uri: fileLink),
    );
    await tester.pumpWidget(
      TabCamApp(library: mine, auth: FakeAuth(), captures: captures()),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await frames(tester);
    expect(find.byType(FileScreen), findsOneWidget);
    // Signed out: no tools, and none of the owner's (Rotate, Rename,
    // Delete); only the view, which changes what shows.
    expectNoTools();
    expect(find.byKey(const Key('view')), findsOneWidget);
    expect(find.byKey(const Key('rename-file')), findsNothing);
    expect(find.byType(EventTool), findsOneWidget);
    // The file's screen too has the one-click sign-in.
    expect(
      find.descendant(
        of: find.byType(FileScreen),
        matching: find.byKey(const Key('quick-sign-in')),
      ),
      findsOneWidget,
    );
    // Back: the capture's list, opened by its link.
    await tester.pageBack();
    await frames(tester);
    expect(find.byType(FileScreen), findsNothing);
    expect(find.byKey(const Key('link-banner')), findsOneWidget);
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
    expect(find.byKey(const Key('quick-sign-in')), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    await frames(tester);
    expect(find.byKey(const Key('welcome')), findsOneWidget);
  });

  testWidgets('a private capture\'s link says so, signed out and signed in', (
    tester,
  ) async {
    await tester.runAsync(ownerShares);
    FakeShareApi.visibilities['$owner/$id'] = CaptureVisibility.private;
    addTearDown(() => FakeShareApi.visibilities.remove('$owner/$id'));
    final mine = Library(PlatformEventStore());
    await tester.runAsync(mine.load);
    await IncomingLinks.instance.didPushRouteInformation(
      RouteInformation(uri: link),
    );
    await tester.pumpWidget(
      TabCamApp(library: mine, auth: FakeAuth(), captures: captures()),
    );
    await frames(tester);
    expect(find.byType(PublicCaptureScreen), findsOneWidget);
    expect(
      find.text('This capture is private: only its owner can open it.'),
      findsOneWidget,
    );
    // Its owner's choice: trying again won't open it.
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
  });

  /// Ana's device, signed in, opening the capture's link with [shares].
  Future<(Library, CloudSync)> anaOpens(
    WidgetTester tester,
    FakeShareApi shares,
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
      shares: shares,
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
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await frames(tester);
    }
    return (mine, sync);
  }

  testWidgets('signed in, a private capture\'s link joins nothing and says '
      'so', (tester) async {
    FakeShareApi.visibilities.clear();
    final shares = FakeShareApi({}, email: 'ana@example.com');
    // Made private before Ana opens it (the owner's ID is known once
    // ownerShares has run, inside anaOpens: so by the key's capture).
    final keyed = <String>{};
    shares.beforeJoin = (capture) {
      FakeShareApi.visibilities[capture] = CaptureVisibility.private;
      keyed.add(capture);
    };
    final (mine, _) = await anaOpens(tester, shares);
    addTearDown(() => keyed.forEach(FakeShareApi.visibilities.remove));
    expect(mine.byId(id), isNull);
    expect(
      find.text('This capture is private: only its owner can open it.'),
      findsOneWidget,
    );
  });

  testWidgets('signed in, not shared with them: the link joins it', (
    tester,
  ) async {
    final (mine, _) = await anaOpens(
      tester,
      FakeShareApi({}, email: 'ana@example.com', identity: 'us-east-1:ana'),
    );
    // In her library from then on, shared to see and add her own files.
    final joined = mine.byId(id)!;
    expect(joined.readOnly, isTrue);
    expect(find.byType(PublicCaptureScreen), findsNothing);
    expect(find.byKey(const Key('link-banner')), findsNothing);
    expect(find.textContaining('Read only'), findsOneWidget);
  });

  testWidgets("signed in, when joining fails: it opens by its link", (
    tester,
  ) async {
    final (mine, _) = await anaOpens(tester, _NoJoining());
    expect(find.byType(PublicCaptureScreen), findsOneWidget);
    expect(find.byKey(const Key('link-banner')), findsOneWidget);
    // Signed in: no Sign in, and Back goes Home.
    expect(find.text('Sign in'), findsNothing);
    expect(find.byKey(const Key('quick-sign-in')), findsNothing);
    expect(mine.all, isEmpty);
    // The tools are theirs; the owner's (Rename) aren't.
    expect(find.byType(DictionaryButton), findsOneWidget);
    expect(find.byType(MetronomeButton), findsOneWidget);
    expect(find.byType(KeysHelpButton), findsOneWidget);
    expect(find.byTooltip('Rename'), findsNothing);
    await tester.pageBack();
    await frames(tester);
    expect(find.byType(PublicCaptureScreen), findsNothing);
  });
}

/// A share API from before joining by link (or offline): it refuses.
class _NoJoining extends FakeShareApi {
  _NoJoining() : super({}, email: 'ana@example.com', identity: 'ana');

  @override
  Future<JoinedCapture> joinLink(
    String token,
    String captureId,
    String key,
  ) async => throw ShareApiException(404, 'No such route');
}
