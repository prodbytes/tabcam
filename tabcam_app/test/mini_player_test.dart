import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/backing_track.dart';
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

  /// The last player made.
  int get lastPlayer => _next - 1;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => _next++;

  /// Each player's events: initialized at once, then what a test sends
  /// ([complete]).
  final _events = <int, StreamController<VideoEvent>>{};

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      (_events[playerId] ??= StreamController<VideoEvent>()
            ..add(
              VideoEvent(
                eventType: VideoEventType.initialized,
                duration: const Duration(minutes: 3),
                size: const Size(320, 240),
              ),
            ))
          .stream;

  /// The player reached its end (video_player then pauses it and seeks to
  /// the end by itself).
  void complete(int playerId) {
    position = const Duration(minutes: 3);
    _events[playerId]!.add(VideoEvent(eventType: VideoEventType.completed));
  }

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

  /// A capture with [kinds]' files (ids k0, k1…) and, if [tab], a text tab;
  /// those at [takes] are Cam's takes ("Take 1"…, marked).
  Future<(Library, String)> captureWith(
    WidgetTester tester,
    List<(PageKind, String)> kinds, {
    bool tab = false,
    List<int> takes = const [],
  }) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late String id;
    await tester.runAsync(() async {
      await library.load();
      // Play plays at once (the count-in has tests of its own).
      await library.writeMeta(BackingTrack.metaName, '{"countIn":false}');
      var event = await library.create(const []);
      for (final (i, (kind, ext)) in kinds.indexed) {
        final take = takes.indexOf(i) + 1;
        final page = EventPage(
          id: 'k$i',
          kind: kind,
          extension: ext,
          title: take > 0 ? 'Take $take' : null,
          take: take > 0,
        );
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

  testWidgets('on a phone the sidebar starts closed, the tools on one '
      'line; opened, it loads the recording, the tools wrap at their full '
      'size, and the player and the notation sheet fit it', (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final (library, id) = await captureWith(tester, [
      (PageKind.image, 'jpg'),
      (PageKind.audio, 'm4a'),
    ], tab: true);
    await tester.pumpWidget(host(EventScreen(library: library, eventId: id)));
    await _frames(tester);
    await tester.tap(find.byKey(const Key('text')));
    await _frames(tester);
    // Closed: the text and its tools have the width, Overtype first on
    // the tools' first line.
    expect(find.byKey(const Key('cam-along-sidebar')), findsNothing);
    final fretUp = find.byTooltip('Fret up (the number under the cursor)');
    expect(
      tester.getRect(find.byKey(const Key('text-overtype'))).top,
      closeTo(tester.getRect(fretUp).top, 0.5),
    );
    // Opened from the More menu, it loads the recording, not playing.
    await tester.tap(find.byKey(const Key('event-more')));
    await _frames(tester);
    await tester.tap(find.byKey(const Key('more-along')));
    await _frames(tester);
    expect(find.byKey(const Key('cam-along-toggle')), findsOneWidget);
    expect(platform.playing, isEmpty);
    final sidebar = tester.getRect(find.byKey(const Key('cam-along-sidebar')));
    expect(sidebar.width, greaterThan(100));
    final plus = tester.getRect(
      find.byTooltip('Fret up (the number under the cursor)'),
    );
    expect(plus.width, closeTo(40, 0.5));
    // Every tool left of the sidebar: on more lines, not past the edge.
    final last = tester.getRect(find.byKey(const Key('text-new-phrase')));
    expect(last.width, closeTo(40, 0.5));
    expect(last.right, lessThanOrEqualTo(sidebar.left));
    expect(last.top, greaterThan(plus.top));

    // The notation sheet, its lines wrapped in the narrow sidebar, takes
    // at most 30% of it and scrolls; the player keeps its buttons, whole
    // (no overflow: it would fail the test).
    final footer = tester.getRect(find.byKey(const Key('cam-along-footer')));
    expect(footer.height, lessThanOrEqualTo(sidebar.height * 0.3 + 0.5));
    expect(footer.bottom, closeTo(sidebar.bottom, 0.5));
    final frame = tester.getRect(find.byKey(const Key('cam-along-frame')));
    final play = tester.getRect(find.byKey(const Key('cam-along-toggle')));
    expect(play.bottom, lessThanOrEqualTo(frame.bottom + 0.5));
    expect(frame.bottom, lessThan(footer.top));
    // The sheet's last row is there, scrolled to.
    await tester.dragUntilVisible(
      find.text('(5)'),
      find.byKey(const Key('cam-along-footer')),
      const Offset(0, -60),
    );
    expect(find.text('(5)'), findsOneWidget);
  });

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
    for (final symbol in ['5_7', '7(9)', '7~', '(5)', 'x']) {
      expect(
        find.descendant(of: sheet, matching: find.text(symbol)),
        findsOneWidget,
      );
    }
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

  testWidgets('a PDF and an image have the play-along sidebar, with the '
      'recording loaded; neither lists anything to follow', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (library, id) = await captureWith(tester, [
      (PageKind.pdf, 'pdf'),
      (PageKind.image, 'jpg'),
      (PageKind.audio, 'm4a'),
    ]);
    for (final file in ['k0', 'k1']) {
      await tester.pumpWidget(
        host(
          FileScreen(
            key: Key(file),
            library: library,
            eventId: id,
            pageId: file,
          ),
        ),
      );
      await _frames(tester);
      expect(find.byKey(const Key('cam-along')), findsOneWidget);
      expect(find.byKey(const Key('cam-along-sidebar')), findsOneWidget);
      expect(find.byKey(const Key('cam-along-frame')), findsOneWidget);
      expect(find.byKey(const Key('cam-along-k2')), findsOneWidget);
      expect(find.textContaining('Follow'), findsNothing);
      expect(find.byKey(const Key('cam-along-k0')), findsNothing);
      expect(find.byKey(const Key('cam-along-k1')), findsNothing);
    }
    // The image itself, pinch-zoomable, beside the sidebar.
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(
      tester.getTopRight(find.byType(InteractiveViewer)).dx,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const Key('cam-along-sidebar'))).dx,
      ),
    );
  });

  testWidgets('with a text tab, a PDF\'s sidebar lists it first; tapped, '
      'the text shows in a pane beside the PDF', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (library, id) = await captureWith(tester, [
      (PageKind.pdf, 'pdf'),
      (PageKind.audio, 'm4a'),
    ], tab: true);
    await tester.pumpWidget(
      host(FileScreen(library: library, eventId: id, pageId: 'k0')),
    );
    await _frames(tester);
    final text = find.byKey(const Key('cam-along-text'));
    expect(text, findsOneWidget);
    expect(
      tester.getTopLeft(text).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('cam-along-k1'))).dy),
    );
    await tester.tap(text);
    await tester.pump();
    final pane = find.byKey(const Key('cam-pdf-pane'));
    expect(pane, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('cam-text-view')),
        matching: find.text('e|--0--3--|', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopRight(pane).dx,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('cam-along-sidebar'))).dx,
      ),
    );
  });

  testWidgets('on a recording\'s file screen, the sidebar\'s files show '
      'Delete, all but the recording\'s own', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (library, id) = await captureWith(tester, [
      (PageKind.pdf, 'pdf'),
      (PageKind.video, 'mp4'),
      (PageKind.audio, 'm4a'),
    ]);
    await tester.pumpWidget(
      host(FileScreen(library: library, eventId: id, pageId: 'k2')),
    );
    await _frames(tester);
    expect(find.byKey(const Key('cam-along-k2')), findsOneWidget);
    expect(find.byKey(const Key('cam-along-delete-k2')), findsNothing);
    expect(find.byKey(const Key('cam-along-delete-k1')), findsOneWidget);
    expect(find.byKey(const Key('cam-along-delete-k0')), findsOneWidget);

    // The video deleted from it: the recording's screen stays.
    await tester.tap(find.byKey(const Key('cam-along-delete-k1')));
    await _frames(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await _frames(tester);
    expect(library.byId(id)!.pages.map((p) => p.id), ['k0', 'k2']);
    expect(find.byKey(const Key('cam-along-k1')), findsNothing);
    expect(find.byKey(const Key('recording-aside')), findsOneWidget);
  });

  testWidgets('a recording playing in the list, deleted from the Text '
      'view\'s sidebar, stops, as the list\'s Delete stops it', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (library, id) = await captureWith(tester, [
      (PageKind.image, 'jpg'),
      (PageKind.audio, 'm4a'),
      (PageKind.audio, 'm4a'),
    ], tab: true);
    await tester.pumpWidget(host(EventScreen(library: library, eventId: id)));
    await _frames(tester);
    // The second recording plays in the list, and plays on in the Text
    // view (the sidebar loads the first, paused).
    await tester.tap(find.byKey(const ValueKey('mini-play-k2')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await _frames(tester);
    expect(platform.playing, hasLength(1));
    final inList = platform.playing.single;
    await tester.tap(find.byKey(const Key('text')));
    await _frames(tester);
    expect(find.byKey(const Key('cam-along-sidebar')), findsOneWidget);
    expect(platform.playing, {inList});
    // Scrolled to, above the notation sheet.
    await tester.ensureVisible(find.byKey(const Key('cam-along-delete-k2')));
    await _frames(tester);

    await tester.tap(find.byKey(const Key('cam-along-delete-k2')));
    await _frames(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await _frames(tester);
    expect(library.byId(id)!.pages.map((p) => p.id), ['k0', 'k1']);
    expect(platform.playing, isEmpty);
    expect(platform.disposed, contains(inList));
  });

  testWidgets('a recording opens in the sidebar: loaded in its frame, '
      'paused, with the pages and PDFs listed to follow; one tapped shows '
      'in a pane beside it', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (library, id) = await captureWith(tester, [
      (PageKind.pdf, 'pdf'),
      (PageKind.image, 'jpg'),
      (PageKind.video, 'mp4'),
      (PageKind.audio, 'm4a'),
    ]);
    await tester.pumpWidget(
      host(FileScreen(library: library, eventId: id, pageId: 'k3')),
    );
    await _frames(tester);
    final sidebar = find.byKey(const Key('cam-along-sidebar'));
    expect(sidebar, findsOneWidget);
    expect(find.byKey(const Key('cam-along')), findsOneWidget);
    expect(find.byKey(const Key('cam-along-frame')), findsOneWidget);
    // The recording, not the video before it, and paused.
    expect(
      tester.widget<ListTile>(find.byKey(const Key('cam-along-k3'))).selected,
      isTrue,
    );
    expect(
      tester.widget<ListTile>(find.byKey(const Key('cam-along-k2'))).selected,
      isFalse,
    );
    expect(platform.playing, isEmpty);
    // No player of its own: the card says it plays in the sidebar.
    expect(find.byKey(const Key('play-pause')), findsNothing);
    expect(find.byKey(const Key('recording-aside')), findsOneWidget);
    expect(find.textContaining('plays in the sidebar'), findsOneWidget);
    // The pages and PDFs to follow, under their heading.
    expect(find.text('Follow a page or PDF'), findsOneWidget);
    final pdf = find.byKey(const Key('cam-along-k0'));
    final image = find.byKey(const Key('cam-along-k1'));
    expect(pdf, findsOneWidget);
    expect(image, findsOneWidget);
    final pane = find.byKey(const Key('cam-pdf-pane'));
    expect(pane, findsNothing);

    await tester.tap(find.byKey(const Key('cam-along-toggle')));
    await _frames(tester);
    expect(platform.playing, hasLength(1));

    // The image, in a pane on the left, zoomable; the recording plays on.
    await tester.ensureVisible(image);
    await tester.pump();
    await tester.tap(image);
    await _frames(tester);
    expect(pane, findsOneWidget);
    expect(find.byKey(const Key('cam-image-k1')), findsOneWidget);
    expect(tester.widget<ListTile>(image).selected, isTrue);
    expect(
      tester.getTopLeft(pane).dx,
      lessThan(tester.getTopLeft(find.byKey(const Key('recording-aside'))).dx),
    );
    expect(platform.playing, hasLength(1));

    // The PDF takes its place; tapped again, the pane goes.
    await tester.ensureVisible(pdf);
    await tester.pump();
    await tester.tap(pdf);
    await _frames(tester);
    expect(find.byKey(const Key('cam-image-k1')), findsNothing);
    expect(tester.widget<ListTile>(pdf).selected, isTrue);
    expect(tester.widget<ListTile>(image).selected, isFalse);
    await tester.tap(pdf);
    await _frames(tester);
    expect(pane, findsNothing);

    // Hiding the sidebar pauses the recording.
    await tester.tap(find.byKey(const Key('cam-along')));
    await _frames(tester);
    expect(sidebar, findsNothing);
    expect(platform.playing, isEmpty);
  });

  testWidgets('a recording\'s sidebar lists Cam\'s takes last: after the '
      'pages and PDFs to follow, under Takes', (tester) async {
    // Tall enough for the whole list.
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (library, id) = await captureWith(
      tester,
      [
        (PageKind.video, 'mp4'),
        (PageKind.audio, 'm4a'),
        (PageKind.pdf, 'pdf'),
        (PageKind.image, 'jpg'),
      ],
      takes: [0],
    );
    await tester.pumpWidget(
      host(FileScreen(library: library, eventId: id, pageId: 'k1')),
    );
    await _frames(tester);
    double top(Finder f) => tester.getTopLeft(f).dy;
    final recording = find.byKey(const Key('cam-along-k1'));
    final pdf = find.byKey(const Key('cam-along-k2'));
    final image = find.byKey(const Key('cam-along-k3'));
    final take = find.byKey(const Key('cam-along-k0'));
    final takes = find.text('Takes');
    expect(takes, findsOneWidget);
    expect(find.text('Take 1'), findsOneWidget);
    // The recording opened, not the take before it.
    expect(tester.widget<ListTile>(recording).selected, isTrue);
    expect(tester.widget<ListTile>(take).selected, isFalse);
    // Recording, the PDF and the image to follow, then the take, last.
    expect(top(recording), lessThan(top(find.text('Follow a page or PDF'))));
    expect(top(find.text('Follow a page or PDF')), lessThan(top(pdf)));
    expect(top(pdf), lessThan(top(image)));
    expect(top(image), lessThan(top(takes)));
    expect(top(takes), lessThan(top(take)));
    expect(platform.playing, isEmpty);
  });
}
