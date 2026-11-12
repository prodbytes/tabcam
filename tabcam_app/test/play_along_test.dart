import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tabcam_app/capture/head_gestures.dart';
import 'package:tabcam_app/capture/link_frame.dart';
import 'package:tabcam_app/capture/media.dart';
import 'package:tabcam_app/capture/backing_track.dart';
import 'package:tabcam_app/capture/play_along_screen.dart';
import 'package:tabcam_app/capture/play_along_sidebar.dart';
import 'package:tabcam_app/capture/auto_pass.dart';
import 'package:tabcam_app/capture/take_log.dart';
import 'package:tabcam_app/capture/take_h264.dart';
import 'package:tabcam_app/capture/take_priority.dart';
import 'package:tabcam_app/capture/take_recorder.dart';
import 'package:tabcam_app/capture/take_sound.dart';
import 'package:tabcam_app/dictionary/dictionary_sidebar.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/delete_confirm.dart';
import 'package:tabcam_app/screens/event_screen.dart';
import 'package:tabcam_app/screens/file_delete.dart';
import 'package:tabcam_app/screens/messages.dart';
import 'package:tabcam_app/screens/sidebar_widths.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'fake_camera.dart';
import 'mini_player_test.dart' show FakeVideoPlatform;

/// Head gestures, faked: the test makes them.
class FakeHeads implements HeadTracking {
  FakeHeads(this.onGesture);

  final void Function(HeadGesture) onGesture;
  int frames = 0;
  bool disposed = false;

  @override
  bool active = true;

  /// Whether it was told a take records, each time it was told.
  final List<bool> recordings = [];

  @override
  set recording(bool recording) => recordings.add(recording);

  @override
  void onImage(CameraImage image) => frames++;

  @override
  final ValueNotifier<bool> face = ValueNotifier(true);

  @override
  set camera(CameraController camera) {}

  @override
  void dispose() => disposed = true;
}

/// The web's take recorder, faked: whether a microphone opens, whether
/// starting fails, and whether it lends its sound to the camera.
class FakeTakeRecorder implements TakeRecorder {
  bool sound = true;
  bool lends = true;
  Object? startError;
  int prepared = 0;
  int started = 0;
  int lent = 0;

  @override
  Future<void> prepare() async => prepared++;

  @override
  Future<bool> hasSound() async => sound;

  @override
  Future<bool> lendSoundToCamera() async {
    lent++;
    return lends;
  }

  @override
  Future<void> start() async {
    if (startError case final error?) throw error;
    started++;
  }

  /// How long it had recorded when the take's clock started, in ms.
  double? sinceStart = 120;

  @override
  double? msSinceStart() => started > 0 ? sinceStart : null;

  @override
  Future<XFile> stop() async => XFile.fromData(
    Uint8List.fromList([7, started]),
    name: 'take.webm',
    mimeType: 'video/webm',
  );

  @override
  void dispose() {}
}

/// The temporary folder, in a test's own.
class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.temporary);

  final String temporary;

  @override
  Future<String?> getTemporaryPath() async => temporary;
}

const _back = CameraDescription(
  name: 'back',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 0,
);
const _front = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 0,
);

/// A made-up riff, three necklines long.
const _tab = '''
[Riff]
e|--0--3--|
B|--1--1--|

e|--5--7--|
B|--5--8--|

e|--12-10-|
B|--13-12-|
''';

/// Rec's tooltip while recording.
const _stopKeys = 'Stop (1) · new take (.)';

/// The bar's Stop (Rec's, [_stopKeys], or Play's), not the sidebar's: a
/// take opens the sidebar, whose frame has a Stop too.
final _camStop = find.byElementPredicate((e) {
  final w = e.widget;
  if (w is! Tooltip || (w.message != 'Stop' && w.message != _stopKeys)) {
    return false;
  }
  var inSidebar = false;
  e.visitAncestorElements((a) {
    inSidebar = a.widget.key == const Key('cam-along-sidebar');
    return !inSidebar;
  });
  return !inSidebar;
});

