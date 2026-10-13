import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabscan_app/auth/auth_service.dart';
import 'package:tabscan_app/cloud/cloud_sync.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/main.dart';

import 'fakes.dart';

void main() {
  testWidgets('without sign-in set up, Profile says so', (tester) async {
    final library = Library(PlatformEventStore());
    await library.load();
    await tester.pumpWidget(TabScanApp(library: library));
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Google'), findsNothing);
    expect(find.textContaining("Sign-in isn't set up"), findsOneWidget);
  });

  testWidgets('a build without sign-in has no sign-in on Home', (tester) async {
    final library = Library(PlatformEventStore());
    await library.load();
    await tester.pumpWidget(TabScanApp(library: library));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-sign-in')), findsNothing);
  });

  testWidgets(
    'signed out, the app is the welcome alone; signed in, all of it',
    (tester) async {
      final library = Library(PlatformEventStore());
      await library.load();
      final auth = FakeAuth();
      final sync = CloudSync(
        library: library,
        auth: auth,
        bucket: FakeBucket(),
        credentials: FakeCredentials(),
        period: const Duration(days: 1),
      )..start();
      await tester.pumpWidget(
        TabScanApp(library: library, auth: auth, sync: sync),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('welcome')), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Capture'), findsNothing);
      await tester.tap(find.text('Sign in with Google'));
      expect(auth.signIns, [AuthProvider.google]);

      await tester.runAsync(() async {
        auth.signInAs('ana');
        while (sync.state != SyncState.synced) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('welcome')), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('ana@example.com'), findsOneWidget);
      expect(find.textContaining('Synced'), findsOneWidget);

      // Signing out: back to the welcome.
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('welcome')), findsOneWidget);
      sync.dispose();
    },
  );
}
