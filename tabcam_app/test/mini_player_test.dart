import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/event_screen.dart';
import 'package:tabcam_app/screens/file_screen.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A video platform that "plays" anything: 3 minutes long, 12 seconds in.
class FakeVideoPlatform extends VideoPlatformBase {
  final playing = <int>{};
  final disposed = <int>[];
  var _next = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => _next++;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(minutes: 3),
      size: const Size(320, 240),
    ),
  );

  @override
  Future<void> play(int playerId) async => playing.add(playerId);

  @override
  Future<void> pause(int playerId) async => playing.remove(playerId);

  @override
  Future<void> dispose(int playerId) async {
    playing.remove(playerId);
    disposed.add(playerId);
  }

  /// Where the players are (tests move it).
  var position = const Duration(seconds: 12);

  @override
  Future<Duration> getPosition(int playerId) async => position;

  /// Whether each player loops.
  final looping = <int, bool>{};

  @override
  Future<void> setLooping(int playerId, bool looping) async =>
      this.looping[playerId] = looping;

  /// Where each seek went.
  final seeks = <Duration>[];

  /// Each player's speed, once set.
  final speeds = <int, double>{};

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async =>
      speeds[playerId] = speed;

  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      seeks.add(position);

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.black);
}

/// The interface's base, with every call the fake doesn't make a no-op.
abstract class VideoPlatformBase extends VideoPlayerPlatform {
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late FakeVideoPlatform platform;
  setUp(() => VideoPlayerPlatform.instance = platform = FakeVideoPlatform());

