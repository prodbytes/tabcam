import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabscan_app/l10n/app_localizations.dart';
import 'package:tabscan_app/library/capture_event.dart';
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/library/search.dart';
import 'package:tabscan_app/screens/library_screen.dart';

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

CaptureEvent _event({
  String title = 'Riff',
  String artist = '',
  String? tabText,
  List<EventPage> pages = const [],
  String? sharedBy,
}) => CaptureEvent(
  id: 'a1',
  title: title,
  artist: artist,
  created: DateTime(2026, 10, 13),
  pages: pages,
  tabText: tabText,
  sharedBy: sharedBy,
);

void main() {
  group('matchesSearch', () {
    test('an empty search matches everything', () {
      expect(matchesSearch(_event(), ''), isTrue);
      expect(matchesSearch(_event(), '   '), isTrue);
    });

    test('finds the title and artist, whatever the case and accents', () {
      final event = _event(title: 'Canción del río', artist: 'Joâo');
      expect(matchesSearch(event, 'cancion'), isTrue);
      expect(matchesSearch(event, 'RIO'), isTrue);
      expect(matchesSearch(event, 'joao'), isTrue);
      expect(matchesSearch(event, 'tango'), isFalse);
    });

    test('every word must match, anywhere', () {
      final event = _event(title: 'Morning riff', artist: 'Me');
      expect(matchesSearch(event, 'riff morning'), isTrue);
      expect(matchesSearch(event, 'riff evening'), isFalse);
    });

    test('finds the tab, file names, links and who shared it', () {
      final event = _event(
        tabText: 'e|--3--5--7--|',
        pages: [
          const EventPage(
            id: 'p1',
            kind: PageKind.pdf,
            extension: 'pdf',
            title: 'Lesson notes',
          ),
          EventPage.link(
            id: 'p2',
            url: Uri.parse('https://example.com/backing-track'),
            title: 'Backing',
          ),
        ],
        sharedBy: 'olga@example.com',
      );
      expect(matchesSearch(event, '--5--'), isTrue);
      expect(matchesSearch(event, 'lesson'), isTrue);
      expect(matchesSearch(event, 'backing-track'), isTrue);
      expect(matchesSearch(event, 'olga'), isTrue);
    });
  });

  testWidgets('Home keeps only the captures that match, and clears', (
    tester,
  ) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    await tester.runAsync(() async {
      await library.load();
      for (final (title, artist) in [
        ('Morning riff', 'Me'),
        ('Blues in A', 'Someone'),
      ]) {
        final event = await library.create(const []);
        await library.update(event.copyWith(title: title, artist: artist));
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: LibraryView(library: library)),
      ),
    );
    await _frames(tester);
    expect(find.text('Morning riff'), findsOneWidget);
    expect(find.text('Blues in A'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('home-search')), 'blues');
    await _frames(tester);
    expect(find.text('Morning riff'), findsNothing);
    expect(find.text('Blues in A'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('home-search')), 'tango');
    await _frames(tester);
    expect(find.text('No captures match “tango”'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Clear search'));
    await _frames(tester);
    expect(find.text('Morning riff'), findsOneWidget);
    expect(find.text('Blues in A'), findsOneWidget);
  });
}
