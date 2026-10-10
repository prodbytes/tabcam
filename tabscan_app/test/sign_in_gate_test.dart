import 'package:flutter_test/flutter_test.dart';
import 'package:tabscan_app/cloud/cloud_sync.dart';
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/main.dart';

import 'fakes.dart';

void main() {
  Future<Library> libraryWithOne() async {
    final library = Library(PlatformEventStore());
    await library.load();
    final event = await library.create(const []);
    await library.addLink(event, Uri.parse('https://example.com/lesson'));
    return library;
  }

  testWidgets('signed out, Share asks to sign in first, then shares', (
    tester,
  ) async {
    final library = await libraryWithOne();
    final auth = FakeAuth();
    final sync = CloudSync(
      library: library,
      auth: auth,
      bucket: FakeBucket(),
      credentials: FakeCredentials(),
      period: const Duration(days: 1),
    )..start();
    addTearDown(sync.dispose);
    await tester.pumpWidget(
      TabScanApp(library: library, auth: auth, sync: sync),
    );

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to share'), findsOneWidget);
    expect(find.text('PDF'), findsNothing);

    // Signing in closes the sheet and goes on to sharing.
    await tester.runAsync(() async => auth.signInAs('ana'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to share'), findsNothing);
    expect(find.text('PDF'), findsOneWidget);
  });

  testWidgets('signed out, closing the sheet shares nothing', (tester) async {
    final library = await libraryWithOne();
    final auth = FakeAuth();
    final sync = CloudSync(
      library: library,
      auth: auth,
      bucket: FakeBucket(),
      credentials: FakeCredentials(),
      period: const Duration(days: 1),
    )..start();
    addTearDown(sync.dispose);
    await tester.pumpWidget(
      TabScanApp(library: library, auth: auth, sync: sync),
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10)); // outside the sheet
    await tester.pumpAndSettle();
    expect(find.text('Sign in to share'), findsNothing);
    expect(find.text('PDF'), findsNothing);
  });

  testWidgets('a build without sign-in shares at once', (tester) async {
    final library = await libraryWithOne();
    await tester.pumpWidget(TabScanApp(library: library));
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(find.text('PDF'), findsOneWidget);
  });

  testWidgets('signed out, Read tab asks to sign in first', (tester) async {
    final library = await libraryWithOne();
    final auth = FakeAuth();
    final sync = CloudSync(
      library: library,
      auth: auth,
      bucket: FakeBucket(),
      credentials: FakeCredentials(),
      period: const Duration(days: 1),
    )..start();
    addTearDown(sync.dispose);
    await tester.pumpWidget(
      TabScanApp(library: library, auth: auth, sync: sync),
    );
    await tester.tap(find.text(library.events.single.title));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Read tab'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to read tabs'), findsOneWidget);
    expect(find.textContaining('they stay on this device'), findsOneWidget);
  });
}
