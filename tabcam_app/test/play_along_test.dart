import 'package:camera_platform_interface/camera_platform_interface.dart';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/capture/head_gestures.dart';
import 'package:tabcam_app/capture/link_frame.dart';
import 'package:tabcam_app/capture/media.dart';
import 'package:tabcam_app/capture/play_along_screen.dart';
import 'package:tabcam_app/capture/take_overlay.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/event_screen.dart';
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

  @override
  void onImage(CameraImage image) => frames++;

  @override
  final ValueNotifier<bool> face = ValueNotifier(true);

  @override
  set camera(CameraController camera) {}

  @override
  void dispose() => disposed = true;
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

void main() {
  late FakeCameraPlatform camera;
  late FakeVideoPlatform video;
  setUp(() {
    CameraPlatform.instance = camera = FakeCameraPlatform();
    VideoPlayerPlatform.instance = video = FakeVideoPlatform();
  });

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
    return button.tooltip == 'Rec' && button.onPressed != null;
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

  testWidgets('Rec records a take, the tab burned in, into the capture; '
      'Play plays it back', (tester) async {
    final (library, id) = await capture(tester, tab: _tab);
    final burned = <List<(TabBand, Uint8List)>>[];
    await tester.pumpWidget(
      app(
        PlayAlongScreen(
          library: library,
          eventId: id,
          cameras: () async => [_back, _front],
          burn: (take, bands) async {
            burned.add(bands);
            return XFile.fromData(
              Uint8List.fromList([7, 7]),
              name: 'burned.mp4',
              mimeType: 'video/mp4',
            );
          },
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

    await tester.tap(find.byTooltip('Rec'));
    await frames(tester);
    expect(camera.recording, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.tap(find.byTooltip('Stop'));
    await until(tester, () => recReady(tester));
    expect(camera.recording, isFalse);
    expect(find.text('Take 1 added to the capture'), findsOneWidget);
    var pages = library.byId(id)!.pages;
    expect(pages, hasLength(2));
    expect(pages.last.kind, PageKind.video);
    expect(pages.last.title, 'Take 1');
    // The tab burned in: the first neckline, then the second.
    final bands = burned.single;
    expect([for (final (b, _) in bands) b.line], [0, 1]);
    expect(bands.first.$1.start, Duration.zero);
    expect(bands.first.$1.end, bands.last.$1.start);
    expect(bands.last.$1.end, isNull);
    expect(bands.first.$2, isNotEmpty);
    // What's saved is the take with the tab.
    late Uint8List saved;
    await tester.runAsync(
      () async => saved = await library.original(library.byId(id)!, pages.last),
    );
    expect(saved, [7, 7]);

    // A second take is Take 2.
    await tester.tap(find.byTooltip('Rec'));
    await frames(tester);
    await tester.tap(find.byTooltip('Stop'));
    await until(tester, () => recReady(tester));
    pages = library.byId(id)!.pages;
    expect(pages.last.title, 'Take 2');

    await tester.tap(find.byTooltip('Play'));
    await frames(tester);
    expect(video.playing, hasLength(1));
    expect(find.byKey(const Key('preview')), findsNothing);
    await tester.tap(find.byTooltip('Stop'));
    await frames(tester);
    expect(video.playing, isEmpty);
    expect(find.byKey(const Key('preview')), findsOneWidget);
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

    heads!.onGesture(HeadGesture.next);
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);
    heads!.onGesture(HeadGesture.next);
    heads!.onGesture(HeadGesture.previous);
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);

    // Recording, the frames still go to it.
    await tester.tap(find.byTooltip('Rec'));
    await frames(tester);
    expect(camera.streaming, isTrue);
    heads!.onGesture(HeadGesture.next);
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Stop'));
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

    await tester.tap(find.byTooltip('Rec'));
    await frames(tester);
    expect(camera.recording, isTrue);
    heads!.onGesture(HeadGesture.next);
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Stop'));
    await until(tester, () => recReady(tester));
    expect(camera.recordings, 1);

    await tester.tap(find.byKey(const Key('cam-heads')));
    await frames(tester);
    expect(heads!.active, isFalse);
    heads!.onGesture(HeadGesture.next);
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);
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
    await tester.tap(find.byTooltip('Rec'));
    await frames(tester);
    await tester.tap(find.byTooltip('Stop'));
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

  testWidgets('Play along: a recording or link from the sidebar plays in a '
      'frame above; space pauses and plays it', (tester) async {
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
    final commands = <bool>[];
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
              link.command = (play) async => commands.add(play);
            }
            return const SizedBox(key: Key('fake-link-frame'));
          },
        ),
      ),
    );
    await frames(tester);
    expect(find.byKey(const Key('cam-along-sidebar')), findsNothing);
    expect(find.byKey(const Key('cam-along-frame')), findsNothing);

    await tester.tap(find.byKey(const Key('cam-along')));
    await frames(tester);
    expect(find.byKey(const Key('cam-along-sidebar')), findsOneWidget);
    // The recording and the link; not the photo.
    expect(find.text('Lesson'), findsOneWidget);
    expect(find.text('Backing track'), findsOneWidget);

    // The recording: plays above the camera.
    await tester.tap(find.byKey(ValueKey('cam-along-$audio')));
    await frames(tester);
    expect(find.byKey(const Key('cam-along-frame')), findsOneWidget);
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
    expect(commands, [false]);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await frames(tester);
    expect(commands, [false, true]);

    // Closed: space turns the tab again.
    await tester.tap(find.byKey(const Key('cam-along-close')));
    await frames(tester);
    expect(find.byKey(const Key('cam-along-frame')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);
  });

  testWidgets('with nothing to play along, no Play along', (tester) async {
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
    expect(find.byKey(const Key('cam-along')), findsNothing);
  });
}
