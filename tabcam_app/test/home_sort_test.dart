import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/library/library_order.dart';
import 'package:tabcam_app/screens/library_screen.dart';

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

CaptureEvent _event(String id, int day, {String? title, String artist = ''}) =>
    CaptureEvent(
      id: id,
      title: title ?? id,
      artist: artist,
      created: DateTime(2026, 10, day),
      pages: const [],
    );

List<String> _ids(List<CaptureEvent> events) => [for (final e in events) e.id];

/// The titles shown on Home, in reading order.
List<String> _shown(WidgetTester tester, List<String> titles) {
  final at = {for (final t in titles) t: tester.getTopLeft(find.text(t))};
  return [...titles]..sort((a, b) {
    final (x, y) = (at[a]!, at[b]!);
    return x.dy != y.dy ? x.dy.compareTo(y.dy) : x.dx.compareTo(y.dx);
  });
}

void main() {
  // Newest first, as the library has them.
  final events = [
    _event('c', 3, title: 'Blues in A', artist: 'Zed'),
    _event('b', 2, title: 'árbol riff'),
    _event('a', 1, title: 'Morning riff', artist: 'Ana'),
  ];

  group('sortEvents', () {
    test('least recently opened: never opened first (newest first), then '
        'from the longest ago', () {
      final opened = {
        'c': DateTime.utc(2026, 11, 2),
        'a': DateTime.utc(2026, 11, 3),
      };
      expect(_ids(sortEvents(events, LibrarySort.leastOpened, opened)), [
        'b',
        'c',
        'a',
      ]);
      expect(_ids(sortEvents(events, LibrarySort.leastOpened, const {})), [
        'c',
        'b',
        'a',
      ]);
    });

    test('recently opened: the last opened first; never opened counts as '
        'opened when made', () {
      final opened = {'a': DateTime.utc(2026, 11, 3)};
      expect(_ids(sortEvents(events, LibrarySort.recentlyOpened, opened)), [
        'a',
        'c',
        'b',
      ]);
    });

    test('newest, oldest, title (case and accents aside), artist (none '
        'last)', () {
      expect(_ids(sortEvents(events, LibrarySort.newest, const {})), [
        'c',
        'b',
        'a',
      ]);
      expect(_ids(sortEvents(events, LibrarySort.oldest, const {})), [
        'a',
        'b',
        'c',
      ]);
      expect(_ids(sortEvents(events, LibrarySort.title, const {})), [
        'b',
        'c',
        'a',
      ]);
      expect(_ids(sortEvents(events, LibrarySort.artist, const {})), [
        'a',
        'c',
        'b',
      ]);
    });
  });

  testWidgets('Home: least recently opened first by default; Sort by picks '
      'another order, kept on the device', (tester) async {
    final store = PlatformEventStore();
    final library = Library(store, null, (_) async => null);
    const titles = ['Morning riff', 'Blues in A', 'Slow one'];
    await tester.runAsync(() async {
      await library.load();
      for (final title in titles) {
        final event = await library.create(const []);
        await library.update(event.copyWith(title: title));
        // Made one after another, a moment apart.
        await Future<void>.delayed(const Duration(milliseconds: 5));
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
    // None opened yet: the newest first.
    expect(_shown(tester, titles), ['Slow one', 'Blues in A', 'Morning riff']);

    // Opened, it goes last.
    final slow = library.events.firstWhere((e) => e.title == 'Slow one');
    await tester.runAsync(() => LibraryOrder.of(library).markOpened(slow.id));
    await _frames(tester);
    expect(_shown(tester, titles), ['Blues in A', 'Morning riff', 'Slow one']);

    // Sort by: the orders, the one in use ticked.
    expect(find.byTooltip('Sort by: Least recently opened'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-sort')));
    await _frames(tester);
    expect(find.text('Sort by'), findsOneWidget);
    expect(
      tester
          .widget<CheckedPopupMenuItem<LibrarySort>>(
            find.byKey(const Key('home-sort-leastopened')),
          )
          .checked,
      isTrue,
    );
    await tester.tap(find.text('Title'));
    await _frames(tester);
    expect(_shown(tester, titles), ['Blues in A', 'Morning riff', 'Slow one']);
    expect(find.byTooltip('Sort by: Title'), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-sort')));
    await _frames(tester);
    await tester.tap(find.text('Newest first'));
    await _frames(tester);
    expect(_shown(tester, titles), ['Slow one', 'Blues in A', 'Morning riff']);

    // Kept: the app's next start reads the order and the opened times.
    await tester.runAsync(() async {
      final again = Library(store, null, (_) async => null);
      await again.load();
      final order = LibraryOrder.of(again);
      await order.load();
      expect(order.sort, LibrarySort.newest);
      expect(order.opened.keys, [slow.id]);
    });
  });
}
