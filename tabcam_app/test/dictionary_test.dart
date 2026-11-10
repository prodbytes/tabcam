import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/dictionary/dictionary_sidebar.dart';
import 'package:tabcam_app/dictionary/music_theory.dart';
import 'package:tabcam_app/dictionary/voicings.dart';
import 'package:tabcam_app/dictionary/youtube_search.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/event_screen.dart';
import 'package:tabcam_app/screens/file_screen.dart';
import 'package:tabcam_app/screens/sidebar_widths.dart';
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

  /// A `search.list` response with a video per title, made up.
  http.Response found(List<String> titles) => http.Response(
    jsonEncode({
      'items': [
        for (final (i, title) in titles.indexed)
          {
            'id': {'videoId': 'vid$i'},
            'snippet': {'title': title, 'channelTitle': 'Channel $i'},
          },
      ],
    }),
    200,
  );

  group('YouTube search', () {
    test('asks the API from the device, once per search', () async {
      final asked = <Uri>[];
      final search = YouTubeSearch(
        apiKey: 'test-key',
        client: MockClient((request) async {
          asked.add(request.url);
          return found([
            'Made-up riff &amp; solo',
            'It&#39;s a &quot;lesson&quot;',
          ]);
        }),
      );
      expect(search.available, isTrue);
      expect(search.cached('made-up riff'), isNull);
      final videos = await search.search(' made-up riff ');
      expect(asked.single.host, 'www.googleapis.com');
      expect(asked.single.path, '/youtube/v3/search');
      expect(asked.single.queryParameters['q'], 'made-up riff');
      expect(asked.single.queryParameters['type'], 'video');
      expect(asked.single.queryParameters['key'], 'test-key');
      expect(videos.map((v) => v.title), [
        'Made-up riff & solo',
        'It\'s a "lesson"',
      ]);
      expect(videos.first.channel, 'Channel 0');
      expect('${videos.first.url}', 'https://www.youtube.com/watch?v=vid0');
      await search.search('Made-Up  Riff');
      expect(asked, hasLength(1));
      expect(search.cached('MADE-UP RIFF'), videos);
    });

    test('fails on an error or a bad answer', () async {
      for (final response in [
        http.Response('{"error": {"code": 403}}', 403),
        http.Response('not json', 200),
        http.Response('{}', 200),
      ]) {
        final search = YouTubeSearch(
          apiKey: 'test-key',
          client: MockClient((_) async => response),
        );
        await expectLater(
          search.search('made-up riff'),
          throwsA(isA<YouTubeSearchFailed>()),
        );
        expect(search.cached('made-up riff'), isNull);
      }
    });

    test('reads thumbnails and skips what is not a video', () {
      final videos = YouTubeSearch.parse({
        'items': [
          {
            'id': {'videoId': 'a'},
            'snippet': {
              'title': 'A',
              'channelTitle': 'C',
              'thumbnails': {
                'medium': {'url': 'https://i.ytimg.com/vi/a/mqdefault.jpg'},
              },
            },
          },
          {
            'id': {'channelId': 'x'},
            'snippet': {'title': 'Channel'},
          },
        ],
      });
      expect(videos, hasLength(1));
      expect(
        '${videos.single.thumbnail}',
        'https://i.ytimg.com/vi/a/mqdefault.jpg',
      );
      expect(
        YouTubeSearch.unescape('&#x41;&#999999999;&lt;b&gt;'),
        'A&#999999999;<b>',
      );
    });

    test('is not available without a key', () {
      expect(YouTubeSearch(apiKey: '').available, isFalse);
    });
  });

  group('the sidebar', () {
    late FakeLauncher launcher;

    setUp(() {
      launcher = FakeLauncher();
      UrlLauncherPlatform.instance = launcher;
      DictionaryState.instance.clear();
      SidebarWidths.instance.clear();
    });

    /// A screen 1200 × 800 with the button and the sidebar beside some
    /// content.
    Future<void> show(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            appBar: AppBar(actions: const [DictionaryButton()]),
            body: const DictionaryBeside(
              child: SizedBox.expand(key: Key('content')),
            ),
          ),
        ),
      );
    }

    Future<void> open(WidgetTester tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('dictionary')));
      await tester.pumpAndSettle();
    }

    final sidebar = find.byKey(const Key('dictionary-sidebar'));
    final query = find.byKey(const Key('dictionary-query'));
    final split = find.byKey(const Key('dictionary-split'));
    double width(WidgetTester tester) => tester.getSize(sidebar).width;

    testWidgets('the button opens it on the right, beside the screen, and '
        'hides it', (tester) async {
      await show(tester);
      expect(sidebar, findsNothing);
      await tester.tap(find.byKey(const Key('dictionary')));
      await tester.pumpAndSettle();
      expect(sidebar, findsOneWidget);
      expect(query, findsOneWidget);
      // The content stays, on the left; the sidebar is 40% of the screen.
      expect(find.byKey(const Key('content')), findsOneWidget);
      expect(tester.getTopRight(sidebar).dx, 1200);
      expect(width(tester), 420);
      expect(
        tester.getTopRight(find.byKey(const Key('content'))).dx,
        lessThan(tester.getTopLeft(sidebar).dx),
      );
      await tester.tap(find.byKey(const Key('dictionary')));
      await tester.pumpAndSettle();
      expect(sidebar, findsNothing);
      expect(find.byKey(const Key('content')), findsOneWidget);
    });

    testWidgets('its close button hides it; the search is kept', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(query, 'Am7');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dictionary-close')));
      await tester.pumpAndSettle();
      expect(sidebar, findsNothing);
      expect(DictionaryState.instance.open, isFalse);
      await tester.tap(find.byKey(const Key('dictionary')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dictionary-chord')), findsOneWidget);
      expect(find.text('Am7'), findsWidgets);
    });

    testWidgets('offers examples to tap', (tester) async {
      await open(tester);
      await tester.tap(find.widgetWithText(ActionChip, 'Am7'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dictionary-chord')), findsOneWidget);
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

    testWidgets('shows a scale on the neck: standing in the sidebar, across '
        'once it is dragged wide', (tester) async {
      await open(tester);
      await tester.enterText(query, 'A minor pentatonic');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dictionary-scale')), findsOneWidget);
      expect(find.text('Scale · A  C  D  E  G'), findsOneWidget);
      expect(find.byKey(const Key('scale-fretboard')), findsOneWidget);
      expect(find.byKey(const Key('scale-fretboard-standing')), findsOneWidget);
      await tester.drag(split, const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scale-fretboard')), findsOneWidget);
      expect(find.byKey(const Key('scale-fretboard-standing')), findsNothing);
    });

    testWidgets('searches YouTube for anything else', (tester) async {
      await open(tester);
      await tester.enterText(query, 'made-up riff lesson');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dictionary-youtube')), findsOneWidget);
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

    group('with YouTube search', () {
      late List<String> asked;
      late http.Response Function(String q) respond;
      late YouTubeSearch app;

      setUp(() {
        app = YouTubeSearch.instance;
        asked = [];
        respond = (q) => found(['$q, part 1', '$q, part 2']);
        YouTubeSearch.instance = YouTubeSearch(
          apiKey: 'test-key',
          client: MockClient((request) async {
            final q = request.url.queryParameters['q']!;
            asked.add(q);
            return respond(q);
          }),
        );
      });
      tearDown(() => YouTubeSearch.instance = app);

      testWidgets('shows its results once typing stops for a couple of '
          'seconds; each opens in a new tab', (tester) async {
        await open(tester);
        await tester.enterText(query, 'made-up riff');
        await tester.pump(const Duration(seconds: 1));
        await tester.enterText(query, 'made-up riff lesson');
        await tester.pump(const Duration(seconds: 1));
        expect(asked, isEmpty);
        expect(
          find.byKey(const Key('dictionary-youtube-searching')),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(asked, ['made-up riff lesson']);
        expect(
          find.byKey(const Key('dictionary-youtube-searching')),
          findsNothing,
        );
        expect(find.text('made-up riff lesson, part 1'), findsOneWidget);
        expect(find.text('Channel 1'), findsOneWidget);
        // The link to YouTube's own search stays above them.
        expect(
          find.byKey(const Key('dictionary-search-youtube')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('dictionary-video-vid1')));
        await tester.pump();
        expect(
          launcher.launched.single.$1,
          'https://www.youtube.com/watch?v=vid1',
        );
        // Back to it later, the results are there without asking again.
        await tester.enterText(query, 'Am');
        await tester.pump();
        await tester.enterText(query, 'made-up riff lesson');
        await tester.pump();
        expect(find.text('made-up riff lesson, part 2'), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        expect(asked, hasLength(1));
      });

      testWidgets('Enter searches without the wait', (tester) async {
        await open(tester);
        await tester.enterText(query, 'made-up riff');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump();
        await tester.pump();
        expect(asked, ['made-up riff']);
        expect(launcher.launched, isEmpty);
        expect(find.text('made-up riff, part 1'), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        expect(asked, hasLength(1));
      });

      testWidgets('nothing is searched for a chord, a scale or nothing', (
        tester,
      ) async {
        await open(tester);
        for (final text in ['Am7', 'E blues', '  ']) {
          await tester.enterText(query, text);
          await tester.pump(const Duration(seconds: 3));
        }
        expect(asked, isEmpty);
      });

      testWidgets('says so when it fails or finds nothing', (tester) async {
        await open(tester);
        respond = (_) => http.Response('{}', 403);
        await tester.enterText(query, 'made-up riff');
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(find.text("Couldn't load YouTube's results."), findsOneWidget);
        respond = (_) => found([]);
        await tester.enterText(query, 'another made-up riff');
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(find.text('YouTube found no videos.'), findsOneWidget);
      });
    });

    testWidgets('its edge drags it wider and narrower, within the screen; a '
        'double tap puts it back', (tester) async {
      await open(tester);
      expect(width(tester), 420);
      // The drag's slop aside, it follows the edge.
      await tester.drag(split, const Offset(-120, 0));
      await tester.pumpAndSettle();
      final wider = width(tester);
      expect(wider, inInclusiveRange(510, 540));
      expect(SidebarWidths.instance.of(SidebarWidths.dictionary), wider);
      await tester.drag(split, const Offset(220, 0));
      await tester.pumpAndSettle();
      expect(width(tester), inInclusiveRange(wider - 220, wider - 190));
      // Never narrower than the least, nor so wide the screen goes.
      await tester.drag(split, const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(width(tester), SidebarWidths.min);
      await tester.drag(split, const Offset(-2000, 0));
      await tester.pumpAndSettle();
      expect(width(tester), 1200 - DictionaryBeside.minChild - 12);
      // Closed and opened again, it keeps its width.
      await tester.tap(find.byKey(const Key('dictionary')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dictionary')));
      await tester.pumpAndSettle();
      expect(width(tester), 1200 - DictionaryBeside.minChild - 12);
      await tester.tap(split);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(split);
      await tester.pumpAndSettle();
      expect(width(tester), 420);
      expect(SidebarWidths.instance.of(SidebarWidths.dictionary), isNull);
    });
  });

  group('rotated', () {
    setUp(() {
      DictionaryState.instance.clear();
      SidebarWidths.instance.clear();
    });

    Future<void> open(
      WidgetTester tester, {
      Size size = const Size(1200, 800),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            appBar: AppBar(actions: const [DictionaryButton()]),
            body: const DictionaryBeside(
              child: SizedBox.expand(key: Key('content')),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('dictionary')));
      await tester.pumpAndSettle();
    }

    final sidebar = find.byKey(const Key('dictionary-sidebar'));
    final query = find.byKey(const Key('dictionary-query'));
    final split = find.byKey(const Key('dictionary-split'));
    final rotate = find.byKey(const Key('dictionary-rotate'));
    final content = find.byKey(const Key('content'));
    double height(WidgetTester tester) => tester.getSize(sidebar).height;

    testWidgets('its Rotate button makes it a panel under the screen, across '
        'it, and puts it back at the side', (tester) async {
      await open(tester);
      final kept = tester.element(content);
      expect(tester.getSize(sidebar).width, 420);
      expect(find.byTooltip('Show the dictionary at the bottom'), findsOne);
      await tester.enterText(query, 'Am7');
      await tester.pumpAndSettle();
      await tester.tap(rotate);
      await tester.pumpAndSettle();
      expect(SidebarWidths.instance.isBelow(SidebarWidths.dictionary), isTrue);
      // Across the screen, at its bottom, 40% of its height; the content
      // over it, the same one (what plays there goes on).
      expect(tester.getRect(sidebar), const Rect.fromLTRB(0, 480, 1200, 800));
      expect(tester.getSize(content).width, 1200);
      expect(
        tester.getBottomLeft(content).dy,
        lessThan(tester.getTopLeft(sidebar).dy),
      );
      expect(tester.element(content), same(kept));
      // What was typed is still there, and typed in.
      expect(find.byKey(const Key('dictionary-chord')), findsOneWidget);
      expect(tester.widget<TextField>(query).focusNode!.hasFocus, isTrue);
      expect(find.byTooltip('Show the dictionary at the side'), findsOne);
      await tester.tap(rotate);
      await tester.pumpAndSettle();
      expect(SidebarWidths.instance.isBelow(SidebarWidths.dictionary), isFalse);
      expect(tester.getSize(sidebar), const Size(420, 800 - 56));
      expect(tester.element(content), same(kept));
      expect(find.byKey(const Key('dictionary-chord')), findsOneWidget);
    });

    testWidgets('a chord\'s necks lie down in the panel, and stand at the '
        'side', (tester) async {
      await open(tester);
      await tester.enterText(query, 'Am7');
      await tester.pumpAndSettle();
      final standing = find.byKey(const Key('chord-diagram-standing'));
      final lying = find.byKey(const Key('chord-diagram-lying'));
      expect(standing, findsWidgets);
      expect(lying, findsNothing);
      final size = tester.getSize(standing.first);
      expect(size.height, greaterThan(size.width));
      await tester.tap(rotate);
      await tester.pumpAndSettle();
      expect(standing, findsNothing);
      expect(lying, findsWidgets);
      // The same picture, turned.
      expect(tester.getSize(lying.first), Size(size.height, size.width));
    });

    testWidgets('a scale\'s neck lies across in the panel, however narrow, '
        'and fits its height', (tester) async {
      await open(tester);
      await tester.enterText(query, 'A minor pentatonic');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scale-fretboard-standing')), findsOneWidget);
      await tester.tap(rotate);
      await tester.pumpAndSettle();
      final lying = find.byKey(const Key('scale-fretboard-lying'));
      expect(find.byKey(const Key('scale-fretboard-standing')), findsNothing);
      expect(lying, findsOneWidget);
      var neck = tester.getRect(lying);
      expect(neck.width, greaterThan(neck.height * 2));
      // All of it shows in the panel, beside its name.
      expect(neck.bottom, lessThanOrEqualTo(800));
      expect(neck.top, greaterThan(tester.getRect(query).bottom));
      expect(
        neck.left,
        greaterThan(tester.getRect(find.textContaining('Scale ·')).right),
      );
      // A phone held up: under its name, still across.
      tester.view.physicalSize = const Size(360, 640);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scale-fretboard-standing')), findsNothing);
      neck = tester.getRect(lying);
      expect(neck.width, greaterThan(neck.height * 2));
      expect(neck.right, lessThanOrEqualTo(360));
    });

    testWidgets('its top edge drags it taller and shorter, within the '
        'screen; a double tap puts it back', (tester) async {
      await open(tester);
      await tester.tap(rotate);
      await tester.pumpAndSettle();
      expect(height(tester), 320);
      await tester.drag(split, const Offset(0, -120));
      await tester.pumpAndSettle();
      final taller = height(tester);
      expect(taller, inInclusiveRange(410, 440));
      expect(SidebarWidths.instance.of(SidebarWidths.dictionaryHeight), taller);
      // Its width at the side is another thing.
      expect(SidebarWidths.instance.of(SidebarWidths.dictionary), isNull);
      await tester.drag(split, const Offset(0, 700));
      await tester.pumpAndSettle();
      expect(height(tester), DictionaryBeside.minHeight);
      await tester.drag(split, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(height(tester), 800 - 56 - DictionaryBeside.minChild - 12);
      await tester.tap(split);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(split);
      await tester.pumpAndSettle();
      expect(height(tester), 320);
    });

    testWidgets('fits a small phone, at the side and under the screen, and '
        'keeps its field where there is no room', (tester) async {
      for (final text in [
        '',
        'F#m7b5',
        'C# harmonic minor',
        'a made-up riff',
      ]) {
        DictionaryState.instance.clear();
        SidebarWidths.instance.clear();
        await open(tester, size: const Size(320, 480));
        await tester.enterText(query, text);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.tap(rotate);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(sidebar).width, 320);
        // Lying down with the keyboard up: a strip is left.
        tester.view.physicalSize = const Size(480, 150);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(query).height, greaterThan(0));
        expect(tester.getRect(query).bottom, lessThanOrEqualTo(150));
        await tester.tap(rotate);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('is cut, not squeezed, where a sidebar beside it leaves it '
        'narrow', (tester) async {
      // A 360 px phone with the metronome's sidebar open: 96 px are left.
      Future<void> narrow(WidgetTester tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              appBar: AppBar(actions: const [DictionaryButton()]),
              body: const Row(
                children: [
                  Expanded(
                    child: DictionaryBeside(
                      child: SizedBox.expand(key: Key('content')),
                    ),
                  ),
                  SizedBox(width: 264),
                ],
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('dictionary')));
        await tester.pump();
      }

      for (final text in ['', 'Am7', 'E blues', 'a made-up riff']) {
        DictionaryState.instance.clear();
        SidebarWidths.instance.clear();
        SidebarWidths.instance.setBelow(SidebarWidths.dictionary, true);
        await narrow(tester);
        await tester.enterText(query, text);
        await tester.pump();
        expect(tester.takeException(), isNull);
        // Laid out at its least width, from its left edge, in its 96 px.
        expect(tester.getSize(sidebar).width, DictionaryBeside.minBelow);
        expect(tester.getTopLeft(sidebar).dx, 0);
        expect(tester.getSize(content).width, 96);
        expect(tester.getSize(query).width, greaterThan(60));
        await tester.pumpWidget(const SizedBox());
      }
      SidebarWidths.instance.clear();
    });

    testWidgets('is kept on the device', (tester) async {
      final store = PlatformEventStore();
      final library = Library(store, null, (_) async => null);
      await tester.runAsync(() async {
        await library.load();
        await SidebarWidths.instance.load(library);
      });
      expect(SidebarWidths.instance.isBelow(SidebarWidths.dictionary), isFalse);
      await open(tester);
      await tester.tap(rotate);
      await tester.pumpAndSettle();
      await tester.drag(split, const Offset(0, -100));
      await tester.pumpAndSettle();
      final tall = height(tester);
      String? saved;
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        saved = await library.readMeta(SidebarWidths.metaName);
      });
      expect(jsonDecode(saved!), {
        'dictionaryHeight': tall,
        'below': ['dictionary'],
      });
      // The app opened again.
      SidebarWidths.instance.clear();
      expect(SidebarWidths.instance.isBelow(SidebarWidths.dictionary), isFalse);
      await tester.runAsync(() => SidebarWidths.instance.load(library));
      await tester.pumpAndSettle();
      expect(SidebarWidths.instance.isBelow(SidebarWidths.dictionary), isTrue);
      expect(height(tester), tall);
      expect(tester.getSize(sidebar).width, 1200);
      SidebarWidths.instance.clear();
    });
  });

  group('the button', () {
    testWidgets('is at the top of the capture and its files, and opens the '
        'sidebar there', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      DictionaryState.instance.clear();
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
      await tester.tap(find.byKey(const Key('dictionary')));
      await tester.pump();
      expect(find.byKey(const Key('dictionary-sidebar')), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: FileScreen(library: library, eventId: id, pageId: pageId),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('dictionary')), findsOneWidget);
      // Still open, on the file's screen too.
      expect(find.byKey(const Key('dictionary-sidebar')), findsOneWidget);
      DictionaryState.instance.clear();
    });
  });
}
