import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/capture/edit_layers.dart';
import 'package:tabcam_app/capture/take_log.dart';
import 'package:tabcam_app/capture/video_edit.dart';
import 'package:tabcam_app/cloud/cloud_ocr.dart';
import 'package:tabcam_app/cloud/cloud_sync.dart';
import 'package:tabcam_app/cloud/ocr_api.dart';
import 'package:tabcam_app/export/download.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/event_screen.dart';
import 'package:tabcam_app/screens/file_screen.dart';
import 'package:tabcam_app/screens/premium_card.dart';
import 'package:tabcam_app/screens/video_edit_screen.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'cloud_ocr_test.dart' show FakeOcrApi;
import 'fakes.dart';
import 'video_edit_test.dart' show FakeEditor, VolumePlatform;

Duration ms(int n) => Duration(milliseconds: n);

/// Made-up necklines.
const _riffA = 'e|--3--5--7--|';
const _riffB = 'e|--5--7--8--|\nB|--5--5--5--|';

/// The fake platform, with each player's seeks.
class _Seeks extends VolumePlatform {
  final seeksOf = <int, List<Duration>>{};

  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      (seeksOf[playerId] ??= []).add(position);
}

/// The service, answering whether the user has Premium only once [gate]
/// opens (a slow first answer).
class _SlowApi extends FakeOcrApi {
  _SlowApi() : super(premium: true);

  final gate = Completer<void>();

  @override
  Future<PremiumStatus> account(String idToken) async {
    await gate.future;
    return super.account(idToken);
  }
}

/// Waits (really) for [done], at most two seconds.
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue, reason: 'timed out');
}

/// Cloud OCR's Premium answers ([api]) for [library], signed in as
/// [auth]'s user, [now] being the time.
class _Premium {
  _Premium(this.library, this.api, this.auth, {DateTime Function()? now})
    : sync = CloudSync(
        library: library,
        auth: auth,
        bucket: FakeBucket(),
        credentials: FakeCredentials(),
        period: const Duration(days: 1),
      ) {
    ocr = CloudOcr(
      library: library,
      auth: auth,
      sync: sync,
      bucket: FakeBucket(),
      credentials: FakeCredentials(),
      api: api,
      now: now,
    );
  }

  final FakeAuth auth;
  final Library library;
  final FakeOcrApi api;
  final CloudSync sync;
  late final CloudOcr ocr;

  void dispose() {
    ocr.dispose();
    sync.dispose();
  }
}

List<PlanLayer> _ofId(RenderPlan plan, String id) => [
  for (final l in plan.layers)
    if (l.id == id) l,
];

