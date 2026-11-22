import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart' show CameraController, CameraImage;
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/backing_track.dart';
import 'package:tabcam_app/capture/cam_session.dart';
import 'package:tabcam_app/capture/head_gestures.dart';
import 'package:tabcam_app/capture/media.dart';
import 'package:tabcam_app/capture/play_along_screen.dart';
import 'package:tabcam_app/capture/play_along_sidebar.dart' show PhraseMarks;
import 'package:tabcam_app/capture/take_log.dart';
import 'package:tabcam_app/capture/sound_reader.dart';
import 'package:tabcam_app/capture/take_sound.dart';
import 'package:tabcam_app/capture/video_edit.dart';
import 'package:tabcam_app/capture/waveform.dart';
import 'package:tabcam_app/cloud/cloud_ocr.dart';
import 'package:tabcam_app/cloud/cloud_sync.dart';
import 'package:tabcam_app/dictionary/dictionary_sidebar.dart';
import 'package:tabcam_app/export/download.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/metronome/metronome.dart';
import 'package:tabcam_app/metronome/click_track.dart';
import 'package:tabcam_app/metronome/metronome_sound.dart';
import 'package:tabcam_app/screens/download_settings.dart';
import 'package:tabcam_app/screens/sidebar_widths.dart';
import 'package:tabcam_app/screens/video_edit_screen.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'cloud_ocr_test.dart' show FakeOcrApi;
import 'fake_camera.dart';
import 'fakes.dart';
import 'mini_player_test.dart' show FakeVideoPlatform;
import 'video_edit_test.dart' show FakeEditor, VolumePlatform;

Duration s(double seconds) => Duration(milliseconds: (seconds * 1000).round());

/// An editor whose renders wait for [hold]: a Download in progress.
class _HeldEditor extends FakeEditor {
  final hold = Completer<void>();

  @override
  Future<XFile> render(
    RenderPlan plan, {
    void Function(double done)? onProgress,
  }) async {
    await hold.future;
    return super.render(plan, onProgress: onProgress);
  }
}

/// Head gestures, faked: whether they're told to look.
class _Heads implements HeadTracking {
  @override
  bool active = true;

  @override
  set recording(bool recording) {}

  @override
  void onImage(CameraImage image) {}

  @override
  final ValueNotifier<bool> face = ValueNotifier(true);

  @override
  set camera(CameraController camera) {}

  @override
  void dispose() {}
}

/// The metronome's clicks, faked.
class _Clicks implements MetronomeSound {
  @override
  Future<void> start(int bpm, TimeSignature signature) async {}

  @override
  Future<void> stop() async {}
}

/// The camera, faked, counting how many times its preview is built and
/// the cameras are asked for.
class _Camera extends FakeCameraPlatform {
  int previews = 0;
  int asked = 0;

  @override
  Widget buildPreview(int cameraId) {
    previews++;
    return super.buildPreview(cameraId);
  }

  @override
  Future<List<CameraDescription>> availableCameras() {
    asked++;
    return super.availableCameras();
  }
}

const _front = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 0,
);

/// A made-up riff, two phrases long.
const _tab = '''
e|--0--3--|
B|--1--1--|

e|--5--7--|
B|--5--8--|
''';

/// A made-up riff on all six strings, one phrase: as high as a phrase
/// gets on a guitar.
const _sixStrings = '''
e|--0--3--|
B|--1--1--|
G|--0--0--|
D|--2--0--|
A|--3--2--|
E|-----3--|
''';

