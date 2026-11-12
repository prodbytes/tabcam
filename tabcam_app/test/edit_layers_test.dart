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
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'video_edit_test.dart' show FakeEditor, VolumePlatform;

Duration ms(int n) => Duration(milliseconds: n);

/// Made-up necklines.
const _riffA = 'e|--3--5--7--|';
const _riffB = 'e|--5--7--8--|';

/// A take's log: its tab's turns ([marks], on the take's clock, into
/// [_riffA] and [_riffB]), [lagMs], and whether it's [burned] in.
TakeLog _log({
  List<(int, int)> marks = const [(0, 0), (4210, 1), (8380, 0)],
  int lagMs = 0,
  bool burned = false,
}) => TakeLog(
  burned: burned,
  lagMs: lagMs,
  tab: TakeTab(lines: const [_riffA, _riffB], marks: marks),
);

/// The tab layers' times and lines, for comparing (the watermark and the
/// title left out).
List<(int, int?, String)> _bands(RenderPlan plan) => [
  for (final l in plan.layers)
    if (l.id == 'tab')
      (l.from.inMilliseconds, l.to?.inMilliseconds, (l.look as BandLook).line),
];

void main() {
  final video = XFile('/tmp/made-up-take.mp4');

  RenderPlan plan(
    PageEdit? edit,
    TakeLog? log, {
    RenderKind kind = RenderKind.video,
    Duration duration = const Duration(seconds: 20),
  }) => RenderPlan.of(
    edit,
    input: video,
    duration: duration,
    inputExtension: 'mp4',
    takeLog: log,
    kind: kind,
  );

  group('the tab layer', () {
    test('mapped through the trim: a start trimmed at 3 s cuts the first '
        'band, the rest move with it', () {
      final p = plan(PageEdit(start: ms(3000), end: ms(20000)), _log());
      expect(_bands(p), [
        (0, 1210, _riffA),
        (1210, 5380, _riffB),
        (5380, 17000, _riffA),
      ]);
      for (final l in p.layers) {
        expect(l.id, 'tab');
        expect(l.anchor, LayerAnchor.bottomFull);
        expect(l.fadeIn, Duration.zero);
        expect(l.opacity, 1);
      }
    });

    test('and through the lag: a turn is lagMs later in the file, the '
        'first staying at its start', () {
      final p = plan(null, _log(lagMs: 180));
      expect(_bands(p), [
        (0, 4390, _riffA),
        (4390, 8560, _riffB),
        (8560, 20000, _riffA),
      ]);
    });

    test('a turn back to the line showing carries its band on; an end trim '
        'cuts the last band', () {
      final log = _log(
        marks: const [(0, 0), (2000, 0), (4000, 1), (6000, 1), (9000, 0)],
      );
      final p = plan(PageEdit(start: Duration.zero, end: ms(7000)), log);
      expect(_bands(p), [(0, 4000, _riffA), (4000, 7000, _riffB)]);
      // Trimmed inside a band: only it.
      expect(_bands(plan(PageEdit(start: ms(4500), end: ms(5500)), log)), [
        (0, 1000, _riffB),
      ]);
    });

    test('its text is the log\'s: the lines the take showed, whatever the '
        'capture\'s tab is now', () {
      // The log keeps its own copy of each neckline; nothing else is read.
      final p = plan(null, _log());
      expect(p.looks, const [BandLook(_riffA), BandLook(_riffB)]);
    });

    test('only for a take whose tab isn\'t in its picture, unless turned off; '
        'never in the sound alone', () {
      expect(plan(null, _log(burned: true)).layers, isEmpty);
      expect(plan(null, null).layers, isEmpty);
      expect(
        plan(null, TakeLog(burned: false)).layers,
        isEmpty,
        reason: 'no tab',
      );
      expect(
        plan(
          PageEdit(start: Duration.zero, end: ms(20000), tab: false),
          _log(),
        ).layers,
        isEmpty,
      );
      expect(plan(null, _log(), kind: RenderKind.sound).layers, isEmpty);
      // The video without sound keeps it: only the sound is dropped.
      expect(plan(null, _log(), kind: RenderKind.silent).layers, hasLength(3));
      expect(tabOffered(_log()), isTrue);
      expect(tabOffered(_log(burned: true)), isFalse);
      expect(tabOffered(null), isFalse);
    });

    test('a video with layers is never saved as it is', () {
      expect(plan(null, null).passthrough, isTrue);
      expect(plan(null, _log()).passthrough, isFalse);
      expect(plan(null, _log(burned: true)).passthrough, isTrue);
    });

    test('goes to the platforms as images, each look once, and layers '
        'naming them', () {
      final p = plan(PageEdit(start: ms(3000), end: ms(20000)), _log());
      final images = [
        Uint8List.fromList([1]),
        Uint8List.fromList([2]),
      ];
      final args = p.toChannel(output: '/tmp/out.mp4', images: images);
      expect(args['images'], images);
      expect(args['layers'], [
        {
          'id': 'tab',
          'image': 0,
          'anchor': 'bottomFull',
          'heightU': 0.0,
          'marginU': 0.0,
          'liftU': 0.0,
          'liftW': 0.0,
          'fromMs': 0,
          'toMs': 1210,
          'fadeInMs': 0,
          'opacity': 1.0,
        },
        containsPair('image', 1),
        containsPair('image', 0),
      ]);
      expect(() => p.toChannel(output: '/tmp/out.mp4'), throwsArgumentError);
      // None: no images, no layers.
      final none = plan(null, null).toChannel(output: '/tmp/out.mp4');
      expect(none.containsKey('layers'), isFalse);
      expect(none.containsKey('images'), isFalse);
    });

    test('Tab off is kept as tab: false, and only then', () {
      final on = PageEdit(start: Duration.zero, end: ms(1000));
      expect(on.tab, isTrue);
      expect(on.toJson().containsKey('tab'), isFalse);
      final off = on.copyWith(tab: false);
      expect(off.toJson()['tab'], false);
      final back = PageEdit.fromJson(jsonDecode(jsonEncode(off.toJson())))!;
      expect(back.tab, isFalse);
      expect(back, off);
      expect(PageEdit.fromJson(on.toJson())!.tab, isTrue);
    });
  });

  testWidgets('a band is as wide as asked, a strip along the bottom', (
    tester,
  ) async {
    late img.Image band;
    await tester.runAsync(() async {
      band = img.decodePng(
        await renderBand('e|--0--3--|\nB|--1--1--|\nG|--2--0--|'),
      )!;
    });
    expect(band.width, bandWidth);
    expect(band.height, lessThan(band.width ~/ 2));
    expect(band.height, greaterThan(0));
  });

  group('a layer', () {
    test('fades in from its start, to its opacity, and shows only while '
        'it lasts', () {
      const title = PlanLayer(
        id: 'title',
        look: BandLook('x'),
        anchor: LayerAnchor.topLeft,
        fadeIn: Duration(seconds: 3),
        opacity: 0.8,
      );
      expect(title.alphaAt(Duration.zero), 0);
      expect(title.alphaAt(ms(1500)), closeTo(0.4, 1e-9));
      expect(title.alphaAt(ms(3000)), 0.8);
      expect(title.alphaAt(const Duration(minutes: 10)), 0.8);
      const band = PlanLayer(
        id: 'tab',
        look: BandLook('x'),
        anchor: LayerAnchor.bottomFull,
        from: Duration(seconds: 1),
        to: Duration(seconds: 2),
      );
      expect(band.alphaAt(ms(999)), 0);
      expect(band.alphaAt(ms(1000)), 1);
      expect(band.alphaAt(ms(1999)), 1);
      expect(band.alphaAt(ms(2000)), 0);
    });

    test('is placed by its anchor, in fractions of the short side', () {
      const image = Size(400, 200);
      PlanLayer at(LayerAnchor anchor) => PlanLayer(
        id: 'x',
        look: const BandLook('x'),
        anchor: anchor,
        heightU: 0.5,
        marginU: 0.25,
        liftU: 0.125,
      );
      // Landscape, the short side 1024: half of it high, a quarter in.
      const landscape = Size(1920, 1024);
      expect(
        at(LayerAnchor.topLeft).rectIn(landscape, image),
        const Rect.fromLTWH(256, 256, 1024, 512),
      );
      expect(
        at(LayerAnchor.bottomRight).rectIn(landscape, image),
        const Rect.fromLTWH(640, 128, 1024, 512),
      );
      // A band: as wide as the frame, along its bottom.
      expect(
        at(LayerAnchor.bottomFull).rectIn(landscape, const Size(1280, 240)),
        const Rect.fromLTWH(0, 664, 1920, 360),
      );
      // Portrait: the same sizes, the short side being its width.
      const portrait = Size(1024, 1920);
      expect(
        at(LayerAnchor.topLeft).rectIn(portrait, image),
        const Rect.fromLTWH(256, 256, 1024, 512),
      );
    });
  });

  group('the layers over a playing video', () {
    testWidgets('carry on from its last report through notices that don\'t '
        'move it (its volume, its buffering); a new report or a seek is '
        'the new start', (tester) async {
      VideoPlayerPlatform.instance = VolumePlatform();
      final video = VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/made-up-take.mp4'),
      );
      addTearDown(video.dispose);
      video.value = const VideoPlayerValue(
        duration: Duration(seconds: 20),
        position: Duration(seconds: 12),
        isInitialized: true,
        isPlaying: true,
      );
      await tester.pumpWidget(
        EditLayers(video: video, layers: const [], start: ms(2000)),
      );
      Duration at() =>
          (tester
                      .widget<CustomPaint>(find.byKey(const Key('edit-layers')))
                      .painter!
                  as EditLayersPainter)
              .at
              .value;
      for (var i = 0; i < 3; i++) {
        await tester.pump(ms(50));
      }
      // 150 ms past the report, 2 s trimmed off the start.
      expect(at(), ms(10150));
      // A volume change (a lane's slider dragged), then buffering: the
      // same place, so the clock carries on, not back to 10 s.
      video.value = video.value.copyWith(volume: 0.5);
      expect(at(), ms(10150));
      await tester.pump(ms(50));
      expect(at(), ms(10200));
      video.value = video.value.copyWith(isBuffering: true);
      await tester.pump(ms(50));
      expect(at(), ms(10250));
      // The player's next report: from there.
      video.value = video.value.copyWith(position: ms(12300));
      expect(at(), ms(10300));
      await tester.pump(ms(50));
      expect(at(), ms(10350));
      // A player that stops reporting: carried on 0.4 s at most.
      for (var i = 0; i < 20; i++) {
        await tester.pump(ms(50));
      }
      expect(at(), ms(10700));
      // Paused: where it says, and the volume doesn't move it.
      video.value = video.value.copyWith(isPlaying: false);
      expect(at(), ms(10300));
      video.value = video.value.copyWith(volume: 1);
      await tester.pump(ms(50));
      expect(at(), ms(10300));
      // A seek while paused: there.
      video.value = video.value.copyWith(position: ms(5000));
      expect(at(), ms(3000));
    });
  });

  group('the editor and the file screen', () {
    late VolumePlatform platform;
    late FakeEditor editor;
    final saved = <(String, Uint8List, String)>[];
    setUp(() {
      VideoPlayerPlatform.instance = platform = VolumePlatform();
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

    /// A capture whose tab is [tabText], with a video (k0): one of Cam's
    /// takes with [log] when [take], else a video added.
    Future<(Library, String)> capture(
      WidgetTester tester, {
      TakeLog? log,
      bool take = true,
      String tabText = '$_riffA\n\n$_riffB',
    }) async {
      final library = Library(PlatformEventStore(), null, (_) async => null);
      late String id;
      await tester.runAsync(() async {
        await library.load();
        var event = await library.create(const []);
        final page = EventPage(
          id: 'k0',
          kind: PageKind.video,
          extension: 'mp4',
          title: take ? 'Take 1' : 'Made-up riff',
          take: take,
          takeLog: log,
        );
        await library.putPageStream(
          event.id,
          page,
          Stream.value(Uint8List.fromList([1, 2, 3])),
        );
        event = event.copyWith(pages: [page], tabText: tabText);
        await library.update(event);
        id = event.id;
      });
      return (library, id);
    }

    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Widget host(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

    Widget editScreen(Library library, String id) => host(
      VideoEditScreen(
        library: library,
        eventId: id,
        page: library.byId(id)!.pages.first,
        pickFile: () async => null,
      ),
    );

    FilterChip tabChip(WidgetTester tester) =>
        tester.widget<FilterChip>(find.byKey(const Key('video-edit-tab')));

    /// The tab's bands over the preview (the watermark, always there
    /// here, left out).
    List<PlanLayer> previewLayers(WidgetTester tester) {
      final found = find.byType(EditLayers);
      if (found.evaluate().isEmpty) return const [];
      return [
        for (final l in tester.widget<EditLayers>(found).layers)
          if (l.id == 'tab') l,
      ];
    }

    bool enabled(WidgetTester tester, String key) =>
        tester.widget<ButtonStyleButton>(find.byKey(Key(key))).enabled;

    testWidgets('a take whose tab is kept apart: the Tab chip, on; the '
        'preview draws its bands, Download renders them, the edit stays '
        'none; Tab off keeps tab: false, and takes them out of both', (
      tester,
    ) async {
      tall(tester);
      final (library, id) = await capture(tester, log: _log());
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);

      expect(find.text('On the video'), findsOneWidget);
      expect(tabChip(tester).selected, isTrue);
      expect(tabChip(tester).onSelected, isNotNull);
      expect(tabChip(tester).tooltip, contains('as it showed'));
      // Enabled, the chip's tooltip is in the tree; no line saying why not.
      expect(
        find.descendant(
          of: find.byKey(const Key('video-edit-tab')),
          matching: find.byWidgetPredicate(
            (w) => w is Tooltip && w.message == tabChip(tester).tooltip,
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('video-edit-tab-why')), findsNothing);
      // The whole take (3:00, the fake's), its bands over the preview.
      expect(previewLayers(tester).map((l) => (l.look as BandLook).line), [
        _riffA,
        _riffB,
        _riffA,
      ]);
      expect(library.byId(id)!.pages.first.edit, isNull);
      expect(enabled(tester, 'video-edit-reset'), isFalse);

      // Download: made, with the tab, not the file as it is.
      await tester.tap(find.byKey(const Key('video-edit-download')));
      await settle(tester);
      final made = editor.rendered.single;
      expect(made.passthrough, isFalse);
      expect(_bands(made), [
        (0, 4210, _riffA),
        (4210, 8380, _riffB),
        (8380, 180000, _riffA),
      ]);
      expect(saved.single.$2, [9, 9, 9]);

      // Tab off: kept, gone from the preview and from Download.
      await tester.tap(find.byKey(const Key('video-edit-tab')));
      await settle(tester);
      expect(tabChip(tester).selected, isFalse);
      expect(previewLayers(tester), isEmpty);
      final edit = library.byId(id)!.pages.first.edit!;
      expect(edit.tab, isFalse);
      expect(edit.toJson()['tab'], false);
      expect(enabled(tester, 'video-edit-reset'), isTrue);
      editor.rendered.clear();
      saved.clear();
      await tester.tap(find.byKey(const Key('video-edit-download')));
      await settle(tester);
      // Nothing else changed: the take, its watermark alone over it.
      expect(_bands(editor.rendered.single), isEmpty);
      expect(editor.rendered.single.layers.single.id, 'mark');

      // Reset: the tab on again, and no edit.
      await tester.tap(find.byKey(const Key('video-edit-reset')));
      await settle(tester);
      expect(tabChip(tester).selected, isTrue);
      expect(previewLayers(tester), hasLength(3));
      expect(library.byId(id)!.pages.first.edit, isNull);
    });

    testWidgets('the bands are the log\'s, though the capture\'s tab changed '
        'since', (tester) async {
      tall(tester);
      final (library, id) = await capture(
        tester,
        log: _log(),
        tabText: 'e|--0--0--0--|',
      );
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      await tester.tap(find.byKey(const Key('video-edit-download')));
      await settle(tester);
      expect(editor.rendered.single.looks.whereType<BandLook>(), const [
        BandLook(_riffA),
        BandLook(_riffB),
      ]);
    });

    testWidgets('a take with its tab in its picture, or from before takes '
        'kept a log: the chip off and disabled, in a tooltip saying why (a '
        'disabled chip shows none of its own), shown on a tap; no line of '
        'its own; nothing drawn', (tester) async {
      tall(tester);
      for (final (log, why) in [
        (_log(burned: true), 'This take has the tab in its picture'),
        (
          null,
          "This take is from an earlier version: its tab can't be drawn "
              'over it',
        ),
      ]) {
        final (library, id) = await capture(tester, log: log);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(editScreen(library, id));
        await settle(tester);
        expect(tabChip(tester).selected, isFalse, reason: '$log');
        expect(tabChip(tester).onSelected, isNull, reason: '$log');
        final tooltip = find.byKey(const Key('video-edit-tab-why'));
        expect(tester.widget<Tooltip>(tooltip).message, why, reason: '$log');
        expect(
          find.descendant(
            of: tooltip,
            matching: find.byKey(const Key('video-edit-tab')),
          ),
          findsOneWidget,
          reason: '$log',
        );
        expect(find.text(why), findsNothing, reason: '$log');
        await tester.tap(find.byKey(const Key('video-edit-tab')));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text(why), findsOneWidget, reason: '$log');
        expect(tabChip(tester).selected, isFalse, reason: '$log');
        await tester.pump(const Duration(seconds: 2));
        await frames(tester);
        expect(previewLayers(tester), isEmpty, reason: '$log');
        editor.rendered.clear();
        saved.clear();
        await tester.tap(find.byKey(const Key('video-edit-download')));
        await settle(tester);
        expect(_bands(editor.rendered.single), isEmpty, reason: '$log');
      }
    });

    testWidgets('a video that isn\'t a take, or a take without a tab (its '
        'log has none; with no log, its capture has none): no Tab chip, '
        'the title and the watermark only', (tester) async {
      tall(tester);
      for (final (log, take, tabText) in [
        (null, false, '$_riffA\n\n$_riffB'),
        (const TakeLog(burned: false), true, '$_riffA\n\n$_riffB'),
        (null, true, ''),
      ]) {
        final (library, id) = await capture(
          tester,
          log: log,
          take: take,
          tabText: tabText,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(editScreen(library, id));
        await settle(tester);
        expect(find.byKey(const Key('video-edit-tab')), findsNothing);
        expect(find.text('On the video'), findsOneWidget);
        expect(find.byKey(const Key('video-edit-title')), findsOneWidget);
        expect(find.byKey(const Key('video-edit-watermark')), findsOneWidget);
        expect(previewLayers(tester), isEmpty);
      }
    });

    testWidgets('the file screen plays a take with its tab over it, with no '
        'edit too; trimmed, from the kept part\'s start', (tester) async {
      tall(tester);
      final (library, id) = await capture(tester, log: _log());
      await tester.pumpWidget(
        host(FileScreen(library: library, eventId: id, pageId: 'k0')),
      );
      await settle(tester);
      await tester.tap(find.byIcon(Icons.play_circle_fill));
      await settle(tester);
      final layers = tester.widget<EditLayers>(find.byType(EditLayers));
      expect(layers.layers, hasLength(3));
      expect(layers.start, Duration.zero);

      await tester.runAsync(
        () => library.setPageEdit(
          id,
          'k0',
          PageEdit(start: ms(3000), end: ms(20000)),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        host(FileScreen(library: library, eventId: id, pageId: 'k0')),
      );
      await settle(tester);
      await tester.tap(find.byIcon(Icons.play_circle_fill));
      await settle(tester);
      final trimmed = tester.widget<EditLayers>(find.byType(EditLayers));
      expect(trimmed.start, ms(3000));
      expect(trimmed.layers.first.to, ms(1210));
      // Played: the video's own sound as it is.
      expect(platform.volumes[platform.lastPlayer], 1);
    });

    testWidgets('the layers follow the video as it plays, carried on '
        'between its reports', (tester) async {
      tall(tester);
      final (library, id) = await capture(tester, log: _log());
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      EditLayersPainter painter() =>
          tester
                  .widget<CustomPaint>(find.byKey(const Key('edit-layers')))
                  .painter!
              as EditLayersPainter;
      // Paused at the start: as the player says.
      expect(painter().at.value, Duration.zero);
      // Playing: the player reports 12 s in (the fake's), and the frame
      // clock carries it on a little between reports.
      await tester.tap(find.byKey(const Key('video-edit-play')));
      await frames(tester);
      expect(painter().at.value.inMilliseconds, inInclusiveRange(12000, 12400));
      // Paused again: where the player last said, and nothing runs.
      await tester.tap(find.byKey(const Key('video-edit-play')));
      await frames(tester);
      expect(painter().at.value, ms(12000));
    });
  });
}