  testWidgets('videos and recordings play from the list, one at a time', (
    tester,
  ) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late String id;
    await tester.runAsync(() async {
      await library.load();
      var event = await library.create(const []);
      for (final (pageId, kind, ext) in [
        ('v1', PageKind.video, 'mp4'),
        ('a1', PageKind.audio, 'mp3'),
      ]) {
        final page = EventPage(id: pageId, kind: kind, extension: ext);
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
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: EventScreen(library: library, eventId: id),
      ),
    );
    await _frames(tester);
    // Each has a play button; nothing plays yet.
    expect(find.byKey(const ValueKey('mini-play-v1')), findsOneWidget);
    expect(find.byKey(const ValueKey('mini-play-a1')), findsOneWidget);
    expect(find.byType(VideoProgressIndicator), findsNothing);

    Future<void> tap(String key) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await _frames(tester);
    }

    // The video plays in its row: progress and time.
    // (Its thumbnail has a player of its own, paused on the first frame.)
    await tap('mini-play-v1');
    expect(platform.playing, hasLength(1));
    final video = platform.playing.single;
    expect(find.byType(VideoProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('mini-time-v1')), findsOneWidget);
    expect(find.text('0:12 / 3:00'), findsOneWidget);

    // Pause and play again.
    await tap('mini-play-v1');
    expect(platform.playing, isEmpty);
    await tap('mini-play-v1');
    expect(platform.playing, {video});

    // The recording stops the video.
    await tap('mini-play-a1');
    expect(platform.disposed, contains(video));
    expect(platform.playing, hasLength(1));
    final recording = platform.playing.single;
    expect(recording, isNot(video));
    expect(find.byKey(const ValueKey('mini-time-v1')), findsNothing);
    expect(find.byKey(const ValueKey('mini-time-a1')), findsOneWidget);

    // Leaving the screen stops it.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(platform.disposed, contains(recording));
  });

  /// A capture with [kinds]' files (ids k0, k1…) and, if [tab], a text tab.
  Future<(Library, String)> captureWith(
    WidgetTester tester,
    List<(PageKind, String)> kinds, {
    bool tab = false,
  }) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late String id;
    await tester.runAsync(() async {
      await library.load();
      var event = await library.create(const []);
      for (final (i, (kind, ext)) in kinds.indexed) {
        final page = EventPage(id: 'k$i', kind: kind, extension: ext);
        await library.putPageStream(
          event.id,
          page,
          Stream.value(Uint8List.fromList([1, 2, 3])),
        );
        event = event.copyWith(pages: [...event.pages, page]);
      }
      if (tab) event = event.copyWith(tabText: 'e|--0--3--|');
      await library.update(event);
      id = event.id;
    });
    return (library, id);
  }

  Widget host(Widget home) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  testWidgets('the Text view has the play-along sidebar, open, with the '
      'recording loaded; the Files view has none, and pauses it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (library, id) = await captureWith(tester, [
      (PageKind.image, 'jpg'),
      (PageKind.audio, 'm4a'),
    ], tab: true);
    await tester.pumpWidget(host(EventScreen(library: library, eventId: id)));
    await _frames(tester);
    await tester.tap(find.byKey(const Key('text')));
    await _frames(tester);
    expect(find.byKey(const Key('cam-along')), findsOneWidget);
    expect(find.byKey(const Key('cam-along-sidebar')), findsOneWidget);
    expect(find.byKey(const Key('cam-along-frame')), findsOneWidget);
    expect(platform.playing, isEmpty);
    // The notation sheet, at the bottom of the sidebar.
    final sheet = find.byKey(const Key('text-notation'));
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('5h7')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('7b9 r7')),
      findsOneWidget,
    );
    expect(
      tester.getBottomLeft(sheet).dy,
      greaterThan(
        tester.getBottomLeft(find.byKey(const Key('cam-along-frame'))).dy,
      ),
    );

    await tester.tap(find.byKey(const Key('cam-along-toggle')));
    await _frames(tester);
    expect(platform.playing, hasLength(1));

    await tester.tap(find.byKey(const Key('files')));
    await _frames(tester);
    expect(find.byKey(const Key('cam-along-sidebar')), findsNothing);
    expect(find.byKey(const Key('cam-along')), findsNothing);
    expect(platform.playing, isEmpty);
  });

  testWidgets('the Text view lists the PDFs to follow, as Cam does: the '
      'sidebar opens for a PDF alone; tapped, it shows in a pane on the '
      'left of the text, and hides tapped again', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (library, id) = await captureWith(tester, [
      (PageKind.pdf, 'pdf'),
    ], tab: true);
    final pdf = library.byId(id)!.pages.single.id;
    await tester.pumpWidget(host(EventScreen(library: library, eventId: id)));
    await _frames(tester);
    await tester.tap(find.byKey(const Key('text')));
    await _frames(tester);
    // Nothing to play: no frame, but the sidebar, for the PDF.
    final sidebar = find.byKey(const Key('cam-along-sidebar'));
    expect(sidebar, findsOneWidget);
    expect(find.byKey(const Key('cam-along-frame')), findsNothing);
    expect(find.text('Follow a PDF'), findsOneWidget);
    expect(find.byKey(const Key('text-notation')), findsOneWidget);
    expect(find.byKey(const Key('text-review')), findsNothing);
    final pane = find.byKey(const Key('cam-pdf-pane'));
    expect(pane, findsNothing);

    final tile = find.byKey(ValueKey('cam-along-$pdf'));
    await tester.tap(tile);
    await _frames(tester);
    expect(pane, findsOneWidget);
    expect(tester.widget<ListTile>(tile).selected, isTrue);
    expect(
      tester.getTopLeft(pane).dx,
      lessThan(tester.getTopLeft(find.byType(TextField)).dx),
    );
    expect(find.byKey(const Key('cam-pdf-split')), findsOneWidget);

    await tester.tap(tile);
    await _frames(tester);
    expect(pane, findsNothing);
  });

  testWidgets('a PDF has the play-along sidebar; an image has none', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (library, id) = await captureWith(tester, [
      (PageKind.pdf, 'pdf'),
      (PageKind.image, 'jpg'),
      (PageKind.audio, 'm4a'),
    ]);
    await tester.pumpWidget(
      host(FileScreen(library: library, eventId: id, pageId: 'k0')),
    );
    await _frames(tester);
    expect(find.byKey(const Key('cam-along')), findsOneWidget);
    expect(find.byKey(const Key('cam-along-sidebar')), findsOneWidget);
    expect(find.byKey(const Key('cam-along-frame')), findsOneWidget);

    await tester.pumpWidget(
      host(
        FileScreen(
          key: const Key('k1'),
          library: library,
          eventId: id,
          pageId: 'k1',
        ),
      ),
    );
    await _frames(tester);
    expect(find.byKey(const Key('cam-along')), findsNothing);
    expect(find.byKey(const Key('cam-along-sidebar')), findsNothing);
  });
}
