import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/capture/head_gestures.dart';
import 'package:tabcam_app/capture/play_along_screen.dart';
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

  testWidgets('Rec records a take into the capture; Play plays it back', (
    tester,
  ) async {
    final (library, id) = await capture(tester, tab: _tab);
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

    await tester.tap(find.byTooltip('Rec'));
    await frames(tester);
    expect(camera.recording, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.tap(find.byTooltip('Stop'));
    await frames(tester);
    expect(camera.recording, isFalse);
    expect(find.text('Take 1 added to the capture'), findsOneWidget);
    var pages = library.byId(id)!.pages;
    expect(pages, hasLength(2));
    expect(pages.last.kind, PageKind.video);
    expect(pages.last.title, 'Take 1');

    // A second take is Take 2.
    await tester.tap(find.byTooltip('Rec'));
    await frames(tester);
    await tester.tap(find.byTooltip('Stop'));
    await frames(tester);
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
    await frames(tester);
    expect(camera.streaming, isTrue);

    // Off: no frames, and a gesture does nothing.
    await tester.tap(find.byKey(const Key('cam-heads')));
    await frames(tester);
    expect(find.byTooltip('Head gestures off'), findsOneWidget);
    expect(camera.streaming, isFalse);
    heads!.onGesture(HeadGesture.previous);
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(heads!.disposed, isTrue);
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
    await frames(tester);
    // Saved before going back.
    expect(find.text('Take 1 added to the capture'), findsOneWidget);
    await tester.pageBack();
    await tester.pump();
    await frames(tester);
    expect(find.byType(PlayAlongScreen), findsNothing);
    // The list, not the Text view, with the take in it.
    expect(find.text('Take 1'), findsOneWidget);
  });
}
