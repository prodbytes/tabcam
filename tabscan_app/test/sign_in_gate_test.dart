import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tabscan_app/recognition/auto_reader.dart';
import 'package:tabscan_app/screens/event_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabscan_app/cloud/cloud_sync.dart';
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/main.dart';

import 'fakes.dart';

void main() {
  // Share copies a link: a clipboard to copy it to.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

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
    expect(find.text('Link copied'), findsNothing);

    // Signing in closes the sheet and goes on to sharing: the link copied.
    await tester.runAsync(() async => auth.signInAs('ana'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to share'), findsNothing);
    expect(find.text('Link copied'), findsOneWidget);
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
    expect(find.text('Link copied'), findsNothing);
  });

  testWidgets('a build without sign-in shares at once', (tester) async {
    final library = await libraryWithOne();
    await tester.pumpWidget(TabScanApp(library: library));
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(find.text('Link copied'), findsOneWidget);
  });

  testWidgets('signed out, a capture waits to be read; Sign in reads it', (
    tester,
  ) async {
    final auth = FakeAuth();
    late Library library;
    late AutoReader reader;
    late String id;
    // All made in the real zone: their futures complete there.
    await tester.runAsync(() async {
      library = Library(PlatformEventStore(), null, (_) async => null);
      await library.load();
      reader = AutoReader(
        library: library,
        auth: auth,
        supported: true,
        read: (pages) async => 'e|--0--3--|',
      );
      await reader.start();
      id = (await library.create([
        img.encodeJpg(img.Image(width: 8, height: 8)),
      ])).id;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    addTearDown(reader.dispose);
    expect(reader.stateOf(id), ReadState.needsSignIn);
    await tester.pumpWidget(
      AutoReaderScope(
        notifier: reader,
        child: MaterialApp(
          home: EventScreen(
            library: library,
            eventId: id,
            sync: CloudSync(
              library: library,
              auth: auth,
              bucket: FakeBucket(),
              credentials: FakeCredentials(),
              period: const Duration(days: 1),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('text')));
    await tester.pump();
    expect(find.text('Reading tabs needs you signed in.'), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Sign in to read tabs'), findsOneWidget);
    expect(find.textContaining('they stay on this device'), findsOneWidget);

    // Signed in: it's read, and the text shows.
    await tester.runAsync(() async {
      auth.signInAs('ana');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(library.byId(id)!.tabText, 'e|--0--3--|');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'e|--0--3--|');
  });
}
