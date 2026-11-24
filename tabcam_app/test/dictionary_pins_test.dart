import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/dictionary/diagrams.dart';
import 'package:tabcam_app/dictionary/dictionary_sidebar.dart';
import 'package:tabcam_app/dictionary/music_theory.dart';
import 'package:tabcam_app/dictionary/voicings.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/dictionary_pin.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/event_screen.dart';
import 'package:tabcam_app/screens/sidebar_widths.dart';

/// A capture's pins, kept here.
class _Keeper extends ChangeNotifier implements PinKeeper {
  _Keeper({this.canPin = true, List<DictionaryPin> pins = const []})
    : _pins = [...pins];

  final List<DictionaryPin> _pins;

  @override
  final bool canPin;

  @override
  List<DictionaryPin> get pins => List.unmodifiable(_pins);

  @override
  Listenable get pinsChanged => this;

  @override
  Future<void> togglePin(DictionaryPin pin) async {
    if (!_pins.remove(pin)) _pins.add(pin);
    notifyListeners();
  }
}

const _c = DictionaryPin('C', [null, 3, 2, 0, 1, 0]);
const _pentatonic = DictionaryPin('A minor pentatonic scale');

void main() {
  group('DictionaryPin', () {
    test('a chord\'s voicing and a scale, back from JSON as they were', () {
      expect(_c.toJson(), {
        'query': 'C',
        'frets': [null, 3, 2, 0, 1, 0],
      });
      expect(_pentatonic.toJson(), {'query': 'A minor pentatonic scale'});
      expect(DictionaryPin.fromJson(_c.toJson()), _c);
      expect(DictionaryPin.fromJson(_pentatonic.toJson()), _pentatonic);
      expect(_c.isChord, isTrue);
      expect(_pentatonic.isChord, isFalse);
    });

    test('what isn\'t a pin is left out, each kept once, at most max', () {
      final pins = DictionaryPin.listFromJson([
        _c.toJson(),
        _c.toJson(),
        {'query': ''},
        {'query': 'x' * (DictionaryPin.maxQuery + 1)},
        {'query': 3},
        {
          'query': 'C',
          'frets': [1, 2, 3],
        },
        {
          'query': 'C',
          'frets': [null, null, null, null, null, null],
        },
        {
          'query': 'C',
          'frets': [null, 3, 2, 0, 1, 25],
        },
        {
          'query': 'C',
          'frets': [null, 3, 2, 0, 1, '0'],
        },
        'C',
        null,
        _pentatonic.toJson(),
      ]);
      expect(pins, [_c, _pentatonic]);
      expect(DictionaryPin.listFromJson('C'), isEmpty);
      expect(
        DictionaryPin.listFromJson([
          for (var i = 0; i < DictionaryPin.max + 10; i++) {'query': 'C$i'},
        ]),
        hasLength(DictionaryPin.max),
      );
    });

    test('kept in event.json, the cloud\'s copy too (so synced and shared '
        'with the capture); nothing written without pins', () {
      final event = CaptureEvent(
        id: 'pins1',
        title: 'made-up riff',
        created: DateTime.utc(2026, 11, 24),
        pins: const [_c, _pentatonic],
      );
      expect(event.toJson(local: false)['pins'], [
        _c.toJson(),
        _pentatonic.toJson(),
      ]);
      expect(CaptureEvent.fromJson(event.toJson()).pins, [_c, _pentatonic]);
      expect(
        event.copyWith(pins: const []).toJson().containsKey('pins'),
        false,
      );
    });

    test('a clone keeps them', () async {
      final library = Library(PlatformEventStore());
      await library.load();
      final event = await library.update(
        (await library.create(const [])).copyWith(pins: const [_c]),
      );
      expect((await library.clone(event)).pins, [_c]);
    });

    test('every chord and scale reads back from its pin', () {
      final voicing = Voicing(const [null, 3, 2, 0, 1, 0]);
      for (final name in ['C', 'F#', 'Bb', 'E']) {
        final root = (Lookup.of(name) as ChordLookup).chord.root;
        for (final quality in chordQualities.values) {
          for (final chord in [
            Chord(root, quality),
            // Over a bass (none for a quality with a slash of its own, 6/9,
            // which the dictionary can't read with one either).
            if (!quality.symbol.contains('/'))
              Chord(
                root,
                quality,
                bass: (Lookup.of('B') as ChordLookup).chord.root,
              ),
          ]) {
            final back = Lookup.of(chordPin(chord, voicing).query);
            expect(back, isA<ChordLookup>(), reason: chord.name);
            expect((back as ChordLookup).chord.name, chord.name);
          }
        }
        for (final type in scaleTypes.values) {
          final scale = Scale(root, type);
          final back = Lookup.of(scalePin(scale).query);
          expect(back, isA<ScaleLookup>(), reason: '$name ${type.key}');
          expect((back as ScaleLookup).scale.type.key, type.key);
          expect(back.scale.root.name, root.name);
        }
      }
    });
  });

  group('in the dictionary', () {
    setUp(() {
      DictionaryState.instance.clear();
      SidebarWidths.instance.clear();
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            appBar: AppBar(actions: const [DictionaryButton()]),
            body: const DictionaryBeside(child: SizedBox.expand()),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('dictionary')));
      await tester.pumpAndSettle();
    }

    final query = find.byKey(const Key('dictionary-query'));
    final pinned = find.byKey(const Key('dictionary-pinned'));

    Future<void> tap(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('a pin beside each voicing\'s + and a scale\'s pins it to the '
        'capture; what\'s pinned shows at the end, whatever is looked up, '
        'its name looks it up, and its pin unpins it', (tester) async {
      final keeper = _Keeper();
      DictionaryState.instance.attachKeeper(keeper);
      await open(tester);
      expect(pinned, findsNothing);

      await tester.enterText(query, 'C');
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pin C x32010 to this capture'), findsOneWidget);
      await tap(tester, find.byTooltip('Pin C x32010 to this capture'));
      expect(keeper.pins, [_c]);
      expect(pinned, findsOneWidget);
      // After the result, its diagram with its name.
      expect(
        tester.getTopLeft(pinned).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const Key('dictionary-chord'))).dy,
        ),
      );
      expect(
        find.descendant(
          of: pinned,
          matching: find.byKey(const Key('chord-diagram')),
        ),
        findsOneWidget,
      );
      // Filled, the result's pin and the pinned one's unpin it.
      expect(find.byTooltip('Unpin C x32010'), findsNWidgets(2));

      // Something else looked up: still there; a scale pinned after it.
      await tester.enterText(query, 'A minor pentatonic');
      await tester.pumpAndSettle();
      expect(pinned, findsOneWidget);
      await tap(tester, find.byKey(const Key('dictionary-pin-scale')));
      expect(keeper.pins, [_c, _pentatonic]);
      expect(
        find.descendant(of: pinned, matching: find.byType(ScaleFretboard)),
        findsOneWidget,
      );

      // Nothing typed: still at the end.
      await tester.enterText(query, '');
      await tester.pumpAndSettle();
      expect(pinned, findsOneWidget);

      // The chord's name looks it up.
      await tap(tester, find.descendant(of: pinned, matching: find.text('C')));
      expect(tester.widget<TextField>(query).controller!.text, 'C');
      expect(find.byKey(const Key('dictionary-chord')), findsOneWidget);

      // Unpinned from the end.
      await tap(
        tester,
        find.descendant(of: pinned, matching: find.byTooltip('Unpin C x32010')),
      );
      expect(keeper.pins, [_pentatonic]);
      await tap(
        tester,
        find.descendant(
          of: pinned,
          matching: find.byTooltip('Unpin A minor pentatonic'),
        ),
      );
      expect(keeper.pins, isEmpty);
      expect(pinned, findsNothing);
    });

    testWidgets('on a capture read only, what\'s pinned shows, with no pins '
        'to tap', (tester) async {
      DictionaryState.instance.attachKeeper(
        _Keeper(canPin: false, pins: const [_c, _pentatonic]),
      );
      await open(tester);
      expect(pinned, findsOneWidget);
      expect(find.byType(ScaleFretboard), findsOneWidget);
      await tester.enterText(query, 'C');
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pin C x32010 to this capture'), findsNothing);
      expect(find.byTooltip('Unpin C x32010'), findsNothing);
    });

    testWidgets('without a capture (Home): no pins, nothing pinned', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(query, 'C');
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pin C x32010 to this capture'), findsNothing);
      expect(pinned, findsNothing);
    });

    testWidgets('a pin it can\'t read back is left out', (tester) async {
      DictionaryState.instance.attachKeeper(
        _Keeper(
          pins: const [
            DictionaryPin('not a chord'),
            DictionaryPin('C'),
            DictionaryPin('A minor pentatonic scale', [null, 3, 2, 0, 1, 0]),
          ],
        ),
      );
      await open(tester);
      expect(pinned, findsNothing);
    });

    testWidgets('a capture\'s screen keeps them in the capture, while it\'s '
        'open; read only, it shows them and keeps none', (tester) async {
      final library = Library(PlatformEventStore());
      late String id, shared;
      await tester.runAsync(() async {
        await library.load();
        id = (await library.create(const [])).id;
        final other = await library.create(const []);
        shared = (await library.update(
          other.copyWith(readOnly: true, pins: const [_pentatonic]),
        )).id;
      });
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EventScreen(library: library, eventId: id),
        ),
      );
      await tester.pump();
      final keeper = DictionaryState.instance.keeper!;
      expect(keeper.canPin, isTrue);
      await tester.runAsync(() => keeper.togglePin(_c));
      expect(library.byId(id)!.pins, [_c]);
      expect(keeper.pins, [_c]);
      await tester.runAsync(() => keeper.togglePin(_c));
      expect(library.byId(id)!.pins, isEmpty);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(DictionaryState.instance.keeper, isNull);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EventScreen(library: library, eventId: shared),
        ),
      );
      await tester.pump();
      final reader = DictionaryState.instance.keeper!;
      expect(reader.canPin, isFalse);
      expect(reader.pins, [_pentatonic]);
      await tester.runAsync(() => reader.togglePin(_c));
      expect(library.byId(shared)!.pins, [_pentatonic]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