void main() {
  late VolumePlatform platform;
  setUp(() {
    VideoPlayerPlatform.instance = platform = VolumePlatform();
    VideoEditor.instance = FakeEditor();
    Downloads.save = (name, bytes, type) async => true;
  });
  tearDown(() {
    VideoEditor.instance = null;
    DownloadSettingsState.instance.reset();
    SidebarWidths.instance.clear();
    DictionaryState.instance.clear();
    MetronomeState.instance.close();
  });

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Lets the view's players open (they do, off the test clock).
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await frames(tester);
  }

  /// A capture named [title] with a video (k0, named [first]), a
  /// recording (k1) and another video (k2, named [second]), kept edited
  /// to 0:10–0:20 when [secondEdit] is.
  Future<(Library, String)> capture(
    WidgetTester tester, {
    Library? into,
    String title = 'Made-up riffs',
    String first = 'First riff',
    String second = 'Second riff',
    PageEdit? secondEdit,
  }) async {
    final library =
        into ?? Library(PlatformEventStore(), null, (_) async => null);
    late String id;
    await tester.runAsync(() async {
      if (into == null) await library.load();
      var event = await library.create(const [], title: title);
      final pages = [
        EventPage(
          id: 'k0',
          kind: PageKind.video,
          extension: 'mp4',
          title: first,
        ),
        const EventPage(id: 'k1', kind: PageKind.audio, extension: 'm4a'),
        EventPage(
          id: 'k2',
          kind: PageKind.video,
          extension: 'mp4',
          title: second,
          edit: secondEdit,
        ),
      ];
      for (final page in pages) {
        await library.putPageStream(
          event.id,
          page,
          Stream.value(Uint8List.fromList([1, 2, 3])),
        );
      }
      event = event.copyWith(pages: pages);
      await library.update(event);
      id = event.id;
    });
    return (library, id);
  }

  Widget editScreen(Library library, String id, {VideoEditing? editor}) =>
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: VideoEditScreen(
          library: library,
          eventId: id,
          page: library.byId(id)!.pages.first,
          editor: editor,
          pickFile: () async => null,
        ),
      );

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Switches the view's main row to [page] ([StudioView.switchMain]),
  /// lets it open, and says whether it switched.
  Future<bool> switchTo(
    WidgetTester tester,
    EventPage? page, {
    String? eventId,
  }) async {
    bool? switched;
    unawaited(
      StudioView.switchMain(
        tester.state<State<StudioView>>(find.byType(StudioView)),
        page,
        eventId: eventId,
      ).then((done) => switched = done),
    );
    await settle(tester);
    await settle(tester);
    expect(switched, isNotNull, reason: 'the switch finished');
    return switched!;
  }

  EventPage pageOf(Library library, String id, String pageId) =>
      library.byId(id)!.pages.firstWhere((p) => p.id == pageId);

  /// The app bar's title.
  String? titleShown(WidgetTester tester) =>
      (tester.widget<AppBar>(find.byType(AppBar)).title as Text).data;

  group('the main row switched', () {
    testWidgets('from A to B: A\'s change still waiting is kept with A, B '
        'opens with its own edit, untouched, and B\'s changes are B\'s', (
      tester,
    ) async {
      tall(tester);
      final kept = PageEdit(start: s(10), end: s(20));
      final (library, id) = await capture(tester, secondEdit: kept);
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      expect(titleShown(tester), 'First riff');
      expect(find.text('Keep 0:00.0–3:00.0'), findsOneWidget);

      // Trimmed to where the player is, 12 s in; not kept yet.
      await tester.tap(find.byKey(const Key('video-edit-end-here')));
      await tester.pump();
      expect(find.text('Keep 0:00.0–0:12.0'), findsOneWidget);
      expect(pageOf(library, id, 'k0').edit, isNull);

      expect(await switchTo(tester, pageOf(library, id, 'k2')), isTrue);
      // A's change kept with A at once, as it went.
      expect(pageOf(library, id, 'k0').edit, PageEdit(start: s(0), end: s(12)));
      // B as it was kept: untouched, and shown.
      expect(pageOf(library, id, 'k2').edit, kept);
      expect(titleShown(tester), 'Second riff');
      expect(find.text('Keep 0:10.0–0:20.0'), findsOneWidget);
      expect(find.byKey(const Key('video-edit-preview')), findsOneWidget);
      // A's player let go of, B's its own.
      expect(platform.disposed, [0]);
      expect(platform.lastPlayer, 1);
      // Nothing of A's is B's: Reset is B's, the edit kept is B's.
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const Key('video-edit-reset')),
            )
            .enabled,
        isTrue,
      );

      // A change now is B's, kept with B; A's stays as it was kept.
      await tester.tap(find.byKey(const Key('video-edit-start-here')));
      await settle(tester);
      expect(find.text('Keep 0:12.0–0:20.0'), findsOneWidget);
      expect(
        pageOf(library, id, 'k2').edit,
        PageEdit(start: s(12), end: s(20)),
      );
      expect(pageOf(library, id, 'k0').edit, PageEdit(start: s(0), end: s(12)));
    });

    testWidgets('to another capture\'s page: the change waiting is kept '
        'with the first capture\'s, the next ones with the other\'s', (
      tester,
    ) async {
      tall(tester);
      final (library, id) = await capture(tester);
      final (_, other) = await capture(
        tester,
        into: library,
        title: 'Other riffs',
        first: 'Other riff',
      );
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      await tester.tap(find.byKey(const Key('video-edit-end-here')));
      await tester.pump();

      expect(
        await switchTo(tester, pageOf(library, other, 'k0'), eventId: other),
        isTrue,
      );
      expect(pageOf(library, id, 'k0').edit, PageEdit(start: s(0), end: s(12)));
      expect(pageOf(library, other, 'k0').edit, isNull);
      expect(titleShown(tester), 'Other riff');
      expect(find.text('Keep 0:00.0–3:00.0'), findsOneWidget);

      await tester.tap(find.byKey(const Key('video-edit-start-here')));
      await settle(tester);
      expect(
        pageOf(library, other, 'k0').edit,
        PageEdit(start: s(12), end: s(180)),
      );
      expect(pageOf(library, id, 'k0').edit, PageEdit(start: s(0), end: s(12)));
    });

    testWidgets('to none: no player opens and nothing spins; back to A, it '
        'opens again with the edit it was left with', (tester) async {
      tall(tester);
      final (library, id) = await capture(tester);
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      await tester.tap(find.byKey(const Key('video-edit-end-here')));
      await tester.pump();

      expect(await switchTo(tester, null), isTrue);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const Key('video-edit-preview')), findsNothing);
      expect(find.byKey(const Key('video-edit-retry')), findsNothing);
      expect(find.byKey(const Key('video-edit-reset')), findsNothing);
      expect(platform.disposed, [0]);
      expect(platform.lastPlayer, 0);
      expect(pageOf(library, id, 'k0').edit, PageEdit(start: s(0), end: s(12)));
      // Nothing is kept from none.
      await settle(tester);
      expect(pageOf(library, id, 'k0').edit, PageEdit(start: s(0), end: s(12)));

      expect(await switchTo(tester, pageOf(library, id, 'k0')), isTrue);
      expect(titleShown(tester), 'First riff');
      expect(find.text('Keep 0:00.0–0:12.0'), findsOneWidget);
      expect(platform.lastPlayer, 1);
      expect(platform.disposed, [0]);
    });

    testWidgets('during a Download it doesn\'t switch', (tester) async {
      tall(tester);
      final (library, id) = await capture(tester);
      final editor = _HeldEditor();
      await tester.pumpWidget(editScreen(library, id, editor: editor));
      await settle(tester);
      await tester.tap(find.byKey(const Key('video-edit-download')));
      await settle(tester);
      expect(find.byKey(const Key('video-edit-progress')), findsOneWidget);

      expect(await switchTo(tester, pageOf(library, id, 'k2')), isFalse);
      expect(titleShown(tester), 'First riff');
      expect(platform.disposed, isEmpty);
      expect(platform.lastPlayer, 0);

      editor.hold.complete();
      await settle(tester);
      expect(find.byKey(const Key('video-edit-progress')), findsNothing);
      expect(editor.rendered, hasLength(1));
    });

    testWidgets('while the page before still opens: its player, once '
        'there, is let go of, and only the new page shows', (tester) async {
      tall(tester);
      final kept = PageEdit(start: s(10), end: s(20));
      final (library, id) = await capture(tester, secondEdit: kept);
      final hold = platform.createHold = Completer<void>();
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      bool? switched;
      unawaited(
        StudioView.switchMain(
          tester.state<State<StudioView>>(find.byType(StudioView)),
          pageOf(library, id, 'k2'),
        ).then((done) => switched = done),
      );
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      platform.createHold = null;
      hold.complete();
      await settle(tester);
      await settle(tester);
      expect(switched, isTrue);
      expect(titleShown(tester), 'Second riff');
      expect(find.text('Keep 0:10.0–0:20.0'), findsOneWidget);
      // Both players made; the first page's let go of as it came.
      expect(platform.lastPlayer, 1);
      expect(platform.disposed, hasLength(1));
      expect(pageOf(library, id, 'k0').edit, isNull);
      expect(pageOf(library, id, 'k2').edit, kept);
    });
  });

  group('Cam\'s view', () {
    late _Camera camera;
    late FakeVideoPlatform video;
    setUp(() {
      CameraPlatform.instance = camera = _Camera();
      VideoPlayerPlatform.instance = video = FakeVideoPlatform();
      // Takes are named by when they start: 10:00 today, then a minute
      // later each time.
      final today = DateTime.now();
      var minutes = 0;
      PlayAlongScreen.now = () =>
          DateTime(today.year, today.month, today.day, 10, minutes++);
      // The camera records the take's sound (the app can't, here).
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            TakeSound.channel,
            (call) async => call.method == 'prepare'
                ? {'ok': false, 'reason': 'not in tests'}
                : null,
          );
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TakeSound.channel, null);
      PlayAlongScreen.now = DateTime.now;
    });

    Future<void> camFrames(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    /// A capture with [tab] ([_tab]'s, unless given) and, as asked, a
    /// recording ("Made-up riff"), a take ("Take 9:30") and a PDF; its ID
    /// and the pages', in that order (null for those it hasn't).
    Future<(Library, String, String?, String?)> camCapture(
      WidgetTester tester, {
      bool song = true,
      bool take = false,
      bool pdf = false,
      String tab = _tab,
    }) async {
      final library = Library(PlatformEventStore(), null, (_) async => null);
      late String id;
      String? songId, takeId;
      await tester.runAsync(() async {
        await library.load();
        // Play plays at once (the count-in has tests of its own).
        await library.writeMeta(BackingTrack.metaName, '{"countIn":false}');
        var event = await library.create(const [], title: 'Made-up riffs');
        event = await library.update(event.copyWith(tabText: tab));
        id = event.id;
        Future<String> add(String name, PageKind kind, String ext) async {
          final added = await library.addMedia(library.byId(id)!, [
            Media(
              XFile.fromData(Uint8List.fromList([1, 2, 3]), name: name),
              kind,
              ext,
            ),
          ]);
          return added.pages.last.id;
        }

        if (pdf) await add('chords.pdf', PageKind.pdf, 'pdf');
        if (song) {
          songId = await add('riff.m4a', PageKind.audio, 'm4a');
          await library.renamePage(id, songId!, 'Made-up riff');
        }
        if (take) {
          takeId = await add('take.mp4', PageKind.video, 'mp4');
          await library.renamePage(id, takeId!, 'Take 9:30');
        }
      });
      return (library, id, songId, takeId);
    }

    Widget cam(Library library, String id, {HeadTracking? heads}) =>
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PlayAlongScreen(
            library: library,
            eventId: id,
            cameras: () async => [_front],
            headTracking: (_, _) => heads,
            takeRecorder: () => null,
            pdfView: (_, _, _) => const SizedBox(key: Key('fake-pdf')),
          ),
        );

    final mainRow = find.byKey(const Key('video-edit-main-row'));
    final play = find.byKey(const Key('video-edit-main-play'));

    /// Rec's own button (its menu's arrow is beside it).
    IconButton rec(WidgetTester tester) => tester.widget<IconButton>(
      find
          .descendant(
            of: find.byKey(const Key('cam-rec')),
            matching: find.byType(IconButton),
          )
          .first,
    );

    /// Opens the take's Edit in the sidebar, and lets the editor open.
    Future<void> editTake(WidgetTester tester, String takeId) async {
      await tester.tap(find.byKey(ValueKey('cam-along-edit-$takeId')));
      await camFrames(tester);
      await camFrames(tester);
    }

    testWidgets('the song chosen is the main row: its name, played and '
        'paused from its header; a tap on its bar takes the same player '
        'there, and the part played follows', (tester) async {
      final (library, id, _, _) = await camCapture(tester);
      await tester.pumpWidget(cam(library, id));
      await camFrames(tester);
      // Its header's name, and on its bar the song's.
      expect(find.text('Song'), findsOneWidget);
      expect(
        find.descendant(of: mainRow, matching: find.text('Made-up riff')),
        findsOneWidget,
      );
      // One player: the song's, loaded paused.
      expect(video.lastPlayer, 0);
      expect(video.playing, isEmpty);
      expect(tester.widget<IconButton>(play).tooltip, 'Play the song');

      await tester.tap(play);
      await camFrames(tester);
      expect(video.playing, {0});
      expect(tester.widget<IconButton>(play).tooltip, 'Pause the song');
      await tester.tap(play);
      await camFrames(tester);
      expect(video.playing, isEmpty);

      // Three quarters along its 3 minutes.
      video.seeks.clear();
      final bar = tester.getRect(find.byKey(const Key('video-edit-main-bar')));
      await tester.tapAt(Offset(bar.left + bar.width * 0.75, bar.center.dy));
      await camFrames(tester);
      expect(video.seeks, hasLength(1));
      expect(video.seeks.single.inMilliseconds, closeTo(135000, 1000));
      expect(video.lastPlayer, 0);
      final played = tester.getSize(
        find.byKey(const Key('video-edit-main-played')),
      );
      expect(played.width / bar.width, closeTo(0.75, 0.01));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the song\'s phrase passes show on the main row as on the '
        'player\'s bar: the same ticks, on the song\'s own time, at once', (
      tester,
    ) async {
      final (library, id, song, _) = await camCapture(tester);
      await tester.runAsync(
        () => library.setPhrases(
          id,
          song!,
          PhraseTimes.none.add(
            const Duration(seconds: 45),
            PassDirection.next,
            1,
          ),
        ),
      );
      await tester.pumpWidget(cam(library, id));
      await camFrames(tester);
      final marks = find.byKey(const Key('video-edit-main-phrase-marks'));
      PhraseMarks painter(Finder f) =>
          tester.widget<CustomPaint>(f).painter! as PhraseMarks;
      expect(painter(marks).at, [const Duration(seconds: 45)]);
      expect(painter(marks).length, const Duration(minutes: 3));
      expect(
        tester.getRect(marks).width,
        closeTo(
          tester.getRect(find.byKey(const Key('video-edit-main-bar'))).width,
          0.5,
        ),
      );
      final player = find.byKey(const Key('cam-along-phrase-marks'));
      if (player.evaluate().isNotEmpty) {
        expect(painter(player).at, painter(marks).at);
      }

      // Another kept: on the row at once.
      await tester.runAsync(
        () => library.setPhrases(
          id,
          song!,
          library
              .phrasesOf(id, song)
              .add(const Duration(seconds: 90), PassDirection.next, 2),
        ),
      );
      await camFrames(tester);
      expect(painter(marks).at, [
        const Duration(seconds: 45),
        const Duration(seconds: 90),
      ]);
      // Cleared: gone.
      await tester.runAsync(() => library.clearPhrases(id, song!));
      await camFrames(tester);
      expect(marks, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nothing that plays, no main row; a song arriving with '
        'nothing loaded, Play along with a song… loads it and opens the '
        'list', (tester) async {
      final (library, id, _, _) = await camCapture(
        tester,
        song: false,
        pdf: true,
      );
      await tester.pumpWidget(cam(library, id));
      await camFrames(tester);
      // The PDF opened the sidebar, to follow it; nothing plays.
      expect(find.byKey(const Key('cam-along-sidebar')), findsOneWidget);
      expect(mainRow, findsNothing);
      expect(find.byKey(const Key('cam-rec')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cam-along')));
      await camFrames(tester);
      expect(find.byKey(const Key('cam-along-sidebar')), findsNothing);

      // A recording arrives (a sync, say): the main row offers it.
      await tester.runAsync(() async {
        final event = await library.addMedia(library.byId(id)!, [
          Media(
            XFile.fromData(Uint8List.fromList([1]), name: 'riff.m4a'),
            PageKind.audio,
            'm4a',
          ),
        ]);
        await library.renamePage(id, event.pages.last.id, 'Made-up riff');
      });
      await camFrames(tester);
      final add = find.byKey(const Key('video-edit-main-add'));
      expect(add, findsOneWidget);
      expect(
        find.descendant(of: mainRow, matching: find.text('Made-up riff')),
        findsNothing,
      );

      await tester.tap(add);
      await camFrames(tester);
      expect(find.byKey(const Key('cam-along-sidebar')), findsOneWidget);
      expect(add, findsNothing);
      expect(
        find.descendant(of: mainRow, matching: find.text('Made-up riff')),
        findsOneWidget,
      );
      expect(video.playing, isEmpty);
    });

    testWidgets('a take\'s Edit opens it in the camera\'s place; a file '
        'picked in the sidebar then keeps the edit with the take and puts '
        'the camera back, that file playing in the main row', (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (library, id, songId, takeId) = await camCapture(
        tester,
        take: true,
      );
      await tester.pumpWidget(cam(library, id));
      await camFrames(tester);
      await editTake(tester, takeId!);
      expect(find.byKey(const Key('video-edit-take-bar')), findsOneWidget);
      expect(find.byKey(const Key('cam-rec')), findsNothing);
      expect(find.byTooltip('Back'), findsOneWidget);
      // The take edited shows neither Edit nor Delete in the sidebar.
      expect(find.byKey(ValueKey('cam-along-edit-$takeId')), findsNothing);
      expect(find.byKey(ValueKey('cam-along-delete-$takeId')), findsNothing);

      // Trimmed to where it is (12 s in), not kept yet.
      await tester.tap(find.byKey(const Key('video-edit-end-here')));
      await tester.pump();
      expect(pageOf(library, id, takeId).edit, isNull);

      await tester.tap(find.byKey(ValueKey('cam-along-$songId')));
      await camFrames(tester);
      expect(pageOf(library, id, takeId).edit?.end, s(12));
      expect(find.byKey(const Key('cam-rec')), findsOneWidget);
      expect(find.byKey(const Key('video-edit-take-bar')), findsNothing);
      expect(find.byTooltip('Back'), findsNothing);
      expect(
        find.descendant(of: mainRow, matching: find.text('Made-up riff')),
        findsOneWidget,
      );
      // Playing: the song's player, the editor's let go of.
      expect(video.playing, {0});
      expect(video.disposed, isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('editing a take with its song in the Song row, the song '
        'deleted in the sidebar leaves the row first: its player let go of, '
        'the edit no longer names it', (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (library, id, songId, takeId) = await camCapture(
        tester,
        take: true,
      );
      await tester.runAsync(
        () => library.setPageEdit(
          id,
          takeId!,
          PageEdit(
            start: Duration.zero,
            end: s(60),
            song: SongMode.manual,
            trackId: songId,
          ),
        ),
      );
      await tester.pumpWidget(cam(library, id));
      await camFrames(tester);
      await editTake(tester, takeId!);
      final songBar = find.byKey(const Key('video-edit-song-bar'));
      expect(songBar, findsOneWidget);
      // The editor's players: the take's, then its song's.
      final songPlayer = video.lastPlayer;
      expect(video.disposed, isNot(contains(songPlayer)));

      await tester.tap(find.byKey(ValueKey('cam-along-delete-$songId')));
      await camFrames(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      bool deleted() => library.byId(id)!.pages.every((p) => p.id != songId);
      for (var i = 0; i < 20 && !deleted(); i++) {
        await camFrames(tester);
      }
      expect(deleted(), isTrue);
      // Still editing the take, alone in its row.
      expect(find.byKey(const Key('video-edit-take-bar')), findsOneWidget);
      expect(songBar, findsNothing);
      expect(video.disposed, contains(songPlayer));
      expect(video.disposed, isNot(contains(songPlayer - 1)));
      // Kept: the edit no longer names the song deleted.
      await tester.pump(const Duration(milliseconds: 500));
      await camFrames(tester);
      final edit = pageOf(library, id, takeId).edit;
      expect(edit?.trackId, isNull);
      expect(edit?.end, s(60));
      expect(tester.takeException(), isNull);
    });

    testWidgets('editing a take, the keys are the editor\'s: the space bar '
        'plays the preview, not the song, and / and . record nothing; back '
        'at the camera, . records', (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (library, id, _, takeId) = await camCapture(tester, take: true);
      await tester.pumpWidget(cam(library, id));
      await camFrames(tester);
      await editTake(tester, takeId!);
      // The sidebar still shows, its keys quiet.
      expect(find.byKey(const Key('cam-along-sidebar')), findsOneWidget);
      final preview = video.lastPlayer;
      expect(preview, isNot(0));

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await camFrames(tester);
      expect(video.playing, {preview});
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await camFrames(tester);
      expect(video.playing, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyEvent(LogicalKeyboardKey.period);
      await camFrames(tester);
      expect(camera.recordings, 0);
      expect(find.byKey(const Key('video-edit-take-bar')), findsOneWidget);
      // The play-along's own keys are quiet: 1 doesn't play the song.
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await camFrames(tester);
      expect(video.playing, isEmpty);

      await tester.pageBack();
      await camFrames(tester);
      expect(find.byKey(const Key('cam-rec')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.period);
      await camFrames(tester);
      expect(camera.recording, isTrue);
      await tester.tap(find.byKey(const Key('cam-rec')).first);
      for (var i = 0; i < 50 && rec(tester).tooltip != 'Rec (.)'; i++) {
        await camFrames(tester);
      }
      expect(camera.recording, isFalse);
      expect(rec(tester).tooltip, 'Rec (.)');
    });

    testWidgets('editing a take, the camera stays open, its head gestures '
        'paused; back, they look again; the metronome plays on through it', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1200, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      MetronomeState.instance.sound = _Clicks();
      final heads = _Heads();
      final (library, id, _, takeId) = await camCapture(tester, take: true);
      await tester.pumpWidget(cam(library, id, heads: heads));
      await camFrames(tester);
      await tester.tap(find.byKey(const Key('cam-heads')));
      await camFrames(tester);
      expect(heads.active, isTrue);
      expect(camera.streaming, isTrue);
      await tester.tap(find.byKey(const Key('metronome')));
      await camFrames(tester);
      unawaited(MetronomeState.instance.play());
      await camFrames(tester);
      expect(MetronomeState.instance.playing, isTrue);

      await editTake(tester, takeId!);
      expect(find.byKey(const Key('video-edit-take-bar')), findsOneWidget);
      expect(heads.active, isFalse);
      expect(camera.streaming, isFalse);
      expect(MetronomeState.instance.playing, isTrue);
      expect(find.byKey(const Key('metronome-sidebar')), findsOneWidget);

      await tester.pageBack();
      await camFrames(tester);
      expect(find.byKey(const Key('preview')), findsOneWidget);
      expect(camera.opened, ['front']);
      expect(heads.active, isTrue);
      expect(camera.streaming, isTrue);
      expect(MetronomeState.instance.playing, isTrue);
      MetronomeState.instance.close();
      await camFrames(tester);
    });

    testWidgets('editing a take beside the play-along sidebar, the '
        'settings are beside the viewer where the room left is wide; the '
        'dictionary narrowing it, they go under the viewer, and back', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1280, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (library, id, _, takeId) = await camCapture(tester, take: true);
      await tester.pumpWidget(cam(library, id));
      await camFrames(tester);
      await editTake(tester, takeId!);
      final along = find.byKey(const Key('cam-along-sidebar'));
      final settings = find.byKey(const Key('video-edit-settings-panel'));
      expect(along, findsOneWidget);
      expect(find.byKey(const Key('video-edit-side')), findsOneWidget);
      expect(
        tester.getRect(settings).right,
        lessThanOrEqualTo(tester.getRect(along).left),
      );

      await tester.tap(find.byKey(const Key('dictionary')));
      await camFrames(tester);
      final dictionary = find.byKey(const Key('dictionary-sidebar'));
      expect(dictionary, findsOneWidget);
      expect(tester.getRect(dictionary).right, 1280);
      // The view's room, between the editor's left edge and the
      // play-along sidebar, is narrower than a wide one now.
      expect(find.byKey(const Key('video-edit-side')), findsNothing);
      expect(find.byKey(const Key('video-edit-inspector')), findsOneWidget);
      expect(along, findsOneWidget);
      expect(
        tester.getRect(settings).right,
        lessThanOrEqualTo(tester.getRect(along).left),
      );
      expect(find.byKey(const Key('video-edit-take-bar')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('dictionary-close')));
      await camFrames(tester);
      expect(dictionary, findsNothing);
      expect(find.byKey(const Key('video-edit-side')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a phone: beside the play-along sidebar the main row gives '
        'way (the sidebar\'s player has the song); a take\'s Edit hides the '
        'sidebar, so the editor has the width, and Back shows it again', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (library, id, _, takeId) = await camCapture(tester, take: true);
      await tester.pumpWidget(cam(library, id));
      await camFrames(tester);
      final along = find.byKey(const Key('cam-along-sidebar'));
      expect(along, findsOneWidget);
      // Too narrow beside it for a bar to read: no rows.
      expect(mainRow, findsNothing);
      expect(find.byKey(const Key('cam-rec')), findsOneWidget);

      await editTake(tester, takeId!);
      expect(along, findsNothing);
      final take = find.byKey(const Key('video-edit-take-bar'));
      expect(take, findsOneWidget);
      // Not cut at the sidebar's edge: the take's bar ends near the
      // screen's.
      expect(tester.getRect(take).right, inInclusiveRange(350, 390));
      expect(tester.takeException(), isNull);

      await tester.pageBack();
      await camFrames(tester);
      expect(find.byKey(const Key('cam-rec')), findsOneWidget);
      expect(along, findsOneWidget);
      expect(mainRow, findsNothing);

      // Hidden, the sidebar leaves the main row the width.
      await tester.tap(find.byKey(const Key('cam-along')));
      await camFrames(tester);
      expect(along, findsNothing);
      expect(
        find.descendant(of: mainRow, matching: find.text('Made-up riff')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a phone on its side: the main row gives way to the camera, '
        'its controls and the phrase stay', (tester) async {
      tester.view
        ..physicalSize = const Size(740, 360)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (library, id, _, _) = await camCapture(tester);
      await tester.pumpWidget(cam(library, id));
      await camFrames(tester);
      // Hidden, the sidebar leaves the camera the width.
      await tester.tap(find.byKey(const Key('cam-along')));
      await camFrames(tester);
      expect(mainRow, findsNothing);
      expect(find.byKey(const Key('cam-rec')), findsOneWidget);
      expect(find.byKey(const Key('neckline')), findsOneWidget);
      expect(find.byKey(const Key('preview')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // The phrase is placed before the rows: on a phone on its side, a
    // phrase as high as a guitar's keeps its place, the camera taking
    // what's left, and the main row gives way.
    for (final (size, text, tab, strings) in const [
      (Size(740, 360), 1.0, _sixStrings, 'six'),
      (Size(844, 390), 1.0, _sixStrings, 'six'),
      (Size(740, 360), 2.0, _tab, 'two'),
      (Size(844, 390), 2.0, _tab, 'two'),
    ]) {
      testWidgets('a phone on its side, ${size.width.round()}x'
          '${size.height.round()} at ${text}x text: a phrase on $strings '
          'strings shows, the main row gives way', (tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        if (text != 1) {
          tester.platformDispatcher.textScaleFactorTestValue = text;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        }
        final (library, id, _, _) = await camCapture(tester, tab: tab);
        // At the largest text, the sidebar's player (open by itself at
        // first) runs out of room in its frame, as it does in a window this
        // short wherever it shows; not this test's. Any other error, while
        // it shows, fails, and once it's hidden, any at all.
        final errors = <FlutterErrorDetails>[];
        final reported = FlutterError.onError;
        if (text != 1) FlutterError.onError = errors.add;
        try {
          await tester.pumpWidget(cam(library, id));
          await camFrames(tester);
          // Hidden, the sidebar leaves the main row the width: only the
          // height decides.
          await tester.tap(find.byKey(const Key('cam-along')));
          await camFrames(tester);
        } finally {
          FlutterError.onError = reported;
        }
        bool sidebarPlayer(FlutterErrorDetails error) =>
            error.informationCollector?.call().join().contains(
              'cam-along-frame',
            ) ??
            false;
        expect(errors.where((error) => !sidebarPlayer(error)), isEmpty);
        await camFrames(tester);
        expect(find.byKey(const Key('neckline')), findsOneWidget);
        expect(mainRow, findsNothing);
        expect(find.byKey(const Key('cam-rec')), findsOneWidget);
        expect(find.byKey(const Key('preview')), findsOneWidget);
        // The phrase is drawn whole, over Cam's controls.
        final phrase = tester.getRect(find.byKey(const Key('neckline')));
        final rec = tester.getRect(find.byKey(const Key('cam-rec')));
        expect(phrase.bottom, lessThanOrEqualTo(rec.top));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a phone on its side with the tab hidden: the main row has '
        'the phrase\'s room', (tester) async {
      tester.view
        ..physicalSize = const Size(844, 390)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (library, id, _, _) = await camCapture(tester, tab: _sixStrings);
      await tester.pumpWidget(cam(library, id));
      await camFrames(tester);
      await tester.tap(find.byKey(const Key('cam-along')));
      await camFrames(tester);
      expect(mainRow, findsNothing);

      await tester.tap(find.byKey(const Key('cam-tab')));
      await camFrames(tester);
      expect(find.byKey(const Key('neckline')), findsNothing);
      expect(mainRow, findsOneWidget);

      // Shown again, the phrase takes its room back from the rows.
      await tester.tap(find.byKey(const Key('cam-tab')));
      await camFrames(tester);
      expect(find.byKey(const Key('neckline')), findsOneWidget);
      expect(mainRow, findsNothing);
      expect(tester.takeException(), isNull);
    });

    final recRow = find.byKey(const Key('video-edit-rec-row'));
    final recording = find.byKey(const Key('video-edit-rec-bar'));
    final taken = find.byKey(const Key('video-edit-rec-take'));
    final time = find.byKey(const Key('video-edit-rec-time'));
    final menu = find.byKey(const Key('video-edit-rec-menu'));
    Finder block(int i) => find.byKey(Key('video-edit-rec-block-$i'));

    /// The take's clock on the test's (each pump moves it on), so how
    /// long a take has recorded is known.
    void testClock(WidgetTester tester) {
      CamSession.takeClock = () => tester.binding.clock.stopwatch();
      addTearDown(() => CamSession.takeClock = Stopwatch.new);
    }

    /// [seconds] go by, a tenth at a time, the song's player moving on
    /// with them while it plays, as a real one does.
    Future<void> playOn(WidgetTester tester, double seconds) async {
      for (var i = 0; i < (seconds * 10).round(); i++) {
        if (video.playing.isNotEmpty) {
          video.position += const Duration(milliseconds: 100);
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// Presses Rec (Stop while recording).
    Future<void> pressRec(WidgetTester tester) => tester.tap(
      find
          .descendant(
            of: find.byKey(const Key('cam-rec')),
            matching: find.byType(IconButton),
          )
          .first,
    );

    /// Stops the take, and lets it be saved.
    Future<void> stop(WidgetTester tester) async {
      await pressRec(tester);
      bool saved() =>
          rec(tester).tooltip == 'Rec (.)' && rec(tester).onPressed != null;
      for (var i = 0; i < 50 && !saved(); i++) {
        await camFrames(tester);
      }
      expect(saved(), isTrue, reason: 'the take saved');
    }

    /// Where [span] is along [bar], in ms on an axis [length] long: its
    /// start and its length.
    (double, double) placed(
      WidgetTester tester,
      Finder span,
      Finder bar,
      Duration length,
    ) {
      final ms = length.inMilliseconds;
      final b = tester.getRect(bar);
      final r = tester.getRect(span);
      return ((r.left - b.left) / b.width * ms, r.width / b.width * ms);
    }

    /// The name the take's row shows.
    Finder named(String name) =>
        find.descendant(of: menu, matching: find.text(name));

    void wide(WidgetTester tester) {
      tester.view
        ..physicalSize = const Size(1200, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    group('the take\'s row', () {
      testWidgets('Rec: a red row under the main row, growing with the song '
          'as it plays in the take, how long it has recorded in its header, '
          'the camera not built again for it; paused and moved on, a gap; '
          'after Stop, the take, named, placed from its log', (tester) async {
        wide(tester);
        testClock(tester);
        final (library, id, songId, _) = await camCapture(tester);
        await tester.pumpWidget(cam(library, id));
        await camFrames(tester);
        // No take yet: no row for one.
        expect(recRow, findsNothing);
        // The song from its start, playing as the take starts.
        video.position = Duration.zero;
        await tester.tap(play);
        await playOn(tester, 0.5);
        expect(video.playing, {0});

        await pressRec(tester);
        await playOn(tester, 0.3);
        expect(camera.recording, isTrue);
        expect(recording, findsOneWidget);
        // Rec's red dot, then how long it has recorded.
        expect(find.byKey(const Key('video-edit-rec-dot')), findsOneWidget);
        expect(tester.widget<Text>(time).data, '0:00');
        // Under the main row: the opened one first.
        expect(
          tester.getRect(recRow).top,
          greaterThan(tester.getRect(mainRow).bottom),
        );
        final previews = camera.previews;

        await playOn(tester, 6);
        expect(tester.widget<Text>(time).data, '0:06');
        // The song from half a second in, 6.3 s of it, on its 3 minutes.
        const song = Duration(minutes: 3);
        var (from, long) = placed(tester, block(0), recording, song);
        expect(from, closeTo(500, 300));
        expect(long, closeTo(6300, 300));
        await playOn(tester, 4);
        (from, long) = placed(tester, block(0), recording, song);
        expect(long, closeTo(10300, 300));
        expect(tester.widget<Text>(time).data, '0:10');
        // Told every quarter of a second, only the row was built again:
        // never the camera's preview.
        expect(camera.previews, previews);

        // Paused: the song's part stops growing, the take goes on.
        await tester.tap(play);
        await playOn(tester, 2);
        expect(video.playing, isEmpty);
        expect(
          placed(tester, block(0), recording, song).$2,
          closeTo(long, 100),
        );
        expect(block(1), findsNothing);
        expect(tester.widget<Text>(time).data, '0:12');
        // Moved on to half way, and played again (counting in, as in a
        // take): a block of its own, a gap between.
        final bar = tester.getRect(
          find.byKey(const Key('video-edit-main-bar')),
        );
        await tester.tapAt(Offset(bar.left + bar.width / 2, bar.center.dy));
        video.position = const Duration(seconds: 90);
        await playOn(tester, 0.2);
        await tester.tap(play);
        await playOn(tester, BackingTrack.countInLength.inSeconds + 4.0);
        expect(video.playing, {0});
        final (from1, long1) = placed(tester, block(1), recording, song);
        expect(from1, closeTo(90000, 400));
        expect(long1, closeTo(4000, 400));
        expect(
          tester.getRect(block(1)).left,
          greaterThan(tester.getRect(block(0)).right + 10),
        );

        await stop(tester);
        // The take, named as it is, placed from its log.
        expect(recording, findsNothing);
        expect(time, findsNothing);
        expect(find.byKey(const Key('video-edit-rec-dot')), findsNothing);
        expect(named('Take 10:00'), findsOneWidget);
        final log = library.byId(id)!.pages.last.takeLog!;
        final spans = songSpansOn(log.song, songId!);
        expect(spans, hasLength(2));
        for (final (i, span) in spans.indexed) {
          final (at, length) = placed(tester, block(i), taken, song);
          expect(at, closeTo(span.from, 400));
          expect(length, closeTo(span.to - span.from, 400));
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('the take\'s row: Play plays it back; / records the next '
          'over it, and again; Edit opens the take in the camera\'s place, '
          'its row then its Song, and Back brings the row back', (
        tester,
      ) async {
        wide(tester);
        testClock(tester);
        final (library, id, _, _) = await camCapture(tester);
        await tester.pumpWidget(cam(library, id));
        await camFrames(tester);
        video.position = Duration.zero;
        await tester.tap(play);
        await playOn(tester, 0.5);
        await pressRec(tester);
        await playOn(tester, 3);
        await stop(tester);
        expect(named('Take 10:00'), findsOneWidget);

        // Play: the take in the viewer (the song paused), Stop again.
        await tester.tap(menu);
        await camFrames(tester);
        await tester.tap(find.byKey(const Key('video-edit-rec-play')));
        await camFrames(tester);
        final take = video.lastPlayer;
        expect(take, isNot(0));
        expect(video.playing, {take});
        await tester.tap(menu);
        await camFrames(tester);
        expect(find.text('Stop the take'), findsOneWidget);
        await tester.tap(find.byKey(const Key('video-edit-rec-play')));
        // Its player let go of as it closes.
        await camFrames(tester);
        await camFrames(tester);
        expect(video.playing, isEmpty);
        expect(video.disposed, contains(take));

        // /: Rec, the take recording in the row in the take's place.
        await tester.sendKeyEvent(LogicalKeyboardKey.slash);
        await playOn(tester, 0.3);
        expect(camera.recording, isTrue);
        expect(recording, findsOneWidget);
        expect(named('Take 10:00'), findsNothing);
        // The song starts with the take, after its count-in.
        await playOn(tester, BackingTrack.countInLength.inSeconds + 1.0);
        expect(video.playing, {0});
        // / again: that take saved, the next recording in its place.
        await tester.sendKeyEvent(LogicalKeyboardKey.slash);
        for (var i = 0; i < 50 && camera.recordings < 2; i++) {
          await camFrames(tester);
        }
        for (var i = 0; i < 50 && !camera.recording; i++) {
          await camFrames(tester);
        }
        expect(camera.recording, isTrue);
        expect(recording, findsOneWidget);
        await playOn(tester, BackingTrack.countInLength.inSeconds + 3.0);
        await stop(tester);
        expect(named('Take 10:02'), findsOneWidget);
        expect(named('Take 10:01'), findsNothing);
        final takeId = library.byId(id)!.pages.last.id;
        // Stop leaves the song playing on.
        expect(video.playing, {0});

        // Edit: the take in the camera's place, its Song under it; the
        // song that played along paused, so only the editor's preview
        // sounds.
        await tester.tap(menu);
        await camFrames(tester);
        await tester.tap(find.byKey(const Key('video-edit-rec-edit')));
        await camFrames(tester);
        await camFrames(tester);
        await camFrames(tester);
        expect(video.playing, isEmpty);
        expect(find.byKey(const Key('cam-rec')), findsNothing);
        expect(recRow, findsNothing);
        final takeRow = find.byKey(const Key('video-edit-take-row'));
        final songRow = find.byKey(const Key('video-edit-song-row'));
        expect(takeRow, findsOneWidget);
        expect(songRow, findsOneWidget);
        expect(
          tester.getRect(songRow).top,
          greaterThan(tester.getRect(takeRow).bottom),
        );
        expect(find.text('Take 10:02'), findsWidgets);
        expect(pageOf(library, id, takeId).take, isTrue);

        await tester.pageBack();
        await camFrames(tester);
        expect(find.byKey(const Key('cam-rec')), findsOneWidget);
        expect(named('Take 10:02'), findsOneWidget);
        expect(taken, findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('no song to play along: the take on the take\'s clock, '
          'rounded up to the next 30 s; after Stop, as it recorded', (
        tester,
      ) async {
        wide(tester);
        testClock(tester);
        final (library, id, _, _) = await camCapture(
          tester,
          song: false,
          pdf: true,
        );
        await tester.pumpWidget(cam(library, id));
        await camFrames(tester);
        expect(mainRow, findsNothing);
        expect(recRow, findsNothing);

        await pressRec(tester);
        await playOn(tester, 0.3);
        // The take alone, from the clock's start, on 30 s.
        expect(recRow, findsOneWidget);
        expect(mainRow, findsNothing);
        await playOn(tester, 6);
        var (from, long) = placed(tester, block(0), recording, s(30));
        expect(from, closeTo(0, 1));
        expect(long, closeTo(6300, 300));
        // Past 30 s: on a minute.
        await playOn(tester, 25);
        expect(tester.widget<Text>(time).data, '0:31');
        (from, long) = placed(tester, block(0), recording, s(60));
        expect(long, closeTo(31300, 300));

        await stop(tester);
        expect(named('Take 10:00'), findsOneWidget);
        (from, long) = placed(tester, block(0), taken, s(60));
        expect(from, closeTo(0, 1));
        expect(long, closeTo(31300, 300));
        // The take plays: the main row offers a song, over the take's.
        final add = find.byKey(const Key('video-edit-main-add'));
        expect(add, findsOneWidget);
        expect(
          tester.getRect(recRow).top,
          greaterThan(tester.getRect(add).bottom),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('Cam closed while a take records: its clock\'s ticker '
          'stops (no timer left)', (tester) async {
        wide(tester);
        testClock(tester);
        final (library, id, _, _) = await camCapture(tester);
        await tester.pumpWidget(cam(library, id));
        await camFrames(tester);
        await pressRec(tester);
        await playOn(tester, 1.3);
        expect(tester.widget<Text>(time).data, '0:01');

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        // A timer still pending would fail the test as it ends.
        expect(tester.takeException(), isNull);
      });

      testWidgets('Cam opened again places its last take from its log; with '
          'another file in the main row, it\'s unplaced', (tester) async {
        wide(tester);
        testClock(tester);
        final (library, id, songId, _) = await camCapture(tester);
        await tester.pumpWidget(cam(library, id));
        await camFrames(tester);
        video.position = s(30);
        await tester.tap(play);
        await playOn(tester, 0.5);
        await pressRec(tester);
        await playOn(tester, 5);
        await stop(tester);
        final takeId = library.byId(id)!.pages.last.id;
        final spans = songSpansOn(
          pageOf(library, id, takeId).takeLog!.song,
          songId!,
        );
        expect(spans, hasLength(1));
        await tester.pumpWidget(const SizedBox());
        await camFrames(tester);

        await tester.pumpWidget(cam(library, id));
        await camFrames(tester);
        expect(named('Take 10:00'), findsOneWidget);
        expect(recording, findsNothing);
        final (at, length) = placed(
          tester,
          block(0),
          taken,
          const Duration(minutes: 3),
        );
        expect(at, closeTo(spans.single.from, 400));
        expect(length, closeTo(spans.single.to - spans.single.from, 400));

        // The take itself in the main row: its own row can't be placed.
        await tester.tap(find.byKey(ValueKey('cam-along-$takeId')));
        await camFrames(tester);
        expect(taken, findsNothing);
        expect(
          find.byKey(const Key('video-edit-rec-unplaced')),
          findsOneWidget,
        );
        expect(named('Take 10:00'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    group('waveforms', () {
      final mainWave = find.byKey(const Key('video-edit-main-wave'));
      final takeWave = find.byKey(const Key('video-edit-rec-wave'));

      /// Lets the files be fetched and their sound read.
      Future<void> read(WidgetTester tester) async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await camFrames(tester);
      }

      testWidgets('the song\'s sound on the main row; once saved, the '
          'take\'s own on its block; kept, so Cam opened again draws them '
          'without reading them again', (tester) async {
        wide(tester);
        testClock(tester);
        final files = <String>[];
        WaveCache.clear();
        SoundReader.opener = () => _SineReader(files);
        addTearDown(() {
          SoundReader.opener = null;
          WaveCache.clear();
        });
        final (library, id, _, _) = await camCapture(tester);
        await tester.pumpWidget(cam(library, id));
        await camFrames(tester);
        await read(tester);
        expect(mainWave, findsOneWidget);
        // Over the whole bar: the song's 3 minutes.
        expect(
          tester.getRect(mainWave).width,
          closeTo(
            tester.getRect(find.byKey(const Key('video-edit-main-bar'))).width,
            1,
          ),
        );
        expect(files, hasLength(1));

        // While a take records there's no file to read yet.
        video.position = s(30);
        await tester.tap(play);
        await playOn(tester, 0.5);
        await pressRec(tester);
        await playOn(tester, 5);
        expect(recording, findsOneWidget);
        expect(takeWave, findsNothing);
        await stop(tester);
        await read(tester);
        expect(taken, findsOneWidget);
        expect(takeWave, findsOneWidget);
        // (Lining the song up in the take's sound reads them too.)
        await read(tester);
        final readSoFar = files.length;

        // Cam closed and opened again: both drawn from what's kept, at
        // once, nothing read again.
        await tester.pumpWidget(const SizedBox());
        await camFrames(tester);
        await tester.pumpWidget(cam(library, id));
        await tester.pump();
        expect(mainWave, findsOneWidget);
        expect(takeWave, findsOneWidget);
        await read(tester);
        expect(files, hasLength(readSoFar));
        expect(tester.takeException(), isNull);
      });

      testWidgets('no reader (a desktop build): no waveforms, nothing '
          'fetched for them, the rows as before', (tester) async {
        wide(tester);
        WaveCache.clear();
        SoundReader.opener = () => null;
        addTearDown(() {
          SoundReader.opener = null;
          WaveCache.clear();
        });
        final (library, id, _, _) = await camCapture(tester);
        await tester.pumpWidget(cam(library, id));
        await camFrames(tester);
        await read(tester);
        expect(find.byKey(const Key('video-edit-main-bar')), findsOneWidget);
        expect(mainWave, findsNothing);
        expect(tester.takeException(), isNull);
      });
    });

    group('Rec over this', () {
      final camButton = find.byKey(const Key('video-edit-cam'));
      final takeBar = find.byKey(const Key('video-edit-take-bar'));

      /// What the take's sound channel was asked (none while no camera
      /// opens).
      late List<String> soundCalls;
      setUp(() {
        soundCalls = [];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(TakeSound.channel, (call) async {
              soundCalls.add(call.method);
              return call.method == 'prepare'
                  ? {'ok': false, 'reason': 'not in tests'}
                  : null;
            });
      });

      /// [camCapture]'s, with a video added after its recording (not a
      /// take: "Made-up riff video"); its ID too.
      Future<(Library, String, String, String)> recCapture(
        WidgetTester tester,
      ) async {
        final (library, id, songId, _) = await camCapture(tester);
        late String videoId;
        await tester.runAsync(() async {
          final added = await library.addMedia(library.byId(id)!, [
            Media(
              XFile.fromData(Uint8List.fromList([4, 5, 6]), name: 'riff.mp4'),
              PageKind.video,
              'mp4',
            ),
          ]);
          videoId = added.pages.last.id;
          await library.renamePage(id, videoId, 'Made-up riff video');
        });
        return (library, id, songId!, videoId);
      }

      /// The video editor on [pageId], as the file screen opens it, Cam's
      /// camera for Rec over this faked as Cam's tests fake it, or, with
      /// [platform], the platform's own (the fakes behind it).
      Widget editor(
        Library library,
        String id,
        String pageId, {
        CloudOcr? ocr,
        bool platform = false,
      }) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: VideoEditScreen(
          library: library,
          eventId: id,
          page: pageOf(library, id, pageId),
          pickFile: () async => null,
          ocr: ocr,
          recSetup: platform
              ? null
              : CamSetup(
                  cameras: () async => [_front],
                  headTracking: (_, _) => null,
                  takeRecorder: () => null,
                  pdfView: (_, _, _) => const SizedBox(key: Key('fake-pdf')),
                  now: () => PlayAlongScreen.now(),
                  takeName: takeName,
                ),
        ),
      );

      /// Lets the editor open its video.
      Future<void> opened(WidgetTester tester) async {
        await camFrames(tester);
        await camFrames(tester);
        expect(takeBar, findsOneWidget);
      }

      /// Presses Rec over this: in the transport, or on a phone, in the
      /// app bar's menu.
      Future<void> recOver(WidgetTester tester) async {
        if (camButton.evaluate().isEmpty) {
          await tester.tap(find.byKey(const Key('video-edit-more')));
          await camFrames(tester);
        }
        await tester.tap(camButton);
        await camFrames(tester);
        await camFrames(tester);
      }

      testWidgets('with Premium: the video edited plays along in the main '
          'row, from the playhead, paused, the list open on it, the camera '
          'in the viewer\'s place; a take recorded over it has it as its '
          'song, its Edit gives Take then that video; Back, then Back, '
          'the edit as it was', (tester) async {
        wide(tester);
        testClock(tester);
        final (library, id, songId, videoId) = await recCapture(tester);
        await tester.pumpWidget(editor(library, id, videoId));
        await opened(tester);
        // A camera by To the end, its name in its tooltip; no lock.
        expect(find.byTooltip('Rec over this'), findsOneWidget);
        expect(find.byKey(const Key('video-edit-cam-locked')), findsNothing);
        expect(
          tester.getRect(camButton).left,
          tester.getRect(find.byKey(const Key('video-edit-to-end'))).right,
        );
        // No camera until it's pressed.
        expect(camera.asked + camera.opened.length, 0);
        expect(find.byKey(const ValueKey('cam-viewer')), findsNothing);
        expect(find.byKey(const Key('cam-along-sidebar')), findsNothing);
        // The preview 5 s in; trimmed there, not kept yet: Rec over this
        // keeps it.
        video.position = s(5);
        await tester.tap(find.byKey(const Key('video-edit-end-here')));
        await tester.pump();
        expect(pageOf(library, id, videoId).edit, isNull);
        final edited = video.lastPlayer;
        video.seeks.clear();

        await tester.tap(camButton);
        await camFrames(tester);
        await camFrames(tester);
        expect(pageOf(library, id, videoId).edit?.end, s(5));
        // The camera, Cam's controls; the editor's player let go of, the
        // video in the main row on a player of its own, loaded paused
        // where the playhead was.
        expect(camera.opened, ['front']);
        expect(find.byKey(const Key('cam-rec')), findsOneWidget);
        expect(takeBar, findsNothing);
        expect(video.disposed, contains(edited));
        expect(video.lastPlayer, edited + 1);
        expect(video.playing, isEmpty);
        expect(video.seeks.last, s(5));
        expect(
          find.descendant(
            of: mainRow,
            matching: find.text('Made-up riff video'),
          ),
          findsOneWidget,
        );
        // The list open on it, which shows it no Delete (Back brings it
        // back to edit).
        expect(find.byKey(const Key('cam-along-sidebar')), findsOneWidget);
        expect(find.byKey(ValueKey('cam-along-delete-$videoId')), findsNothing);
        expect(find.byTooltip('Back'), findsOneWidget);
        expect(titleShown(tester), 'Made-up riffs');

        // A take over it: it plays along, from 5 s, after the take's
        // count-in.
        await pressRec(tester);
        await playOn(tester, 0.3);
        expect(camera.recording, isTrue);
        await playOn(tester, BackingTrack.countInLength.inSeconds + 1.0);
        expect(video.playing, {edited + 1});
        await playOn(tester, 3);
        await stop(tester);
        expect(named('Take 10:00'), findsOneWidget);
        final take = library.byId(id)!.pages.last;
        expect(take.take, isTrue);
        final spans = songSpansOn(take.takeLog!.song, videoId);
        expect(spans, hasLength(1));
        expect(spans.single.from, closeTo(5000, 400));
        // Placed along the video in the take's row.
        expect(find.byKey(const Key('video-edit-rec-take')), findsOneWidget);

        // Its Edit: the take, then the video lined up as its song.
        await tester.tap(menu);
        await camFrames(tester);
        await tester.tap(find.byKey(const Key('video-edit-rec-edit')));
        await camFrames(tester);
        await camFrames(tester);
        await camFrames(tester);
        final takeRow = find.byKey(const Key('video-edit-take-row'));
        final songRow = find.byKey(const Key('video-edit-song-row'));
        expect(takeRow, findsOneWidget);
        expect(songRow, findsOneWidget);
        expect(
          tester.getRect(songRow).top,
          greaterThan(tester.getRect(takeRow).bottom),
        );
        expect(
          find.descendant(
            of: songRow,
            matching: find.textContaining('Made-up riff video'),
          ),
          findsWidgets,
        );
        expect(titleShown(tester), 'Take 10:00');
        // The video, Back's to put back after the camera, shows no Delete
        // in the sidebar (nor the take edited); the song not on Back's
        // list does.
        expect(find.byKey(const Key('cam-along-sidebar')), findsOneWidget);
        expect(find.byKey(ValueKey('cam-along-delete-$videoId')), findsNothing);
        expect(
          find.byKey(ValueKey('cam-along-delete-${take.id}')),
          findsNothing,
        );
        expect(
          find.byKey(ValueKey('cam-along-delete-$songId')),
          findsOneWidget,
        );

        // Back: the camera, the video still in the main row.
        await tester.pageBack();
        await camFrames(tester);
        expect(find.byKey(const Key('cam-rec')), findsOneWidget);
        expect(
          find.descendant(
            of: mainRow,
            matching: find.text('Made-up riff video'),
          ),
          findsOneWidget,
        );
        // Back again: the video's edit, as it was kept; what played along
        // paused; Back now closes the editor.
        await tester.tap(play);
        await camFrames(tester);
        expect(video.playing, isNotEmpty);
        await tester.pageBack();
        await camFrames(tester);
        await camFrames(tester);
        expect(takeBar, findsOneWidget);
        expect(find.byKey(const Key('cam-rec')), findsNothing);
        expect(titleShown(tester), 'Made-up riff video');
        expect(find.text('Keep 0:00.0–0:05.0'), findsOneWidget);
        expect(find.byTooltip('Back'), findsNothing);
        expect(video.playing, isEmpty);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a phone: in the app bar\'s menu, the trims at their full '
          'size; Back gives the edit the width, the sidebar hidden, and Rec '
          'over this again puts the same camera back, the sidebar with it', (
        tester,
      ) async {
        tester.view
          ..physicalSize = const Size(390, 844)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final (library, id, _, videoId) = await recCapture(tester);
        await tester.pumpWidget(editor(library, id, videoId));
        await opened(tester);
        // Not in the transport, whose trims keep their size.
        expect(camButton, findsNothing);
        for (final key in ['video-edit-start-here', 'video-edit-end-here']) {
          expect(
            tester.getSize(find.byKey(Key(key))),
            const Size(48, 48),
            reason: key,
          );
        }
        final along = find.byKey(const Key('cam-along-sidebar'));

        await recOver(tester);
        expect(find.byKey(const Key('cam-rec')), findsOneWidget);
        expect(along, findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pageBack();
        await camFrames(tester);
        await camFrames(tester);
        expect(along, findsNothing);
        expect(takeBar, findsOneWidget);
        // Not cut at the sidebar's edge.
        expect(tester.getRect(takeBar).right, inInclusiveRange(350, 390));
        expect(tester.takeException(), isNull);

        await recOver(tester);
        expect(find.byKey(const Key('cam-rec')), findsOneWidget);
        expect(along, findsOneWidget);
        // The video still in the backing track, paused; one camera.
        expect(video.playing, isEmpty);
        expect(camera.opened, ['front']);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a phone, a take edited in Cam with the sidebar hidden: Rec '
          'over this loads the take alone, no other file first, and the '
          'sidebar shows again', (tester) async {
        tester.view
          ..physicalSize = const Size(390, 844)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final (library, id, songId, takeId) = await camCapture(
          tester,
          take: true,
        );
        await tester.pumpWidget(cam(library, id));
        await camFrames(tester);
        final along = find.byKey(const Key('cam-along-sidebar'));
        expect(along, findsOneWidget);
        await editTake(tester, takeId!);
        expect(takeBar, findsOneWidget);
        // Hidden, to leave the edit its room.
        expect(along, findsNothing);
        final players = video.lastPlayer;

        await recOver(tester);
        expect(find.byKey(const Key('cam-rec')), findsOneWidget);
        // The sidebar again, the take the one playing along.
        expect(along, findsOneWidget);
        bool chosen(String pageId) => tester
            .widget<ListTile>(find.byKey(ValueKey('cam-along-$pageId')))
            .selected;
        expect(chosen(takeId), isTrue);
        expect(chosen(songId!), isFalse);
        // One player more: the take's, in the backing track; the song
        // that played along before isn't loaded again on the way.
        expect(video.lastPlayer, players + 1);
        expect(video.disposed, isNot(contains(players + 1)));
        expect(tester.takeException(), isNull);
      });

      testWidgets('a page on Back\'s list deleted meanwhile (synced away): '
          'Back doesn\'t put it back, and with nothing before it, the editor '
          'closes', (tester) async {
        wide(tester);
        final (library, id, _, videoId) = await recCapture(tester);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => TextButton(
                key: const Key('launch'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        (editor(library, id, videoId) as MaterialApp).home!,
                  ),
                ),
                child: const Text('Edit'),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('launch')));
        await opened(tester);
        await recOver(tester);
        expect(find.byKey(const Key('cam-rec')), findsOneWidget);

        await tester.runAsync(() async {
          final event = library.byId(id)!;
          await library.deletePage(
            event,
            event.pages.firstWhere((p) => p.id == videoId),
          );
        });
        await camFrames(tester);
        await tester.pageBack();
        await camFrames(tester);
        await camFrames(tester);
        expect(find.byType(VideoEditScreen), findsNothing);
        expect(find.byKey(const Key('launch')), findsOneWidget);
        expect(find.textContaining("can't be played"), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('without Premium: it says so, and pressed, the Premium '
          'card, no camera: no Cam, the cameras never asked for, the take\'s '
          'sound never set up', (tester) async {
        wide(tester);
        final (library, id, _, videoId) = await recCapture(tester);
        // Signed out: no Premium.
        final auth = FakeAuth();
        final sync = CloudSync(
          library: library,
          auth: auth,
          bucket: FakeBucket(),
          credentials: FakeCredentials(),
          period: const Duration(days: 1),
        );
        final ocr = CloudOcr(
          library: library,
          auth: auth,
          sync: sync,
          bucket: FakeBucket(),
          credentials: FakeCredentials(),
          api: FakeOcrApi(),
        );
        addTearDown(() {
          ocr.dispose();
          sync.dispose();
        });
        // The platform's camera, behind the fakes: asked for, they'd say.
        await tester.pumpWidget(
          editor(library, id, videoId, ocr: ocr, platform: true),
        );
        await opened(tester);
        expect(
          find.byTooltip('Rec over this: tabs.cam Premium'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('video-edit-cam-locked')), findsOneWidget);

        await tester.tap(camButton);
        await camFrames(tester);
        expect(find.byKey(const Key('video-edit-premium')), findsOneWidget);
        expect(
          find.textContaining('Cam is part of tabs.cam Premium'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('premium-not-now')));
        await camFrames(tester);
        expect(find.byKey(const Key('video-edit-premium')), findsNothing);
        // Still the edit; nothing of Cam's.
        expect(takeBar, findsOneWidget);
        expect(find.byKey(const Key('cam-rec')), findsNothing);
        expect(find.byKey(const ValueKey('cam-viewer')), findsNothing);
        expect(find.byKey(const Key('cam-along')), findsNothing);
        expect(find.byTooltip('Back'), findsNothing);
        expect(camera.asked, 0);
        expect(camera.opened, isEmpty);
        expect(soundCalls, isEmpty);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Premium not known yet (signed in, the service couldn\'t '
          'check): no lock said; pressed, Premium\'s card checks, and no '
          'camera opens', (tester) async {
        wide(tester);
        final (library, id, _, videoId) = await recCapture(tester);
        final auth = FakeAuth()..signInAs('u1');
        final sync = CloudSync(
          library: library,
          auth: auth,
          bucket: FakeBucket(),
          credentials: FakeCredentials(),
          period: const Duration(days: 1),
        );
        final ocr = CloudOcr(
          library: library,
          auth: auth,
          sync: sync,
          bucket: FakeBucket(),
          credentials: FakeCredentials(),
          api: FakeOcrApi()..rbacr = false,
        );
        addTearDown(() {
          ocr.dispose();
          sync.dispose();
        });
        await tester.pumpWidget(
          editor(library, id, videoId, ocr: ocr, platform: true),
        );
        await opened(tester);
        expect(ocr.free, isFalse);
        expect(find.byTooltip('Rec over this'), findsOneWidget);
        expect(find.byTooltip('Rec over this: tabs.cam Premium'), findsNothing);
        expect(find.byKey(const Key('video-edit-cam-locked')), findsNothing);

        await tester.tap(camButton);
        await camFrames(tester);
        expect(find.byKey(const Key('video-edit-premium')), findsOneWidget);
        await tester.tap(find.byKey(const Key('premium-not-now')));
        await camFrames(tester);
        expect(takeBar, findsOneWidget);
        expect(find.byKey(const Key('cam-rec')), findsNothing);
        expect(camera.asked, 0);
        expect(soundCalls, isEmpty);
        expect(tester.takeException(), isNull);
      });

      testWidgets('an editor where it isn\'t pressed: played, paused and '
          'closed, no camera is asked for, nor the take\'s sound', (
        tester,
      ) async {
        wide(tester);
        final (library, id, _, videoId) = await recCapture(tester);
        await tester.pumpWidget(editor(library, id, videoId, platform: true));
        await opened(tester);
        await tester.tap(find.byKey(const Key('video-edit-play')));
        await camFrames(tester);
        await tester.tap(find.byKey(const Key('video-edit-play')));
        await camFrames(tester);
        await tester.pumpWidget(const SizedBox());
        await camFrames(tester);
        expect(camera.asked, 0);
        expect(camera.opened, isEmpty);
        expect(soundCalls, isEmpty);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a take edited in Cam: Rec over this puts it in the main '
          'row; Back gives the take\'s edit, then the camera', (tester) async {
        wide(tester);
        final (library, id, songId, takeId) = await camCapture(
          tester,
          take: true,
        );
        await tester.pumpWidget(cam(library, id));
        await camFrames(tester);
        expect(
          find.descendant(of: mainRow, matching: find.text('Made-up riff')),
          findsOneWidget,
        );
        await editTake(tester, takeId!);
        expect(takeBar, findsOneWidget);
        // Cam's own: Premium's already, so no lock said.
        expect(camButton, findsOneWidget);
        expect(find.byTooltip('Rec over this: tabs.cam Premium'), findsNothing);

        await tester.tap(camButton);
        await camFrames(tester);
        await camFrames(tester);
        expect(find.byKey(const Key('cam-rec')), findsOneWidget);
        expect(
          find.descendant(of: mainRow, matching: find.text('Take 9:30')),
          findsOneWidget,
        );
        expect(video.playing, isEmpty);
        // One camera all along.
        expect(camera.opened, ['front']);

        await tester.pageBack();
        await camFrames(tester);
        await camFrames(tester);
        expect(takeBar, findsOneWidget);
        expect(titleShown(tester), 'Take 9:30');
        await tester.pageBack();
        await camFrames(tester);
        expect(find.byKey(const Key('cam-rec')), findsOneWidget);
        expect(find.byTooltip('Back'), findsNothing);
        // The take still plays along: Rec over this put it there.
        expect(
          find.descendant(of: mainRow, matching: find.text('Take 9:30')),
          findsOneWidget,
        );
        expect(songId, isNotNull);
        expect(tester.takeException(), isNull);
      });
    });
  });
}

/// A sound reader that hears a sine in every file (a second of it), and
/// notes which files it read.
class _SineReader implements SoundReader {
  _SineReader(this.files);

  final List<String> files;

  @override
  Future<Float32List?> samples(
    XFile file, {
    required Duration from,
    required Duration length,
    required int rate,
  }) async {
    files.add(file.name);
    return Float32List.fromList([
      for (var i = 0; i < rate; i++) sin(2 * pi * 220 * i / rate) / 2,
    ]);
  }

  @override
  void close() {}
}
