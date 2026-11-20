import 'dart:async';

import 'package:camera/camera.dart' show CameraController, CameraImage;
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/backing_track.dart';
import 'package:tabcam_app/capture/head_gestures.dart';
import 'package:tabcam_app/capture/media.dart';
import 'package:tabcam_app/capture/play_along_screen.dart';
import 'package:tabcam_app/capture/take_sound.dart';
import 'package:tabcam_app/capture/video_edit.dart';
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

import 'fake_camera.dart';
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
    late FakeCameraPlatform camera;
    late FakeVideoPlatform video;
    setUp(() {
      CameraPlatform.instance = camera = FakeCameraPlatform();
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

    /// A capture with [_tab] and, as asked, a recording ("Made-up riff"),
    /// a take ("Take 9:30") and a PDF; its ID and the pages', in that
    /// order (null for those it hasn't).
    Future<(Library, String, String?, String?)> camCapture(
      WidgetTester tester, {
      bool song = true,
      bool take = false,
      bool pdf = false,
    }) async {
      final library = Library(PlatformEventStore(), null, (_) async => null);
      late String id;
      String? songId, takeId;
      await tester.runAsync(() async {
        await library.load();
        // Play plays at once (the count-in has tests of its own).
        await library.writeMeta(BackingTrack.metaName, '{"countIn":false}');
        var event = await library.create(const [], title: 'Made-up riffs');
        event = await library.update(event.copyWith(tabText: _tab));
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
  });
}
