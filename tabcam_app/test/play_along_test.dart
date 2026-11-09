import 'dart:convert';

import 'package:camera_platform_interface/camera_platform_interface.dart';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/capture/head_gestures.dart';
import 'package:tabcam_app/capture/link_frame.dart';
import 'package:tabcam_app/capture/media.dart';
import 'package:tabcam_app/capture/backing_track.dart';
import 'package:tabcam_app/capture/play_along_screen.dart';
import 'package:tabcam_app/capture/play_along_sidebar.dart';
import 'package:tabcam_app/capture/take_overlay.dart';
import 'package:tabcam_app/dictionary/dictionary_sidebar.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/event_screen.dart';
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

/// The bar's Stop (Rec's or Play's), not the sidebar's: a take opens the
/// sidebar, whose frame has a Stop too.
final _camStop = find.byElementPredicate((e) {
  final w = e.widget;
  if (w is! Tooltip || w.message != 'Stop') return false;
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
    await tester.tap(_camStop);
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
    await tester.tap(find.byTooltip('Rec'));
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
          burn: (take, _) async => take,
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
    await tester.tap(find.byTooltip('Rec'));
    await frames(tester);
    await at(10);
    await pass();
    expect(find.text('2 / 3'), findsOneWidget);
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
    // Marked on the song's progress bar.
    expect(find.byKey(const Key('cam-along-phrase-marks')), findsOneWidget);
    expect(find.text('2 phrase passes'), findsOneWidget);

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
      find.byTooltip('Auto-pass off: the tab turns only when you turn it'),
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
    expect(find.byKey(const Key('cam-along-phrases')), findsNothing);
    expect(find.byKey(const Key('cam-along-phrase-marks')), findsNothing);
  });
}
