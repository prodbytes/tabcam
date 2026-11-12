import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/edit_layers.dart';
import 'package:tabcam_app/capture/video_edit.dart';
import 'package:tabcam_app/export/download.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/edited_playback.dart';
import 'package:tabcam_app/screens/file_screen.dart';
import 'package:tabcam_app/screens/video_edit_screen.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'video_edit_test.dart' show FakeEditor, VolumePlatform;

Duration s(double seconds) => Duration(milliseconds: (seconds * 1000).round());

/// [json] through a JSON string, as saved and loaded.
Object? _encoded(Object? json) => jsonDecode(jsonEncode(json));

/// The fades in and out: the video from and to black, both sounds with
/// it, 3 s each by default, each from 0 (none) to 10 s, never more than
/// half the kept part.
void main() {
  group('the fades\' level', () {
    test('rises over the fade in, falls over the fade out, straight lines; '
        'black and silent outside the output', () {
      final fades = Fades(fadeIn: s(3), fadeOut: s(2), length: s(20));
      expect(fades.any, isTrue);
      expect(fades.levelAt(Duration.zero), 0);
      expect(fades.levelAt(s(1.5)), closeTo(0.5, 1e-9));
      expect(fades.levelAt(s(3)), 1);
      expect(fades.levelAt(s(10)), 1);
      expect(fades.levelAt(s(18)), 1);
      expect(fades.levelAt(s(19)), closeTo(0.5, 1e-9));
      expect(fades.levelAt(s(20)), 0);
      expect(fades.levelAt(s(-1)), 0);
      expect(fades.levelAt(s(21)), 0);
      expect(fades.blackAt(s(1.5)), closeTo(0.5, 1e-9));
      expect(fades.blackAt(s(10)), 0);
      // None: as it is throughout.
      expect(Fades.none.any, isFalse);
      expect(Fades.none.levelAt(Duration.zero), 1);
      expect(Fades(length: s(20)).levelAt(s(-1)), 1);
      // Only out.
      final out = Fades(fadeOut: s(4), length: s(8));
      expect(out.levelAt(Duration.zero), 1);
      expect(out.levelAt(s(6)), closeTo(0.5, 1e-9));
    });
  });

  group('in the edit', () {
    PageEdit read(Map<String, Object?> json) =>
        PageEdit.fromJson(_encoded(json))!;

    test('3 s each by default, not written; another written; an edit kept '
        'before the fades has the default ones', () {
      final edit = PageEdit(start: s(1), end: s(9));
      expect((edit.fadeIn, edit.fadeOut), (s(3), s(3)));
      expect(edit.toJson().keys, isNot(contains('fadeInMs')));
      expect(edit.toJson().keys, isNot(contains('fadeOutMs')));
      // From an older app, or before the fades: the default ones.
      for (final old in [
        {'startMs': 1000, 'endMs': 9000, 'sound': 'original'},
        {'v': 2, 'startMs': 1000, 'endMs': 9000, 'sound': 'original'},
      ]) {
        expect((read(old).fadeIn, read(old).fadeOut), (s(3), s(3)));
      }
      final changed = edit.copyWith(fadeIn: Duration.zero, fadeOut: s(5.5));
      final json = changed.toJson();
      expect(json['fadeInMs'], 0);
      expect(json['fadeOutMs'], 5500);
      expect(read(json), changed);
      expect(changed, isNot(edit));
      // Known keys, not a newer app's.
      expect(read(json).extra, isEmpty);
    });

    test('kept within 0 and 10 s', () {
      final edit = read({
        'v': 2,
        'startMs': 0,
        'endMs': 60000,
        'sound': 'original',
        'fadeInMs': -50,
        'fadeOutMs': 25000,
      });
      expect((edit.fadeIn, edit.fadeOut), (Duration.zero, s(10)));
      expect(
        PageEdit(start: Duration.zero, end: s(60)).copyWith(fadeIn: s(12)),
        PageEdit(start: Duration.zero, end: s(60), fadeIn: s(10)),
      );
      // Played at most half the kept part long.
      expect(PageEdit.fadeWithin(s(3), s(4)), s(2));
      expect(PageEdit.fadeWithin(s(9), s(60)), s(9));
      expect(PageEdit.fadeWithin(s(30), s(60)), s(10));
      expect(PageEdit.fadeWithin(s(3), Duration.zero), Duration.zero);
    });
  });

  group('in the render plan', () {
    final video = XFile('/tmp/made-up-take.mp4');

    RenderPlan plan(
      PageEdit? edit, {
      RenderKind kind = RenderKind.video,
      bool fades = true,
    }) => RenderPlan.of(
      edit,
      input: video,
      duration: s(20),
      inputExtension: 'mp4',
      kind: kind,
      fades: fades,
    );

    test('3 s each with no edit or by default, as the edit says otherwise, '
        'never more than half the kept part', () {
      expect((plan(null).fadeIn, plan(null).fadeOut), (s(3), s(3)));
      final edit = PageEdit(start: s(2), end: s(12));
      expect(
        plan(edit).fades,
        Fades(fadeIn: s(3), fadeOut: s(3), length: s(10)),
      );
      expect(
        plan(edit.copyWith(fadeIn: s(1), fadeOut: Duration.zero)).fades,
        Fades(fadeIn: s(1), length: s(10)),
      );
      // A kept part 4 s long: 2 s each, meeting in the middle.
      final short = plan(PageEdit(start: s(2), end: s(6)));
      expect((short.fadeIn, short.fadeOut), (s(2), s(2)));
      expect(short.fades.levelAt(s(2)), 1);
      // Without the picture, or without the sound: the same fades.
      expect(plan(edit, kind: RenderKind.sound).fades, plan(edit).fades);
      expect(plan(edit, kind: RenderKind.silent).fades, plan(edit).fades);
      // Left out where asked (the file screen's player).
      expect(plan(edit, fades: false).fades.any, isFalse);
    });

    test('go to the platforms as fadeInMs and fadeOutMs, left out when '
        'none; a video that fades is never saved as it is', () {
      final edit = PageEdit(start: s(2), end: s(12), fadeOut: s(1.5));
      final args = plan(edit).toChannel(output: '/tmp/out.mp4');
      expect(args['fadeInMs'], 3000);
      expect(args['fadeOutMs'], 1500);
      final none = plan(
        edit.copyWith(fadeIn: Duration.zero, fadeOut: Duration.zero),
      ).toChannel(output: '/tmp/out.mp4');
      expect(none.containsKey('fadeInMs'), isFalse);
      expect(none.containsKey('fadeOutMs'), isFalse);

      final whole = PageEdit(start: Duration.zero, end: s(20));
      expect(plan(whole).passthrough, isFalse);
      expect(
        plan(whole.copyWith(fadeIn: Duration.zero, fadeOut: Duration.zero))
            .passthrough,
        isTrue,
      );
      expect(plan(whole.copyWith(fadeIn: Duration.zero)).passthrough, isFalse);
      // Fades are part of what makes two plans the same.
      expect(plan(whole), isNot(plan(whole.copyWith(fadeIn: s(1)))));
      // A fade's change moves no sound: the preview seeks nothing for it.
      expect(plan(whole.copyWith(fadeIn: s(1))).timeline, plan(whole).timeline);
    });
  });

  testWidgets('the black painted over the preview is the fades\' at that '
      'time', (tester) async {
    Future<int> darkness(Fades fades, Duration at) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 4, 4),
        Paint()..color = Colors.white,
      );
      paintFade(canvas, const Size(4, 4), fades, at);
      final picture = recorder.endRecording();
      final bytes = (await tester.runAsync(() async {
        final image = await picture.toImage(4, 4);
        final data = await image.toByteData();
        image.dispose();
        return data!;
      }))!;
      picture.dispose();
      return 255 - bytes.getUint8(0);
    }

    final fades = Fades(fadeIn: s(2), fadeOut: s(2), length: s(10));
    expect(await darkness(fades, Duration.zero), 255);
    expect(await darkness(fades, s(1)), inInclusiveRange(126, 129));
    expect(await darkness(fades, s(5)), 0);
    expect(await darkness(fades, s(10)), 255);
    expect(await darkness(Fades.none, Duration.zero), 0);
  });

  group('the preview\'s sound', () {
    late VolumePlatform platform;
    setUp(() => VideoPlayerPlatform.instance = platform = VolumePlatform());

    Future<VideoPlayerController> player(WidgetTester tester) async {
      final take = (await tester.runAsync(() async {
        final take = VideoPlayerController.networkUrl(
          Uri.parse('https://example.com/made-up-take.mp4'),
        );
        await take.initialize();
        return take;
      }))!;
      addTearDown(take.dispose);
      return take;
    }

    Future<void> ticks(WidgetTester tester, int n) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('while it plays, the own lane fades in and out with the '
        'picture; paused, it\'s at its level; without fades, as it is', (
      tester,
    ) async {
      final take = await player(tester);
      final id = take.playerId;
      final playback = EditedPlayback(take);
      addTearDown(playback.dispose);
      // Kept 0–20 s, at 60%.
      final edit = PageEdit(start: Duration.zero, end: s(20), ownVolume: 0.6);
      await playback.set(EditedPlayback.planOf(edit, duration: s(180)));
      expect(platform.volumes[id], 0.6);

      // Played from 1.5 s: half way in, from before it plays.
      platform.position = s(1.5);
      await take.seekTo(s(1.5));
      await playback.playPause();
      expect(platform.volumes[id], closeTo(0.3, 1e-9));
      await ticks(tester, 3);
      expect(platform.volumes[id], closeTo(0.3, 1e-9));
      // In the middle: its level.
      platform.position = s(10);
      await ticks(tester, 3);
      expect(platform.volumes[id], closeTo(0.6, 1e-9));
      // 0.6 s before the end: a fifth of it.
      platform.position = s(19.4);
      await ticks(tester, 3);
      expect(platform.volumes[id], closeTo(0.12, 1e-6));
      // Paused, a change of the plan puts it at its level.
      await take.pause();
      await playback.set(EditedPlayback.planOf(edit, duration: s(180)));
      expect(platform.volumes[id], 0.6);

      // Without fades: as loud at the start as anywhere.
      await playback.set(
        EditedPlayback.planOf(
          edit.copyWith(fadeIn: Duration.zero, fadeOut: Duration.zero),
          duration: s(180),
        ),
      );
      platform.position = s(1.5);
      await take.seekTo(s(1.5));
      await playback.playPause();
      await ticks(tester, 3);
      expect(platform.volumes[id], 0.6);
      await take.pause();
      await ticks(tester, 2);
    });
  });

  group('the editor', () {
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

    /// A capture with a video (k0, 3 min long, the fake's) and a
    /// recording (k1).
    Future<(Library, String)> capture(WidgetTester tester) async {
      final library = Library(PlatformEventStore(), null, (_) async => null);
      late String id;
      await tester.runAsync(() async {
        await library.load();
        var event = await library.create(const [], title: 'Blue Riff');
        for (final page in [
          const EventPage(
            id: 'k0',
            kind: PageKind.video,
            extension: 'mp4',
            title: 'Made-up riff',
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

    /// Scrolls to [key]'s widget, and taps it.
    Future<void> tapVisible(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await settle(tester);
      await tester.tap(find.byKey(Key(key)));
    }

    InputChip chip(WidgetTester tester) =>
        tester.widget<InputChip>(find.byKey(const Key('video-edit-fades')));

    Fades previewFades(WidgetTester tester) =>
        tester.widget<EditLayers>(find.byType(EditLayers)).fades;

    PageEdit? kept(Library library, String id) =>
        library.byId(id)!.pages.first.edit;

    Slider slider(WidgetTester tester, String which) =>
        tester.widget<Slider>(find.byKey(Key('video-edit-fade-$which')));

    String shown(WidgetTester tester, String which) => tester
        .widget<Text>(find.byKey(Key('video-edit-fade-$which-value')))
        .data!;

    testWidgets('a fresh video fades in and out over 3 s: on its chip, on '
        'the Take lane, in the preview and in Download; the edit stays '
        'none. Off, none; on again, as they were', (tester) async {
      sized(tester, const Size(900, 1600));
      final (library, id) = await capture(tester);
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);

      expect(chip(tester).selected, isTrue);
      expect(find.byKey(const Key('video-edit-take-fades')), findsOneWidget);
      expect(
        previewFades(tester),
        Fades(fadeIn: s(3), fadeOut: s(3), length: s(180)),
      );
      expect(kept(library, id), isNull);
      await tester.tap(find.byKey(const Key('video-edit-download')));
      await settle(tester);
      expect(
        editor.rendered.single.fades,
        Fades(fadeIn: s(3), fadeOut: s(3), length: s(180)),
      );

      // Off: kept as none; nothing on the lane or over the preview.
      await tester.tap(find.byKey(const Key('video-edit-fades')));
      await settle(tester);
      expect(chip(tester).selected, isFalse);
      expect(
        (kept(library, id)!.fadeIn, kept(library, id)!.fadeOut),
        (Duration.zero, Duration.zero),
      );
      expect(find.byKey(const Key('video-edit-take-fades')), findsNothing);
      expect(previewFades(tester).any, isFalse);
      editor.rendered.clear();
      await tester.tap(find.byKey(const Key('video-edit-download')));
      await settle(tester);
      expect(editor.rendered.single.fades.any, isFalse);

      // On again: 3 s each, the defaults, so the edit is none again.
      await tester.tap(find.byKey(const Key('video-edit-fades')));
      await settle(tester);
      expect(chip(tester).selected, isTrue);
      expect(kept(library, id), isNull);
    });

    testWidgets('on a wide screen the sliders are beside the chips: each '
        'fade from 0 to 10 s, kept as it moves, and only half the kept '
        'part at most; Reset puts back 3 s', (tester) async {
      sized(tester, const Size(1280, 1000));
      final (library, id) = await capture(tester);
      await tester.runAsync(
        () => library.setPageEdit(id, 'k0', PageEdit(start: s(2), end: s(6))),
      );
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      expect(find.byKey(const Key('video-edit-fade-fields')), findsOneWidget);
      expect(find.byKey(const Key('video-edit-fades-edit')), findsNothing);
      // A 4 s kept part: at most 2 s each, though 3 s is kept.
      expect(slider(tester, 'in').max, 2);
      expect(shown(tester, 'in'), '2.0 s');
      expect(previewFades(tester).fadeIn, s(2));

      // The whole video kept again: up to 10 s, the 3 s kept back.
      await tester.runAsync(() => library.setPageEdit(id, 'k0', null));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      expect(slider(tester, 'in').max, 10);
      expect(slider(tester, 'in').value, 3);

      slider(tester, 'in').onChanged!(1.54);
      await settle(tester);
      slider(tester, 'out').onChanged!(8);
      await settle(tester);
      expect(shown(tester, 'in'), '1.5 s');
      expect(shown(tester, 'out'), '8.0 s');
      expect(
        (kept(library, id)!.fadeIn, kept(library, id)!.fadeOut),
        (s(1.5), s(8)),
      );
      expect(kept(library, id)!.toJson()['fadeOutMs'], 8000);
      expect(
        previewFades(tester),
        Fades(fadeIn: s(1.5), fadeOut: s(8), length: s(180)),
      );

      // No fades: both none; the chip with them.
      await tester.tap(find.byKey(const Key('video-edit-fades-off')));
      await settle(tester);
      expect(chip(tester).selected, isFalse);
      expect(slider(tester, 'in').value, 0);
      // Back on: as they were.
      await tester.tap(find.byKey(const Key('video-edit-fades')));
      await settle(tester);
      expect(
        (kept(library, id)!.fadeIn, kept(library, id)!.fadeOut),
        (s(1.5), s(8)),
      );

      await tester.tap(find.byKey(const Key('video-edit-reset')));
      await settle(tester);
      expect(kept(library, id), isNull);
      expect(slider(tester, 'in').value, 3);
      expect(slider(tester, 'out').value, 3);
    });

    testWidgets('on a phone, the chip\'s button opens the sliders in place '
        'of the chips (closing the title\'s fields); Done closes them; they '
        'fit at the largest text size', (tester) async {
      sized(tester, const Size(400, 900));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final (library, id) = await capture(tester);
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      expect(find.byKey(const Key('video-edit-fade-fields')), findsNothing);

      await tapVisible(tester, 'video-edit-fades-edit');
      await settle(tester);
      expect(find.byKey(const Key('video-edit-fade-fields')), findsOneWidget);
      expect(find.byKey(const Key('video-edit-on-video')), findsNothing);
      slider(tester, 'out').onChanged!(0);
      await settle(tester);
      expect(kept(library, id)!.fadeOut, Duration.zero);
      expect(kept(library, id)!.fadeIn, s(3));
      expect(tester.takeException(), isNull);

      await tapVisible(tester, 'video-edit-fades-done');
      await settle(tester);
      expect(find.byKey(const Key('video-edit-fade-fields')), findsNothing);
      expect(find.byKey(const Key('video-edit-on-video')), findsOneWidget);
      // Still fading in: the chip's on.
      expect(chip(tester).selected, isTrue);

      // Open again, a tap on the title in the preview opens its fields in
      // their place.
      await tapVisible(tester, 'video-edit-fades-edit');
      await settle(tester);
      expect(find.byKey(const Key('video-edit-fade-fields')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('video-edit-preview')));
      await settle(tester);
      final box = tester.getRect(find.byKey(const Key('video-edit-preview')));
      await tester.tapAt(
        box.topLeft + Offset(box.shortestSide * 0.05, box.shortestSide * 0.05),
      );
      await settle(tester);
      expect(find.byKey(const Key('video-edit-title-fields')), findsOneWidget);
      expect(find.byKey(const Key('video-edit-fade-fields')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the preview draws the black only while it plays: paused, '
        'the frame shows as it is (a trim shows where it cuts)', (
      tester,
    ) async {
      sized(tester, const Size(900, 1600));
      final (library, id) = await capture(tester);
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      EditLayersPainter painter() =>
          tester
                  .widget<CustomPaint>(find.byKey(const Key('edit-layers')))
                  .painter!
              as EditLayersPainter;
      expect(painter().fades.any, isTrue);
      expect(painter().playing.value, isFalse);
      await tester.tap(find.byKey(const Key('video-edit-play')));
      await frames(tester);
      expect(painter().playing.value, isTrue);
      await tester.tap(find.byKey(const Key('video-edit-play')));
      await frames(tester);
      expect(painter().playing.value, isFalse);
    });

    testWidgets('the file screen\'s player leaves the fades to Download: '
        'no black, its sound as the edit says from the start', (tester) async {
      sized(tester, const Size(900, 1600));
      final (library, id) = await capture(tester);
      await tester.runAsync(
        () => library.setPageEdit(
          id,
          'k0',
          PageEdit(start: Duration.zero, end: s(20), ownVolume: 0.5),
        ),
      );
      platform.position = s(1);
      await tester.pumpWidget(
        app(FileScreen(library: library, eventId: id, pageId: 'k0')),
      );
      await settle(tester);
      await tester.tap(find.byIcon(Icons.play_circle_fill));
      await settle(tester);
      expect(previewFades(tester).any, isFalse);
      expect(platform.volumes[platform.lastPlayer], 0.5);
    });
  });
}
