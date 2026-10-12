import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabscan_app/cloud/cloud_sync.dart';
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/library/library.dart';
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
      shares: sharing ? FakeShareApi({}, email: 'ana@example.com') : null,
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

  testWidgets('one Share: the sheet offers Share with people', (tester) async {
    await open(tester);
    expect(find.byTooltip('Share'), findsOneWidget);
    expect(find.byTooltip('Share with people'), findsNothing);

    await tester.tap(find.byTooltip('Share'));
    await frames(tester);
    expect(find.text('Link'), findsOneWidget);
    expect(find.text('Share with people'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    // Right after the link, the default.
    expect(
      tester.getTopLeft(find.text('Link')).dy,
      lessThan(tester.getTopLeft(find.text('Share with people')).dy),
    );

    await tester.tap(find.text('Share with people'));
    await frames(tester);
    expect(find.byType(PeopleSheet), findsOneWidget);
    expect(find.text('PDF'), findsNothing);
  });

  testWidgets('a build without sharing: no Share with people', (tester) async {
    await open(tester, sharing: false);
    await tester.tap(find.byTooltip('Share'));
    await frames(tester);
    expect(find.text('Link'), findsOneWidget);
    expect(find.text('Share with people'), findsNothing);
  });
}
