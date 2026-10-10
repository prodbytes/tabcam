import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/main.dart';

void main() {
  Future<Library> empty() async {
    final library = Library(PlatformEventStore());
    await library.load();
    return library;
  }

  testWidgets('Home, Capture and Profile, in the bottom navigation bar', (
    tester,
  ) async {
    await tester.pumpWidget(TabScanApp(library: await empty()));
    final bar = find.byType(NavigationBar);
    for (final label in ['Home', 'Capture', 'Profile']) {
      expect(find.descendant(of: bar, matching: find.text(label)), findsOne);
    }
    // Home: the events, here none, pointing to Capture.
    expect(find.text('TabScan'), findsOneWidget);
    expect(find.text('No tabs yet'), findsOneWidget);
    expect(find.textContaining('Go to Capture'), findsOneWidget);

    await tester.tap(find.descendant(of: bar, matching: find.text('Capture')));
    await tester.pumpAndSettle();
    expect(find.text('Scan'), findsOneWidget);
    for (final add in ['Photos & videos', 'Files', 'Link']) {
      expect(find.text(add), findsOneWidget);
    }

    await tester.tap(find.descendant(of: bar, matching: find.text('Profile')));
    await tester.pumpAndSettle();
    expect(find.text('About'), findsOneWidget);
    expect(find.textContaining("Sign-in isn't set up"), findsOneWidget);
  });

  testWidgets('a link from Capture is a new event, shown on Home', (
    tester,
  ) async {
    final library = await empty();
    await tester.pumpWidget(TabScanApp(library: library));
    await tester.tap(find.text('Capture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'example.com/lesson');
    await tester.enterText(find.byType(TextField).last, 'Lesson one');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    final event = library.events.single;
    expect(event.title, 'Lesson one');
    expect(event.pages.single.isLink, isTrue);
    // Back on Home, with the message and Open.
    expect(find.text('No tabs yet'), findsNothing);
    expect(find.text('Saved "Lesson one" (1 link)'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    // The new card's outline goes after 3 s; the message, with its Open,
    // after 6 s, by itself.
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Saved "Lesson one" (1 link)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Saved "Lesson one" (1 link)'), findsNothing);
  });
}
