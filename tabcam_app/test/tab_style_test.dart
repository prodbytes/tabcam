import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/capture/edit_layers.dart';
import 'package:tabcam_app/capture/take_log.dart';
import 'package:tabcam_app/capture/video_edit.dart';
import 'package:tabcam_app/export/download.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/file_screen.dart';
import 'package:tabcam_app/screens/video_edit_screen.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'video_edit_test.dart' show FakeEditor, VolumePlatform;

Duration ms(int n) => Duration(milliseconds: n);

/// [json] through a JSON string, as saved and loaded.
Object? _encoded(Object? json) => jsonDecode(jsonEncode(json));

/// Made-up necklines: two short ones, a six-string staff and one too long
/// for any band to draw its text bigger.
const _riffA = 'e|--3--5--7--|';
const _riffB = 'e|--5--7--8--|';
const _staff = 'e|--0--|\nB|--1--|\nG|--0--|\nD|--2--|\nA|--3--|\nE|-----|';
final _long = 'e|${'-' * 100}|';

/// A take's log, its tab turning from [_riffA] to [_riffB] at 4.21 s and
/// back at 8.38 s.
TakeLog _log() => TakeLog(
  burned: false,
  tab: TakeTab(
    lines: const [_riffA, _riffB],
    marks: const [(0, 0), (4210, 1), (8380, 0)],
  ),
);

/// [band] drawn and decoded.
Future<img.Image> _drawn(WidgetTester tester, BandLook band) async {
  late img.Image image;
  await tester.runAsync(() async {
    image = img.decodePng(await renderBand(band))!;
  });
  return image;
}

/// [image]'s pixels as (r, g, b, a).
Iterable<(int, int, int, int)> _pixels(img.Image image) sync* {
  for (final p in image) {
    yield (p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt());
  }
}

(int, int, int, int) _at(img.Image image, int x, int y) {
  final p = image.getPixel(x, y);
  return (p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt());
}

