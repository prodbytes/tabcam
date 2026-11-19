import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/dictionary/cifraclub_search.dart';
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
import 'package:tabcam_app/screens/tab_text_view.dart';
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

    test('the cut circle is half-diminished, in symbols and words', () {
      for (final q in [
        'Bø',
        'BØ',
        'Bø7',
        'B∅',
        'Bm7(b5)',
        'B-7b5',
        'B half diminished',
        'B half-diminished',
        'b half dim',
        'B half diminished chord',
        'Si semidisminuido',
        'Si meio-diminuto',
        'Si meio diminuto',
      ]) {
        expect(chord(q).name, 'Bm7b5', reason: q);
      }
      expect(chord('Bbø').name, 'Bbm7b5');
      expect(chord('Bb half diminished').name, 'Bbm7b5');
    });

    test('the triangle is a major seventh, however it\'s typed', () {
      for (final q in [
        'CΔ',
        'CΔ7',
        'C∆',
        'C∆7',
        'C△7',
        'C^7',
        'C^',
        'C7M',
        'C major 7',
        'C major seventh',
        'Do séptima mayor',
        'Dó sétima maior',
      ]) {
        expect(chord(q).name, 'Cmaj7', reason: q);
      }
      expect(chord('CΔ9').name, 'Cmaj9');
      expect(chord('CmΔ7').name, 'Cm(maj7)');
      expect(chord('C-Δ7').name, 'Cm(maj7)');
      expect(chord('Cm7M').name, 'Cm(maj7)');
      expect(chord('BbΔ7').name, 'Bbmaj7');
      expect(chord('Bb^7').name, 'Bbmaj7');
    });

    test('the circle is diminished; "diminished" alone is the scale', () {
      expect(chord('C˚').name, 'Cdim');
      expect(chord('C˚7').name, 'Cdim7');
      expect(chord('C diminished 7').name, 'Cdim7');
      expect(chord('C diminished seventh').name, 'Cdim7');
      expect(chord('C augmented').name, 'Caug');
      expect(Lookup.of('C diminished'), isA<ScaleLookup>());
    });

    test('tell their other symbols', () {
      expect(chord('Bm7b5').otherNames, ['Bø', 'Bø7', 'Bm7(b5)', 'B-7b5']);
      expect(chord('Cmaj7').otherNames, ['CΔ7', 'CΔ', 'CM7', 'C7M']);
      expect(chord('Cmaj7/E').otherNames.first, 'CΔ7/E');
      expect(chord('C').otherNames, isEmpty);
      // Every symbol shown reads back as the same chord.
      for (final q in [
        'Bm7b5',
        'Cmaj7',
        'Cm(maj7)',
        'Bdim',
        'Bdim7',
        'Caug',
        'Caug7',
        'Cm7',
        'Cmaj9',
      ]) {
        for (final other in chord(q).otherNames) {
          expect(chord(other).name, q, reason: other);
        }
      }
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

  /// Cifra Club's index's answer, in the parentheses it wraps it in: an
  /// artist first (not shown), then a song per (artist slug, song slug,
  /// title), by a made-up band.
  http.Response cifra(List<(String, String, String)> songs) => http.Response(
    '(${jsonEncode({
      'response': {
        'numFound': songs.length + 1,
        'docs': [
          {
            't': '1',
            'm': 'Made-up Band',
            'a': 'Made-up Band',
            'i': '',
            'd': 'made-up-band',
          },
          for (final (artist, slug, title) in songs)
            {
              't': '2',
              'm': title,
              'a': 'Made-up Band',
              'i': '',
              'd': artist,
              'u': slug,
            },
        ],
      },
    })})',
    200,
  );

  /// [query] as the site writes an address part.
  String slugOf(String query) => query
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  group('a scale written in a tab', () {
    List<List<int?>> position(String query) =>
        scalePosition((Lookup.of(query) as ScaleLookup).scale);

    /// Each column's string and fret, low E as 0.
    List<(int, int)> notes(List<List<int?>> columns) => [
      for (final c in columns)
        for (final (s, f) in c.indexed)
          if (f != null) (s, f),
    ];

    test('A minor pentatonic: the box at the fifth fret, two notes a '
        'string, root to root and on', () {
      final columns = position('A minor pentatonic');
      for (final c in columns) {
        expect(c, hasLength(6));
        expect(c.whereType<int>(), hasLength(1));
      }
      expect(notes(columns), [
        (0, 5),
        (0, 8),
        (1, 5),
        (1, 7),
        (2, 5),
        (2, 7),
        (3, 5),
        (3, 7),
        (4, 5),
        (4, 8),
        (5, 5),
        (5, 8),
      ]);
    });

    test('a root on the open string: the open position', () {
      expect(notes(position('E minor pentatonic')), [
        (0, 0),
        (0, 3),
        (1, 0),
        (1, 2),
        (2, 0),
        (2, 2),
        (3, 0),
        (3, 2),
        (4, 0),
        (4, 3),
        (5, 0),
        (5, 3),
      ]);
    });

    test('every note in the scale and going up, within five frets', () {
      for (final query in [
        'C major scale',
        'F# harmonic minor',
        'D dorian',
        'Bb blues',
        'G chromatic',
      ]) {
        final scale = (Lookup.of(query) as ScaleLookup).scale;
        final played = [
          for (final (s, f) in notes(scalePosition(scale)))
            standardTuning[s] + f,
        ];
        expect(played.first % 12, scale.root.pitchClass, reason: query);
        for (var i = 1; i < played.length; i++) {
          expect(played[i], greaterThan(played[i - 1]), reason: query);
        }
        expect(
          played.every((p) => scale.pitchClasses.contains(p % 12)),
          isTrue,
          reason: query,
        );
        final frets = notes(scalePosition(scale)).map((n) => n.$2);
        expect(
          frets.reduce((a, b) => a > b ? a : b) -
              frets.reduce((a, b) => a < b ? a : b),
          lessThanOrEqualTo(4),
          reason: query,
        );
      }
    });
  });

  group('Cifra Club search', () {
    test('asks the site\'s index from the device, once per search; the '
        'songs only, three at most', () async {
      final asked = <Uri>[];
      final search = CifraClubSearch(
        client: MockClient((request) async {
          asked.add(request.url);
          return cifra([
            for (var i = 1; i <= 5; i++) ('made-up-band', 'riff-$i', 'Riff $i'),
          ]);
        }),
      );
      expect(search.cached('made-up riff'), isNull);
      final songs = await search.search(' made-up riff ');
      expect(asked.single.host, 'solr.sscdn.co');
      expect(asked.single.path, '/cc/h2/');
      expect(asked.single.queryParameters['q'], 'made-up riff');
      expect(asked.single.queryParameters['wt'], 'json');
      expect(asked.single.queryParameters['rows'], '10');
      expect(songs.map((s) => s.title), ['Riff 1', 'Riff 2', 'Riff 3']);
      expect(songs.first.artist, 'Made-up Band');
      expect(
        '${songs.first.url}',
        'https://www.cifraclub.com.br/made-up-band/riff-1/',
      );
      await search.search('Made-Up  Riff');
      expect(asked, hasLength(1));
      expect(search.cached('MADE-UP RIFF'), songs);
    });

    test('reads the index\'s docs: the songs, with their picture; not the '
        'artists, nor an odd address', () {
      final songs = CifraClubSearch.parse(
        jsonDecode(
          CifraClubSearch.unwrap(
            '({"response":{"numFound":4,"docs":['
            '{"t":"1","m":"Made-up Band","a":"Made-up Band","i":"",'
            '"d":"made-up-band"},'
            '{"t":"2","m":"Made-up riff","a":"Made-up Band",'
            '"i":"a/b/c/d/abcd-tb.jpg","d":"made-up-band","u":"made-up-riff"},'
            '{"t":"2","m":"Odd","a":"Odd","i":"../x.jpg","d":"../etc",'
            '"u":"riff"},'
            '{"t":2,"m":"Numbered type","a":"Band","d":"band","u":"numbered"}'
            ']}})',
          ),
        ),
      );
      expect(songs.map((s) => s.id), [
        'made-up-band/made-up-riff',
        'band/numbered',
      ]);
      expect(
        '${songs.first.image}',
        'https://akamai.sscdn.co/letras/100x100/fotos/a/b/c/d/abcd-tb.jpg',
      );
      expect(songs.last.image, isNull);
    });

    test('fails on an error or a bad answer', () async {
      for (final response in [
        http.Response('{}', 403),
        http.Response('not json', 200),
        http.Response('({"response":{}})', 200),
      ]) {
        final search = CifraClubSearch(
          client: MockClient((_) async => response),
        );
        await expectLater(
          search.search('made-up riff'),
          throwsA(isA<CifraClubSearchFailed>()),
        );
      }
    });
  });

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
      expect(asked.single.queryParameters['maxResults'], '3');
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

    // Cifra Club's search, answered from here: a tab of the song searched.
    late List<String> askedSongs;
    late http.Response Function(String q) respondSongs;
    late CifraClubSearch cifraClub;

    setUp(() {
      launcher = FakeLauncher();
      UrlLauncherPlatform.instance = launcher;
      DictionaryState.instance.clear();
      SidebarWidths.instance.clear();
      cifraClub = CifraClubSearch.instance;
      askedSongs = [];
      respondSongs = (q) => cifra([('made-up-band', slugOf(q), '$q (tab)')]);
      CifraClubSearch.instance = CifraClubSearch(
        client: MockClient((request) async {
          final q = request.url.queryParameters['q']!;
          askedSongs.add(q);
          return respondSongs(q);
        }),
      );
    });
    tearDown(() => CifraClubSearch.instance = cifraClub);

    /// A screen 1200 × 800 with the button and the sidebar beside some
    /// content, on a capture titled [title] (none: Home).
    Future<void> show(WidgetTester tester, {String? title}) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            appBar: AppBar(actions: const [DictionaryButton()]),
            body: DictionaryBeside(
              title: title,
              child: const SizedBox.expand(key: Key('content')),
            ),
          ),
        ),
      );
    }

    Future<void> open(WidgetTester tester, {String? title}) async {
      await show(tester, title: title);
      await tester.tap(find.byKey(const Key('dictionary')));
      await tester.pumpAndSettle();
    }

    final sidebar = find.byKey(const Key('dictionary-sidebar'));
    final query = find.byKey(const Key('dictionary-query'));
    final split = find.byKey(const Key('dictionary-split'));
    double width(WidgetTester tester) => tester.getSize(sidebar).width;

    testWidgets('beside the Text view, + writes a chord or a scale in the '
        'text; elsewhere there is no +', (tester) async {
      await open(tester);
      await tester.enterText(query, 'C');
      await tester.pump();
      expect(find.byTooltip('Write x32010 in the text'), findsNothing);

      final library = Library(PlatformEventStore());
      late String id;
      await tester.runAsync(() async {
        await library.load();
        id = (await library.create(const [])).id;
      });
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DictionaryBeside(
              child: TabTextView(library: library, eventId: id),
            ),
          ),
        ),
      );
      await tester.pump();
      final chord = find.byKey(const Key('dictionary-write-x32010'));
      expect(chord, findsOneWidget);
      expect(find.byTooltip('Write x32010 in the text'), findsOneWidget);
      await tester.tap(chord);
      await tester.pump();
      final text = find.byType(TextField).first;
      String typed() => tester.widget<TextField>(text).controller!.text;
      expect(typed().split('\n').first, startsWith('e|-0-'));
      expect(typed().split('\n')[4], startsWith('A|-3-'));

      // A scale follows the chord on its phrase, a note a column.
      await tester.enterText(query, 'A minor pentatonic');
      await tester.pump();
      await tester.tap(find.byKey(const Key('dictionary-write-scale')));
      await tester.pump();
      expect(typed().split('\n').last, startsWith('E|---5-8-----'));
      expect(typed().split('\n').first, startsWith('e|-0-${'-' * 20}5-8-'));
      // Saved as an edit.
      await tester.pump(const Duration(seconds: 2));
      expect(library.byId(id)!.tabText, typed());

      // Gone with the Text view.
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: DictionaryBeside(child: SizedBox.expand()),
          ),
        ),
      );
      await tester.pump();
      expect(DictionaryState.instance.writer, isNull);
      expect(
        find.byTooltip('Write A minor pentatonic in the text'),
        findsNothing,
      );
    });

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

    testWidgets('keys the chord symbols and how to type them; a row\'s '
        'tap looks it up', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('dictionary-symbols')), findsOneWidget);
      expect(find.text('half-diminished · Bø'), findsOneWidget);
      expect(find.text('major seventh · CΔ7'), findsOneWidget);
      expect(find.textContaining('hold o for ø'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('dictionary-symbol-Bø')));
      await tester.tap(find.byKey(const Key('dictionary-symbol-Bø')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dictionary-chord')), findsOneWidget);
      expect(find.text('Bm7b5'), findsOneWidget);
      expect(
        find.text('half-diminished · Also written Bø, Bø7, Bm7(b5), B-7b5'),
        findsOneWidget,
      );
    });

    testWidgets('a chord with no other symbol has no such line', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(query, 'C major 7');
      await tester.pumpAndSettle();
      expect(find.text('Cmaj7'), findsOneWidget);
      expect(
        find.text('major seventh · Also written CΔ7, CΔ, CM7, C7M'),
        findsOneWidget,
      );
      await tester.enterText(query, 'G7');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dictionary-chord')), findsOneWidget);
      expect(find.byKey(const Key('dictionary-also')), findsNothing);
    });

    test('the extended pills have voicings', () {
      for (final q in ['Bø', 'GΔ7', 'Cadd9', 'Am11']) {
        final c = (Lookup.of(q) as ChordLookup).chord;
        expect(voicingsOf(c), isNotEmpty, reason: q);
      }
      final am11 = (Lookup.of('Am11') as ChordLookup).chord;
      expect(am11.quality.degrees.map((d) => d.label), contains('9'));
      expect(am11.quality.degrees.map((d) => d.label), contains('11'));
    });

    testWidgets('looks up an added ninth and a ninth and eleventh', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(query, 'Cadd9');
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('dictionary-chord')),
          matching: find.text('Cadd9'),
        ),
        findsOneWidget,
      );
      expect(find.text('1  3  5  9'), findsOneWidget);
      await tester.enterText(query, '');
      await tester.pumpAndSettle();
      await tester.enterText(query, 'Am11');
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('dictionary-chord')),
          matching: find.text('Am11'),
        ),
        findsOneWidget,
      );
      expect(find.text('1  b3  5  b7  9  11'), findsOneWidget);
      expect(find.byKey(const Key('chord-diagram')), findsWidgets);
    });

    testWidgets('looks up the symbols\' chords: Bø and GΔ7', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(query, 'Bø');
      await tester.pumpAndSettle();
      expect(find.text('Bm7b5'), findsOneWidget);
      await tester.enterText(query, '');
      await tester.pumpAndSettle();
      await tester.enterText(query, 'GΔ7');
      await tester.pumpAndSettle();
      expect(find.text('Gmaj7'), findsOneWidget);
      expect(
        find.text('major seventh · Also written GΔ7, GΔ, GM7, G7M'),
        findsOneWidget,
      );
    });

    testWidgets('offers a few examples to tap, under a placeholder alone', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Type anything'), findsOneWidget);
      expect(
        tester
            .widgetList<ActionChip>(find.byType(ActionChip))
            .map((c) => (c.label as Text).data)
            .toList(),
        [
          'C',
          'Am',
          'F#m7b5',
          'Bb',
          'A minor pentatonic',
          'E blues',
          'D dorian',
        ],
      );
      await tester.tap(find.widgetWithText(ActionChip, 'Am'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dictionary-chord')), findsOneWidget);
      expect(find.byKey(const Key('chord-diagram')), findsWidgets);
    });

    testWidgets('offers the capture\'s title as the first pill; tapped, it '
        'is searched', (tester) async {
      await open(tester, title: '  Made-up riff  ');
      final chips = find.byType(ActionChip);
      expect(
        tester.widget<ActionChip>(chips.first).key,
        const Key('dictionary-title'),
      );
      expect(
        find.descendant(of: chips.first, matching: find.text('Made-up riff')),
        findsOneWidget,
      );
      // The examples follow.
      expect(find.widgetWithText(ActionChip, 'C'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dictionary-title')));
      await tester.pump();
      expect(find.widgetWithText(TextField, 'Made-up riff'), findsOneWidget);
      expect(find.byKey(const Key('dictionary-youtube')), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(askedSongs, ['Made-up riff']);
      expect(find.text('Made-up riff (tab)'), findsOneWidget);
    });

    testWidgets('without YouTube\'s key, Cifra Club is still searched; Enter '
        'searches it at once, and opens YouTube\'s search', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('dictionary-title')), findsNothing);
      await tester.enterText(query, 'made-up riff');
      await tester.pump();
      expect(
        find.byKey(const Key('dictionary-cifraclub-searching')),
        findsOneWidget,
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump();
      expect(askedSongs, ['made-up riff']);
      expect(
        launcher.launched.single.$1,
        'https://www.youtube.com/results?search_query=made-up+riff',
      );
      expect(find.text('made-up riff (tab)'), findsOneWidget);
      expect(find.text('Made-up Band'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(askedSongs, hasLength(1));
    });

    testWidgets('shows a chord as it is typed', (tester) async {
      await open(tester);
      await tester.enterText(query, 'F#m7b5');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dictionary-chord')), findsOneWidget);
      expect(find.text('Chord · F#  A  C  E'), findsOneWidget);
      expect(find.text('1  b3  b5  b7'), findsOneWidget);
      expect(find.byKey(const Key('chord-diagram')), findsWidgets);
      // Enter does nothing more for a chord, and nothing is searched.
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(launcher.launched, isEmpty);
      await tester.pump(const Duration(seconds: 3));
      expect(askedSongs, isEmpty);
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
        // Cifra Club's too, at once.
        expect(find.text('made-up riff lesson (tab)'), findsOneWidget);
        expect(
          find.byKey(const Key('dictionary-cifraclub-searching')),
          findsNothing,
        );
        await tester.pump(const Duration(seconds: 3));
        expect(asked, hasLength(1));
        expect(askedSongs, hasLength(1));
      });

      testWidgets('shows Cifra Club\'s tabs under YouTube\'s videos; each '
          'opens on Cifra Club', (tester) async {
        await open(tester);
        await tester.enterText(query, 'made-up riff');
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(asked, ['made-up riff']);
        expect(askedSongs, ['made-up riff']);
        final youTube = find.byKey(const Key('dictionary-youtube'));
        final cifraClub = find.byKey(const Key('dictionary-cifraclub'));
        expect(
          tester.getTopLeft(cifraClub).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(youTube).dy),
        );
        expect(find.text('Tabs on Cifra Club'), findsOneWidget);
        expect(find.text('made-up riff (tab)'), findsOneWidget);
        expect(find.text('Made-up Band'), findsOneWidget);
        await tester.tap(
          find.byKey(const Key('dictionary-song-made-up-band/made-up-riff')),
        );
        await tester.pump();
        expect(
          launcher.launched.single.$1,
          'https://www.cifraclub.com.br/made-up-band/made-up-riff/',
        );
      });

      testWidgets('Enter searches without the wait', (tester) async {
        await open(tester);
        await tester.enterText(query, 'made-up riff');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump();
        await tester.pump();
        expect(asked, ['made-up riff']);
        expect(askedSongs, ['made-up riff']);
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
        expect(askedSongs, isEmpty);
      });

      testWidgets('says so when it fails or finds nothing', (tester) async {
        await open(tester);
        respond = (_) => http.Response('{}', 403);
        respondSongs = (_) => http.Response('', 500);
        await tester.enterText(query, 'made-up riff');
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(find.text("Couldn't load YouTube's results."), findsOneWidget);
        expect(
          find.text("Couldn't load Cifra Club's results."),
          findsOneWidget,
        );
        respond = (_) => found([]);
        respondSongs = (_) => cifra([]);
        await tester.enterText(query, 'another made-up riff');
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(find.text('YouTube found no videos.'), findsOneWidget);
        expect(find.text('Cifra Club found no tabs.'), findsOneWidget);
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