void main() {
  late FakeCameraPlatform camera;
  late FakeVideoPlatform video;
  setUp(() {
    CameraPlatform.instance = camera = FakeCameraPlatform();
    VideoPlayerPlatform.instance = video = FakeVideoPlatform();
    SidebarWidths.instance.clear();
    DictionaryState.instance.clear();
    // Android (the tests' platform) records the take's sound in the app
    // where it can; here it can't, so the camera does, unless a test
    // fakes it (the Android group).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          TakeSound.channel,
          (call) async => call.method == 'prepare'
              ? {'ok': false, 'reason': 'not in tests'}
              : null,
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TakeSound.channel, null),
  );

  Future<void> frames(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<(Library, String)> capture(WidgetTester tester, {String? tab}) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late String id;
    await tester.runAsync(() async {
      await library.load();
      // Play plays at once (the count-in has tests of its own).
      await library.writeMeta(BackingTrack.metaName, '{"countIn":false}');
      final event = await library.create([
        img.encodeJpg(img.Image(width: 8, height: 8)),
      ]);
      id = (await library.update(event.copyWith(tabText: tab))).id;
    });
    return (library, id);
  }

  Widget app(Widget home) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  /// Pumps until [done] (a take saved, say), for up to a few seconds.
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 50 && !done(); i++) {
      await frames(tester);
    }
    expect(done(), isTrue);
  }

  /// Whether Rec is back (the take saved).
  bool recReady(WidgetTester tester) {
    final rec = find.descendant(
      of: find.byKey(const Key('cam-rec')),
      matching: find.byType(IconButton),
    );
    final button = tester.widget<IconButton>(rec);
    return button.tooltip == 'Rec (1)' && button.onPressed != null;
  }

  String shown(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('neckline'))).data!;

  testWidgets('Cam opens the front camera with the tab, one neckline at a '
      'time; keys move along it', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    await tester.pumpWidget(app(EventScreen(library: library, eventId: id)));
    await frames(tester);
    await tester.tap(find.byKey(const Key('cam')));
    await frames(tester);
    expect(find.byType(PlayAlongScreen), findsOneWidget);
    expect(find.byKey(const Key('preview')), findsOneWidget);
    expect(shown(tester), '[Riff]\ne|--0--3--|\nB|--1--1--|');
    expect(find.text('1 / 3'), findsOneWidget);

    // Any key: the next; Backspace, ←, ↑ and Page Up: the one before.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(shown(tester), 'e|--5--7--|\nB|--5--8--|');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);
    // The last stays the last.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);
    for (final back in [
      LogicalKeyboardKey.backspace,
      LogicalKeyboardKey.arrowUp,
    ]) {
      await tester.sendKeyEvent(back);
      await tester.pump();
    }
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text('1 / 3'), findsOneWidget);
    // Shift alone is no key press.
    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.text('1 / 3'), findsOneWidget);

    // A tap on the neckline, and its arrows.
    await tester.tap(find.byKey(const Key('neckline')));
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous line'));
    await tester.pump();
    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('Tab hides the tab from the screen and shows it again; '
      'hidden, keys still turn it', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    await tester.pumpWidget(app(EventScreen(library: library, eventId: id)));
    await frames(tester);
    await tester.tap(find.byKey(const Key('cam')));
    await frames(tester);
    expect(find.byKey(const Key('neckline')), findsOneWidget);
    expect(find.text('Hide tab'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cam-tab')));
    await tester.pump();
    expect(find.byKey(const Key('neckline')), findsNothing);
    expect(find.text('Show tab'), findsOneWidget);

    // Hidden, a key still turns it (the keys came back to Cam).
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    await tester.tap(find.byKey(const Key('cam-tab')));
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('Hide tab'), findsOneWidget);
  });

  testWidgets('Rec records a take into the capture, saved at once as the '
      'camera recorded it: no tab burned in (no "Adding the tab" card), its '
      'log keeping the tab apart from its picture; Play plays it back', (
    tester,
  ) async {
    final (library, id) = await capture(tester, tab: _tab);
    // What used to burn the tab in: never called.
    final overlays = <MethodCall>[];
    const overlay = MethodChannel('tabcam/take_overlay');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(overlay, (call) async {
      overlays.add(call);
      return (call.arguments as Map)['output'];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(overlay, null));
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_back, _front],
        ),
      ),
    );
    await frames(tester);
    expect(camera.opened, ['front']);
    // Nothing to play yet.
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const Key('cam-play')),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    expect(camera.recording, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.tap(_camStop);
    await tester.pump();
    expect(find.text('Adding the tab to the video…'), findsNothing);
    await until(tester, () => recReady(tester));
    expect(camera.recording, isFalse);
    expect(overlays, isEmpty);
    expect(find.text('Adding the tab to the video…'), findsNothing);
    expect(find.text('Take 1 added to the capture'), findsOneWidget);
    var pages = library.byId(id)!.pages;
    expect(pages, hasLength(2));
    expect(pages.last.kind, PageKind.video);
    expect(pages.last.title, 'Take 1');
    // Marked as Cam's take.
    expect(pages.last.take, isTrue);
    // What's saved is the camera's file as it is.
    late Uint8List saved;
    await tester.runAsync(
      () async => saved = await library.original(library.byId(id)!, pages.last),
    );
    expect(saved, [9, 1]);
    // Its log: the tab not in its picture (the editor draws it), the
    // necklines it showed, each turn, and the lag, told from the camera's
    // start and stop.
    final log = pages.last.takeLog!;
    expect(log.burned, isFalse);
    expect(log.tab!.lines, [
      '[Riff]\ne|--0--3--|\nB|--1--1--|',
      'e|--5--7--|\nB|--5--8--|',
    ]);
    expect([for (final (_, line) in log.tab!.marks) line], [0, 1]);
    expect(log.tab!.marks.first.$1, 0);
    // The editor's bands: the first neckline, then the second.
    final bands = bandsOf(log.tab!.fileMarks(log.lagMs));
    expect([for (final b in bands) b.line], [0, 1]);
    expect(bands.first.start, Duration.zero);
    expect(bands.last.end, isNull);
    expect(log.lagFrom, LagFrom.bounds);
    expect(log.lagRaw.keys, [
      'startCallMs',
      'startReturnMs',
      'stopCallMs',
      'stopReturnMs',
    ]);
    expect(log.lagRaw['startCallMs'], lessThanOrEqualTo(0));
    expect(log.lagMs, greaterThanOrEqualTo(0));
    expect(log.song, isEmpty);

    // A second take is Take 2.
    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));
    pages = library.byId(id)!.pages;
    expect(pages.last.title, 'Take 2');

    await tester.tap(find.byTooltip('Play'));
    await frames(tester);
    expect(video.playing, hasLength(1));
    expect(find.byKey(const Key('preview')), findsNothing);
    await tester.tap(_camStop);
    await frames(tester);
    expect(video.playing, isEmpty);
    expect(find.byKey(const Key('preview')), findsOneWidget);
  });

  testWidgets('a take\'s log keeps every turn of the tab as it came (with '
      'Auto-pass off, the tab hidden), the phrase passes as before; '
      'the tab never in its picture, the log says so', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    // Hidden, it still turns, and the turn is noted.
    await tester.tap(find.byKey(const Key('cam-tab')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    // Auto-pass off: a turn, but no pass of the take's.
    await tester.tap(find.byKey(const Key('cam-auto-pass')));
    await frames(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));

    var take = library.byId(id)!.pages.last;
    final log = take.takeLog!;
    expect(log.burned, isFalse);
    expect(log.tab!.lines, hasLength(3));
    expect([for (final (_, line) in log.tab!.marks) line], [0, 1, 2, 1]);
    // The phrase passes leave the turn made with Auto-pass off out.
    final marks = [
      for (final (ms, line) in log.tab!.marks)
        (Duration(milliseconds: ms), line),
    ];
    List<(PassDirection, int, int)> passes(PhraseTimes times) => [
      for (final p in times.passes) (p.direction, p.line, p.count),
    ];
    final saved = passes(library.phrasesOf(id, take.id));
    expect(saved, passes(takePhrases(marks, skip: {3})));
    expect(saved, isNot(passes(takePhrases(marks))));
    expect(saved, isNotEmpty);

    // The next take, too: only what it showed.
    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));
    take = library.byId(id)!.pages.last;
    expect(take.title, 'Take 2');
    expect(take.takeLog!.burned, isFalse);
    // Only the neckline it showed: the second.
    expect(take.takeLog!.tab!.lines, ['e|--5--7--|\nB|--5--8--|']);
    expect(take.takeLog!.tab!.marks, [(0, 0)]);
  });

  testWidgets('with no tab, a take\'s log has none', (tester) async {
    final (library, id) = await capture(tester);
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));
    final log = library.byId(id)!.pages.last.takeLog!;
    expect(log.tab, isNull);
    expect(log.burned, isFalse);
  });

  testWidgets('reopened, Cam plays the capture\'s last take, its necklines '
      'turning as its log says (lag and all), even those its tab has no '
      'more', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    // An older take, recorded when the tab had another first line.
    const old = 'e|--3--5--|\nB|--3--5--|';
    final log = TakeLog(
      burned: false,
      lagMs: 200,
      lagFrom: LagFrom.bounds,
      tab: TakeTab.of(
        [old, 'e|--12-10-|\nB|--13-12-|'],
        [(Duration.zero, 0), (const Duration(seconds: 5), 1)],
      ),
    );
    await tester.runAsync(() async {
      await library.addMedia(
        library.byId(id)!,
        [
          Media(
            XFile.fromData(Uint8List.fromList([5, 5]), name: 'take.mp4'),
            PageKind.video,
            'mp4',
          ),
        ],
        take: true,
        takeLog: log,
      );
    });
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    expect(find.text('1 / 3'), findsOneWidget);

    video.position = const Duration(seconds: 1);
    await tester.tap(find.byTooltip('Play'));
    await frames(tester);
    expect(video.playing, hasLength(1));
    // Its own first line, no longer the tab's: shown as it was.
    expect(shown(tester), old);
    expect(find.text('1 / 3'), findsNothing);
    // 5 s on the take's clock is 5.2 s in the file.
    video.position = const Duration(milliseconds: 5100);
    await frames(tester);
    expect(shown(tester), old);
    video.position = const Duration(milliseconds: 5300);
    await frames(tester);
    expect(shown(tester), 'e|--12-10-|\nB|--13-12-|');
    expect(find.text('3 / 3'), findsOneWidget);

    await tester.tap(_camStop);
    await frames(tester);
    expect(video.playing, isEmpty);
    expect(find.text('3 / 3'), findsOneWidget);
  });

  /// Adds a take ([extension]'s) to capture [id], as another device's
  /// arrives.
  Future<void> addTake(
    WidgetTester tester,
    Library library,
    String id, {
    String extension = 'mp4',
  }) => tester.runAsync(() async {
    await library.addMedia(
      library.byId(id)!,
      [
        Media(
          XFile.fromData(Uint8List.fromList([5, 5]), name: 'take.$extension'),
          PageKind.video,
          extension,
        ),
      ],
      take: true,
      takeLog: const TakeLog(burned: true),
    );
  });

  bool playEnabled(WidgetTester tester) =>
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const Key('cam-play')),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed !=
      null;

  testWidgets('while the take Play plays opens (its file still arriving), '
      'Rec, 1 and . wait, and Play, showing Stop, lets it go', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    await addTake(tester, library, id);
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    expect(recReady(tester), isTrue);

    var hold = video.createHold = Completer<void>();
    await tester.tap(find.byTooltip('Play'));
    await frames(tester);
    expect(video.playing, isEmpty);
    expect(recReady(tester), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await frames(tester);
    expect(camera.recording, isFalse);
    // Play again: let go of; it opens to be let go of at once.
    await tester.tap(_camStop);
    await frames(tester);
    expect(recReady(tester), isTrue);
    hold.complete();
    await frames(tester);
    expect(video.playing, isEmpty);
    expect(video.disposed, [video.lastPlayer]);
    expect(find.byTooltip('Play'), findsOneWidget);

    // Waited for, it plays.
    hold = video.createHold = Completer<void>();
    await tester.tap(find.byTooltip('Play'));
    await frames(tester);
    expect(recReady(tester), isFalse);
    hold.complete();
    await frames(tester);
    expect(video.playing, hasLength(1));
    await tester.tap(_camStop);
    await frames(tester);
    expect(video.playing, isEmpty);
    expect(recReady(tester), isTrue);
  });

  testWidgets('on iOS, Play passes over a take it can\'t play (a WebM, '
      'recorded in a browser) for the last it can', (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(TakeAudio.channel, (_) async => null);
    addTearDown(
      () => messenger.setMockMethodCallHandler(TakeAudio.channel, null),
    );
    expect(takePlaysHere('video/webm'), isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      expect(takePlaysHere('video/webm'), isFalse);
      expect(takePlaysHere('video/mp4'), isTrue);
      final (library, id) = await capture(tester, tab: _tab);
      await addTake(tester, library, id, extension: 'webm');
      Widget cam() => app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      );
      await tester.pumpWidget(cam());
      await frames(tester);
      // Only a WebM: nothing to play.
      expect(playEnabled(tester), isFalse);

      // An MP4 before it: that one.
      await tester.pumpWidget(const SizedBox());
      await addTake(tester, library, id);
      await addTake(tester, library, id, extension: 'webm');
      await tester.pumpWidget(cam());
      await frames(tester);
      expect(playEnabled(tester), isTrue);
      await tester.tap(find.byTooltip('Play'));
      await frames(tester);
      expect(video.playing, hasLength(1));
      await tester.tap(_camStop);
      await frames(tester);
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a tab with a neckline twice: the take just recorded plays '
      'back on the copy that showed, and leaves Cam there', (tester) async {
    // The third staff the same as the second (the log keeps its text once).
    const twice = '''
e|--0--3--|
B|--1--1--|

e|--5--7--|
B|--5--8--|

e|--5--7--|
B|--5--8--|
''';
    final (library, id) = await capture(tester, tab: twice);
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    await tester.tap(find.byTooltip('Next line'));
    await tester.pump();
    await tester.tap(find.byTooltip('Next line'));
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));
    final log = library.byId(id)!.pages.last.takeLog!;
    expect(log.tab!.lines, hasLength(2));
    expect([for (final (_, line) in log.tab!.marks) line], [0, 1, 1]);

    // Back to the first line, then Play from the take's end.
    await tester.tap(find.byTooltip('Previous line'));
    await tester.pump();
    await tester.tap(find.byTooltip('Previous line'));
    await tester.pump();
    expect(find.text('1 / 3'), findsOneWidget);
    video.position = const Duration(minutes: 1);
    await tester.tap(find.byTooltip('Play'));
    await frames(tester);
    expect(video.playing, hasLength(1));
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.tap(_camStop);
    await frames(tester);
    expect(find.text('3 / 3'), findsOneWidget);
  });

  testWidgets('recording comes first: on iOS the take\'s sound is set up '
      'when Cam opens and again as a take starts; while it records, head '
      'gestures look less often and sync waits; the take plays back mixed '
      'with others', (tester) async {
    final audio = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(TakeAudio.channel, (call) async {
      audio.add(call.method);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(TakeAudio.channel, null),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final (library, id) = await capture(tester, tab: _tab);
      late FakeHeads heads;
      await tester.pumpWidget(
        app(
          PlayAlongScreen(
            library: library,
            eventId: id,
            cameras: () async => [_front],
            headTracking: (_, onGesture) => heads = FakeHeads(onGesture),
            takeRecorder: () => null,
          ),
        ),
      );
      await frames(tester);
      // The camera records sound, at a bitrate for music; the microphone
      // joins it now, and the session is set, before any take.
      final settings = camera.settings.single!;
      expect(settings.enableAudio, isTrue);
      expect(settings.audioBitrate, TakePriority.iosAudioBitrate);
      expect(camera.prepared, 1);
      expect(audio, ['prepare']);
      expect(TakePriority.recording.value, isFalse);

      await tester.tap(find.byTooltip('Rec (1)'));
      await frames(tester);
      expect(camera.recording, isTrue);
      expect(audio, ['prepare', 'prepare']);
      expect(TakePriority.recording.value, isTrue);
      expect(heads.recordings, [true]);

      await tester.tap(_camStop);
      await until(tester, () => recReady(tester));
      expect(camera.recording, isFalse);
      expect(library.byId(id)!.pages.last.title, 'Take 1');
      expect(TakePriority.recording.value, isFalse);
      expect(heads.recordings, [true, false]);

      // Played back, the take leaves others' sound playing.
      await tester.tap(find.byTooltip('Play'));
      await frames(tester);
      expect(video.playing, hasLength(1));
      expect(video.mixes, isNotEmpty);
      expect(video.mixes, everyElement(isTrue));
      await tester.tap(_camStop);
      await frames(tester);

      // Closed: the session's mode back to the default.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(audio.last, 'release');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('iOS: a take every browser plays', () {
    /// The calls on `tabcam/video_edit` ([TakeH264]); the codec the take
    /// is told to be in; while set, `h264` waits for it; and what `h264`
    /// fails with, if it's to.
    late List<String> calls;
    late String? codec;
    Completer<void>? converting;
    PlatformException? fail;
    late Directory dir;

    Future<void> open(WidgetTester tester) async {
      calls = [];
      codec = 'avc1';
      converting = null;
      fail = null;
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('take_h264_test');
      });
      addTearDown(() => dir.deleteSync(recursive: true));
      final paths = PathProviderPlatform.instance;
      addTearDown(() => PathProviderPlatform.instance = paths);
      PathProviderPlatform.instance = _Paths(dir.path);
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(TakeAudio.channel, (_) async => null);
      messenger.setMockMethodCallHandler(TakeH264.channel, (call) async {
        calls.add(call.method);
        if (call.method == 'codec') return codec;
        await converting?.future;
        if (fail case final error?) throw error;
        final output = (call.arguments as Map)['output'] as String;
        File(output).writeAsBytesSync([8, 8]);
        return output;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(TakeAudio.channel, null);
        messenger.setMockMethodCallHandler(TakeH264.channel, null);
      });
    }

    Future<Uint8List> saved(WidgetTester tester, Library library, String id) =>
        tester
            .runAsync(
              () => library.original(
                library.byId(id)!,
                library.byId(id)!.pages.last,
              ),
            )
            .then((bytes) => bytes!);

    Future<void> take(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Rec (1)'));
      await frames(tester);
      await tester.tap(_camStop);
      await frames(tester);
    }

    testWidgets('an H.264 take is saved as it is; an HEVC one is made H.264 '
        'as it\'s saved, a card saying so meanwhile', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await open(tester);
        final (library, id) = await capture(tester, tab: _tab);
        await tester.pumpWidget(
          app(
            PlayAlongScreen(
              library: library,
              eventId: id,
              cameras: () async => [_front],
              headTracking: (_, _) => null,
              takeRecorder: () => null,
            ),
          ),
        );
        await frames(tester);

        await take(tester);
        await until(tester, () => recReady(tester));
        expect(calls, ['codec']);
        expect(await saved(tester, library, id), [9, 1]);

        codec = 'hvc1';
        converting = Completer<void>();
        await take(tester);
        await until(tester, () => calls.length == 3);
        await tester.pump();
        expect(calls, ['codec', 'codec', 'h264']);
        expect(
          find.text('Saving the take so every browser plays it…'),
          findsOneWidget,
        );
        converting!.complete();
        await until(tester, () => recReady(tester));
        expect(
          find.text('Saving the take so every browser plays it…'),
          findsNothing,
        );
        final pages = library.byId(id)!.pages;
        expect(pages.last.title, 'Take 2');
        expect(pages.last.takeLog!.burned, isFalse);
        expect(await saved(tester, library, id), [8, 8]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('should making it H.264 fail, the take is saved as recorded, '
        'and a message says so', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await open(tester);
        codec = 'hvc1';
        fail = PlatformException(code: 'failed', message: 'export failed');
        final (library, id) = await capture(tester, tab: _tab);
        await tester.pumpWidget(
          app(
            PlayAlongScreen(
              library: library,
              eventId: id,
              cameras: () async => [_front],
              headTracking: (_, _) => null,
              takeRecorder: () => null,
            ),
          ),
        );
        await frames(tester);
        await take(tester);
        await until(tester, () => recReady(tester));
        expect(calls, ['codec', 'h264']);
        expect(library.byId(id)!.pages.last.title, 'Take 1');
        expect(await saved(tester, library, id), [9, 1]);
        expect(
          find.textContaining(
            'The take was saved as the camera recorded it, which some '
            'browsers can\'t play: export failed',
          ),
          findsOneWidget,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  testWidgets('1 presses Rec and Stop (the top row\'s or the keypad\'s); '
      'held, it doesn\'t repeat; it doesn\'t turn the tab', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    expect(find.text('1 / 3'), findsOneWidget);

    // 1 down: a take starts; held (repeats), it records on.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1);
    await frames(tester);
    expect(camera.recording, isTrue);
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.digit1);
      await frames(tester);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
    await frames(tester);
    expect(camera.recording, isTrue);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const Key('cam-rec')),
              matching: find.byType(IconButton),
            ),
          )
          .tooltip,
      _stopKeys,
    );
    // Other keys still turn the tab.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);

    // 1 again: Stop, the take saved.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await until(tester, () => recReady(tester));
    expect(camera.recording, isFalse);
    var pages = library.byId(id)!.pages;
    expect(pages, hasLength(2));
    expect(pages.last.title, 'Take 1');
    expect(find.text('2 / 3'), findsOneWidget);

    // The keypad's 1 too.
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
    await frames(tester);
    expect(camera.recording, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
    await until(tester, () => recReady(tester));
    expect(camera.recording, isFalse);
    pages = library.byId(id)!.pages;
    expect(pages, hasLength(3));
    expect(pages.last.title, 'Take 2');
    expect(find.text('2 / 3'), findsOneWidget);

    // Ctrl + 1 is no Rec: it turns the tab as any key.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await frames(tester);
    expect(camera.recording, isFalse);
    expect(find.text('3 / 3'), findsOneWidget);

    // While a take plays back, Rec is dead, and so is 1.
    await tester.tap(find.byTooltip('Play'));
    await frames(tester);
    expect(video.playing, hasLength(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await frames(tester);
    expect(camera.recording, isFalse);
    expect(library.byId(id)!.pages, hasLength(3));
    await tester.tap(_camStop);
    await frames(tester);
    expect(video.playing, isEmpty);
  });

  testWidgets('. saves the take and starts a new one (the main keyboard\'s '
      'or the keypad\'s); held, it doesn\'t repeat; not recording, it '
      'starts a take; it doesn\'t turn the tab', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    List<EventPage> pages() => library.byId(id)!.pages;

    // Not recording: . starts a take, as Rec.
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await frames(tester);
    expect(camera.recording, isTrue);
    expect(pages(), hasLength(1));
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);

    // Recording: . saves Take 1 and records again; held, no more.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.period);
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.period);
      await frames(tester);
    }
    await until(tester, () => pages().length == 2 && camera.recording);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.period);
    await frames(tester);
    expect(camera.recordings, 1);
    expect(camera.recording, isTrue);
    expect(pages(), hasLength(2));
    expect(pages().last.title, 'Take 1');
    expect(find.text('Take 1 added to the capture'), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const Key('cam-rec')),
              matching: find.byType(IconButton),
            ),
          )
          .tooltip,
      _stopKeys,
    );

    // The keypad's . too.
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadDecimal);
    await until(tester, () => pages().length == 3 && camera.recording);
    expect(pages().last.title, 'Take 2');
    expect(camera.recordings, 2);

    // Ctrl + . is no new take: it turns the tab as any key.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await frames(tester);
    expect(camera.recording, isTrue);
    expect(pages(), hasLength(3));
    expect(find.text('3 / 3'), findsOneWidget);

    // Stop saves the last: Take 3.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await until(tester, () => recReady(tester));
    expect(camera.recording, isFalse);
    expect(pages(), hasLength(4));
    expect(pages().last.title, 'Take 3');
  });

  testWidgets('. pressed again while the take is saved for the next does '
      'nothing, nor does 1; the next starts once it\'s saved', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    List<EventPage> pages() => library.byId(id)!.pages;

    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    expect(camera.recording, isTrue);

    final hold = camera.stopHold = Completer<void>();
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await frames(tester);
    // Saving: the camera stopped, no new take yet.
    expect(camera.recording, isFalse);
    expect(camera.recordings, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadDecimal);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await frames(tester);
    expect(camera.recording, isFalse);
    expect(pages(), hasLength(1));
    // Rec is dead meanwhile.
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const Key('cam-rec')),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );

    hold.complete();
    await until(tester, () => pages().length == 2 && camera.recording);
    await frames(tester);
    // One take saved, one recording: the presses meanwhile did nothing.
    expect(pages().last.title, 'Take 1');
    expect(camera.recordings, 1);
    expect(camera.recording, isTrue);

    camera.stopHold = null;
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));
    expect(pages(), hasLength(3));
    expect(pages().last.title, 'Take 2');
  });

  testWidgets('., 1 and Rec pressed again while a take starts do nothing: '
      'one recording starts', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    List<EventPage> pages() => library.byId(id)!.pages;

    final hold = camera.startHold = Completer<void>();
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await frames(tester);
    expect(camera.starts, 1);
    expect(camera.recording, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadDecimal);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    expect(camera.starts, 1);

    camera.startHold = null;
    hold.complete();
    await until(tester, () => camera.recording);
    await frames(tester);
    expect(camera.starts, 1);
    expect(find.textContaining("Couldn't record"), findsNothing);

    // One take, saved at Stop.
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));
    expect(camera.recordings, 1);
    expect(pages(), hasLength(2));
    expect(pages().last.title, 'Take 1');
  });

  testWidgets('the keypad\'s decimal key typing "," (a European layout on '
      'the web) is . too; the comma key turns the tab', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    List<EventPage> pages() => library.byId(id)!.pages;

    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(camera.recording, isFalse);

    Future<void> keypadComma() => tester.sendKeyEvent(
      LogicalKeyboardKey.comma,
      physicalKey: PhysicalKeyboardKey.numpadDecimal,
      character: ',',
    );
    await keypadComma();
    await frames(tester);
    expect(camera.recording, isTrue);
    expect(find.text('2 / 3'), findsOneWidget);

    await keypadComma();
    await until(tester, () => pages().length == 2 && camera.recording);
    expect(pages().last.title, 'Take 1');
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));
    expect(pages().last.title, 'Take 2');
  });

  testWidgets('. keeps the take when the next can\'t start', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    expect(camera.recording, isTrue);

    camera.startError = CameraException('busy', 'the camera is busy');
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await until(tester, () => recReady(tester));
    expect(camera.recording, isFalse);
    final pages = library.byId(id)!.pages;
    expect(pages, hasLength(2));
    expect(pages.last.title, 'Take 1');
    // Its message, then the failure's.
    expect(find.text('Take 1 added to the capture'), findsOneWidget);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.textContaining("Couldn't record"), findsOneWidget);
  });

  testWidgets('without a text tab, it says so', (tester) async {
    final (library, id) = await capture(tester);
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_back],
        ),
      ),
    );
    await frames(tester);
    expect(find.textContaining('No text tab yet'), findsOneWidget);
    expect(find.byKey(const Key('neckline')), findsNothing);
  });

  testWidgets('a nod turns the tab; head gestures switch off', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    FakeHeads? heads;
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, onGesture) => heads = FakeHeads(onGesture),
        ),
      ),
    );
    await frames(tester);
    // The camera's frames go to it.
    expect(camera.streaming, isTrue);
    expect(find.byTooltip(RegExp('^Head gestures on')), findsOneWidget);
    // Seeing a face: the theme's primary colour.
    final context = tester.element(find.byKey(const Key('cam-heads')));
    expect(
      tester.widget<IconButton>(find.byKey(const Key('cam-heads'))).color,
      Theme.of(context).colorScheme.primary,
    );

    heads!.onGesture(HeadGesture.next);
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);
    heads!.onGesture(HeadGesture.next);
    heads!.onGesture(HeadGesture.previous);
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);

    // Recording, the frames still go to it.
    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    expect(camera.streaming, isTrue);
    heads!.onGesture(HeadGesture.next);
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));
    expect(camera.streaming, isTrue);

    // Off: no frames, and a gesture does nothing.
    await tester.tap(find.byKey(const Key('cam-heads')));
    await frames(tester);
    expect(find.byTooltip('Head gestures off'), findsOneWidget);
    expect(camera.streaming, isFalse);
    expect(heads!.active, isFalse);
    heads!.onGesture(HeadGesture.previous);
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);

    // Off, a take streams no frames either (on iOS each would be copied
    // on the queue that writes the take's sound).
    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    expect(camera.recording, isTrue);
    expect(camera.streaming, isFalse);
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));
    expect(camera.streaming, isFalse);

    await tester.pumpWidget(const SizedBox());
    expect(heads!.disposed, isTrue);
  });

  testWidgets('with a camera that streams no frames (the web\'s), head '
      'gestures still work, and it records', (tester) async {
    camera.imageStreaming = false;
    final (library, id) = await capture(tester, tab: _tab);
    FakeHeads? heads;
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, onGesture) => heads = FakeHeads(onGesture),
        ),
      ),
    );
    await frames(tester);
    expect(camera.streaming, isFalse);
    expect(heads!.active, isTrue);
    expect(find.byKey(const Key('cam-heads')), findsOneWidget);

    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    expect(camera.recording, isTrue);
    heads!.onGesture(HeadGesture.next);
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));
    expect(camera.recordings, 1);

    await tester.tap(find.byKey(const Key('cam-heads')));
    await frames(tester);
    expect(heads!.active, isFalse);
    heads!.onGesture(HeadGesture.next);
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);
  });

  group('web: no take without its sound', () {
    Future<(Library, String)> open(
      WidgetTester tester,
      FakeTakeRecorder recorder,
    ) async {
      camera.imageStreaming = false;
      final (library, id) = await capture(tester, tab: _tab);
      await tester.pumpWidget(
        app(
          PlayAlongScreen(
            library: library,
            eventId: id,
            cameras: () async => [_front],
            headTracking: (_, _) => null,
            takeRecorder: () => recorder,
          ),
        ),
      );
      await frames(tester);
      return (library, id);
    }

    testWidgets('with no microphone (refused, or none), Rec records '
        'nothing and says why', (tester) async {
      final recorder = FakeTakeRecorder()..sound = false;
      final (library, id) = await open(tester, recorder);
      expect(recorder.prepared, 1);
      await tester.tap(find.byTooltip('Rec (1)'));
      await frames(tester);
      expect(recorder.started, 0);
      expect(camera.starts, 0);
      expect(camera.recording, isFalse);
      expect(find.textContaining('No take without its sound'), findsOneWidget);
      expect(recReady(tester), isTrue);
      expect(library.byId(id)!.pages, hasLength(1));
      expect(TakePriority.recording.value, isFalse);
    });

    testWidgets('the recorder failing, the camera records the take alone '
        'with the microphone\'s sound', (tester) async {
      final recorder = FakeTakeRecorder()
        ..startError = StateError('the camera isn\'t showing yet');
      final (library, id) = await open(tester, recorder);
      await tester.tap(find.byTooltip('Rec (1)'));
      await frames(tester);
      expect(recorder.lent, 1);
      expect(camera.recording, isTrue);
      // The same take either way: nothing to say.
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(_camStop);
      await until(tester, () => recReady(tester));
      expect(library.byId(id)!.pages.last.title, 'Take 1');
      // No tab in its picture, its log says; the lag told by the bounds.
      final log = library.byId(id)!.pages.last.takeLog!;
      expect(log.burned, isFalse);
      expect(log.tab!.lines, hasLength(1));
      expect(log.lagFrom, LagFrom.bounds);
    });

    testWidgets('a take recorded by the recorder: no tab in its picture, '
        'its log says, its lag the recorder\'s', (tester) async {
      final recorder = FakeTakeRecorder()..sinceStart = 86.6;
      final (library, id) = await open(tester, recorder);
      await tester.tap(find.byTooltip('Rec (1)'));
      await frames(tester);
      expect(recorder.started, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      await tester.tap(_camStop);
      await until(tester, () => recReady(tester));
      final log = library.byId(id)!.pages.last.takeLog!;
      expect(log.burned, isFalse);
      expect(log.lagMs, 87);
      expect(log.lagFrom, LagFrom.recorder);
      expect(log.lagRaw['recorderStartMs'], -87);
      expect([for (final (_, line) in log.tab!.marks) line], [0, 1]);
    });

    testWidgets('the recorder failing and the microphone not lent, no take', (
      tester,
    ) async {
      final recorder = FakeTakeRecorder()
        ..startError = StateError('no recorder')
        ..lends = false;
      final (library, id) = await open(tester, recorder);
      await tester.tap(find.byTooltip('Rec (1)'));
      await frames(tester);
      expect(recorder.lent, 1);
      expect(camera.starts, 0);
      expect(camera.recording, isFalse);
      expect(find.textContaining('No take without its sound'), findsOneWidget);
      expect(recReady(tester), isTrue);
      expect(library.byId(id)!.pages, hasLength(1));
    });
  });

  group('Android: the take\'s sound recorded by the app', () {
    /// The calls on `tabcam/take_sound`, and what the camera was doing at
    /// each (started recordings, recording).
    late List<(String, int, bool)> calls;
    late List<Object?> stopArgs;
    late List<Object?> prepareArgs;

    /// What the native side does: [prepared] for `prepare` (then
    /// [preparedAgain], if set, for the next ones), the files `stop` gives
    /// in turn ([takes]), or an error for a method in [fail].
    late Map<String, Object?> prepared;
    late Map<String, Object?>? preparedAgain;
    late List<String> takes;
    late Map<String, PlatformException> fail;
    late String? warning;
    late Directory dir;

    setUp(() {
      calls = [];
      stopArgs = [];
      prepareArgs = [];
      preparedAgain = null;
      prepared = {
        'ok': true,
        'source': 'unprocessed',
        'sampleRate': 48000,
        'channels': 2,
      };
      takes = [];
      fail = {};
      warning = null;
    });

    Future<void> open(WidgetTester tester, {int takeCount = 1}) async {
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('take_sound_test');
        for (var i = 0; i < takeCount; i++) {
          final file = File('${dir.path}/take-$i.mp4');
          await file.writeAsBytes([5, i]);
          takes.add(file.path);
        }
      });
      addTearDown(() => dir.deleteSync(recursive: true));
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(TakeSound.channel, (call) async {
        calls.add((call.method, camera.starts, camera.recording));
        if (fail[call.method] case final error?) throw error;
        return switch (call.method) {
          'prepare' => () {
            prepareArgs.add(call.arguments);
            return prepareArgs.length > 1
                ? preparedAgain ?? prepared
                : prepared;
          }(),
          'stop' => () {
            stopArgs.add(call.arguments);
            return {
              'path': takes.removeAt(0),
              'leadMs': 120.0,
              'warning': warning,
            };
          }(),
          _ => null,
        };
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(TakeSound.channel, null),
      );
    }

    List<String> methods() => [for (final (m, _, _) in calls) m];

    Widget cam(Library library, String id) => PlayAlongScreen(
      library: library,
      eventId: id,
      cameras: () async => [_front],
      headTracking: (_, _) => null,
      takeRecorder: () => null,
    );

    testWidgets('the camera opens without sound; Rec starts the sound before '
        'the camera, Stop puts it into the take (and that\'s the take: no '
        'burn after); '
        '. does it again; closed, the microphone is closed', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await open(tester, takeCount: 2);
        final (library, id) = await capture(tester, tab: _tab);
        await tester.pumpWidget(app(cam(library, id)));
        await frames(tester);
        expect(methods(), ['prepare']);
        expect(camera.settings.single!.enableAudio, isFalse);

        await tester.tap(find.byTooltip('Rec (1)'));
        await frames(tester);
        expect(camera.recording, isTrue);
        // The sound started before the camera; the camera's start told
        // once it recorded.
        expect(calls, [
          ('prepare', 0, false),
          ('start', 0, false),
          ('videoStarted', 1, true),
        ]);

        await tester.tap(_camStop);
        await until(tester, () => recReady(tester));
        expect(calls.sublist(3), [
          ('videoStopping', 1, true),
          ('stop', 1, false),
        ]);
        // The camera's video went to the sound, and what came back is the
        // take, saved as it is.
        expect(stopArgs.single, containsPair('video', isA<String>()));
        var pages = library.byId(id)!.pages;
        expect(pages.last.title, 'Take 1');
        expect(pages.last.takeLog!.burned, isFalse);
        late Uint8List saved;
        await tester.runAsync(
          () async =>
              saved = await library.original(library.byId(id)!, pages.last),
        );
        expect(saved, [5, 0]);
        expect(find.textContaining('without its sound'), findsNothing);

        // . : the take saved with its sound, and the next started the
        // same way.
        await tester.sendKeyEvent(LogicalKeyboardKey.period);
        await frames(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.period);
        await until(
          tester,
          () => library.byId(id)!.pages.length == 3 && camera.recording,
        );
        expect(methods().sublist(5), [
          'start',
          'videoStarted',
          'videoStopping',
          'stop',
          'start',
          'videoStarted',
        ]);
        pages = library.byId(id)!.pages;
        await tester.runAsync(
          () async =>
              saved = await library.original(library.byId(id)!, pages.last),
        );
        expect(saved, [5, 1]);

        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(methods().last, 'release');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('where the app can\'t record the sound (no microphone '
        'source works), the camera records it, as before', (tester) async {
      prepared = {'ok': false, 'reason': 'No microphone could be opened'};
      await open(tester);
      final (library, id) = await capture(tester, tab: _tab);
      await tester.pumpWidget(app(cam(library, id)));
      await frames(tester);
      expect(camera.settings.single!.enableAudio, isTrue);
      await tester.tap(find.byTooltip('Rec (1)'));
      await frames(tester);
      expect(camera.recording, isTrue);
      await tester.tap(_camStop);
      await until(tester, () => recReady(tester));
      // Only prepared (and released when Cam closes).
      expect(methods(), ['prepare']);
      expect(library.byId(id)!.pages.last.title, 'Take 1');
    });

    testWidgets('the microphone refused when the app asked, then allowed at '
        'the camera\'s prompt (the camera opened with sound): the app '
        'records the sound after all', (tester) async {
      prepared = {
        'ok': false,
        'reason': 'The microphone isn\'t allowed',
        'refused': true,
      };
      preparedAgain = {
        'ok': true,
        'source': 'unprocessed',
        'sampleRate': 48000,
        'channels': 2,
      };
      await open(tester);
      final (library, id) = await capture(tester, tab: _tab);
      await tester.pumpWidget(app(cam(library, id)));
      await frames(tester);
      // Asked once; prepared again, without asking, once the camera opened.
      expect(camera.settings.single!.enableAudio, isTrue);
      expect(prepareArgs, [
        {'ask': true},
        {'ask': false},
      ]);
      expect(calls.last, ('prepare', 0, false));
      await tester.tap(find.byTooltip('Rec (1)'));
      await frames(tester);
      expect(camera.recording, isTrue);
      await tester.tap(_camStop);
      await until(tester, () => recReady(tester));
      expect(methods(), [
        'prepare',
        'prepare',
        'start',
        'videoStarted',
        'videoStopping',
        'stop',
      ]);
      late Uint8List saved;
      await tester.runAsync(
        () async => saved = await library.original(
          library.byId(id)!,
          library.byId(id)!.pages.last,
        ),
      );
      expect(saved, [5, 0]);
    });

    testWidgets('the microphone refused, and still not usable once the '
        'camera opened: the camera records the sound', (tester) async {
      prepared = {
        'ok': false,
        'reason': 'The microphone isn\'t allowed',
        'refused': true,
      };
      preparedAgain = {'ok': false, 'reason': 'No microphone could be opened'};
      await open(tester);
      final (library, id) = await capture(tester, tab: _tab);
      await tester.pumpWidget(app(cam(library, id)));
      await frames(tester);
      expect(camera.settings.single!.enableAudio, isTrue);
      await tester.tap(find.byTooltip('Rec (1)'));
      await frames(tester);
      expect(camera.recording, isTrue);
      await tester.tap(_camStop);
      await until(tester, () => recReady(tester));
      expect(methods(), ['prepare', 'prepare']);
      expect(library.byId(id)!.pages.last.title, 'Take 1');
    });

    testWidgets('the sound not starting (the microphone busy), no take, '
        'and a message says why', (tester) async {
      fail['start'] = PlatformException(
        code: 'failed',
        message: 'The microphone is in use',
      );
      await open(tester);
      final (library, id) = await capture(tester, tab: _tab);
      await tester.pumpWidget(app(cam(library, id)));
      await frames(tester);
      await tester.tap(find.byTooltip('Rec (1)'));
      await frames(tester);
      expect(camera.starts, 0);
      expect(camera.recording, isFalse);
      expect(
        find.textContaining(
          "Couldn't record: PlatformException(failed, "
          'The microphone is in use',
        ),
        findsOneWidget,
      );
      expect(recReady(tester), isTrue);
      expect(library.byId(id)!.pages, hasLength(1));
      expect(TakePriority.recording.value, isFalse);
    });

    testWidgets('the camera not starting, the sound is dropped', (
      tester,
    ) async {
      await open(tester);
      final (library, id) = await capture(tester, tab: _tab);
      await tester.pumpWidget(app(cam(library, id)));
      await frames(tester);
      camera.startError = CameraException('busy', 'The camera is busy');
      await tester.tap(find.byTooltip('Rec (1)'));
      await frames(tester);
      expect(methods(), ['prepare', 'start', 'cancel']);
      expect(camera.recording, isFalse);
      expect(library.byId(id)!.pages, hasLength(1));
    });

    testWidgets('the sound not put in: the take is kept, and a message says '
        'it has no sound', (tester) async {
      fail['stop'] = PlatformException(
        code: 'failed',
        message: 'No sound was recorded',
      );
      await open(tester);
      final (library, id) = await capture(tester, tab: _tab);
      await tester.pumpWidget(app(cam(library, id)));
      await frames(tester);
      await tester.tap(find.byTooltip('Rec (1)'));
      await frames(tester);
      await tester.tap(_camStop);
      await until(tester, () => recReady(tester));
      final pages = library.byId(id)!.pages;
      expect(pages.last.title, 'Take 1');
      late Uint8List saved;
      await tester.runAsync(
        () async =>
            saved = await library.original(library.byId(id)!, pages.last),
      );
      // The camera's own.
      expect(saved, [9, 1]);
      expect(
        find.text(
          'The take was saved without its sound: No sound was '
          'recorded',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a sound with a problem: the take is kept with it, and a '
        'message says what', (tester) async {
      warning = 'the microphone gave only silence';
      await open(tester);
      final (library, id) = await capture(tester, tab: _tab);
      await tester.pumpWidget(app(cam(library, id)));
      await frames(tester);
      await tester.tap(find.byTooltip('Rec (1)'));
      await frames(tester);
      await tester.tap(_camStop);
      await until(tester, () => recReady(tester));
      final pages = library.byId(id)!.pages;
      expect(pages.last.title, 'Take 1');
      late Uint8List saved;
      await tester.runAsync(
        () async =>
            saved = await library.original(library.byId(id)!, pages.last),
      );
      expect(saved, [5, 0]);
      expect(
        find.text("Check the take's sound: the microphone gave only silence"),
        findsOneWidget,
      );
    });
  });

  testWidgets('where head gestures can\'t work, there\'s no switch', (
    tester,
  ) async {
    final (library, id) = await capture(tester, tab: _tab);
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
        ),
      ),
    );
    await frames(tester);
    expect(find.byKey(const Key('cam-heads')), findsNothing);
    expect(camera.streaming, isFalse);
  });

  testWidgets('back from Cam, the capture shows its new takes', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    await tester.pumpWidget(
      app(EventScreen(library: library, eventId: id, initialText: true)),
    );
    await frames(tester);
    await tester.tap(find.byKey(const Key('cam')));
    await frames(tester);
    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));
    // Saved before going back (here without the tab: no native code).
    expect(library.byId(id)!.pages, hasLength(2));
    await tester.pageBack();
    await tester.pump();
    await frames(tester);
    expect(find.byType(PlayAlongScreen), findsNothing);
    // The list, not the Text view, with the take in it.
    expect(find.text('Take 1'), findsOneWidget);
  });

  testWidgets('Play along: the sidebar opens with the first file loaded, '
      'paused, in a frame at its top; a recording or link from it plays '
      'there; space pauses and plays it; Stop and 0 go back to the start; '
      '← and → skip in it, ↑ and ↓ turn the tab; '
      'hidden, it pauses and space turns the tab', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    late String audio, youTube;
    await tester.runAsync(() async {
      var event = await library.addMedia(library.byId(id)!, [
        Media(
          XFile.fromData(Uint8List.fromList([1]), name: 'lesson.m4a'),
          PageKind.audio,
          'm4a',
        ),
      ]);
      audio = event.pages.last.id;
      await library.renamePage(id, audio, 'Lesson');
      event = await library.addLink(
        library.byId(id)!,
        Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        title: 'Backing track',
      );
      youTube = event.pages.last.id;
    });
    final links = <LinkFrameController>[];
    final commands = <LinkCommand>[];
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
          linkFrame: (link) {
            if (!links.contains(link)) {
              links.add(link);
              link.command = (command) async => commands.add(command);
            }
            return const SizedBox(key: Key('fake-link-frame'));
          },
        ),
      ),
    );
    await frames(tester);
    // Open, with the first file (the recording, not the photo) loaded in
    // the frame, paused.
    expect(find.byKey(const Key('cam-along-sidebar')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('cam-along-sidebar')),
        matching: find.byKey(const Key('cam-along-frame')),
      ),
      findsOneWidget,
    );
    expect(find.text('Lesson'), findsNWidgets(2));
    expect(find.text('Backing track'), findsOneWidget);
    expect(video.playing, isEmpty);
    expect(find.byKey(const Key('cam-along-stop')), findsOneWidget);

    // Repeat is on: it loops; tapped, it doesn't.
    expect(video.looping.values.single, isTrue);
    await tester.tap(find.byKey(const Key('cam-along-repeat')));
    await frames(tester);
    expect(video.looping.values.single, isFalse);
    expect(find.byTooltip('Repeat off'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cam-along-repeat')));
    await frames(tester);
    expect(video.looping.values.single, isTrue);

    // » and « go 10 seconds forward and back, not before the start.
    await tester.tap(find.byKey(const Key('cam-along-forward')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('cam-along-forward')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('cam-along-back')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('cam-along-back')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('cam-along-back')));
    await frames(tester);
    expect(video.seeks, const [
      Duration(seconds: 10),
      Duration(seconds: 20),
      Duration(seconds: 10),
      Duration.zero,
      Duration.zero,
    ]);
    video.seeks.clear();

    // Play, then Stop.
    await tester.tap(find.byKey(const Key('cam-along-toggle')));
    await frames(tester);
    expect(video.playing, hasLength(1));
    await tester.tap(find.byKey(const Key('cam-along-stop')));
    await frames(tester);
    expect(video.playing, isEmpty);

    // Hidden (the frame with it, paused) and shown again.
    await tester.tap(find.byKey(const Key('cam-along-toggle')));
    await frames(tester);
    expect(video.playing, hasLength(1));
    // 0: back to the start, playing on.
    video.seeks.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await frames(tester);
    expect(video.seeks, const [Duration.zero]);
    expect(video.playing, hasLength(1));

    // ← and →: back and on in the track, the tab staying; ↓ and ↑ turn
    // the tab.
    final line = shown(tester);
    video.seeks.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await frames(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await frames(tester);
    expect(video.seeks, hasLength(2));
    expect(video.seeks.last, lessThan(video.seeks.first));
    expect(shown(tester), line);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await frames(tester);
    expect(shown(tester), isNot(line));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await frames(tester);
    expect(shown(tester), line);
    await tester.tap(find.byKey(const Key('cam-along')));
    await frames(tester);
    expect(find.byKey(const Key('cam-along-sidebar')), findsNothing);
    expect(find.byKey(const Key('cam-along-frame')), findsNothing);
    expect(video.playing, isEmpty);
    await tester.tap(find.byKey(const Key('cam-along')));
    await frames(tester);
    expect(find.byKey(const Key('cam-along-sidebar')), findsOneWidget);

    // The recording, tapped in the sidebar: plays in its frame.
    await tester.tap(find.byKey(ValueKey('cam-along-$audio')));
    await frames(tester);
    expect(video.playing, hasLength(1));

    // Space pauses and plays it; the neckline stays.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await frames(tester);
    expect(video.playing, isEmpty);
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await frames(tester);
    expect(video.playing, hasLength(1));
    // Other keys still turn the tab.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);

    // The link, in its place: the recording stops.
    await tester.tap(find.byKey(ValueKey('cam-along-$youTube')));
    await frames(tester);
    expect(video.playing, isEmpty);
    expect(find.byKey(const Key('fake-link-frame')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await frames(tester);
    expect(commands, [LinkCommand.pause]);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await frames(tester);
    expect(commands, [LinkCommand.pause, LinkCommand.play]);
    await tester.tap(find.byKey(const Key('cam-along-stop')));
    await frames(tester);
    expect(commands.last, LinkCommand.stop);

    // Hidden: space turns the tab again.
    await tester.tap(find.byKey(const Key('cam-along')));
    await frames(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);
  });

  testWidgets('the play-along sidebar\'s edge drags it wider and narrower, '
      'kept for the next screen; a double tap puts it back', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    await tester.runAsync(() async {
      await library.addMedia(library.byId(id)!, [
        Media(
          XFile.fromData(Uint8List.fromList([1]), name: 'riff.m4a'),
          PageKind.audio,
          'm4a',
        ),
      ]);
    });
    Widget cam() => app(
      PlayAlongScreen(
        library: library,
        eventId: id,
        cameras: () async => [_front],
        headTracking: (_, _) => null,
        takeRecorder: () => null,
      ),
    );
    await tester.pumpWidget(cam());
    await frames(tester);
    final sidebar = find.byKey(const Key('cam-along-sidebar'));
    final split = find.byKey(const Key('cam-along-split'));
    double width() => tester.getSize(sidebar).width;
    // Half the 800 px screen, at most 360.
    expect(width(), 360);
    await tester.drag(split, const Offset(-120, 0));
    await frames(tester);
    final wider = width();
    expect(wider, inInclusiveRange(450, 480));
    expect(SidebarWidths.instance.of(SidebarWidths.playAlong), wider);
    // Another screen's sidebar is as wide.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(cam());
    await frames(tester);
    expect(width(), wider);
    // Not narrower than the least.
    await tester.drag(split, const Offset(600, 0));
    await frames(tester);
    expect(width(), SidebarWidths.min);
    await tester.tap(split);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(split);
    await frames(tester);
    expect(width(), 360);
  });

  testWidgets('the dictionary opens beside Cam; typing in it doesn\'t turn '
      'the tab, and closed, the keys turn it again', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dictionary')));
    await frames(tester);
    expect(find.byKey(const Key('dictionary-sidebar')), findsOneWidget);
    expect(find.byKey(const Key('preview')), findsOneWidget);
    await tester.showKeyboard(find.byKey(const Key('dictionary-query')));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.enterText(find.byKey(const Key('dictionary-query')), 'Am');
    await frames(tester);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.byKey(const Key('dictionary-chord')), findsOneWidget);
    await tester.tap(find.byKey(const Key('dictionary-close')));
    await frames(tester);
    expect(find.byKey(const Key('dictionary-sidebar')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('with nothing to play along, no Play along', (tester) async {
    final (library, id) = await capture(tester);
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    expect(find.byKey(const Key('cam-along')), findsNothing);
    expect(find.byKey(const Key('cam-along-sidebar')), findsNothing);
    expect(find.byKey(const Key('cam-along-frame')), findsNothing);
  });

  testWidgets('Play along opens when a file to play along with arrives '
      'after Cam opens, and stays hidden once hidden', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    expect(find.byKey(const Key('cam-along-sidebar')), findsNothing);

    // A recording arrives (a sync, say): the sidebar opens, with it
    // loaded, paused.
    await tester.runAsync(
      () => library.addMedia(library.byId(id)!, [
        Media(
          XFile.fromData(Uint8List.fromList([1]), name: 'riff.m4a'),
          PageKind.audio,
          'm4a',
        ),
      ]),
    );
    await frames(tester);
    expect(find.byKey(const Key('cam-along-sidebar')), findsOneWidget);
    expect(find.byKey(const Key('cam-along-frame')), findsOneWidget);
    expect(video.playing, isEmpty);

    // Hidden by the user, another arriving doesn't open it again.
    await tester.tap(find.byKey(const Key('cam-along')));
    await frames(tester);
    await tester.runAsync(
      () => library.addMedia(library.byId(id)!, [
        Media(
          XFile.fromData(Uint8List.fromList([2]), name: 'riff2.m4a'),
          PageKind.audio,
          'm4a',
        ),
      ]),
    );
    await frames(tester);
    expect(find.byKey(const Key('cam-along-sidebar')), findsNothing);
  });

  testWidgets('a PDF is listed in the sidebar to follow; tapped, it shows '
      'in a pane on the left of the camera, and hides tapped again or '
      'closed; hiding the sidebar keeps it', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    late String pdf;
    await tester.runAsync(() async {
      final event = await library.addMedia(library.byId(id)!, [
        Media(
          XFile.fromData(Uint8List.fromList([1]), name: 'sheet.pdf'),
          PageKind.pdf,
          'pdf',
        ),
      ]);
      pdf = event.pages.last.id;
      await library.renamePage(id, pdf, 'Sheet');
    });
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
          pdfView: (_, _, page) =>
              SizedBox(key: ValueKey('fake-pdf-${page.id}')),
        ),
      ),
    );
    await frames(tester);
    // The sidebar opens for the PDF alone: nothing to play, so no frame.
    final sidebar = find.byKey(const Key('cam-along-sidebar'));
    expect(sidebar, findsOneWidget);
    expect(find.byKey(const Key('cam-along-frame')), findsNothing);
    expect(find.text('Follow a PDF'), findsOneWidget);
    expect(find.text('Play along'), findsNothing);
    final tile = find.byKey(ValueKey('cam-along-$pdf'));
    expect(
      find.descendant(of: tile, matching: find.text('Sheet')),
      findsOneWidget,
    );
    final pane = find.byKey(const Key('cam-pdf-pane'));
    expect(pane, findsNothing);

    // Tapped: the PDF in a pane on the left, the tile marked.
    await tester.tap(tile);
    await tester.pump();
    expect(pane, findsOneWidget);
    expect(find.byKey(ValueKey('fake-pdf-$pdf')), findsOneWidget);
    expect(tester.widget<ListTile>(tile).selected, isTrue);
    expect(
      tester.getTopLeft(pane).dx,
      lessThan(tester.getTopLeft(find.byKey(const Key('neckline'))).dx),
    );
    expect(tester.getTopLeft(pane).dx, lessThan(tester.getTopLeft(sidebar).dx));

    // Its separator dragged: narrower to the left, wider to the right
    // (a smaller camera); kept for the next time it shows; a double tap:
    // back to its width.
    final width = tester.getSize(pane).width;
    final split = find.byKey(const Key('cam-pdf-split'));
    await tester.drag(split, const Offset(-100, 0));
    await tester.pump();
    expect(tester.getSize(pane).width, closeTo(width - 100, 1));
    await tester.drag(split, const Offset(50, 0));
    await tester.pump();
    expect(tester.getSize(pane).width, closeTo(width - 50, 1));
    // Not past the camera's narrowest.
    await tester.drag(split, const Offset(5000, 0));
    await tester.pump();
    expect(
      tester.getTopLeft(sidebar).dx - tester.getTopRight(pane).dx,
      greaterThanOrEqualTo(PlayAlongBeside.minChild),
    );
    await tester.drag(split, const Offset(-5000, 0));
    await tester.pump();
    expect(tester.getSize(pane).width, PlayAlongBeside.minPdf);
    await tester.drag(split, const Offset(150, 0));
    await tester.pump();
    final dragged = tester.getSize(pane).width;
    await tester.tap(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();
    expect(tester.getSize(pane).width, dragged);
    await tester.tap(split);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(split);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(pane).width, width);

    // Tapped again: hidden.
    await tester.tap(tile);
    await tester.pump();
    expect(pane, findsNothing);
    expect(tester.widget<ListTile>(tile).selected, isFalse);

    // Closed from the pane.
    await tester.tap(tile);
    await tester.pump();
    expect(pane, findsOneWidget);
    await tester.tap(find.byKey(const Key('cam-pdf-close')));
    await tester.pump();
    expect(pane, findsNothing);

    // The sidebar hidden keeps the PDF showing; the keys still turn the tab.
    await tester.tap(tile);
    await tester.pump();
    await tester.tap(find.byKey(const Key('cam-along')));
    await tester.pump();
    expect(sidebar, findsNothing);
    expect(pane, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);

    // The PDF deleted: the pane closes.
    await tester.runAsync(() {
      final event = library.byId(id)!;
      return library.deletePage(
        event,
        event.pages.singleWhere((p) => p.id == pdf),
      );
    });
    await frames(tester);
    expect(pane, findsNothing);
  });

  testWidgets('Rec starts the song in the sidebar\'s player; one playing '
      'already plays on; with the sidebar hidden, nothing starts', (
    tester,
  ) async {
    final (library, id) = await capture(tester, tab: _tab);
    await tester.runAsync(() async {
      await library.addMedia(library.byId(id)!, [
        Media(
          XFile.fromData(Uint8List.fromList([1]), name: 'riff.m4a'),
          PageKind.audio,
          'm4a',
        ),
      ]);
    });
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    video.position = Duration.zero;
    // Loaded in the frame, not playing: Rec plays it.
    expect(video.playing, isEmpty);
    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    expect(video.playing, hasLength(1));
    // The take's Stop leaves it playing; Rec again doesn't pause it.
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));
    expect(video.playing, hasLength(1));
    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    expect(video.playing, hasLength(1));
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));

    // The sidebar hidden (which pauses it): Rec starts nothing.
    await tester.tap(find.byKey(const Key('cam-along')));
    await frames(tester);
    expect(video.playing, isEmpty);
    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    expect(video.playing, isEmpty);
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));

    // With it showing again, 1 starts a take and the song, as Rec does.
    await tester.tap(find.byKey(const Key('cam-along')));
    await frames(tester);
    expect(video.playing, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await frames(tester);
    expect(camera.recording, isTrue);
    expect(video.playing, hasLength(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await until(tester, () => recReady(tester));
    expect(camera.recording, isFalse);
  });

  testWidgets('. with a song in the sidebar: it stops at once, back at its '
      'start, and plays from there with the new take', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    await tester.runAsync(() async {
      await library.addMedia(library.byId(id)!, [
        Media(
          XFile.fromData(Uint8List.fromList([1]), name: 'riff.m4a'),
          PageKind.audio,
          'm4a',
        ),
      ]);
    });
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    // . starts a take and the song, as Rec, from where it is.
    expect(video.playing, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await frames(tester);
    expect(camera.recording, isTrue);
    expect(video.playing, hasLength(1));
    expect(video.seeks, isEmpty);

    // Again: the song stops at once, back at its start, while the take
    // is saved…
    video.position = const Duration(seconds: 40);
    final hold = camera.stopHold = Completer<void>();
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await frames(tester);
    expect(video.playing, isEmpty);
    expect(video.seeks, [Duration.zero]);
    expect(camera.recording, isFalse);

    // …then it plays from there with the new take.
    video.position = Duration.zero;
    hold.complete();
    await until(
      tester,
      () => library.byId(id)!.pages.length == 3 && camera.recording,
    );
    await frames(tester);
    expect(library.byId(id)!.pages.last.title, 'Take 1');
    expect(video.playing, hasLength(1));
    expect(video.seeks, [Duration.zero]);

    camera.stopHold = null;
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));
    expect(library.byId(id)!.pages.last.title, 'Take 2');
  });

  testWidgets('Phrase passes: recording along with a song notes each turn '
      'at its position, marked in its player; another time through, '
      'auto-pass turns the tab there (a pass by hand right after it is the '
      'same pass); off, it does not; forgotten, they are gone', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    late String song;
    await tester.runAsync(() async {
      final event = await library.addMedia(library.byId(id)!, [
        Media(
          XFile.fromData(Uint8List.fromList([1]), name: 'song.m4a'),
          PageKind.audio,
          'm4a',
        ),
      ]);
      song = event.pages.last.id;
    });
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    Future<void> at(num seconds) async {
      video.position = Duration(milliseconds: (seconds * 1000).round());
      await frames(tester);
    }

    Future<void> pass() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await frames(tester);
    }

    // The song plays from its start, and Cam records along with it.
    video.position = Duration.zero;
    await tester.tap(find.byKey(const Key('cam-along-toggle')));
    await frames(tester);
    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    await at(10);
    await pass();
    expect(find.text('2 / 3'), findsOneWidget);
    // Marked on the song's progress bar at once, while still recording.
    expect(find.byKey(const Key('cam-along-phrase-marks')), findsOneWidget);
    await at(20);
    await pass();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));

    var event = library.byId(id)!;
    expect(event.phrases[song]!.passes, [
      const PhrasePass(Duration(seconds: 10), PassDirection.next, 1),
      const PhrasePass(Duration(seconds: 20), PassDirection.next, 2),
    ]);
    // The take keeps its own, and no file holds them: the photo, the song
    // and the take are all the capture has.
    final take = event.pages.last;
    expect(take.title, 'Take 1');
    // (The take's clock is the wall's: its two turns, a moment apart here,
    // are one pass, to where they went.)
    expect(event.phrases[take.id]!.passes.last.line, 2);
    expect(event.pages, hasLength(3));
    // Marked on the song's progress bar, with no count; the button that
    // clears them at the bar's right, on its line.
    final marks = find.byKey(const Key('cam-along-phrase-marks'));
    expect(marks, findsOneWidget);
    expect(find.textContaining('phrase pass'), findsNothing);
    final clear = find.byKey(const Key('cam-along-phrases-clear'));
    expect(
      find.byTooltip('Clear the phrase passes marked on the bar'),
      findsOneWidget,
    );
    expect(tester.getCenter(clear).dy, closeTo(tester.getCenter(marks).dy, 1));
    expect(
      tester.getTopLeft(clear).dx,
      greaterThanOrEqualTo(tester.getTopRight(marks).dx),
    );

    // Back at the start (the song repeating): the first line again; each
    // pass turns the tab as the song passes it.
    await at(1);
    expect(find.text('1 / 3'), findsOneWidget);
    for (final t in [2.5, 4, 5.5, 7, 8.5, 9.9]) {
      await at(t);
    }
    expect(find.text('1 / 3'), findsOneWidget);
    await at(10.5);
    expect(find.text('2 / 3'), findsOneWidget);
    // Passed by hand too, right after: the same pass, not one more; once.
    await at(11);
    await pass();
    expect(find.text('2 / 3'), findsOneWidget);
    await pass();
    expect(find.text('3 / 3'), findsOneWidget);

    // Off (kept on the device): the tab stays where the user leaves it.
    expect(find.text('Auto-pass'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cam-auto-pass')));
    await frames(tester);
    expect(
      find.byTooltip(
        'Auto-pass off: the tab turns only when you turn it, and no phrase '
        'passes are recorded',
      ),
      findsOneWidget,
    );
    await at(1);
    expect(find.text('3 / 3'), findsOneWidget);
    String? settings;
    await tester.runAsync(() async => settings = await library.readMeta('cam'));
    expect(jsonDecode(settings!), {'autoPass': false});

    // Forgotten: no marks, nothing kept.
    await tester.tap(find.byKey(const Key('cam-along-phrases-clear')));
    await frames(tester);
    event = library.byId(id)!;
    expect(event.phrases.containsKey(song), isFalse);
    expect(find.byKey(const Key('cam-along-phrases-clear')), findsNothing);
    expect(find.byKey(const Key('cam-along-phrase-marks')), findsNothing);
  });

  testWidgets('with Auto-pass off, recording along with a song notes no '
      'phrase passes, for the song or the take, and leaves the song\'s as '
      'they are; switched on while recording, the turns from then on are '
      'noted', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    late String song;
    const before = PhrasePass(Duration(seconds: 8), PassDirection.next, 1);
    await tester.runAsync(() async {
      final event = await library.addMedia(library.byId(id)!, [
        Media(
          XFile.fromData(Uint8List.fromList([1]), name: 'riff.m4a'),
          PageKind.audio,
          'm4a',
        ),
      ]);
      song = event.pages.last.id;
      // The song has a pass from an earlier take; auto-pass is off.
      await library.setPhrases(
        id,
        song,
        PhraseTimes.none.add(before.at, before.direction, before.line),
      );
      await library.writeMeta('cam', '{"autoPass":false}');
    });
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    const off =
        'Auto-pass off: the tab turns only when you turn it, and no phrase '
        'passes are recorded';
    expect(find.byTooltip(off), findsOneWidget);
    Future<void> at(num seconds) async {
      video.position = Duration(milliseconds: (seconds * 1000).round());
      await frames(tester);
    }

    Future<void> pass() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await frames(tester);
    }

    // The song plays, and Cam records along with it: the tab turns by
    // hand only (not at the song's pass), and no turn is noted.
    video.position = Duration.zero;
    await tester.tap(find.byKey(const Key('cam-along-toggle')));
    await frames(tester);
    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    await at(9);
    expect(find.text('1 / 3'), findsOneWidget);
    await at(10);
    await pass();
    expect(find.text('2 / 3'), findsOneWidget);
    await at(20);
    await pass();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));

    var event = library.byId(id)!;
    expect(event.phrases[song]!.passes, [before]);
    var take = event.pages.last;
    expect(take.title, 'Take 1');
    expect(event.phrases.containsKey(take.id), isFalse);
    expect(event.phrases.keys, [song]);
    // ("Saved Take 1" shows meanwhile, at the top.)
    Messenger.maybeOf(tester.element(find.byKey(const Key('cam-auto-pass'))))!
        .hide();
    await frames(tester);

    // Another take: two turns back with it off, then it's switched on
    // (the tab goes where the song's pass shows) and a turn then is noted.
    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    await at(30);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await frames(tester);
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cam-auto-pass')));
    await frames(tester);
    await at(31);
    expect(find.text('2 / 3'), findsOneWidget);
    await at(40);
    await pass();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));

    event = library.byId(id)!;
    expect(event.phrases[song]!.passes, [
      before,
      const PhrasePass(Duration(seconds: 40), PassDirection.next, 2),
    ]);
    take = event.pages.last;
    expect(take.title, 'Take 2');
    // The take's own: the two turns back made with it off are no passes;
    // the one auto-pass made once on and the one by hand are (within two
    // seconds on the take's clock, here: merged into one).
    expect(
      [
        for (final p in event.phrases[take.id]!.passes)
          (p.direction, p.line, p.count),
      ],
      [(PassDirection.next, 2, 2)],
    );
  });

  testWidgets('Phrase passes cleared while recording: the marks go at once, '
      'the take records on, and passes made after are noted and marked '
      'again', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    late String song;
    await tester.runAsync(() async {
      final event = await library.addMedia(library.byId(id)!, [
        Media(
          XFile.fromData(Uint8List.fromList([1]), name: 'riff.m4a'),
          PageKind.audio,
          'm4a',
        ),
      ]);
      song = event.pages.last.id;
    });
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    Future<void> at(num seconds) async {
      video.position = Duration(milliseconds: (seconds * 1000).round());
      await frames(tester);
    }

    Future<void> pass() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await frames(tester);
    }

    final marks = find.byKey(const Key('cam-along-phrase-marks'));
    final clear = find.byKey(const Key('cam-along-phrases-clear'));
    video.position = Duration.zero;
    // Rec starts the song too.
    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    expect(marks, findsNothing);
    await at(10);
    await pass();
    // Marked as soon as it's passed.
    expect(marks, findsOneWidget);

    await tester.tap(clear);
    await frames(tester);
    expect(marks, findsNothing);
    expect(clear, findsNothing);
    // Still recording, the song still playing.
    expect(_camStop, findsOneWidget);
    expect(video.playing, hasLength(1));

    await at(20);
    await pass();
    expect(marks, findsOneWidget);
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));
    // Only the pass made after clearing is kept.
    expect(library.byId(id)!.phrases[song]!.passes, [
      const PhrasePass(Duration(seconds: 20), PassDirection.next, 2),
    ]);
  });

  testWidgets('Phrase passes are per file: two songs played along in one '
      'take each keep their own, at their own times, and auto-pass follows '
      'the one that plays', (tester) async {
    // Tall enough for the sidebar to list both songs under the frame.
    tester.view
      ..physicalSize = const Size(1200, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (library, id) = await capture(tester, tab: _tab);
    late String first, second;
    await tester.runAsync(() async {
      final event = await library.addMedia(library.byId(id)!, [
        Media(
          XFile.fromData(Uint8List.fromList([1]), name: 'riff-a.m4a'),
          PageKind.audio,
          'm4a',
        ),
        Media(
          XFile.fromData(Uint8List.fromList([2]), name: 'riff-b.mp3'),
          PageKind.audio,
          'mp3',
        ),
      ]);
      (first, second) = (event.pages[1].id, event.pages[2].id);
    });
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    Future<void> at(num seconds) async {
      video.position = Duration(milliseconds: (seconds * 1000).round());
      await frames(tester);
    }

    Future<void> pass() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await frames(tester);
    }

    // The first song plays, recording: a pass at 10 s; then the second, in
    // its place: a pass at 5 s.
    video.position = Duration.zero;
    await tester.tap(find.byKey(const Key('cam-along-toggle')));
    await frames(tester);
    await tester.tap(find.byTooltip('Rec (1)'));
    await frames(tester);
    await at(10);
    await pass();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('cam-along-$second')));
    await frames(tester);
    await at(5);
    await pass();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));

    final event = library.byId(id)!;
    expect(event.phrases[first]!.passes, [
      const PhrasePass(Duration(seconds: 10), PassDirection.next, 1),
    ]);
    expect(event.phrases[second]!.passes, [
      const PhrasePass(Duration(seconds: 5), PassDirection.next, 2),
    ]);
    expect(find.byKey(const Key('cam-along-phrase-marks')), findsOneWidget);

    // The second plays on: its pass turns the tab, the first's doesn't.
    await at(1);
    expect(find.text('2 / 3'), findsOneWidget);
    for (final t in [2.5, 4, 5.5]) {
      await at(t);
    }
    expect(find.text('3 / 3'), findsOneWidget);
    for (final t in [7, 8.5, 10, 11.5]) {
      await at(t);
    }
    expect(find.text('3 / 3'), findsOneWidget);

    // The first again: its own pass, not the second's.
    await tester.tap(find.byKey(ValueKey('cam-along-$first')));
    await frames(tester);
    await at(1);
    expect(find.text('1 / 3'), findsOneWidget);
    for (final t in [2.5, 4, 5.5, 7, 8.5, 9.9]) {
      await at(t);
    }
    expect(find.text('1 / 3'), findsOneWidget);
    await at(10.5);
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('the text tab is listed first in the sidebar to follow; '
      'tapped, it shows in the pane on the left of the camera, and hides '
      'tapped again or closed; a PDF chosen takes its place', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    late String pdf;
    await tester.runAsync(() async {
      final event = await library.addMedia(library.byId(id)!, [
        Media(
          XFile.fromData(Uint8List.fromList([1]), name: 'sheet.pdf'),
          PageKind.pdf,
          'pdf',
        ),
      ]);
      pdf = event.pages.last.id;
    });
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
          pdfView: (_, _, page) =>
              SizedBox(key: ValueKey('fake-pdf-${page.id}')),
        ),
      ),
    );
    await frames(tester);
    final text = find.byKey(const Key('cam-along-text'));
    final pdfTile = find.byKey(ValueKey('cam-along-$pdf'));
    expect(text, findsOneWidget);
    expect(find.text('Text tab'), findsOneWidget);
    // First, above the PDFs.
    expect(tester.getTopLeft(text).dy, lessThan(tester.getTopLeft(pdfTile).dy));
    final pane = find.byKey(const Key('cam-pdf-pane'));
    final view = find.byKey(const Key('cam-text-view'));
    expect(pane, findsNothing);

    // Tapped: the text in the pane on the left, the row marked.
    await tester.tap(text);
    await tester.pump();
    expect(pane, findsOneWidget);
    expect(view, findsOneWidget);
    expect(
      find.descendant(
        of: view,
        matching: find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == _tab,
        ),
      ),
      findsOneWidget,
    );
    expect(tester.widget<ListTile>(text).selected, isTrue);
    expect(
      tester.getTopLeft(pane).dx,
      lessThan(tester.getTopLeft(find.byKey(const Key('neckline'))).dx),
    );

    // It follows the capture's edits.
    await tester.runAsync(
      () => library.update(library.byId(id)!.copyWith(tabText: 'e|--3--|')),
    );
    await frames(tester);
    expect(
      find.byWidgetPredicate(
        (w) => w is SelectableText && w.data == 'e|--3--|',
      ),
      findsOneWidget,
    );

    // A PDF chosen takes the pane; the text chosen again takes it back.
    await tester.tap(pdfTile);
    await tester.pump();
    expect(view, findsNothing);
    expect(find.byKey(ValueKey('fake-pdf-$pdf')), findsOneWidget);
    expect(tester.widget<ListTile>(text).selected, isFalse);
    await tester.tap(text);
    await tester.pump();
    expect(view, findsOneWidget);
    expect(find.byKey(ValueKey('fake-pdf-$pdf')), findsNothing);
    expect(tester.widget<ListTile>(pdfTile).selected, isFalse);

    // Tapped again: hidden; closed from the pane.
    await tester.tap(text);
    await tester.pump();
    expect(pane, findsNothing);
    await tester.tap(text);
    await tester.pump();
    await tester.tap(find.byKey(const Key('cam-pdf-close')));
    await tester.pump();
    expect(pane, findsNothing);

    // The text cleared: the row goes, the pane closes.
    await tester.tap(text);
    await tester.pump();
    await tester.runAsync(
      () => library.update(library.byId(id)!.copyWith(tabText: '')),
    );
    await frames(tester);
    expect(pane, findsNothing);
    expect(text, findsNothing);
  });

  testWidgets('with the text tab alone, Play along shows but the sidebar '
      'doesn\'t open by itself; opened, it lists the text', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    expect(find.byKey(const Key('cam-along')), findsOneWidget);
    expect(find.byKey(const Key('cam-along-sidebar')), findsNothing);
    await tester.tap(find.byKey(const Key('cam-along')));
    await frames(tester);
    expect(find.byKey(const Key('cam-along-sidebar')), findsOneWidget);
    expect(find.byKey(const Key('cam-along-frame')), findsNothing);
    await tester.tap(find.byKey(const Key('cam-along-text')));
    await tester.pump();
    expect(find.byKey(const Key('cam-text-view')), findsOneWidget);
  });

  testWidgets('Cam\'s takes are the last thing in the sidebar, under '
      'Takes, the most recent first: an old take (named "Take 3", '
      'not marked) and a marked take renamed too; the file loaded first '
      'is a song, not a take', (tester) async {
    // Tall enough for the sidebar to list everything under the frame.
    tester.view
      ..physicalSize = const Size(1200, 2000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (library, id) = await capture(tester, tab: _tab);
    final ids = <String, String>{};
    await tester.runAsync(() async {
      Media video(String name) => Media(
        XFile.fromData(Uint8List.fromList([1]), name: name),
        PageKind.video,
        'mp4',
      );
      Future<void> add(
        String key,
        Media media, {
        bool take = false,
        String? title,
      }) async {
        final event = await library.addMedia(library.byId(id)!, [
          media,
        ], take: take);
        ids[key] = event.pages.last.id;
        if (title != null) await library.renamePage(id, ids[key]!, title);
      }

      // A take first, then a song, a take, the PDF, an old take, a link
      // and a take renamed.
      await add('take1', video('take.mp4'), take: true, title: 'Take 1');
      await add(
        'song',
        Media(
          XFile.fromData(Uint8List.fromList([1]), name: 'riff.m4a'),
          PageKind.audio,
          'm4a',
        ),
        title: 'Riff',
      );
      await add('take2', video('take.mp4'), take: true, title: 'Take 2');
      await add(
        'pdf',
        Media(
          XFile.fromData(Uint8List.fromList([1]), name: 'sheet.pdf'),
          PageKind.pdf,
          'pdf',
        ),
        title: 'Sheet',
      );
      // Saved before takes were marked: named as Cam names them.
      await add('take3', video('take.mp4'), title: 'Take 3');
      final event = await library.addLink(
        library.byId(id)!,
        Uri.parse('https://example.com/backing'),
        title: 'Backing track',
      );
      ids['link'] = event.pages.last.id;
      await add('renamed', video('take.mp4'), take: true, title: 'Best one');
      // A video of the user's own, not a take.
      await add('lesson', video('lesson.mp4'), title: 'Lesson');
    });
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
          linkFrame: (_) => const SizedBox(key: Key('fake-link-frame')),
          pdfView: (_, _, page) =>
              SizedBox(key: ValueKey('fake-pdf-${page.id}')),
        ),
      ),
    );
    await frames(tester);
    expect(find.byKey(const Key('cam-along-sidebar')), findsOneWidget);
    Finder row(String key) => find.byKey(ValueKey('cam-along-${ids[key]}'));
    double top(Finder f) => tester.getTopLeft(f).dy;
    final order = [
      find.byKey(const Key('cam-along-text')),
      row('song'),
      row('link'),
      row('lesson'),
      row('pdf'),
      // The most recent take first.
      find.text('Takes'),
      row('renamed'),
      row('take3'),
      row('take2'),
      row('take1'),
    ];
    for (final f in order) {
      expect(f, findsOneWidget);
    }
    for (var i = 1; i < order.length; i++) {
      expect(top(order[i - 1]), lessThan(top(order[i])), reason: '$i');
    }
    // The songs' heading over the songs, the PDF's under them.
    expect(top(find.text('Play along')), lessThan(top(row('song'))));
    expect(top(find.text('Follow a PDF')), greaterThan(top(row('lesson'))));
    // The song loaded first, not Take 1 (the capture's first file).
    expect(tester.widget<ListTile>(row('song')).selected, isTrue);
    expect(tester.widget<ListTile>(row('take1')).selected, isFalse);

    // A take plays along as the songs do.
    await tester.tap(row('take2'));
    await frames(tester);
    expect(tester.widget<ListTile>(row('take2')).selected, isTrue);
  });

  testWidgets('with only takes to play along, the most recent loads, '
      'listed first', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    late String take1, take2;
    await tester.runAsync(() async {
      for (final n in [1, 2]) {
        final event = await library.addMedia(library.byId(id)!, [
          Media(
            XFile.fromData(Uint8List.fromList([n]), name: 'take.mp4'),
            PageKind.video,
            'mp4',
          ),
        ], take: true);
        await library.renamePage(id, event.pages.last.id, 'Take $n');
        if (n == 1) {
          take1 = event.pages.last.id;
        } else {
          take2 = event.pages.last.id;
        }
      }
    });
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    expect(find.text('Takes'), findsOneWidget);
    expect(find.text('Play along'), findsNothing);
    final first = find.byKey(ValueKey('cam-along-$take1'));
    final second = find.byKey(ValueKey('cam-along-$take2'));
    expect(tester.widget<ListTile>(second).selected, isTrue);
    expect(tester.widget<ListTile>(first).selected, isFalse);
    expect(tester.getTopLeft(second).dy, lessThan(tester.getTopLeft(first).dy));
  });

  group('isTake', () {
    EventPage video(String? title, {bool take = false}) => EventPage(
      id: 'p1',
      kind: PageKind.video,
      extension: 'mp4',
      title: title,
      take: take,
    );

    test('a marked take is one, whatever its name', () {
      expect(isTake(video('Best one', take: true)), isTrue);
      expect(isTake(video(null, take: true)), isTrue);
    });

    test('an old take: a video named as Cam names them, in any language', () {
      expect(isTake(video('Take 3')), isTrue);
      expect(isTake(video('Toma 12')), isTrue);
      expect(isTake(video('Take')), isFalse);
      expect(isTake(video('Retake 3')), isFalse);
      expect(isTake(video('Take 3 again')), isFalse);
      expect(isTake(video('Lesson')), isFalse);
      expect(isTake(video(null)), isFalse);
      // Not a video: not a take.
      expect(
        isTake(
          const EventPage(
            id: 'p2',
            kind: PageKind.audio,
            extension: 'm4a',
            title: 'Take 3',
          ),
        ),
        isFalse,
      );
    });

    test('the mark is kept: renamed, edited, and through JSON (sync)', () {
      final take = video('Take 1', take: true);
      final renamed = take.copyWith(title: () => 'Best one');
      expect(renamed.take, isTrue);
      expect(take.copyWith(edit: () => null).take, isTrue);
      final json = jsonDecode(jsonEncode(renamed.toJson()));
      expect(json['take'], isTrue);
      expect(EventPage.fromJson(json).take, isTrue);
      // Not a take: no mark in its JSON.
      expect(video('Lesson').toJson().containsKey('take'), isFalse);
      expect(EventPage.fromJson(video('Lesson').toJson()).take, isFalse);
    });
  });

  /// Rec (or Stop), whatever its tooltip says.
  final rec = find.descendant(
    of: find.byKey(const Key('cam-rec')),
    matching: find.byType(IconButton),
  );

  testWidgets('each file in the sidebar has Delete at the right of its row, '
      'the text tab none; it asks first, as the list does: cancelled, the '
      'take stays; confirmed, it goes with its file, the player lets go of '
      'it and Play has no take', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    await tester.tap(rec);
    await frames(tester);
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));
    final take = library.byId(id)!.pages.last;
    expect(take.title, 'Take 1');

    // The take opens the sidebar, loaded in its frame; its row ends in
    // Delete.
    expect(find.byKey(const Key('cam-along-frame')), findsOneWidget);
    final row = find.byKey(ValueKey('cam-along-${take.id}'));
    final delete = find.byKey(ValueKey('cam-along-delete-${take.id}'));
    expect(find.descendant(of: row, matching: delete), findsOneWidget);
    expect(tester.widget<IconButton>(delete).tooltip, 'Delete Take 1');
    final title = find.descendant(of: row, matching: find.text('Take 1'));
    expect(
      tester.getTopLeft(delete).dx,
      greaterThan(tester.getTopRight(title).dx),
    );
    expect(
      tester.getTopRight(row).dx - tester.getTopRight(delete).dx,
      lessThanOrEqualTo(24),
    );
    // The text tab's row has none.
    expect(
      find.descendant(
        of: find.byKey(const Key('cam-along-text')),
        matching: find.byIcon(Icons.delete_outline),
      ),
      findsNothing,
    );

    // Cancelled: the take stays.
    await tester.tap(delete);
    await frames(tester);
    expect(find.text('Delete "Take 1"?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await frames(tester);
    expect(library.byId(id)!.pages.map((p) => p.id), contains(take.id));
    expect(find.byKey(const Key('cam-along-frame')), findsOneWidget);

    // Confirmed: it goes, with its file; the frame lets go of it, and
    // Play has nothing to play back.
    await tester.tap(delete);
    await frames(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await frames(tester);
    expect(library.byId(id)!.pages.map((p) => p.id), isNot(contains(take.id)));
    late bool kept;
    await tester.runAsync(() async => kept = await library.hasPage(id, take));
    expect(kept, isFalse);
    expect(row, findsNothing);
    expect(find.byKey(const Key('cam-along-frame')), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const Key('cam-play')),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('deleting the song playing in the sidebar stops it and closes '
      'its frame; while a take records, Delete is greyed', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    late EventPage song;
    await tester.runAsync(() async {
      final event = await library.addMedia(library.byId(id)!, [
        Media(
          XFile.fromData(Uint8List.fromList([1]), name: 'riff.m4a'),
          PageKind.audio,
          'm4a',
        ),
      ]);
      song = event.pages.last;
    });
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    final delete = find.byKey(ValueKey('cam-along-delete-${song.id}'));
    expect(tester.widget<IconButton>(delete).onPressed, isNotNull);

    // Recording: greyed.
    await tester.tap(rec);
    await frames(tester);
    expect(tester.widget<IconButton>(delete).onPressed, isNull);
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));
    expect(tester.widget<IconButton>(delete).onPressed, isNotNull);

    // A new take (.): still greyed after the old one is saved, while the
    // next starts.
    await tester.tap(rec);
    await frames(tester);
    final started = camera.starts;
    final hold = camera.startHold = Completer<void>();
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await until(tester, () => camera.starts > started && !camera.recording);
    await frames(tester);
    expect(tester.widget<IconButton>(delete).onPressed, isNull);
    camera.startHold = null;
    hold.complete();
    await until(tester, () => camera.recording);
    await frames(tester);
    expect(tester.widget<IconButton>(delete).onPressed, isNull);
    await tester.tap(_camStop);
    await until(tester, () => recReady(tester));
    expect(tester.widget<IconButton>(delete).onPressed, isNotNull);

    // Playing (Rec played it), with its mark left of Delete.
    expect(video.playing, hasLength(1));
    final row = find.byKey(ValueKey('cam-along-${song.id}'));
    final mark = find.descendant(
      of: row,
      matching: find.byIcon(Icons.graphic_eq),
    );
    expect(mark, findsOneWidget);
    expect(
      tester.getTopRight(mark).dx,
      lessThanOrEqualTo(tester.getTopLeft(delete).dx),
    );

    await tester.tap(delete);
    await frames(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await frames(tester);
    expect(library.byId(id)!.pages.map((p) => p.id), isNot(contains(song.id)));
    expect(video.playing, isEmpty);
    expect(row, findsNothing);
    // The take is what's left to play: nothing loads by itself.
    expect(find.byKey(const Key('cam-along-frame')), findsNothing);
  });

  testWidgets('a followed PDF deleted from the sidebar stops being followed', (
    tester,
  ) async {
    final (library, id) = await capture(tester, tab: _tab);
    late String pdf;
    await tester.runAsync(() async {
      final event = await library.addMedia(library.byId(id)!, [
        Media(
          XFile.fromData(Uint8List.fromList([1]), name: 'sheet.pdf'),
          PageKind.pdf,
          'pdf',
        ),
      ]);
      pdf = event.pages.last.id;
    });
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
          pdfView: (_, _, page) =>
              SizedBox(key: ValueKey('fake-pdf-${page.id}')),
        ),
      ),
    );
    await frames(tester);
    await tester.tap(find.byKey(ValueKey('cam-along-$pdf')));
    await tester.pump();
    expect(find.byKey(const Key('cam-pdf-pane')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('cam-along-delete-$pdf')));
    await frames(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await frames(tester);
    expect(library.byId(id)!.pages.map((p) => p.id), isNot(contains(pdf)));
    expect(find.byKey(const Key('cam-pdf-pane')), findsNothing);
    expect(find.byKey(ValueKey('cam-along-$pdf')), findsNothing);
  });

  testWidgets('on a capture shared to read, the sidebar lists the reader\'s '
      'own take after the owner\'s files; only theirs has Delete, and it '
      'deletes it from their contribution', (tester) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late String id;
    late EventPage song, mine;
    await tester.runAsync(() async {
      await library.load();
      await library.writeMeta(BackingTrack.metaName, '{"countIn":false}');
      var event = await library.create([
        img.encodeJpg(img.Image(width: 8, height: 8)),
      ]);
      id = event.id;
      event = await library.addMedia(event, [
        Media(
          XFile.fromData(Uint8List.fromList([1]), name: 'riff.m4a'),
          PageKind.audio,
          'm4a',
        ),
      ]);
      song = event.pages.last;
      await library.applyRemote(
        library
            .byId(id)!
            .copyWith(
              tabText: _tab,
              sharedBy: 'owner@example.com',
              readOnly: true,
            ),
      );
      // The reader's own take: their contribution's.
      event = await library.addMedia(library.byId(id)!, [
        Media(
          XFile.fromData(Uint8List.fromList([2]), name: 'take.mp4'),
          PageKind.video,
          'mp4',
        ),
      ]);
      mine = event.myContribution!.pages.single;
    });
    final event = library.byId(id)!;
    expect(mayDeleteFile(event, song), isFalse);
    expect(mayDeleteFile(event, mine), isTrue);

    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    final songRow = find.byKey(ValueKey('cam-along-${song.id}'));
    final mineRow = find.byKey(ValueKey('cam-along-${mine.id}'));
    expect(songRow, findsOneWidget);
    expect(mineRow, findsOneWidget);
    expect(
      tester.getTopLeft(mineRow).dy,
      greaterThan(tester.getTopLeft(songRow).dy),
    );
    expect(find.byKey(ValueKey('cam-along-delete-${song.id}')), findsNothing);
    final delete = find.byKey(ValueKey('cam-along-delete-${mine.id}'));
    expect(find.descendant(of: mineRow, matching: delete), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    // Deleted, from their contribution and with its file; the owner's
    // files stay.
    late bool kept;
    await tester.runAsync(() async => kept = await library.hasPage(id, mine));
    expect(kept, isTrue);
    await tester.tap(delete);
    await frames(tester);
    expect(find.text('Delete "Video 1"?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await frames(tester);
    final now = library.byId(id)!;
    expect(now.myContribution!.pages, isEmpty);
    expect(now.pages.map((p) => p.id), contains(song.id));
    await tester.runAsync(() async => kept = await library.hasPage(id, mine));
    expect(kept, isFalse);
    expect(mineRow, findsNothing);

    // Shared to edit, the owner's files show it.
    await tester.runAsync(
      () => library.applyRemote(library.byId(id)!.copyWith(readOnly: false)),
    );
    await frames(tester);
    expect(find.byKey(ValueKey('cam-along-delete-${song.id}')), findsOneWidget);
  });

  testWidgets('the sidebar\'s Delete asks with "Don\'t ask again", the '
      'list\'s confirm: ticked in the sidebar, neither the sidebar\'s next '
      'delete nor the list\'s asks', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    final songs = <String>[];
    await tester.runAsync(() async {
      for (final riff in ['riff-a', 'riff-b', 'riff-c']) {
        final event = await library.addMedia(library.byId(id)!, [
          Media(
            XFile.fromData(Uint8List.fromList([1]), name: '$riff.m4a'),
            PageKind.audio,
            'm4a',
          ),
        ]);
        songs.add(event.pages.last.id);
      }
    });
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_front],
          headTracking: (_, _) => null,
          takeRecorder: () => null,
        ),
      ),
    );
    await frames(tester);
    List<String> ids() => [for (final p in library.byId(id)!.pages) p.id];
    final dontAsk = find.byKey(const Key('dont-ask-again'));

    // The shared confirm, its box unticked; ticked and confirmed, the
    // song goes and a file's delete no longer asks.
    await tester.tap(find.byKey(ValueKey('cam-along-delete-${songs[0]}')));
    await frames(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(dontAsk).value, isFalse);
    await tester.tap(dontAsk);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await frames(tester);
    expect(ids(), isNot(contains(songs[0])));
    expect(DeleteConfirms.of(library).asks(DeleteKind.file), isFalse);
    // A reader's own file still asks: another kind.
    expect(DeleteConfirms.of(library).asks(DeleteKind.contribution), isTrue);

    // The sidebar's next delete goes at once.
    await tester.tap(find.byKey(ValueKey('cam-along-delete-${songs[1]}')));
    await frames(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(ids(), isNot(contains(songs[1])));

    // And so does the capture's list's.
    await tester.pumpWidget(app(EventScreen(library: library, eventId: id)));
    await frames(tester);
    await tester.tap(find.byKey(ValueKey('delete-${songs[2]}')));
    await frames(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(ids(), isNot(contains(songs[2])));
  });
}