void main() {
  group('the tab\'s style, kept with the edit', () {
    final edit = PageEdit(start: Duration.zero, end: ms(20000));

    test('the default is how bands always looked, and isn\'t written', () {
      expect(edit.tabStyle, EditTabStyle.standard);
      expect(EditTabStyle.standard.isStandard, isTrue);
      expect(
        (
          EditTabStyle.standard.size,
          EditTabStyle.standard.opacity,
          EditTabStyle.standard.colors,
        ),
        (1.0, 0.7, TabColors.dark),
      );
      expect(edit.toJson().containsKey('tabStyle'), isFalse);
      expect(EditTabStyle.standard.toJson(), isEmpty);
    });

    test('only what isn\'t the default is written, and read back the same', () {
      const style = EditTabStyle(
        size: 1.5,
        opacity: 0.35,
        colors: TabColors.light,
      );
      final styled = edit.copyWith(tabStyle: style);
      expect(styled.toJson()['tabStyle'], {
        'size': 1.5,
        'opacity': 0.35,
        'colors': 'light',
      });
      expect(
        edit
            .copyWith(tabStyle: const EditTabStyle(size: 1.25))
            .toJson()['tabStyle'],
        {'size': 1.25},
      );
      expect(
        edit
            .copyWith(tabStyle: const EditTabStyle(colors: TabColors.gold))
            .toJson()['tabStyle'],
        {'colors': 'gold'},
      );
      final back = PageEdit.fromJson(_encoded(styled.toJson()))!;
      expect(back.tabStyle, style);
      expect(back, styled);
      expect(
        back.extra,
        isEmpty,
        reason: 'a key of its own, not a newer app\'s',
      );
      // Back to the default: the key goes.
      expect(
        styled.copyWith(tabStyle: EditTabStyle.standard).toJson(),
        isNot(contains('tabStyle')),
      );
    });

    test('read within its bounds: sizes from 50% to 200%, opacities 0 to 1, '
        'to the hundredth; an unknown colour, or no number, the default', () {
      PageEdit read(Object? style) =>
          PageEdit.fromJson(_encoded({...edit.toJson(), 'tabStyle': style}))!;
      expect(
        read({'size': 9, 'opacity': -1, 'colors': 'neon'}).tabStyle,
        const EditTabStyle(size: 2, opacity: 0),
      );
      expect(
        read({'size': 0.1, 'opacity': 4}).tabStyle,
        const EditTabStyle(size: 0.5, opacity: 1),
      );
      expect(
        read({'size': 1.234, 'opacity': 0.456}).tabStyle,
        const EditTabStyle(size: 1.23, opacity: 0.46),
      );
      expect(
        read({'size': 'big', 'opacity': null}).tabStyle,
        EditTabStyle.standard,
      );
      expect(read('large').tabStyle, EditTabStyle.standard);
      expect(read({'colors': 'brand'}).tabStyle.colors, TabColors.brand);
      // copyWith keeps them within too.
      expect(
        EditTabStyle.standard.copyWith(size: 5, opacity: 0.333),
        const EditTabStyle(size: 2, opacity: 0.33),
      );
    });

    test('an edit kept before the style looks as it did', () {
      final old = {
        'v': 2,
        'startMs': 0,
        'endMs': 20000,
        'sound': 'original',
        'tab': false,
      };
      final read = PageEdit.fromJson(old)!;
      expect(read.tabStyle, EditTabStyle.standard);
      expect(read.toJson(), old);
    });
  });

  group('the plan', () {
    RenderPlan plan(EditTabStyle style, {Size? frame}) => RenderPlan.of(
      PageEdit(start: Duration.zero, end: ms(20000), tabStyle: style),
      input: XFile('/tmp/made-up-take.mp4'),
      duration: ms(20000),
      inputExtension: 'mp4',
      takeLog: _log(),
      watermark: 'Recorded by TabCam',
      frame: frame,
    );

    List<BandLook> bands(RenderPlan p) => [
      for (final l in p.layers)
        if (l.look case final BandLook band) band,
    ];

    test('carries the style in every band\'s look; the default look is '
        'as it always was', () {
      const style = EditTabStyle(
        size: 0.8,
        opacity: 0.2,
        colors: TabColors.gold,
      );
      expect(bands(plan(style)), [
        const BandLook(_riffA, style: style),
        const BandLook(_riffB, style: style),
        const BandLook(_riffA, style: style),
      ]);
      expect(bands(plan(EditTabStyle.standard)).first, const BandLook(_riffA));
      // The layers stay where they were: along the bottom.
      for (final l in plan(style).layers.where((l) => l.id == 'tab')) {
        expect(l.anchor, LayerAnchor.bottomFull);
      }
    });

    test('drawn as wide as the frame (from 1280 up to 4096 pixels), so '
        'Download never scales it up; grown, never more than 40% of the '
        'frame high', () {
      const big = EditTabStyle(size: 2);
      final landscape = bands(plan(big, frame: const Size(1920, 1080))).first;
      expect(landscape.width, 1920);
      expect(landscape.maxAspect, closeTo(0.4 * 1080 / 1920, 1e-9));
      final portrait = bands(plan(big, frame: const Size(1080, 1920))).first;
      expect(portrait.width, 1280);
      expect(portrait.maxAspect, closeTo(0.4 * 1920 / 1080, 1e-9));
      expect(bands(plan(big, frame: const Size(7680, 4320))).first.width, 4096);
      // Not known: a landscape 16:9 frame, 1280 wide.
      final unknown = bands(plan(big)).first;
      expect(unknown.width, bandWidth);
      expect(unknown.maxAspect, closeTo(0.4 * 9 / 16, 1e-9));
      // At its default size or smaller, no bound: it's never bigger.
      expect(
        bands(
          plan(const EditTabStyle(size: 0.5), frame: const Size(1920, 1080)),
        ).first.maxAspect,
        isNull,
      );
    });

    test('never smaller than reads on the frame: its text, against the '
        'frame\'s short side, no smaller than at 50% on a 16:9 one', () {
      expect(TabLayout.minSizeOf(null), 0.5);
      expect(TabLayout.minSizeOf(const Size(1920, 1080)), 0.5);
      expect(TabLayout.minSizeOf(const Size(1920, 1088)), 0.5);
      expect(TabLayout.minSizeOf(const Size(2560, 1080)), 0.5);
      expect(TabLayout.minSizeOf(const Size(1440, 1080)), 0.65);
      expect(TabLayout.minSizeOf(const Size(1080, 1080)), 0.9);
      expect(TabLayout.minSizeOf(const Size(1080, 1920)), 0.9);
      // Kept at 50%, a portrait take's band is drawn at 90%; bigger ones,
      // and a landscape take's, as they are.
      const small = EditTabStyle(size: 0.5, opacity: 0.3);
      expect(
        bands(plan(small, frame: const Size(1080, 1920))).first.style,
        const EditTabStyle(size: 0.9, opacity: 0.3),
      );
      expect(
        bands(plan(small, frame: const Size(1920, 1080))).first.style,
        small,
      );
      expect(
        bands(
          plan(const EditTabStyle(size: 1.2), frame: const Size(1080, 1920)),
        ).first.style.size,
        1.2,
      );
    });

    test('the watermark rises above a bigger band', () {
      double lift(EditTabStyle style) =>
          plan(style).layers.singleWhere((l) => l.id == 'mark').liftW;
      expect(
        lift(const EditTabStyle(size: 1.5)),
        greaterThan(lift(EditTabStyle.standard)),
      );
      expect(
        lift(const EditTabStyle(size: 0.5)),
        lessThan(lift(EditTabStyle.standard)),
      );
      // Opacity and colours change no size.
      expect(
        lift(const EditTabStyle(opacity: 0, colors: TabColors.light)),
        lift(EditTabStyle.standard),
      );
    });
  });

  group('a band drawn', () {
    testWidgets('as high as its size says; a staff too long to grow stays '
        'as big as fits; a grown band within its bound', (tester) async {
      Future<int> high(BandLook band) async =>
          (await _drawn(tester, band)).height;
      final normal = await high(const BandLook(_riffA));
      final large = await high(
        const BandLook(_riffA, style: EditTabStyle(size: 1.5)),
      );
      final small = await high(
        const BandLook(_riffA, style: EditTabStyle(size: 0.5)),
      );
      expect(small, lessThan(normal));
      expect(large, greaterThan(normal));
      // Text and padding scale with it: 1.5× the text, the same padding.
      final pad = 2 * bandWidth / 64;
      expect(large - pad, closeTo((normal - pad) * 1.5, 2));
      // The default is what it always was.
      expect(
        await high(const BandLook(_riffA, style: EditTabStyle.standard)),
        normal,
      );
      // A line as long as the band: no bigger, never wider.
      expect(
        await high(BandLook(_long, style: const EditTabStyle(size: 2))),
        await high(BandLook(_long)),
      );
      // A staff grown to twice its size, bounded at a quarter of the width;
      // never under its default size, whatever the bound.
      final bounded = await high(
        const BandLook(_staff, style: EditTabStyle(size: 2), maxAspect: 0.25),
      );
      // (Within a pixel or two: the text's lines are laid out whole.)
      expect(bounded, lessThanOrEqualTo(0.25 * bandWidth + 2));
      expect(bounded, greaterThan(await high(const BandLook(_staff))));
      expect(
        await high(
          const BandLook(_staff, style: EditTabStyle(size: 2), maxAspect: 0.01),
        ),
        await high(const BandLook(_staff)),
      );
      // Drawn wider, the same shape.
      final wide = await _drawn(tester, const BandLook(_riffA, width: 1920));
      expect(wide.width, 1920);
      expect(wide.height / 1920, closeTo(normal / bandWidth, 0.002));
    });

    testWidgets('grows up to the size the Size slider stops at, and no '
        'further', (tester) async {
      for (final (lines, frame) in [
        (const [_staff], const Size(1920, 1080)),
        (const [_staff], const Size(320, 240)),
        (const [_staff], const Size(1080, 1920)),
        ([_riffA, _long], const Size(1920, 1080)),
        ([_long], const Size(1920, 1080)),
      ]) {
        final most = tabSizeMost(lines, frame);
        expect(most, greaterThanOrEqualTo(TabLayout.minSizeOf(frame)));
        expect(most, lessThanOrEqualTo(EditTabStyle.maxSize));
        double tallest(double size) {
          final style = EditTabStyle(size: size);
          return [
            for (final line in lines)
              bandAspect(
                BandLook(
                  line,
                  style: style,
                  maxAspect: TabLayout.maxAspectOf(style, frame),
                  width: TabLayout.widthOf(frame),
                ),
              ),
          ].reduce(max);
        }

        final reason = '$lines over $frame: $most';
        expect(tallest(EditTabStyle.maxSize), tallest(most), reason: reason);
        if (most - 0.05 >= TabLayout.minSizeOf(frame) && most > 1) {
          expect(tallest(most - 0.05), lessThan(tallest(most)), reason: reason);
        }
      }
      // A staff over a landscape take stops short of 200% (40% of the
      // frame's height); short riffs grow all the way.
      expect(tabSizeMost(const [_staff], const Size(1920, 1080)), lessThan(2));
      expect(tabSizeMost(const [_riffA], const Size(1920, 1080)), 2);
    });

    // (Within a pixel or two: the text's lines are laid out whole.)
    testWidgets('never higher than the bound the plan places it by', (
      tester,
    ) async {
      for (final band in [
        const BandLook(_riffA),
        const BandLook(_staff, style: EditTabStyle(size: 2)),
        const BandLook(_staff, style: EditTabStyle(size: 0.5)),
        const BandLook(_staff, style: EditTabStyle(size: 2), maxAspect: 0.25),
        BandLook(_long, style: const EditTabStyle(size: 1.7)),
      ]) {
        expect(
          bandAspect(band),
          lessThanOrEqualTo(bandAspectBound(band) + 2 / bandWidth),
          reason: '$band',
        );
      }
    });

    testWidgets('its background as opaque as its style says, in its '
        'colours; the text opaque, and outlined as the background fades', (
      tester,
    ) async {
      // The default: 70% black (0xB3), as it always was.
      expect(_at(await _drawn(tester, const BandLook(_riffA)), 0, 0), (
        0,
        0,
        0,
        0xB3,
      ));
      expect(
        _at(
          await _drawn(
            tester,
            const BandLook(
              _riffA,
              style: EditTabStyle(opacity: 0.4, colors: TabColors.light),
            ),
          ),
          0,
          0,
        ),
        (255, 255, 255, 102),
      );
      final gold = await _drawn(
        tester,
        const BandLook(_riffA, style: EditTabStyle(colors: TabColors.gold)),
      );
      expect(
        _pixels(gold).where((p) => p == (0xE0, 0xA0, 0x30, 255)),
        isNotEmpty,
        reason: 'gold text',
      );
      final brand = await _drawn(
        tester,
        const BandLook(
          _riffA,
          style: EditTabStyle(opacity: 1, colors: TabColors.brand),
        ),
      );
      expect(_at(brand, 0, 0), (0xE0, 0xA0, 0x30, 255));
      expect(
        _pixels(brand).where((p) => p == (0x11, 0x11, 0x11, 255)),
        isNotEmpty,
      );

      // No background: nothing but the text, white, outlined in black.
      final clear = await _drawn(
        tester,
        const BandLook(_riffA, style: EditTabStyle(opacity: 0)),
      );
      expect(_at(clear, 0, 0).$4, 0);
      expect(
        _pixels(clear).where((p) => p == (255, 255, 255, 255)),
        isNotEmpty,
      );
      expect(_pixels(clear).where((p) => p == (0, 0, 0, 255)), isNotEmpty);
      // A faint background (30% or 45%) doesn't carry the text alone: the
      // outline is at full strength until 50%, then fades out by 70%.
      for (final opacity in [0.3, 0.45, 0.5]) {
        final faint = await _drawn(
          tester,
          BandLook(_riffA, style: EditTabStyle(opacity: opacity)),
        );
        expect(
          _pixels(faint).where((p) => p == (0, 0, 0, 255)),
          isNotEmpty,
          reason: '$opacity',
        );
      }
      expect(TabLayout.outlineOf(0), 1);
      expect(TabLayout.outlineOf(0.5), 1);
      expect(TabLayout.outlineOf(0.6), closeTo(0.5, 1e-9));
      expect(TabLayout.outlineOf(0.7), 0);
      expect(TabLayout.outlineOf(1), 0);
      // At 70% the background's there and the text has no outline.
      final normal = await _drawn(tester, const BandLook(_riffA));
      expect(_pixels(normal).where((p) => p == (0, 0, 0, 255)), isEmpty);
      expect(
        _pixels(normal).where((p) => p == (255, 255, 255, 255)),
        isNotEmpty,
      );
    });

    testWidgets('goes to Android and iOS in the images the layers name', (
      tester,
    ) async {
      RenderPlan plan(EditTabStyle style) => RenderPlan.of(
        PageEdit(start: Duration.zero, end: ms(20000), tabStyle: style),
        input: XFile('/tmp/made-up-take.mp4'),
        duration: ms(20000),
        inputExtension: 'mp4',
        takeLog: _log(),
        frame: const Size(1920, 1080),
      );
      Future<List<img.Image>> images(RenderPlan p) async {
        late List<Uint8List> pngs;
        await tester.runAsync(() async => pngs = await layerImages(p));
        final args = p.toChannel(output: '/tmp/out.mp4', images: pngs);
        expect(args['images'], pngs);
        expect(
          [for (final l in args['layers']! as List) (l as Map)['image']],
          [0, 1, 0],
        );
        return [for (final png in pngs) img.decodePng(png)!];
      }

      final normal = await images(plan(EditTabStyle.standard));
      final styled = await images(
        plan(
          const EditTabStyle(size: 1.5, opacity: 0, colors: TabColors.light),
        ),
      );
      expect(normal.first.width, 1920);
      expect(styled.first.width, 1920);
      expect(styled.first.height, greaterThan(normal.first.height));
      expect(_at(normal.first, 0, 0), (0, 0, 0, 0xB3));
      expect(_at(styled.first, 0, 0).$4, 0);
    });
  });

  group('the editor', () {
    late FakeEditor editor;
    setUp(() {
      VideoPlayerPlatform.instance = VolumePlatform();
      VideoEditor.instance = editor = FakeEditor();
      Downloads.save = (name, bytes, type) async => true;
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

    Future<(Library, String)> capture(
      WidgetTester tester, {
      TakeLog? log,
    }) async {
      final library = Library(PlatformEventStore(), null, (_) async => null);
      late String id;
      await tester.runAsync(() async {
        await library.load();
        var event = await library.create(const [], title: 'Blue Riff');
        final page = EventPage(
          id: 'k0',
          kind: PageKind.video,
          extension: 'mp4',
          title: 'Take 1',
          take: true,
          takeLog: log ?? _log(),
        );
        await library.putPageStream(
          event.id,
          page,
          Stream.value(Uint8List.fromList([1, 2, 3])),
        );
        event = event.copyWith(pages: [page], tabText: '$_riffA\n\n$_riffB');
        await library.update(event);
        id = event.id;
      });
      return (library, id);
    }

    void sized(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Widget app(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

    Widget editScreen(Library library, String id) => app(
      VideoEditScreen(
        library: library,
        eventId: id,
        page: library.byId(id)!.pages.first,
        pickFile: () async => null,
      ),
    );

    Future<void> tapVisible(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await settle(tester);
      await tester.tap(find.byKey(Key(key)));
    }

    /// The style the preview draws the tab's bands in (each the same).
    EditTabStyle previewStyle(WidgetTester tester) {
      final styles = {
        for (final l
            in tester.widget<EditLayers>(find.byType(EditLayers)).layers)
          if (l.look case final BandLook band) band.style,
      };
      return styles.single;
    }

    PageEdit? kept(Library library, String id) =>
        library.byId(id)!.pages.first.edit;

    Slider slider(WidgetTester tester, String which) =>
        tester.widget<Slider>(find.byKey(Key('video-edit-tab-$which')));

    String shown(WidgetTester tester, String which) => tester
        .widget<Text>(find.byKey(Key('video-edit-tab-$which-value')))
        .data!;

    bool enabled(WidgetTester tester, String key) =>
        tester.widget<ButtonStyleButton>(find.byKey(Key(key))).enabled;

    testWidgets('on a phone, the Tab chip\'s button opens its style in place '
        'of the chips: each change shows in the preview at once and is '
        'kept; a swatch picks its colours; Default style puts it back; '
        'Done closes it; Download draws it', (tester) async {
      sized(tester, const Size(400, 900));
      final (library, id) = await capture(tester);
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      expect(find.byKey(const Key('video-edit-tab-style')), findsNothing);
      expect(previewStyle(tester), EditTabStyle.standard);

      await tapVisible(tester, 'video-edit-tab-style-edit');
      await settle(tester);
      expect(find.byKey(const Key('video-edit-tab-style')), findsOneWidget);
      expect(
        find.text('Tab style · How the tab looks over the video'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('video-edit-on-video')), findsNothing);
      expect(slider(tester, 'size').value, 1);
      // The fake video is 4:3 (320 × 240): no smaller than reads on it
      // (as 50% on a 16:9 one); its short riffs grow all the way.
      expect(slider(tester, 'size').min, 0.65);
      expect(slider(tester, 'size').max, 2);
      expect(slider(tester, 'size').divisions, 27);
      expect(shown(tester, 'size'), '100%');
      expect(shown(tester, 'opacity'), '70%');
      expect(enabled(tester, 'video-edit-tab-style-reset'), isFalse);

      slider(tester, 'size').onChanged!(1.5);
      await settle(tester);
      expect(shown(tester, 'size'), '150%');
      expect(previewStyle(tester), const EditTabStyle(size: 1.5));
      slider(tester, 'opacity').onChanged!(0.25);
      await settle(tester);
      expect(shown(tester, 'opacity'), '25%');
      await tapVisible(tester, 'video-edit-tab-colors-gold');
      await settle(tester);
      const style = EditTabStyle(
        size: 1.5,
        opacity: 0.25,
        colors: TabColors.gold,
      );
      expect(previewStyle(tester), style);
      expect(kept(library, id)!.tabStyle, style);
      expect(kept(library, id)!.toJson()['tabStyle'], {
        'size': 1.5,
        'opacity': 0.25,
        'colors': 'gold',
      });
      // The swatch picked says so, to a screen reader too.
      expect(
        tester.getSemantics(
          find.byKey(const Key('video-edit-tab-colors-gold')),
        ),
        matchesSemantics(
          label: 'Gold on black',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(find.byKey(const Key('video-edit-download')));
      await settle(tester);
      expect(
        {
          for (final look in editor.rendered.single.looks)
            if (look case final BandLook band) band.style,
        },
        {style},
      );

      // Default style: as it was, the edit none again.
      await tapVisible(tester, 'video-edit-tab-style-reset');
      await settle(tester);
      expect(previewStyle(tester), EditTabStyle.standard);
      expect(kept(library, id), isNull);
      expect(shown(tester, 'size'), '100%');

      await tapVisible(tester, 'video-edit-tab-style-done');
      await settle(tester);
      expect(find.byKey(const Key('video-edit-tab-style')), findsNothing);
      expect(find.byKey(const Key('video-edit-on-video')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    Future<void> playing(WidgetTester tester, bool playing) async => expect(
      tester
          .widget<IconButton>(find.byKey(const Key('video-edit-play')))
          .tooltip,
      playing ? 'Pause' : 'Play',
    );

    testWidgets('on a phone, a long press on the band in the preview opens '
        'the style (a tap on it plays or pauses, as anywhere on the '
        'picture); a change to it turns the tab back on; the title\'s '
        'fields and the fades\' sliders take its place', (tester) async {
      sized(tester, const Size(400, 900));
      final (library, id) = await capture(tester);
      await tester.runAsync(
        () => library.setPageEdit(
          id,
          'k0',
          PageEdit(start: Duration.zero, end: ms(180000), tab: false),
        ),
      );
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      // Off: no band to press; its button still opens it.
      await tapVisible(tester, 'video-edit-tab-style-edit');
      await settle(tester);
      slider(tester, 'size').onChanged!(0.75);
      await settle(tester);
      expect(kept(library, id)!.tab, isTrue);
      expect(previewStyle(tester), const EditTabStyle(size: 0.75));

      // The fades' button closes it.
      await tapVisible(tester, 'video-edit-tab-style-done');
      await settle(tester);
      await tapVisible(tester, 'video-edit-fades-edit');
      await settle(tester);
      expect(find.byKey(const Key('video-edit-fade-fields')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('video-edit-preview')));
      await settle(tester);
      final box = tester.getRect(find.byKey(const Key('video-edit-preview')));
      final onBand = box.bottomCenter - const Offset(0, 2);

      // A tap on the band plays (and pauses) the video; nothing opens.
      await tester.tapAt(onBand);
      await settle(tester);
      await playing(tester, true);
      expect(find.byKey(const Key('video-edit-tab-style')), findsNothing);
      expect(find.byKey(const Key('video-edit-fade-fields')), findsOneWidget);
      await tester.tapAt(onBand);
      await settle(tester);
      await playing(tester, false);

      // A long press on it opens the style in the fades' place.
      await tester.longPressAt(onBand);
      await settle(tester);
      expect(find.byKey(const Key('video-edit-tab-style')), findsOneWidget);
      expect(find.byKey(const Key('video-edit-fade-fields')), findsNothing);
      await playing(tester, false);
      // Elsewhere on the picture, a long press opens nothing.
      await tapVisible(tester, 'video-edit-tab-style-done');
      await settle(tester);
      await tester.longPressAt(box.center);
      await settle(tester);
      expect(find.byKey(const Key('video-edit-tab-style')), findsNothing);
    });

    testWidgets('on a wide screen a tap on the band plays or pauses the '
        'video, as anywhere on the picture', (tester) async {
      sized(tester, const Size(1280, 900));
      final (library, id) = await capture(tester);
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      final box = tester.getRect(find.byKey(const Key('video-edit-preview')));
      final onBand = box.bottomCenter - const Offset(0, 2);
      final side = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const Key('video-edit-side')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .pixels;
      await tester.tapAt(onBand);
      await settle(tester);
      await playing(tester, true);
      await tester.tapAt(onBand);
      await settle(tester);
      await playing(tester, false);
      // Nothing scrolls nor opens (the style is always beside it), even on
      // a long press.
      await tester.longPressAt(onBand);
      await settle(tester);
      expect(
        tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byKey(const Key('video-edit-side')),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position
            .pixels,
        side,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Size slider offers only the sizes that change the '
        'band over this video', (tester) async {
      sized(tester, const Size(1280, 1000));
      // A six-string staff over the 4:3 fake video: grown, it reaches 40%
      // of the frame's height before 200%.
      final (library, id) = await capture(
        tester,
        log: TakeLog(
          burned: false,
          tab: TakeTab(lines: const [_staff], marks: const [(0, 0)]),
        ),
      );
      await tester.runAsync(
        () => library.setPageEdit(
          id,
          'k0',
          PageEdit(
            start: Duration.zero,
            end: ms(180000),
            tabStyle: const EditTabStyle(size: 2),
          ),
        ),
      );
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      const frame = Size(320, 240);
      final most = tabSizeMost(const [_staff], frame);
      expect(most, lessThan(2));
      expect(slider(tester, 'size').max, most);
      expect(slider(tester, 'size').min, TabLayout.minSizeOf(frame));
      // Kept at 200%, it's drawn (and shown) as big as it gets.
      expect(slider(tester, 'size').value, most);
      expect(shown(tester, 'size'), '${(most * 100).round()}%');
      expect(previewStyle(tester).size, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('on a wide screen the style is under the chips, without a '
        'button or Done; Reset puts it back with the rest', (tester) async {
      sized(tester, const Size(1280, 1000));
      final (library, id) = await capture(tester);
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      expect(find.byKey(const Key('video-edit-tab-style')), findsOneWidget);
      expect(find.text('How the tab looks over the video'), findsOneWidget);
      expect(find.byKey(const Key('video-edit-tab-style-edit')), findsNothing);
      expect(find.byKey(const Key('video-edit-tab-style-done')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('video-edit-side')),
          matching: find.byKey(const Key('video-edit-tab-size')),
        ),
        findsOneWidget,
      );
      await tapVisible(tester, 'video-edit-tab-colors-light');
      await settle(tester);
      slider(tester, 'opacity').onChanged!(1);
      await settle(tester);
      expect(
        previewStyle(tester),
        const EditTabStyle(opacity: 1, colors: TabColors.light),
      );
      await tester.tap(find.byKey(const Key('video-edit-reset')));
      await settle(tester);
      expect(previewStyle(tester), EditTabStyle.standard);
      expect(kept(library, id), isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a take whose tab is in its picture has no style to change', (
      tester,
    ) async {
      sized(tester, const Size(1280, 1000));
      final (library, id) = await capture(
        tester,
        log: TakeLog(burned: true, tab: _log().tab),
      );
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      expect(find.byKey(const Key('video-edit-tab-style')), findsNothing);
      sized(tester, const Size(400, 900));
      await settle(tester);
      expect(find.byKey(const Key('video-edit-tab-style-edit')), findsNothing);
    });

    for (final (name, size) in [
      ('a 360-point phone', const Size(360, 740)),
      ('a wide screen', const Size(1280, 900)),
    ]) {
      testWidgets('the style fits at the largest text size, on $name', (
        tester,
      ) async {
        sized(tester, size);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final (library, id) = await capture(tester);
        await tester.pumpWidget(editScreen(library, id));
        await settle(tester);
        if (size.width < 840) {
          await tapVisible(tester, 'video-edit-tab-style-edit');
          await settle(tester);
        }
        await tester.ensureVisible(
          find.byKey(const Key('video-edit-tab-style-reset')),
        );
        await settle(tester);
        expect(
          find.byKey(const Key('video-edit-tab-colors-brand')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the file screen\'s player draws the tab as styled', (
      tester,
    ) async {
      sized(tester, const Size(900, 1600));
      final (library, id) = await capture(tester);
      const style = EditTabStyle(size: 1.2, colors: TabColors.brand);
      await tester.runAsync(
        () => library.setPageEdit(
          id,
          'k0',
          PageEdit(start: Duration.zero, end: ms(20000), tabStyle: style),
        ),
      );
      await tester.pumpWidget(
        app(FileScreen(library: library, eventId: id, pageId: 'k0')),
      );
      await settle(tester);
      await tester.tap(find.byIcon(Icons.play_circle_fill));
      await settle(tester);
      expect(previewStyle(tester), style);
    });
  });
}
