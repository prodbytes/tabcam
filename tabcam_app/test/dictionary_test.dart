import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/dictionary/dictionary_screen.dart';
import 'package:tabcam_app/dictionary/music_theory.dart';
import 'package:tabcam_app/dictionary/voicings.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/event_screen.dart';
import 'package:tabcam_app/screens/file_screen.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'fakes.dart';

void main() {
  String notes(List<Note> notes) => notes.map((n) => n.name).join(' ');

  Chord chord(String query) => (Lookup.of(query) as ChordLookup).chord;
  Scale scale(String query) => (Lookup.of(query) as ScaleLookup).scale;

  group('chords', () {
    test('are read with their notes spelled from the root', () {
      expect(chord('C').name, 'C');
      expect(notes(chord('C').notes), 'C E G');
      expect(notes(chord('C#').notes), 'C# E# G#');
      expect(notes(chord('Db').notes), 'Db F Ab');
      expect(notes(chord('Am7').notes), 'A C E G');
      expect(notes(chord('F#m7b5').notes), 'F# A C E');
      expect(notes(chord('Bdim7').notes), 'B D F Ab');
      expect(notes(chord('Eaug').notes), 'E G# B#');
      expect(notes(chord('G7').notes), 'G B D F');
      expect(notes(chord('Cmaj7').notes), 'C E G B');
      expect(notes(chord('A9').notes), 'A C# E G B');
      expect(notes(chord('C6/9').notes), 'C E G A D');
      expect(chord('C6/9').bass, isNull);
    });

    test('are written in many ways', () {
      expect(chord('CM7').quality.symbol, 'maj7');
      expect(chord('Cm7').quality.symbol, 'm7');
      expect(chord('C major').name, 'C');
      expect(chord('A minor').name, 'Am');
      expect(chord('a min').name, 'Am');
      expect(chord('Bb').name, 'Bb');
      expect(chord('bb').name, 'Bb');
      expect(chord('bm').name, 'Bm');
      expect(chord('Bbm').name, 'Bbm');
      expect(chord('C♯m').name, 'C#m');
      expect(chord('E♭').name, 'Eb');
      expect(chord('C°').name, 'Cdim');
      expect(chord('Cø7').name, 'Cm7b5');
      expect(chord('C+').name, 'Caug');
      expect(chord('Csus').name, 'Csus4');
      expect(chord('C chord').name, 'C');
      expect(chord('Do menor').name, 'Cm');
      expect(chord('Ré').name, 'D');
      expect(chord('Sol7').name, 'G7');
      expect(chord('Sib').name, 'Bb');
      expect(chord('Fá maior').name, 'F');
    });

    test('with another bass note', () {
      final c = chord('G/B');
      expect(c.name, 'G/B');
      expect(c.bass?.name, 'B');
      expect(c.bassPitchClass, 11);
      expect(chord('Am7/G').name, 'Am7/G');
      expect(chord('C / E').name, 'C/E');
    });
  });

  group('scales', () {
    test('are read with their notes spelled from the root', () {
      expect(notes(scale('C major scale').notes), 'C D E F G A B');
      expect(notes(scale('A minor pentatonic').notes), 'A C D E G');
      expect(notes(scale('A pentatonic').notes), 'A B C# E F#');
      expect(notes(scale('E blues').notes), 'E G A Bb B D');
      expect(notes(scale('F# dorian').notes), 'F# G# A B C# D# E');
      expect(notes(scale('C lydian').notes), 'C D E F# G A B');
      expect(notes(scale('Bb major scale').notes), 'Bb C D Eb F G A');
      expect(notes(scale('c harmonic minor').notes), 'C D Eb F G Ab B');
      expect(notes(scale('G mixolydian mode').notes), 'G A B C D E F');
      expect(notes(scale('C whole tone').notes), 'C D E F# G# Bb');
      expect(scale('A natural minor').type.key, 'minor');
      expect(scale('A aeolian').type.key, 'minor');
      expect(scale('A minor scale').type.key, 'minor');
      expect(scale('Re menor escala').root.name, 'D');
      expect(scale('La pentatónica menor').type.key, 'minor pentatonic');
      expect(scale('Mi dórico').type.key, 'dorian');
    });

    test('a chord is a chord, a scale a scale, a song neither', () {
      expect(Lookup.of('C major'), isA<ChordLookup>());
      expect(Lookup.of('C major scale'), isA<ScaleLookup>());
      expect(Lookup.of('A minor'), isA<ChordLookup>());
      expect(Lookup.of('A minor pentatonic'), isA<ScaleLookup>());
      expect(Lookup.of('B blues'), isA<ScaleLookup>());
      expect(Lookup.of('Bb'), isA<ChordLookup>());
      expect(Lookup.of('made-up riff'), isA<Other>());
      expect(Lookup.of('Cmajor9thing'), isA<Other>());
      expect(Lookup.of('H7'), isA<Other>());
      expect(Lookup.of(''), isA<Other>());
      expect(Lookup.of('   '), isA<Other>());
    });
  });

  group('voicings', () {
    List<String> shapes(String query) =>
        voicingsOf(chord(query)).map((v) => v.label).toList();

    test('find the open chords', () {
      expect(shapes('C'), contains('x32010'));
      expect(shapes('A'), contains('x02220'));
      expect(shapes('G'), contains('320003'));
      expect(shapes('E'), contains('022100'));
      expect(shapes('D'), contains('xx0232'));
      expect(shapes('Am'), contains('x02210'));
      expect(shapes('Em'), contains('022000'));
      expect(shapes('Dm'), contains('xx0231'));
      expect(shapes('G7'), contains('320001'));
      expect(shapes('B7'), contains('x21202'));
      expect(shapes('C7'), contains('x32310'));
      expect(shapes('Fmaj7'), anyOf(contains('xx3210'), contains('102210')));
    });

    test('find the barre chords, up the neck', () {
      expect(shapes('F'), contains('133211'));
      expect(shapes('Bm'), contains('x24432'));
      expect(shapes('Bb'), contains('x13331'));
      expect(shapes('C'), contains('x35553'));
      expect(shapes('Am'), contains('577555'));
      expect(shapes('G/B'), contains('x20003'));
      expect(shapes('E5'), contains('022xxx'));
      // Up the neck, and no more than two per starting fret.
      final bases = voicingsOf(chord('C')).map((v) => v.baseFret).toList();
      expect(bases, List.of(bases)..sort());
      for (final b in bases.toSet()) {
        expect(bases.where((x) => x == b).length, lessThanOrEqualTo(2));
      }
    });

    test('keep the bass on the root, or the slash bass', () {
      for (final q in ['C', 'F#m7', 'Bb', 'G/B', 'C/E', 'A13']) {
        final c = chord(q);
        for (final v in voicingsOf(c)) {
          final lowest = v.frets.indexWhere((f) => f != null);
          expect(
            (standardTuning[lowest] + v.frets[lowest]!) % 12,
            c.bassPitchClass,
            reason: '$q ${v.label}',
          );
          final pcs = {
            for (var s = 0; s < 6; s++)
              if (v.frets[s] case final f?) (standardTuning[s] + f) % 12,
          };
          expect(pcs, containsAll(c.requiredPitchClasses), reason: '$q $v');
          expect(v.highestFret - v.lowestFret, lessThanOrEqualTo(3));
        }
      }
    });

    test('count fingers, a barre as one', () {
      expect(fingersOf([null, 3, 2, 0, 1, 0]), 3);
      expect(fingersOf([1, 3, 3, 2, 1, 1]), 4);
      expect(fingersOf([null, 0, 2, 2, 2, 0]), 3);
      expect(fingersOf([null, null, 7, 5, 5, 5]), 2);
      expect(fingersOf([1, 3, 3, 2, 1, 1]), 4);
      expect(fingersOf([1, 3, 3, 3, 1, 1]), 4);
      expect(fingersOf([1, 2, 3, 4, 5, 1]), isNull);
      expect(Voicing([1, 3, 3, 2, 1, 1]).barre, isTrue);
      expect(Voicing([1, 3, 3, 2, 1, 1]).barreFrom, 0);
      expect(Voicing([null, null, 0, 2, 3, 2]).barre, isFalse);
      expect(Voicing([null, null, 0, 2, 3, 2]).baseFret, 1);
      expect(Voicing([null, 5, 7, 7, 6, 5]).baseFret, 5);
    });
  });

  group('the screen', () {
    late FakeLauncher launcher;

    setUp(() {
      launcher = FakeLauncher();
      UrlLauncherPlatform.instance = launcher;
    });

    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(appBar: AppBar(actions: const [DictionaryButton()])),
        ),
      );
      await tester.tap(find.byKey(const Key('dictionary')));
      await tester.pumpAndSettle();
    }

    final query = find.byKey(const Key('dictionary-query'));

    testWidgets('opens from the button, with examples to tap', (tester) async {
      await open(tester);
      expect(find.byType(DictionaryScreen), findsOneWidget);
      expect(query, findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, 'Am7'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dictionary-chord')), findsOneWidget);
      expect(find.text('Am7'), findsWidgets);
      expect(find.byKey(const Key('chord-diagram')), findsWidgets);
    });

    testWidgets('shows a chord as it is typed', (tester) async {
      await open(tester);
      await tester.enterText(query, 'F#m7b5');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dictionary-chord')), findsOneWidget);
      expect(find.text('Chord · F#  A  C  E'), findsOneWidget);
      expect(find.text('1  b3  b5  b7'), findsOneWidget);
      expect(find.byKey(const Key('chord-diagram')), findsWidgets);
      // Enter does nothing more for a chord.
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(launcher.launched, isEmpty);
    });

    testWidgets('shows a scale on the neck', (tester) async {
      await open(tester);
      await tester.enterText(query, 'A minor pentatonic');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dictionary-scale')), findsOneWidget);
      expect(find.text('A minor pentatonic'), findsWidgets);
      expect(find.text('Scale · A  C  D  E  G'), findsOneWidget);
      expect(find.byKey(const Key('scale-fretboard')), findsOneWidget);
      expect(find.byKey(const Key('chord-diagram')), findsNothing);
    });

    testWidgets('searches YouTube for anything else', (tester) async {
      await open(tester);
      await tester.enterText(query, 'made-up riff lesson');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dictionary-youtube')), findsOneWidget);
      expect(find.byKey(const Key('chord-diagram')), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(launcher.launched, hasLength(1));
      expect(
        launcher.launched.single.$1,
        'https://www.youtube.com/results?search_query=made-up+riff+lesson',
      );
      await tester.tap(find.byKey(const Key('dictionary-search-youtube')));
      await tester.pump();
      expect(launcher.launched, hasLength(2));
    });
  });

  group('the button', () {
    testWidgets('is at the top of the capture and its files', (tester) async {
      final library = Library(PlatformEventStore(), null, (_) async => null);
      late String id;
      late String pageId;
      await tester.runAsync(() async {
        await library.load();
        final event = await library.create([
          img.encodeJpg(img.Image(width: 8, height: 4)),
        ]);
        id = event.id;
        pageId = event.pages.first.id;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: EventScreen(library: library, eventId: id),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('dictionary')), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: FileScreen(library: library, eventId: id, pageId: pageId),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('dictionary')), findsOneWidget);
    });
  });
}
