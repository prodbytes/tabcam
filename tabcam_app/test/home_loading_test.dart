import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/cloud/cloud_sync.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/library_screen.dart';

import 'fakes.dart';

/// Signed in, Home says the captures are loading until the first pass
/// brings them, not that there are none.
void main() {
  late FakeBucket bucket;
  late Library library;
  late CloudSync sync;
  late FakeAuth auth;

  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(() async {
      bucket = FakeBucket();
      auth = FakeAuth();
      library = Library(PlatformEventStore());
      await library.load();
      sync = CloudSync(
        library: library,
        auth: auth,
        bucket: bucket,
        credentials: FakeCredentials(),
        period: const Duration(days: 1),
        debounce: const Duration(days: 1),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LibraryView(library: library, sync: sync),
        ),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }

  testWidgets('loading while the first pass runs, then the captures', (
    tester,
  ) async {
    await open(tester);
    final hold = bucket.holdList = Completer<void>();
    await tester.runAsync(() async {
      sync.start();
      auth.signInAs('me');
    });
    await settle(tester);
    expect(find.byKey(const Key('library-loading')), findsOneWidget);
    expect(find.text('Loading your captures…'), findsOneWidget);

    hold.complete();
    await settle(tester);
    expect(find.byKey(const Key('library-loading')), findsNothing);
    // Nothing in the folder: now it's truly empty.
    expect(find.text('No tabs yet'), findsOneWidget);
    await tester.runAsync(() async => sync.dispose());
  });

  testWidgets('the first pass failing says so, with Try again', (tester) async {
    await open(tester);
    bucket
      ..failStatus = 500
      ..failNext = 1;
    await tester.runAsync(() async {
      sync.start();
      auth.signInAs('me');
    });
    await settle(tester);
    expect(find.text("Your captures couldn't be loaded"), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.text('No tabs yet'), findsOneWidget);
    await tester.runAsync(() async => sync.dispose());
  });

  testWidgets('without cloud sync, an empty library is just empty', (
    tester,
  ) async {
    await tester.runAsync(() async {
      library = Library(PlatformEventStore());
      await library.load();
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: LibraryView(library: library)),
      ),
    );
    await settle(tester);
    expect(find.text('No tabs yet'), findsOneWidget);
  });
}
