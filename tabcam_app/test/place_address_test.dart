import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/cloud/cloud_sync.dart';
import 'package:tabcam_app/export/incoming_links.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/main.dart';
import 'package:tabcam_app/screens/event_screen.dart';
import 'package:tabcam_app/screens/file_screen.dart';
import 'package:tabcam_app/screens/place.dart';

import 'fakes.dart';

const riff = 'e|--0--2--3--|\nB|--1--------|';

/// The web page's address, as a test sets it.
class FakeAddress implements PlaceAddress {
  FakeAddress(String url) : current = Uri.parse(url);

  @override
  Uri current;

  @override
  void replace(Uri address) => current = address;

  Map<String, String> get query => current.queryParameters;
}

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await frames(tester);
}

const app = 'https://tabcam.nu01.com/app/';

void main() {
  group('a place in the address', () {
    test('reads back as it was written', () {
      const place = Place(
        tab: 'profile',
        eventId: 'abc123',
        text: true,
        fileId: 'f1',
      );
      final address = place.inAddress(Uri.parse(app));
      expect(
        address.toString(),
        '$app?tab=profile&open=abc123&view=text&file=f1',
      );
      final back = Place.fromAddress(address);
      expect(
        (back.tab, back.eventId, back.text, back.fileId),
        ('profile', 'abc123', true, 'f1'),
      );
    });

    test('Home with nothing open is the bare address', () {
      final address = const Place(tab: 'home')
          .inAddress(Uri.parse('$app?tab=capture&open=abc123&view=files'));
      expect(address.toString(), app);
      final none = Place.fromAddress(Uri.parse(app));
      expect(
        (none.tab, none.eventId, none.text, none.fileId),
        (null, null, false, null),
      );
    });

    test("keeps the site's base, port and Flutter's fragment", () {
      final address = const Place(eventId: 'abc123')
          .inAddress(Uri.parse('https://local.tabcam.nu01.com:2443/app/#/'));
      expect(
        address.toString(),
        'https://local.tabcam.nu01.com:2443/app/?open=abc123&view=files#/',
      );
      expect(
        const Place(tab: 'capture')
            .inAddress(Uri.parse('https://rc.tabcam.nu01.com/app/'))
            .toString(),
        'https://rc.tabcam.nu01.com/app/?tab=capture',
      );
    });

    test("an open event drops a capture link's key; a sign-in code goes", () {
      final link = Uri.parse('$app?c=abc123&k=secret&f=p1&signin-code=123456');
      expect(const Place(eventId: 'abc123').inAddress(link).queryParameters, {
        'open': 'abc123',
        'view': 'files',
      });
      // Still waiting for the link (nothing open): it stays.
      expect(const Place(tab: 'profile').inAddress(link).queryParameters, {
        'c': 'abc123',
        'k': 'secret',
        'f': 'p1',
        'tab': 'profile',
      });
    });

    test('bad IDs and tabs are left out', () {
      final place = Place.fromAddress(
        Uri.parse('$app?tab=../x&open=../etc&view=text&file=a/b'),
      );
      expect(
        (place.tab, place.eventId, place.text, place.fileId),
        (null, null, false, null),
      );
      final file = Place.fromAddress(Uri.parse('$app?open=abc123&file=../x'));
      expect((file.eventId, file.fileId), ('abc123', null));
    });
  });

  group('on the web, a reload', () {
    late Library library;
    late FakeAddress address;

    setUp(() {
      library = Library(PlatformEventStore(), null, (_) async => null);
    });
    tearDown(() {
      PlaceMemory.address = null;
      IncomingLinks.instance.take();
    });

    Future<CaptureEvent> riffEvent(WidgetTester tester, {int pages = 1}) async {
      late CaptureEvent event;
      await tester.runAsync(() async {
        await library.load();
        final made = await library.create([
          for (var i = 0; i < pages; i++)
            img.encodeJpg(img.Image(width: 8, height: 8)),
        ]);
        event = await library.update(
          made.copyWith(title: 'Made-up riff', tabText: riff),
        );
      });
      return event;
    }

    testWidgets('opens the capture in the address, on its Text view', (
      tester,
    ) async {
      final event = await riffEvent(tester);
      PlaceMemory.address = address = FakeAddress(
        '$app?open=${event.id}&view=text',
      );
      await tester.pumpWidget(TabCamApp(library: library));
      await settle(tester);
      expect(find.byType(EventScreen), findsOneWidget);
      expect(find.textContaining('e|--0--2--3--|'), findsWidgets);
      expect(address.query, {'open': event.id, 'view': 'text'});
    });

    testWidgets('opens the file that was open over the capture', (
      tester,
    ) async {
      final event = await riffEvent(tester, pages: 2);
      final file = event.pages.last.id;
      PlaceMemory.address = address = FakeAddress(
        '$app?open=${event.id}&view=files&file=$file',
      );
      await tester.pumpWidget(TabCamApp(library: library));
      await settle(tester);
      expect(find.byType(FileScreen), findsOneWidget);
      expect(find.text('Page 2'), findsOneWidget);

      await tester.pageBack();
      await frames(tester);
      expect(find.byType(FileScreen), findsNothing);
      expect(address.query, {'open': event.id, 'view': 'files'});
    });

    testWidgets('a capture that is gone leaves Home, quietly', (tester) async {
      await riffEvent(tester);
      PlaceMemory.address = address = FakeAddress(
        '$app?tab=profile&open=abc123&view=text',
      );
      await tester.pumpWidget(TabCamApp(library: library));
      await settle(tester);
      expect(find.byType(EventScreen), findsNothing);
      // On its tab still; the capture forgotten.
      expect(find.text('About'), findsOneWidget);
      expect(address.query, {'tab': 'profile'});
    });

    testWidgets('moving around writes the address', (tester) async {
      final event = await riffEvent(tester);
      PlaceMemory.address = address = FakeAddress(app);
      await tester.pumpWidget(TabCamApp(library: library));
      await settle(tester);
      expect(address.current.toString(), app);

      await tester.tap(find.text('Capture'));
      await frames(tester);
      expect(address.query, {'tab': 'capture'});
      await tester.tap(find.text('Home'));
      await frames(tester);
      expect(address.current.toString(), app);

      await tester.tap(find.text('Made-up riff'));
      await frames(tester);
      expect(find.byType(EventScreen), findsOneWidget);
      expect(address.query, {'open': event.id, 'view': 'files'});

      await tester.tap(find.byKey(const Key('text')));
      await frames(tester);
      expect(address.query, {'open': event.id, 'view': 'text'});

      await tester.pageBack();
      await frames(tester);
      expect(find.byType(EventScreen), findsNothing);
      expect(address.current.toString(), app);
    });

    testWidgets('a clone is where the user is, until it closes', (
      tester,
    ) async {
      final event = await riffEvent(tester);
      PlaceMemory.address = address = FakeAddress(
        '$app?open=${event.id}&view=text',
      );
      await tester.pumpWidget(TabCamApp(library: library));
      await settle(tester);
      await tester.tap(find.byTooltip('Clone'));
      await settle(tester);
      final copy = library.events.firstWhere((e) => e.id != event.id);
      final opened = tester.widgetList<EventScreen>(find.byType(EventScreen));
      expect([for (final s in opened) s.eventId], [copy.id]);
      expect(address.query, {'open': copy.id, 'view': 'files'});

      await tester.pageBack();
      await frames(tester);
      expect(find.byType(EventScreen), findsNothing);
      expect(address.current.toString(), app);
    });

    testWidgets("a capture's link wins over the address's place", (
      tester,
    ) async {
      final other = await riffEvent(tester);
      late CaptureEvent linked;
      await tester.runAsync(() async {
        linked = await library.create([
          img.encodeJpg(img.Image(width: 8, height: 8)),
        ]);
      });
      final link = Uri.parse('$app?c=${linked.id}&k=${newLinkKey()}');
      await IncomingLinks.instance.didPushRouteInformation(
        RouteInformation(uri: link),
      );
      PlaceMemory.address = address = FakeAddress(
        '$link&open=${other.id}&view=text',
      );
      await tester.pumpWidget(TabCamApp(library: library));
      await settle(tester);
      final opened = tester.widgetList<EventScreen>(find.byType(EventScreen));
      expect([for (final s in opened) s.eventId], [linked.id]);
      // The link's key isn't left in the address: the capture is.
      expect(address.query, {'open': linked.id, 'view': 'files'});
    });

    group('signed in', () {
      late FakeBucket bucket;

      /// This user's capture, synced to the cloud from another tab (or
      /// before the reload); its ID.
      Future<String> uploaded(WidgetTester tester) async {
        late String id;
        await tester.runAsync(() async {
          bucket = FakeBucket();
          final there = Library(PlatformEventStore(), null, (_) async => null);
          await there.load();
          final made = await there.create([
            img.encodeJpg(img.Image(width: 8, height: 8)),
          ]);
          id = (await there.update(made.copyWith(tabText: riff))).id;
          final sync = CloudSync(
            library: there,
            auth: FakeAuth()..signInAs('me'),
            bucket: bucket,
            credentials: FakeCredentials(),
            period: const Duration(days: 1),
          )..start();
          while (sync.state != SyncState.synced) {
            expect(sync.state, isNot(SyncState.failed));
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          sync.dispose();
        });
        return id;
      }

      /// The reloaded page: an empty library, signed in again, its first
      /// pass held until [hold] completes.
      Future<CloudSync> reload(
        WidgetTester tester,
        Completer<void> hold,
      ) async {
        late CloudSync sync;
        final auth = FakeAuth();
        await tester.runAsync(() async {
          await library.load();
          bucket.holdList = hold;
          sync = CloudSync(
            library: library,
            auth: auth,
            bucket: bucket,
            credentials: FakeCredentials(),
            period: const Duration(days: 1),
            debounce: const Duration(days: 1),
          )..start();
          auth.signInAs('me');
        });
        addTearDown(sync.dispose);
        await tester.pumpWidget(
          TabCamApp(library: library, auth: auth, sync: sync),
        );
        return sync;
      }

      testWidgets('waits for the first pass to bring the capture', (
        tester,
      ) async {
        final id = await uploaded(tester);
        PlaceMemory.address = address = FakeAddress('$app?open=$id&view=text');
        final hold = Completer<void>();
        await reload(tester, hold);
        await settle(tester);
        // Not down yet: Home loads, and the address still names it.
        expect(find.byType(EventScreen), findsNothing);
        expect(address.query, {'open': id, 'view': 'text'});

        hold.complete();
        for (var i = 0; i < 4; i++) {
          await settle(tester);
        }
        expect(find.byType(EventScreen), findsOneWidget);
        expect(find.textContaining('e|--0--2--3--|'), findsWidgets);
        expect(address.query, {'open': id, 'view': 'text'});
      });

      testWidgets('a pass that fails keeps waiting for the next', (
        tester,
      ) async {
        final id = await uploaded(tester);
        bucket
          ..failStatus = 500
          ..failNext = 1;
        PlaceMemory.address = address = FakeAddress('$app?open=$id&view=files');
        final sync = await reload(tester, Completer<void>()..complete());
        for (var i = 0; i < 3; i++) {
          await settle(tester);
        }
        expect(sync.state, SyncState.failed);
        expect(find.byType(EventScreen), findsNothing);
        expect(address.query, {'open': id, 'view': 'files'});

        await tester.runAsync(() async => unawaited(sync.syncNow()));
        for (var i = 0; i < 4; i++) {
          await settle(tester);
        }
        expect(find.byType(EventScreen), findsOneWidget);
        expect(address.query, {'open': id, 'view': 'files'});
      });

      testWidgets('one the first pass doesn\'t bring leaves Home', (
        tester,
      ) async {
        await uploaded(tester);
        PlaceMemory.address = address = FakeAddress(
          '$app?open=abc123&view=files',
        );
        final hold = Completer<void>();
        await reload(tester, hold);
        await settle(tester);
        expect(address.query, {'open': 'abc123', 'view': 'files'});
        hold.complete();
        for (var i = 0; i < 4; i++) {
          await settle(tester);
        }
        expect(find.byType(EventScreen), findsNothing);
        expect(address.current.toString(), app);
      });
    });
  });
}
