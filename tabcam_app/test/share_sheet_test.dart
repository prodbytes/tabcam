import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/cloud/cloud_sync.dart';
import 'package:tabcam_app/cloud/share_api.dart';
import 'package:tabcam_app/dictionary/public_search.dart';
import 'package:tabcam_app/export/capture_link.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/main.dart';
import 'package:tabcam_app/screens/event_screen.dart';

import 'fakes.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late Library library;
  late FakeAuth auth;
  late CloudSync sync;
  late String id;
  late FakeShareApi api;

  Future<void> open(WidgetTester tester, {bool sharing = true}) async {
    library = Library(PlatformEventStore(), null, (_) async => null);
    auth = FakeAuth();
    await tester.runAsync(() async {
      await library.load();
      final event = await library.create([
        img.encodeJpg(img.Image(width: 8, height: 8)),
      ]);
      id = event.id;
    });
    sync = CloudSync(
      library: library,
      auth: auth,
      bucket: FakeBucket(),
      credentials: FakeCredentials(),
      shares: sharing
          ? (api = FakeShareApi({}, email: 'ana@example.com'))
          : null,
      period: const Duration(days: 1),
    );
    addTearDown(sync.dispose);
    await tester.runAsync(() async {
      sync.start();
      auth.signInAs('ana');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EventScreen(library: library, eventId: id, sync: sync),
      ),
    );
    await frames(tester);
  }

  /// What Share copied: the clipboard's text, as the platform got it.
  String? copied;
  setUp(() {
    copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
  });

  /// The sheet's choice for [v] is the one chosen.
  bool chosen(WidgetTester tester, CaptureVisibility v) =>
      tester
          .widget<RadioGroup<CaptureVisibility>>(
            find.byType(RadioGroup<CaptureVisibility>),
          )
          .groupValue ==
      v;

  testWidgets(
    'Share copies the link on the tap itself: the URL, nothing else',
    (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Share'));
      // Copied at once: no frame, no wait. With its key, made now, so
      // anyone holding the link can open it.
      // A short link: the site, /s/ and the key, 12 letters and digits.
      expect(copied, matches(RegExp(r'^https://tabs\.cam/s/[A-Za-z0-9]{12}$')));
      await frames(tester);
      // The key is kept on the capture and recorded by the share API,
      // unlisted: anyone holding the link opens it.
      final key = library.byId(id)!.linkKey!;
      expect(copied, CaptureLink.of(library.byId(id)!).toString());
      expect(copied, 'https://tabs.cam/s/$key');
      expect(FakeShareApi.links[key], '/$id');
      expect(FakeShareApi.visibilities['/$id'], CaptureVisibility.unlisted);
      expect(find.text('Link copied'), findsOneWidget);
      // No formats: the sheet is who can open it, unlisted chosen.
      expect(find.text('PDF'), findsNothing);
      expect(find.text('Who can open it'), findsOneWidget);
      expect(find.text('Public'), findsOneWidget);
      expect(find.text('Unlisted'), findsOneWidget);
      expect(find.text('Private'), findsOneWidget);
      expect(chosen(tester, CaptureVisibility.unlisted), isTrue);
      expect(library.byId(id)!.shownVisibility, CaptureVisibility.unlisted);
      await tester.tap(find.text('Done'));
      await frames(tester);
      expect(find.byType(BottomSheet), findsNothing);

      // Again: the same link.
      final first = copied;
      await tester.tap(find.byTooltip('Share'));
      await frames(tester);
      expect(copied, first);
      expect(library.byId(id)!.linkKey, key);
      await tester.tap(find.text('Done'));
      await frames(tester);
    },
  );

  testWidgets(
    'Private, Public and back: the same link, the share API told each time',
    (tester) async {
      await open(tester);
      await tester.runAsync(
        () => library.patch(
          id,
          (e) => e.copyWith(title: 'Riff in E', artist: 'The Made-Ups'),
        ),
      );
      await tester.tap(find.byTooltip('Share'));
      await frames(tester);
      final key = library.byId(id)!.linkKey!;

      // Private: only the owner opens it, the key kept.
      await tester.tap(find.byKey(const Key('share-private')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await frames(tester);
      expect(chosen(tester, CaptureVisibility.private), isTrue);
      var event = library.byId(id)!;
      expect(event.visibility, CaptureVisibility.private);
      expect(event.linkKey, key);
      expect(FakeShareApi.visibilities['/$id'], CaptureVisibility.private);
      expect(api.calls.last, 'publish $id private');
      expect(FakeShareApi.public['/$id'], isNull);
      await expectLater(
        api.openLink(id, key),
        throwsA(
          isA<ShareApiException>().having((e) => e.private, 'private', true),
        ),
      );

      // Public: found by tabs.cam's search, by its title and artist.
      await tester.tap(find.byKey(const Key('share-public')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await frames(tester);
      event = library.byId(id)!;
      expect(event.visibility, CaptureVisibility.public);
      expect(event.linkKey, key);
      expect(FakeShareApi.visibilities['/$id'], CaptureVisibility.public);
      final found = await tester.runAsync(() => api.searchPublic('made-ups'));
      expect(found!.single.captureId, id);
      expect(found.single.key, key);
      expect(found.single.title, 'Riff in E');
      expect(found.single.artist, 'The Made-Ups');
      await tester.tap(find.text('Done'));
      await frames(tester);

      // Shown again: public chosen; Unlisted takes it out of the search.
      await tester.tap(find.byTooltip('Share'));
      await frames(tester);
      expect(copied, 'https://tabs.cam/s/$key');
      expect(chosen(tester, CaptureVisibility.public), isTrue);
      await tester.tap(find.byKey(const Key('share-unlisted')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await frames(tester);
      expect(library.byId(id)!.visibility, CaptureVisibility.unlisted);
      expect(FakeShareApi.visibilities['/$id'], CaptureVisibility.unlisted);
      expect(FakeShareApi.public['/$id'], isNull);
      await tester.tap(find.text('Done'));
      await tester.pump(const Duration(seconds: 3)); // the change's sync
      await frames(tester);
    },
  );

  test('the dictionary finds public captures through the share API', () async {
    final search = PublicSearch(
      api: FakeShareApi({}, email: 'bea@example.com'),
    );
    FakeShareApi.public['owner/riff1'] = const PublicCapture(
      captureId: 'riff1',
      key: 'abcdefghijkl',
      title: 'Riff in E',
      artist: 'The Made-Ups',
    );
    expect(PublicSearch.searches('e'), isFalse);
    expect(PublicSearch.searches('ri'), isTrue);
    final found = await search.search('riff made');
    expect(found.single.captureId, 'riff1');
    expect(search.cached('Riff  Made'), same(found));
    expect(
      found.single.link(Uri.parse('https://tabs.cam/app/')).toString(),
      'https://tabs.cam/app/?c=riff1&k=abcdefghijkl',
    );
    FakeShareApi.public.remove('owner/riff1');
  });

  testWidgets('a key from before short links is replaced by a short one', (
    tester,
  ) async {
    await open(tester);
    const old = 'riffkey-0123456789abcdefghijklmn'; // 32, base64url
    await tester.runAsync(
      () => library.patch(id, (e) => e.copyWith(linkKey: old)),
    );
    await frames(tester);
    await tester.tap(find.byTooltip('Share'));
    await frames(tester);
    final key = library.byId(id)!.linkKey!;
    expect(key, isNot(old));
    expect(key, hasLength(12));
    expect(copied, 'https://tabs.cam/s/$key');
    expect(FakeShareApi.links[key], '/$id');
    await tester.pump(const Duration(seconds: 3)); // the change's sync
    await frames(tester);
  });

  testWidgets('a link the API couldn\'t record is recorded at the next pass', (
    tester,
  ) async {
    await open(tester);
    api.failPublish = Exception('offline');
    await tester.tap(find.byTooltip('Share'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await frames(tester);
    // It failed once (the fake throws once), then the pass Share starts
    // recorded it.
    expect(api.failPublish, isNull);
    final key = library.byId(id)!.linkKey!;
    expect(FakeShareApi.links[key], '/$id');
    await tester.pump(const Duration(seconds: 3)); // the change's sync
    await frames(tester);
  });

  testWidgets('Share is the only sharing button', (tester) async {
    await open(tester);
    expect(find.byTooltip('Share'), findsOneWidget);
    expect(find.byIcon(Icons.group_add_outlined), findsNothing);
  });

  testWidgets('a build without sharing: Share copies an owner-only link', (
    tester,
  ) async {
    await open(tester, sharing: false);
    await tester.tap(find.byTooltip('Share'));
    await frames(tester);
    // No share API, no key: the link opens it for its owner only, and
    // there's no one else to choose.
    expect(copied, endsWith('/app/?c=$id'));
    expect(find.text('Who can open it'), findsNothing);
  });

  testWidgets('a Home card\'s Share copies the link too', (tester) async {
    library = Library(PlatformEventStore(), null, (_) async => null);
    auth = FakeAuth();
    await tester.runAsync(() async {
      await library.load();
      id = (await library.create([
        img.encodeJpg(img.Image(width: 8, height: 8)),
      ])).id;
    });
    sync = CloudSync(
      library: library,
      auth: auth,
      bucket: FakeBucket(),
      credentials: FakeCredentials(),
      period: const Duration(days: 1),
    );
    addTearDown(sync.dispose);
    await tester.runAsync(() async {
      sync.start();
      auth.signInAs('ana');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpWidget(
      TabCamApp(library: library, auth: auth, sync: sync),
    );
    await frames(tester);
    await tester.tap(find.byTooltip('More'));
    await frames(tester);
    await tester.tap(find.text('Share'));
    await frames(tester);
    expect(copied, 'https://tabs.cam/app/?c=$id');
    expect(find.text('Link copied'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });
}
