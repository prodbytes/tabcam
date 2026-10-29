import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/library/search.dart';
import 'package:tabcam_app/screens/event_screen.dart';
import 'package:tabcam_app/screens/library_screen.dart';

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

/// A library with made-up riffs, each in the study given (or none).
Future<Library> _library(
  WidgetTester tester,
  List<(String, String)> riffs,
) async {
  final library = Library(PlatformEventStore(), null, (_) async => null);
  await tester.runAsync(() async {
    await library.load();
    for (final (title, study) in riffs) {
      final event = await library.create(const []);
      await library.update(event.copyWith(title: title, study: study));
    }
  });
  return library;
}

void main() {
  test('a study is saved with the event, and none is left out', () {
    final event = CaptureEvent(
      id: 'a1',
      title: 'Riff',
      created: DateTime(2026, 10, 29),
      study: 'Jazz chords',
    );
    final json = event.toJson(local: false);
    expect(json['study'], 'Jazz chords');
    expect(CaptureEvent.fromJson(json).study, 'Jazz chords');
    final none = event.copyWith(study: '');
    expect(none.toJson().containsKey('study'), isFalse);
    expect(CaptureEvent.fromJson(none.toJson()).study, '');
  });

  test('search finds the study', () {
    final event = CaptureEvent(
      id: 'a1',
      title: 'Riff',
      created: DateTime(2026, 10, 29),
      study: 'Acordes de jazz',
    );
    expect(matchesSearch(event, 'jazz'), isTrue);
  });

  testWidgets('Home has no study chips until a study is set', (tester) async {
    final library = await _library(tester, [('Morning riff', '')]);
    await tester.pumpWidget(
      _app(Scaffold(body: LibraryView(library: library))),
    );
    await _frames(tester);
    expect(find.byKey(const Key('home-studies')), findsNothing);
  });

  testWidgets('a study chip shows only its captures; again, all', (
    tester,
  ) async {
    final library = await _library(tester, [
      ('Morning riff', 'Jazz chords'),
      ('Blues in A', 'Blues'),
      ('Loose riff', ''),
    ]);
    expect(library.studies, ['Blues', 'Jazz chords']);
    await tester.pumpWidget(
      _app(Scaffold(body: LibraryView(library: library))),
    );
    await _frames(tester);
    final chips = find.byKey(const Key('home-studies'));
    expect(chips, findsOneWidget);

    await tester.tap(find.descendant(of: chips, matching: find.text('Blues')));
    await _frames(tester);
    expect(find.text('Blues in A'), findsOneWidget);
    expect(find.text('Morning riff'), findsNothing);
    expect(find.text('Loose riff'), findsNothing);

    await tester.tap(find.descendant(of: chips, matching: find.text('Blues')));
    await _frames(tester);
    expect(find.text('Morning riff'), findsOneWidget);
    expect(find.text('Loose riff'), findsOneWidget);
  });

  testWidgets('the study is set from the open capture, with the name', (
    tester,
  ) async {
    final library = await _library(tester, [
      ('Morning riff', ''),
      ('Blues in A', 'Blues practice'),
    ]);
    final id = library.events.firstWhere((e) => e.title == 'Morning riff').id;
    await tester.pumpWidget(_app(EventScreen(library: library, eventId: id)));
    await _frames(tester);
    expect(find.byKey(const Key('event-study-line')), findsNothing);

    await tester.tap(find.byTooltip('Rename'));
    await _frames(tester);
    final study = find.byKey(const Key('event-study'));
    expect(study, findsOneWidget);
    // The user's studies are suggested as they type.
    await tester.enterText(study, 'blu');
    await _frames(tester);
    await tester.tap(find.text('Blues practice'));
    await _frames(tester);
    await tester.tap(find.text('Save'));
    await _frames(tester);

    expect(library.byId(id)!.study, 'Blues practice');
    expect(library.byId(id)!.title, 'Morning riff');
    expect(find.byKey(const Key('event-study-line')), findsOneWidget);

    // Emptied, it's in no study.
    await tester.tap(find.byTooltip('Rename'));
    await _frames(tester);
    await tester.enterText(find.byKey(const Key('event-study')), '');
    await tester.tap(find.text('Save'));
    await _frames(tester);
    expect(library.byId(id)!.study, '');
    expect(find.byKey(const Key('event-study-line')), findsNothing);
  });
}
