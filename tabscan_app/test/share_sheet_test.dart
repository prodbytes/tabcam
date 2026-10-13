import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabscan_app/cloud/cloud_sync.dart';
import 'package:tabscan_app/export/capture_link.dart';
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/main.dart';
import 'package:tabscan_app/screens/event_screen.dart';
import 'package:tabscan_app/screens/people_sheet.dart';

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

  testWidgets('Share copies the link on the tap itself: the URL, nothing else', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Share'));
    // Copied at once: no frame, no sheet, no wait. With its key, made
    // now, so anyone holding the link can open it.
    expect(
      copied,
      matches(
        RegExp(
          r'^https://tabscan\.nu01\.com/app/\?c=[a-z0-9]+&k=[A-Za-z0-9_-]{32}$',
        ),
      ),
    );
    expect(copied, startsWith('https://tabscan.nu01.com/app/?c=$id&k='));
    await frames(tester);
    // The key is kept on the capture and recorded by the share API.
    final key = library.byId(id)!.linkKey!;
    expect(copied, CaptureLink.of(library.byId(id)!).toString());
    expect(copied, endsWith('/app/?c=$id&k=$key'));
    expect(FakeShareApi.links[key], '/$id');
    expect(find.text('Link copied'), findsOneWidget);
    // No sheet, no options.
    expect(find.text('PDF'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);

    // Again: the same link.
    final first = copied;
    await tester.tap(find.byTooltip('Share'));
    await frames(tester);
    expect(copied, first);
    expect(library.byId(id)!.linkKey, key);
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

  testWidgets('Share with people has its own button', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Share with people'));
    await frames(tester);
    expect(find.byType(PeopleSheet), findsOneWidget);
    expect(copied, isNull);
  });

  testWidgets('a build without sharing: no Share with people', (tester) async {
    await open(tester, sharing: false);
    expect(find.byTooltip('Share with people'), findsNothing);
    await tester.tap(find.byTooltip('Share'));
    await frames(tester);
    // No share API, no key: the link opens it for its owner only.
    expect(copied, endsWith('/app/?c=$id'));
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
      TabScanApp(library: library, auth: auth, sync: sync),
    );
    await frames(tester);
    await tester.tap(find.byTooltip('More'));
    await frames(tester);
    await tester.tap(find.text('Share'));
    await frames(tester);
    expect(copied, 'https://tabscan.nu01.com/app/?c=$id');
    expect(find.text('Link copied'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });
}