void main() {
  group('the default title, from the capture', () {
    test('its name and artist, two lines', () {
      expect(captureTitleLines('Blue Riff', 'Made-up Band'), [
        'Blue Riff',
        'Made-up Band',
      ]);
      expect(captureTitleLines('  Blue Riff ', ''), ['Blue Riff']);
    });

    test('a name with its artist in it, with none apart: split', () {
      for (final name in [
        'Blue Riff by Made-up Band',
        'Blue Riff – Made-up Band',
        'Blue Riff - Made-up Band',
      ]) {
        expect(captureTitleLines(name, ''), [
          'Blue Riff',
          'Made-up Band',
        ], reason: name);
      }
      // With an artist apart, the name is the name.
      expect(captureTitleLines('Blue Riff - Live', 'Made-up Band'), [
        'Blue Riff - Live',
        'Made-up Band',
      ]);
    });

    test('a name the app gave it is no title', () {
      expect(captureTitleLines('Tab 2026-11-11 10:00', ''), isEmpty);
      expect(captureTitleLines('Tab 2026-11-11 10:00 (copy)', ''), isEmpty);
      expect(
        captureTitleLines(defaultTitle(DateTime(2026, 11, 11, 9, 5)), ''),
        isEmpty,
      );
    });

    test('a copy\'s " (copy)" is left off', () {
      expect(captureTitleLines('Blue Riff (copy)', 'Made-up Band'), [
        'Blue Riff',
        'Made-up Band',
      ]);
      expect(captureTitleLines('Blue Riff by Made-up Band (copy) (copy)', ''), [
        'Blue Riff',
        'Made-up Band',
      ]);
    });

    test('at most two lines of 80 characters, the empty ones left out', () {
      final long = 'x' * 100;
      expect(titleText([long, '', 'b', 'c']), ['x' * 80, 'b']);
      expect(titleText(const ['', '  ']), isEmpty);
    });

    test('80 characters as a person counts them, as the fields do: an '
        'emoji is one, never cut in two', () {
      const face = '\u{1F600}'; // two UTF-16 units
      const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}'; // eight
      // 41 characters (81 units): kept whole.
      final fits = 'a${face * 40}';
      expect(titleText([fits]), [fits]);
      expect(EditTitle.clean([fits]), [fits]);
      // Longer: 80 of them, each whole.
      for (final line in ['a${face * 100}', family * 100]) {
        for (final kept in [
          titleText([line]),
          EditTitle.clean([line])!,
        ]) {
          expect(kept.single.characters.length, 80);
          expect(line.startsWith(kept.single), isTrue);
          final units = kept.single.codeUnits;
          expect(units.last & 0xFC00, isNot(0xD800), reason: 'no half pair');
        }
      }
      expect(titleText(['${family * 80}x']).single, family * 80);
      // Kept through the edit's JSON as typed.
      final edit = EditTitle.of(lines: [fits]);
      expect(EditTitle.fromJson(jsonDecode(jsonEncode(edit!.toJson()))), edit);
    });
  });

  group('the title over the video', () {
    RenderPlan plan(
      PageEdit? edit, {
      List<String> title = const ['Blue Riff', 'Made-up Band'],
      RenderKind kind = RenderKind.video,
    }) => RenderPlan.of(
      edit,
      duration: const Duration(seconds: 20),
      inputExtension: 'mp4',
      title: title,
      kind: kind,
    );

    test('fades in over the kept part\'s first 3 s, then stays to its end, '
        'a start trim included', () {
      for (final edit in [null, PageEdit(start: ms(5000), end: ms(20000))]) {
        final title = _ofId(plan(edit), 'title').single;
        expect(title.alphaAt(Duration.zero), 0, reason: '$edit');
        expect(title.alphaAt(ms(1500)), closeTo(0.5, 1e-9), reason: '$edit');
        expect(title.alphaAt(ms(3000)), 1, reason: '$edit');
        expect(title.alphaAt(ms(14999)), 1, reason: '$edit');
        expect(title.to, isNull);
        expect(title.anchor, LayerAnchor.topLeft);
        expect(title.marginU, TitleLayout.margin);
        expect(title.heightU, TitleLayout.heightU(2));
        expect(title.look, const TitleLook(['Blue Riff', 'Made-up Band']));
      }
    });

    test('its text: the capture\'s, or what was typed; one line is less '
        'high; off, none, the text typed kept', () {
      expect(
        _ofId(
          plan(
            PageEdit(
              start: Duration.zero,
              end: ms(20000),
              title: const EditTitle(lines: ['Red Riff']),
            ),
          ),
          'title',
        ).single,
        isA<PlanLayer>()
            .having((l) => l.look, 'look', const TitleLook(['Red Riff']))
            .having((l) => l.heightU, 'heightU', TitleLayout.heightU(1)),
      );
      final off = PageEdit(
        start: Duration.zero,
        end: ms(20000),
        title: const EditTitle(on: false, lines: ['Red Riff']),
      );
      expect(_ofId(plan(off), 'title'), isEmpty);
      expect(off.title!.lines, ['Red Riff']);
      // No name to show (the app's, or none typed): no title.
      expect(_ofId(plan(null, title: const []), 'title'), isEmpty);
      // Not in the sound alone; in the video without sound.
      expect(plan(null, kind: RenderKind.sound).layers, isEmpty);
      expect(_ofId(plan(null, kind: RenderKind.silent), 'title'), hasLength(1));
    });

    test('kept as title: {on, lines} only when not the default; the lines '
        'trimmed, at most two of 80 characters', () {
      final edit = PageEdit(start: Duration.zero, end: ms(1000));
      expect(edit.toJson().containsKey('title'), isFalse);
      expect(edit.toJson().containsKey('watermark'), isFalse);
      expect(EditTitle.of(), isNull);
      expect(EditTitle.fromJson({'on': true}), isNull);
      final typed = edit.copyWith(
        title: EditTitle.of(lines: [' Red Riff ', 'y' * 90, 'z']),
        watermark: false,
      );
      expect(typed.title!.lines, ['Red Riff', 'y' * 80]);
      final json = jsonDecode(jsonEncode(typed.toJson())) as Map;
      expect(json['title'], {
        'on': true,
        'lines': ['Red Riff', 'y' * 80],
      });
      expect(json['watermark'], false);
      expect(PageEdit.fromJson(json), typed);
      final off = edit.copyWith(title: EditTitle.of(on: false));
      expect(off.toJson()['title'], {'on': false});
      expect(PageEdit.fromJson(off.toJson())!.title, off.title);
      // Typed empty: the trailing empty lines go, an empty first stays.
      expect(EditTitle.clean(['', 'Made-up Band', '']), ['', 'Made-up Band']);
    });
  });

  group('the watermark', () {
    final log = TakeLog(
      burned: false,
      tab: TakeTab(
        lines: const [_riffA, _riffB],
        marks: const [(0, 0), (4000, 1)],
      ),
    );

    RenderPlan plan(
      PageEdit? edit, {
      bool premium = false,
      TakeLog? takeLog,
      BandAspect aspect = bandAspectBound,
    }) => RenderPlan.of(
      edit,
      duration: const Duration(seconds: 20),
      inputExtension: 'mp4',
      watermark: 'Recorded by TabCam',
      premium: premium,
      takeLog: takeLog,
      bandAspect: aspect,
    );

    test('turned off, it\'s left out only for a Premium downloader: it '
        'stays when their Premium isn\'t known, or for a collaborator '
        'without it; a build without the service can remove it', () {
      final off = PageEdit(
        start: Duration.zero,
        end: ms(20000),
        watermark: false,
        fadeIn: Duration.zero,
        fadeOut: Duration.zero,
      );
      expect(_ofId(plan(off, premium: true), 'mark'), isEmpty);
      // Not known (no answer, none kept), or a collaborator without
      // Premium: the same, not Premium now.
      expect(_ofId(plan(off), 'mark'), hasLength(1));
      // On, it's there for Premium too.
      expect(_ofId(plan(null, premium: true), 'mark'), hasLength(1));
      expect(watermarkUnlocked(null), isTrue);
      expect(plan(off, premium: true).passthrough, isTrue);
      expect(plan(null).passthrough, isFalse);
    });

    test('at the bottom right, small, the whole video through; above the '
        'tab\'s tallest band when it\'s drawn', () {
      final mark = _ofId(plan(null), 'mark').single;
      expect(mark.look, const WatermarkLook('Recorded by TabCam'));
      expect(mark.anchor, LayerAnchor.bottomRight);
      expect(mark.heightU, WatermarkLayout.heightU);
      expect(mark.marginU, WatermarkLayout.margin);
      expect((mark.from, mark.to, mark.fadeIn), (Duration.zero, null, ms(0)));
      expect(mark.liftW, 0);
      // With the tab: lifted by its tallest band (here 0.2 of the width).
      final lifted = _ofId(
        plan(null, takeLog: log, aspect: (b) => b.line == _riffB ? 0.2 : 0.1),
        'mark',
      ).single;
      expect(lifted.liftW, 0.2);
      // Only the bands in this output count: trimmed to before B shows.
      expect(
        _ofId(
          plan(
            PageEdit(start: Duration.zero, end: ms(3000)),
            takeLog: log,
            aspect: (b) => b.line == _riffB ? 0.2 : 0.1,
          ),
          'mark',
        ).single.liftW,
        0.1,
      );
      // Placed: 3% of the short side (1080) in, and the band higher.
      const frame = Size(1920, 1080);
      const image = Size(400, 40);
      final rect = lifted.rectIn(frame, image);
      final height = WatermarkLayout.heightU * 1080;
      expect(rect.bottom, closeTo(1080 - 0.03 * 1080 - 0.2 * 1920, 1e-6));
      expect(rect.height, closeTo(height, 1e-6));
      expect(rect.right, closeTo(1920 - 0.03 * 1080, 1e-6));
      // The tab off: down at its margin.
      expect(
        _ofId(
          plan(
            PageEdit(start: Duration.zero, end: ms(20000), tab: false),
            takeLog: log,
          ),
          'mark',
        ).single.liftW,
        0,
      );
      // A band's height is never more than the bound says.
      expect(
        bandAspectBound(const BandLook(_riffB)),
        closeTo(2 * 1.2 / 48 + 2 / 64, 1e-9),
      );
    });

    test('goes to the platforms with its lift', () {
      final p = plan(null, takeLog: log, aspect: (_) => 0.25);
      final args = p.toChannel(
        output: '/tmp/out.mp4',
        images: [for (final _ in p.looks) Uint8List(1)],
      );
      expect(
        (args['layers'] as List).last,
        allOf(
          containsPair('anchor', 'bottomRight'),
          containsPair('liftW', 0.25),
          containsPair('id', 'mark'),
        ),
      );
    });
  });

  testWidgets('the title and the watermark are drawn as high as their '
      'layers say', (tester) async {
    late img.Image title;
    late img.Image mark;
    final looks = [
      titlePicture(const ['Blue Riff', 'Made-up Band']),
      titlePicture(const ['Blue Riff']),
      watermarkPicture('Made with TabCam'),
    ];
    expect(looks[0].size.height, TitleLayout.heightU(2) * layerShort);
    expect(looks[1].size.height, TitleLayout.heightU(1) * layerShort);
    expect(looks[2].size.height, WatermarkLayout.heightU * layerShort);
    await tester.runAsync(() async {
      title = img.decodePng(await looks[0].png())!;
      mark = img.decodePng(await looks[2].png())!;
    });
    expect(title.height, (TitleLayout.heightU(2) * layerShort).round());
    expect(title.width, greaterThan(title.height));
    expect(mark.height, (WatermarkLayout.heightU * layerShort).round());
    for (final look in looks) {
      look.dispose();
    }
  });

  group('Premium now, for the watermark', () {
    late Library library;
    late FakeAuth auth;
    late DateTime clock;
    final made = <_Premium>[];
    setUp(() async {
      library = Library(PlatformEventStore());
      await library.load();
      auth = FakeAuth();
      clock = DateTime(2026, 11, 12, 10);
    });
    tearDown(() {
      for (final p in made) {
        p.dispose();
      }
      made.clear();
    });

    _Premium premium({bool has = true, Object? error}) {
      final p = _Premium(
        library,
        FakeOcrApi(premium: has)..error = error,
        auth,
        now: () => clock,
      );
      made.add(p);
      return p;
    }

    test('the service\'s answer, kept a week on the device for the same '
        'account (offline)', () async {
      final online = premium()..ocr.start();
      online.auth.signInAs('ana');
      await _until(() => online.ocr.premiumNow);
      for (var i = 0; i < 400; i++) {
        if (await library.readMeta(CloudOcr.premiumName) != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(jsonDecode((await library.readMeta(CloudOcr.premiumName))!), {
        'user': 'ana',
        'premium': true,
        'at': clock.millisecondsSinceEpoch,
      });

      // Offline: the service can't be asked; the answer kept stands.
      final offline = premium(error: Exception('offline'))..ocr.start();
      await _until(() => !offline.ocr.checking);
      await _until(() => offline.ocr.premiumNow);
      expect(offline.ocr.status, isNull);

      // A week and a day later: no longer.
      clock = clock.add(const Duration(days: 8));
      expect(offline.ocr.premiumNow, isFalse);
      clock = clock.subtract(const Duration(days: 8));
      expect(offline.ocr.premiumNow, isTrue);

      // Another account: not theirs.
      offline.auth.signInAs('bea', 'token2');
      await _until(() => !offline.ocr.checking);
      expect(offline.ocr.premiumNow, isFalse);
    });

    test('unknown and not kept: not Premium; the service saying no wins over '
        'what was kept', () async {
      final unknown = premium(error: Exception('offline'))..ocr.start();
      unknown.auth.signInAs('ana');
      await _until(() => unknown.api.accountCalls == 1);
      await _until(() => !unknown.ocr.checking);
      expect(unknown.ocr.premiumNow, isFalse);
      expect(watermarkUnlocked(unknown.ocr), isFalse);

      await library.writeMeta(
        CloudOcr.premiumName,
        jsonEncode({
          'user': 'ana',
          'premium': true,
          'at': clock.millisecondsSinceEpoch,
        }),
      );
      final lapsed = premium(has: false)..ocr.start();
      await _until(() => lapsed.api.accountCalls == 1);
      await _until(() => !lapsed.ocr.checking);
      expect(lapsed.ocr.status!.premium, isFalse);
      expect(lapsed.ocr.premiumNow, isFalse);
    });
  });

  group('the editor', () {
    late _Seeks platform;
    late FakeEditor editor;
    final saved = <(String, Uint8List, String)>[];
    setUp(() {
      VideoPlayerPlatform.instance = platform = _Seeks();
      VideoEditor.instance = editor = FakeEditor();
      saved.clear();
      Downloads.save = (name, bytes, type) async {
        saved.add((name, bytes, type));
        return true;
      };
    });
    tearDown(() => VideoEditor.instance = null);

    Future<void> frames(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await frames(tester);
    }

    /// A capture named "Blue Riff", by "Made-up Band", with a video (k0,
    /// one of Cam's takes when [take]) and a recording (k1).
    Future<(Library, String)> capture(
      WidgetTester tester, {
      bool take = false,
    }) async {
      final library = Library(PlatformEventStore(), null, (_) async => null);
      late String id;
      await tester.runAsync(() async {
        await library.load();
        var event = await library.create(const [], title: 'Blue Riff');
        for (final page in [
          EventPage(
            id: 'k0',
            kind: PageKind.video,
            extension: 'mp4',
            title: 'Made-up riff',
            take: take,
          ),
          const EventPage(id: 'k1', kind: PageKind.audio, extension: 'm4a'),
        ]) {
          await library.putPageStream(
            event.id,
            page,
            Stream.value(Uint8List.fromList([1, 2, 3])),
          );
          event = event.copyWith(pages: [...event.pages, page]);
        }
        await library.update(event.copyWith(artist: 'Made-up Band'));
        id = event.id;
      });
      return (library, id);
    }

    void sized(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Widget editScreen(Library library, String id, {CloudOcr? ocr}) =>
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: VideoEditScreen(
            library: library,
            eventId: id,
            page: library.byId(id)!.pages.first,
            pickFile: () async => null,
            ocr: ocr,
          ),
        );

    List<PlanLayer> preview(WidgetTester tester) {
      final found = find.byType(EditLayers);
      if (found.evaluate().isEmpty) return const [];
      return tester.widget<EditLayers>(found).layers;
    }

    PlanLayer? previewTitle(WidgetTester tester) =>
        preview(tester).where((l) => l.id == 'title').firstOrNull;

    bool enabled(WidgetTester tester, String key) =>
        tester.widget<ButtonStyleButton>(find.byKey(Key(key))).enabled;

    InputChip titleChip(WidgetTester tester) =>
        tester.widget<InputChip>(find.byKey(const Key('video-edit-title')));

    FilterChip markChip(WidgetTester tester) => tester.widget<FilterChip>(
      find.byKey(const Key('video-edit-watermark')),
    );

    PageEdit? kept(Library library, String id) =>
        library.byId(id)!.pages.first.edit;

    testWidgets('a fresh video: the capture\'s name as its title and the '
        'watermark, over the preview and in Download; the edit stays none '
        'and Reset off, yet Download makes the video', (tester) async {
      sized(tester, const Size(900, 1600));
      final (library, id) = await capture(tester);
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);

      expect(titleChip(tester).selected, isTrue);
      expect(markChip(tester).selected, isTrue);
      expect(markChip(tester).avatar, isNull, reason: 'no service: unlocked');
      expect(preview(tester).map((l) => l.look), const [
        WatermarkLook('Made with TabCam'),
        TitleLook(['Blue Riff', 'Made-up Band']),
      ]);
      expect(previewTitle(tester)!.fadeIn, TitleLayout.fadeIn);
      expect(kept(library, id), isNull);
      expect(enabled(tester, 'video-edit-reset'), isFalse);

      await tester.tap(find.byKey(const Key('video-edit-download')));
      await settle(tester);
      final plan = editor.rendered.single;
      expect(plan.passthrough, isFalse);
      expect(plan.layers.map((l) => l.id), ['mark', 'title']);
      expect(plan.layers.last.fadeIn, TitleLayout.fadeIn);
      expect(saved.single.$2, [9, 9, 9]);
    });

    testWidgets('typing the title shows it in the preview at once, as it '
        'ends up, without seeking the song again; No title keeps the '
        'text typed; the capture\'s name comes back', (tester) async {
      sized(tester, const Size(900, 1600));
      final (library, id) = await capture(tester, take: true);
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      // A take: its watermark says so.
      expect(
        preview(tester).first.look,
        const WatermarkLook('Recorded by TabCam'),
      );

      // A song along it, playing.
      await tester.tap(find.byKey(const Key('video-edit-song-add')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('video-edit-track-k1')));
      await settle(tester);
      final song = platform.lastPlayer;
      await tester.tap(find.byKey(const Key('video-edit-play')));
      await settle(tester);
      expect(platform.playing, contains(song));
      final seeks = [...?platform.seeksOf[song]];
      expect(seeks, isNotEmpty);

      await tester.enterText(
        find.byKey(const Key('video-edit-title-1')),
        'Red Riff',
      );
      await tester.pump();
      expect(
        previewTitle(tester)!.look,
        const TitleLook(['Red Riff', 'Made-up Band']),
      );
      // Being typed: shown as it ends up, not fading in.
      expect(previewTitle(tester)!.fadeIn, Duration.zero);
      await tester.enterText(
        find.byKey(const Key('video-edit-title-2')),
        'Another Band',
      );
      await settle(tester);
      expect(platform.seeksOf[song], seeks);
      expect(platform.playing, contains(song));
      expect(
        kept(library, id)!.title,
        const EditTitle(lines: ['Red Riff', 'Another Band']),
      );
      expect(enabled(tester, 'video-edit-reset'), isTrue);

      // No title: off, the text kept, in the edit and the fields.
      await tester.tap(find.byKey(const Key('video-edit-title-off')));
      await settle(tester);
      expect(previewTitle(tester), isNull);
      expect(titleChip(tester).selected, isFalse);
      expect(
        kept(library, id)!.title,
        const EditTitle(on: false, lines: ['Red Riff', 'Another Band']),
      );
      expect(find.text('Red Riff'), findsOneWidget);
      // The chip turns it on again, as typed.
      await tester.tap(find.byKey(const Key('video-edit-title')));
      await settle(tester);
      expect(
        previewTitle(tester)!.look,
        const TitleLook(['Red Riff', 'Another Band']),
      );

      // The capture's name: the text typed goes.
      await tester.tap(find.byKey(const Key('video-edit-title-capture')));
      await settle(tester);
      expect(kept(library, id)!.title, isNull);
      expect(find.text('Blue Riff'), findsOneWidget);
      expect(platform.seeksOf[song], seeks);
    });

    testWidgets('on a phone, ✎ or a tap on the title in the preview opens '
        'its fields in place of the chips; Done closes them', (tester) async {
      sized(tester, const Size(400, 900));
      final (library, id) = await capture(tester);
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      expect(find.byKey(const Key('video-edit-title-fields')), findsNothing);

      await tester.tap(find.byKey(const Key('video-edit-title-edit')));
      await settle(tester);
      expect(find.byKey(const Key('video-edit-title-fields')), findsOneWidget);
      expect(find.byKey(const Key('video-edit-on-video')), findsNothing);
      expect(previewTitle(tester)!.fadeIn, Duration.zero);
      await tester.tap(find.byKey(const Key('video-edit-title-done')));
      await settle(tester);
      expect(find.byKey(const Key('video-edit-title-fields')), findsNothing);
      expect(find.byKey(const Key('video-edit-on-video')), findsOneWidget);
      expect(previewTitle(tester)!.fadeIn, TitleLayout.fadeIn);

      // A tap on the title, at the preview's top left.
      final box = tester.getRect(find.byKey(const Key('video-edit-preview')));
      final short = box.shortestSide;
      final played = [...platform.playing];
      await tester.tapAt(box.topLeft + Offset(short * 0.05, short * 0.05));
      await settle(tester);
      expect(find.byKey(const Key('video-edit-title-fields')), findsOneWidget);
      expect(platform.playing, played, reason: 'not played');
      // Elsewhere, it plays.
      await tester.tap(find.byKey(const Key('video-edit-title-done')));
      await settle(tester);
      await tester.tapAt(box.bottomRight - const Offset(4, 4));
      await settle(tester);
      expect(platform.playing, isNotEmpty);
      expect(find.byKey(const Key('video-edit-title-fields')), findsNothing);
    });

    testWidgets('without Premium the watermark is locked on: a tap shows the '
        'Premium card, and it stays on; Premium arriving late unlocks it '
        'in place', (tester) async {
      sized(tester, const Size(900, 1600));
      final (library, id) = await capture(tester);
      final api = _SlowApi();
      late _Premium p;
      await tester.runAsync(() async {
        p = _Premium(library, api, FakeAuth())..ocr.start();
        p.auth.signInAs('ana');
        await _until(() => p.ocr.checking);
      });
      addTearDown(() => p.dispose());
      await tester.pumpWidget(editScreen(library, id, ocr: p.ocr));
      await settle(tester);

      expect(markChip(tester).selected, isTrue);
      expect(markChip(tester).avatar, isNotNull);
      expect(markChip(tester).tooltip, 'Premium removes the watermark');
      await tester.tap(find.byKey(const Key('video-edit-watermark')));
      await settle(tester);
      expect(find.byKey(const Key('video-edit-premium')), findsOneWidget);
      expect(find.text('Premium removes the watermark'), findsWidgets);
      await tester.tap(find.byKey(const Key('premium-not-now')));
      await settle(tester);
      expect(find.byKey(const Key('video-edit-premium')), findsNothing);
      expect(markChip(tester).selected, isTrue);
      expect(kept(library, id), isNull);

      // Premium's answer comes: unlocked where it is.
      await tester.runAsync(() async {
        api.gate.complete();
        await _until(() => p.ocr.premium);
      });
      await settle(tester);
      expect(markChip(tester).avatar, isNull);
      await tester.tap(find.byKey(const Key('video-edit-watermark')));
      await settle(tester);
      expect(markChip(tester).selected, isFalse);
      expect(kept(library, id)!.watermark, isFalse);
      await tester.tap(find.byKey(const Key('video-edit-download')));
      await settle(tester);
      expect(editor.rendered.single.layers.map((l) => l.id), ['title']);
    });

    testWidgets('the file screen plays a video with its title over it, '
        'with no edit too, but not the watermark (Download\'s); No title '
        'takes it off there too', (tester) async {
      sized(tester, const Size(900, 1600));
      final (library, id) = await capture(tester);
      Future<List<PlanLayer>> played() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: FileScreen(library: library, eventId: id, pageId: 'k0'),
          ),
        );
        await settle(tester);
        await tester.tap(find.byIcon(Icons.play_circle_fill));
        await settle(tester);
        return preview(tester);
      }

      expect((await played()).map((l) => l.look), const [
        TitleLook(['Blue Riff', 'Made-up Band']),
      ]);
      expect((await played()).single.fadeIn, TitleLayout.fadeIn);

      await tester.runAsync(
        () => library.setPageEdit(
          id,
          'k0',
          PageEdit(
            start: Duration.zero,
            end: ms(20000),
            title: const EditTitle(lines: ['Riff two']),
          ),
        ),
      );
      expect((await played()).map((l) => l.look), const [
        TitleLook(['Riff two']),
      ]);

      await tester.runAsync(
        () => library.setPageEdit(
          id,
          'k0',
          PageEdit(
            start: Duration.zero,
            end: ms(20000),
            title: const EditTitle(on: false, lines: ['Riff two']),
          ),
        ),
      );
      expect(await played(), isEmpty);
    });

    testWidgets('a clone opens with Premium\'s service too: without '
        'Premium, the copy\'s watermark stays locked', (tester) async {
      sized(tester, const Size(900, 1600));
      final (library, id) = await capture(tester);
      late _Premium p;
      await tester.runAsync(() async {
        p = _Premium(library, FakeOcrApi(premium: false), FakeAuth())
          ..ocr.start();
        p.auth.signInAs('ana');
        await _until(() => p.ocr.status != null);
      });
      addTearDown(() => p.dispose());
      expect(watermarkUnlocked(p.ocr), isFalse);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EventScreen(library: library, eventId: id, ocr: p.ocr),
        ),
      );
      await settle(tester);
      await tester.tap(find.byTooltip('Clone'));
      await settle(tester);
      await settle(tester);
      final copy = tester.widget<EventScreen>(find.byType(EventScreen));
      expect(copy.eventId, isNot(id));
      expect(copy.ocr, same(p.ocr));
    });

    for (final (name, size) in [
      ('a phone', const Size(400, 900)),
      ('a wide screen', const Size(1280, 900)),
    ]) {
      testWidgets('the chips and the title\'s fields fit at the largest text '
          'size, on $name', (tester) async {
        sized(tester, size);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final (library, id) = await capture(tester, take: true);
        await tester.pumpWidget(editScreen(library, id));
        await settle(tester);
        expect(find.byKey(const Key('video-edit-watermark')), findsOneWidget);
        if (size.width < 840) {
          await tester.ensureVisible(
            find.byKey(const Key('video-edit-title-edit')),
          );
          await tester.tap(find.byKey(const Key('video-edit-title-edit')));
          await settle(tester);
        }
        expect(find.byKey(const Key('video-edit-title-1')), findsOneWidget);
        expect(
          find.byKey(const Key('video-edit-title-capture')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
