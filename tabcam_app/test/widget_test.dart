import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/main.dart';

void main() {
  Future<Library> empty() async {
    final library = Library(PlatformEventStore());
    await library.load();
    return library;
  }

  testWidgets('Home, Capture and Profile, in the bottom navigation bar', (
    tester,
  ) async {
    await tester.pumpWidget(TabCamApp(library: await empty()));
    final bar = find.byType(NavigationBar);
    for (final label in ['Home', 'Capture', 'Profile']) {
      expect(find.descendant(of: bar, matching: find.text(label)), findsOne);
    }
    // Home: the events, here none, pointing to Capture.
    expect(find.text('TabCam'), findsOneWidget);
    expect(find.text('No tabs yet'), findsOneWidget);
    expect(find.textContaining('Go to Capture'), findsOneWidget);

    await tester.tap(find.descendant(of: bar, matching: find.text('Capture')));
    await tester.pumpAndSettle();
    expect(find.text('Scan'), findsOneWidget);
    // Document (PDFs) first in Add, then the others, in this order.
    final adds = ['Document', 'Photos & videos', 'Files', 'Link'];
    for (final add in adds) {
      expect(find.text(add), findsOneWidget);
    }
    final ys = [for (final add in adds) tester.getTopLeft(find.text(add)).dy];
    expect(ys, [...ys]..sort());
    expect(find.text('PDF files'), findsOneWidget);

    await tester.tap(find.descendant(of: bar, matching: find.text('Profile')));
    await tester.pumpAndSettle();
    expect(find.text('About'), findsOneWidget);
    expect(find.textContaining("Sign-in isn't set up"), findsOneWidget);
  });

  testWidgets('a link from Capture is a new event, shown on Home', (
    tester,
  ) async {
    final library = await empty();
    await tester.pumpWidget(TabCamApp(library: library));
    await tester.tap(find.text('Capture'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Link'));
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

  testWidgets('Home shows my captures and those shared with me', (
    tester,
  ) async {
    final library = await empty();
    Future<void> add(String title, {String? sharedBy}) async {
      var event = await library.create(const []);
      event = await library.update(event.copyWith(title: title));
      if (sharedBy != null) {
        await library.setSharing(event, sharedBy, readOnly: true);
      }
    }

    await add('My riff');
    await tester.pumpWidget(TabCamApp(library: library));
    await tester.pumpAndSettle();
    // Nothing shared yet: just the grid, without headings.
    expect(find.text('My riff'), findsOneWidget);
    expect(find.text('My captures'), findsNothing);
    expect(find.text('Shared with me'), findsNothing);

    await add('Their riff', sharedBy: 'friend@example.com');
    await tester.pumpAndSettle();
    expect(find.text('My captures'), findsOneWidget);
    expect(find.text('Shared with me'), findsOneWidget);
    expect(find.text('My riff'), findsOneWidget);
    expect(find.text('Their riff'), findsOneWidget);
    expect(find.textContaining('shared by friend@example.com'), findsOne);
    // Mine above, shared below.
    expect(
      tester.getTopLeft(find.text('My riff')).dy,
      lessThan(tester.getTopLeft(find.text('Shared with me')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Shared with me')).dy,
      lessThan(tester.getTopLeft(find.text('Their riff')).dy),
    );
  });
}
