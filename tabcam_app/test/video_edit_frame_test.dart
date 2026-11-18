import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show LogicalKeyboardKey, PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/edit_layers.dart';
import 'package:tabcam_app/capture/video_edit.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/video_edit_screen.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'video_edit_test.dart' show FakeEditor, VolumePlatform;

Duration s(double seconds) => Duration(milliseconds: (seconds * 1000).round());

/// m:ss.t, as the editor says a time.
String _time(Duration d) {
  final tenths = d.inMilliseconds ~/ 100;
  final seconds = (tenths ~/ 10) % 60;
  return '${tenths ~/ 600}:${seconds.toString().padLeft(2, '0')}.${tenths % 10}';
}

/// The fake platform, each player where its last seek put it or a test
/// puts it ([positions]; 12 s in until then), with each player's seeks.
class _Placed extends VolumePlatform {
  final positions = <int, Duration>{};
  final seeksOf = <int, List<Duration>>{};

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? position;

  @override
  Future<void> seekTo(int playerId, Duration position) {
    (seeksOf[playerId] ??= []).add(position);
    positions[playerId] = position;
    return super.seekTo(playerId, position);
  }
}

/// The fake platform, whose first player can't open its file.
class _OpensSecond extends VolumePlatform {
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => playerId == 0
      ? Stream.error(
          PlatformException(code: 'made-up', message: 'a made-up failure'),
        )
      : super.videoEventsFor(playerId);
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets the screen's players open (they do, off the test clock).
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await _frames(tester);
}

void main() {
  setUp(() => VideoEditor.instance = FakeEditor());
  tearDown(() => VideoEditor.instance = null);

  /// A capture with a video (k0), 3 minutes long as the fake players say,
  /// and a recording (k1).
  Future<(Library, String)> capture(WidgetTester tester) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late String id;
    await tester.runAsync(() async {
      await library.load();
      var event = await library.create(const []);
      for (final (i, (kind, ext)) in [
        (PageKind.video, 'mp4'),
        (PageKind.audio, 'm4a'),
      ].indexed) {
        final page = EventPage(
          id: 'k$i',
          kind: kind,
          extension: ext,
          title: i == 0 ? 'Made-up riff' : null,
        );
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

  Widget editScreen(Library library, String id, {Locale? locale}) =>
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: VideoEditScreen(
          library: library,
          eventId: id,
          page: library.byId(id)!.pages.first,
          pickFile: () async => null,
        ),
      );

  /// The editor on a video kept from 1:00 to 2:00, its players [platform]'s.
  Future<void> openTrimmed(WidgetTester tester, _Placed platform) async {
    VideoPlayerPlatform.instance = platform;
    sized(tester, const Size(900, 1600));
    final (library, id) = await capture(tester);
    await tester.runAsync(
      () => library.setPageEdit(id, 'k0', PageEdit(start: s(60), end: s(120))),
    );
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    expect(find.text('Keep 1:00.0–2:00.0'), findsOneWidget);
  }

  /// A click on the ruler, [part] of the way along it.
  Future<void> clickRuler(WidgetTester tester, double part) async {
    final ruler = tester.getRect(find.byKey(const Key('video-edit-ruler')));
    await tester.tapAt(
      Offset(ruler.left + ruler.width * part, ruler.center.dy),
    );
    await _settle(tester);
  }

  String timeShown(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('video-edit-time'))).data!;

  testWidgets('a click on the ruler while it plays keeps it playing from '
      'there', (tester) async {
    final platform = _Placed();
    await openTrimmed(tester, platform);
    await tester.tap(find.byKey(const Key('video-edit-play')));
    await _settle(tester);
    expect(platform.playing, contains(0));
    platform.paused.clear();

    // Half way along: 1:30, in the kept part.
    await clickRuler(tester, 0.5);
    expect(platform.seeksOf[0]!.last.inMilliseconds, closeTo(90000, 500));
    expect(platform.paused, isNot(contains(0)));
    expect(platform.playing, contains(0));
    expect(timeShown(tester), _time(platform.seeksOf[0]!.last));

    // A quarter along: 0:45, cut off. It plays on there too, not brought
    // to the kept part's start.
    await clickRuler(tester, 0.25);
    expect(platform.seeksOf[0]!.last.inMilliseconds, closeTo(45000, 500));
    expect(platform.seeksOf[0], hasLength(2));
    expect(platform.paused, isNot(contains(0)));
    expect(platform.playing, contains(0));
    expect(timeShown(tester), _time(platform.seeksOf[0]!.last));
  });

  testWidgets('paused in a cut part, Play starts there; it stops at the '
      'kept part\'s end, and Play then starts at its start', (tester) async {
    final platform = _Placed();
    await openTrimmed(tester, platform);
    // While it plays outside the kept part, the preview draws nothing
    // over the video.
    expect(tester.widget<EditLayers>(find.byType(EditLayers)).kept, s(60));

    // A quarter along the ruler: 0:45, before the kept part. The click
    // plays nothing by itself.
    await clickRuler(tester, 0.25);
    expect(platform.playing, isEmpty);
    final there = platform.seeksOf[0]!.single;
    expect(there.inMilliseconds, closeTo(45000, 500));
    expect(timeShown(tester), _time(there));

    await tester.tap(find.byKey(const Key('video-edit-play')));
    await _settle(tester);
    expect(platform.playing, contains(0));
    expect(platform.seeksOf[0], [there]);
    // As the video is: its own sound at its level, not faded in.
    expect(platform.volumes[0], 1);

    // Playing on, up to the kept part's end, 2:00: paused there.
    platform.positions[0] = s(119.95);
    await _settle(tester);
    expect(platform.playing, contains(0));
    platform.positions[0] = s(120.05);
    await _settle(tester);
    expect(platform.playing, isNot(contains(0)));
    expect(platform.seeksOf[0], [there, s(120)]);
    expect(timeShown(tester), '2:00.0');
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    // Play again: from the kept part's start.
    await tester.tap(find.byKey(const Key('video-edit-play')));
    await _settle(tester);
    expect(platform.seeksOf[0], [there, s(120), s(60)]);
    expect(platform.playing, contains(0));
  });

  testWidgets('a player that fails says the video can\'t be played; Try '
      'again opens it again, with the edit as it was', (tester) async {
    final platform = VolumePlatform();
    VideoPlayerPlatform.instance = platform;
    sized(tester, const Size(900, 1600));
    final (library, id) = await capture(tester);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    expect(find.byKey(const Key('video-edit-retry')), findsNothing);

    // Trimmed to where the player is, 12 s in, and the player fails
    // before that's kept with the page.
    await tester.tap(find.byKey(const Key('video-edit-end-here')));
    await tester.pump();
    expect(find.text('Keep 0:00.0–0:12.0'), findsOneWidget);
    expect(library.byId(id)!.pages.first.edit, isNull);
    platform.fail(0);
    await tester.pump();
    expect(find.text('This video can\'t be played here'), findsOneWidget);
    expect(find.byKey(const Key('video-edit-play')), findsNothing);
    expect(find.byKey(const Key('video-edit-preview')), findsNothing);

    await tester.tap(find.byKey(const Key('video-edit-retry')));
    await _settle(tester);
    expect(find.text('This video can\'t be played here'), findsNothing);
    expect(find.byKey(const Key('video-edit-retry')), findsNothing);
    expect(find.byKey(const Key('video-edit-preview')), findsOneWidget);
    expect(find.text('Keep 0:00.0–0:12.0'), findsOneWidget);
    expect(library.byId(id)!.pages.first.edit!.end, s(12));
    // A new player, the failed one let go of; it plays.
    expect(platform.disposed, [0]);
    expect(platform.lastPlayer, 1);
    await tester.tap(find.byKey(const Key('video-edit-play')));
    await _settle(tester);
    expect(platform.playing, contains(1));
    expect(find.byIcon(Icons.pause), findsOneWidget);
  });

  testWidgets('a video that can\'t be opened says so; Try again opens it', (
    tester,
  ) async {
    final platform = _OpensSecond();
    VideoPlayerPlatform.instance = platform;
    sized(tester, const Size(900, 1600));
    final (library, id) = await capture(tester);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    expect(find.text('This video can\'t be played here'), findsOneWidget);
    expect(find.byKey(const Key('video-edit-play')), findsNothing);

    await tester.tap(find.byKey(const Key('video-edit-retry')));
    await _settle(tester);
    expect(find.text('This video can\'t be played here'), findsNothing);
    expect(find.byKey(const Key('video-edit-play')), findsOneWidget);
    expect(find.text('Keep 0:00.0–3:00.0'), findsOneWidget);
    await tester.tap(find.byKey(const Key('video-edit-play')));
    await _settle(tester);
    expect(platform.playing, contains(platform.lastPlayer));
  });

  Duration lastSeek(_Placed platform) => platform.seeksOf[0]!.last;

  testWidgets('To the start and To the end go to the kept part\'s ends, '
      'then the video\'s; To the end pauses', (tester) async {
    final platform = _Placed();
    await openTrimmed(tester, platform);
    Future<void> press(String key) async {
      await tester.tap(find.byKey(Key(key)));
      await _settle(tester);
    }

    // From 1:30, in the kept part: its start, 1:00, then the video's.
    await clickRuler(tester, 0.5);
    await press('video-edit-to-start');
    expect(lastSeek(platform), s(60));
    expect(timeShown(tester), '1:00.0');
    await press('video-edit-to-start');
    expect(lastSeek(platform), Duration.zero);

    // The kept part's end, 2:00, then the video's, 3:00.
    await press('video-edit-to-end');
    expect(lastSeek(platform), s(120));
    await press('video-edit-to-end');
    expect(lastSeek(platform), s(180));
    expect(timeShown(tester), '3:00.0');

    // Playing, To the end pauses it there; To the start plays on.
    await press('video-edit-to-start');
    await tester.tap(find.byKey(const Key('video-edit-play')));
    await _settle(tester);
    expect(platform.playing, contains(0));
    platform.paused.clear();
    await press('video-edit-to-end');
    expect(platform.paused, contains(0));
    expect(platform.playing, isNot(contains(0)));
    expect(lastSeek(platform), s(120));
  });

  testWidgets('Home, End and the arrows move the preview; not while the '
      'title is typed in', (tester) async {
    final platform = _Placed();
    await openTrimmed(tester, platform);
    await clickRuler(tester, 0.5);
    final from = lastSeek(platform);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(lastSeek(platform), from + s(0.1));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await _settle(tester);
    expect(lastSeek(platform), from + s(0.1) - s(1));

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await _settle(tester);
    expect(lastSeek(platform), s(60));
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await _settle(tester);
    expect(lastSeek(platform), Duration.zero);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await _settle(tester);
    expect(lastSeek(platform), s(120));

    // In the title's field, the keys are the field's.
    final seeks = platform.seeksOf[0]!.length;
    await tester.tap(find.byType(TextField).first);
    await _settle(tester);
    for (final key in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
    ]) {
      await tester.sendKeyEvent(key);
    }
    await _settle(tester);
    expect(platform.seeksOf[0], hasLength(seeks));
  });

  group('the frame', () {
    final sizes = <(String, Size, double)>[
      ('a phone', const Size(390, 844), 1),
      ('a small phone, the largest text', const Size(360, 740), 2),
      ('a phone on its side', const Size(740, 360), 1),
      ('a laptop', const Size(1280, 800), 1),
    ];
    for (final (name, size, scale) in sizes) {
      for (final locale in const [Locale('en'), Locale('es'), Locale('pt')]) {
        testWidgets('the viewer, the transport and the lanes fit without '
            'scrolling: $name, ${locale.languageCode}', (tester) async {
          VideoPlayerPlatform.instance = VolumePlatform();
          sized(tester, size);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final (library, id) = await capture(tester);
          await tester.pumpWidget(editScreen(library, id, locale: locale));
          await _settle(tester);
          expect(tester.takeException(), isNull);

          final screen = Offset.zero & size;
          Rect rect(String key) => tester.getRect(find.byKey(Key(key)));
          for (final key in [
            'video-edit-preview',
            'video-edit-play',
            'video-edit-to-start',
            'video-edit-to-end',
            'video-edit-ruler',
            'video-edit-take-bar',
            'video-edit-song-add',
          ]) {
            final r = rect(key);
            expect(r.isEmpty, isFalse, reason: key);
            expect(
              screen.contains(r.topLeft) &&
                  screen.contains(r.bottomRight - const Offset(1, 1)),
              isTrue,
              reason: '$key at $r',
            );
          }
          // The transport right over the ruler; the lanes flush with the
          // bottom edge.
          expect(
            rect('video-edit-play').bottom,
            lessThanOrEqualTo(rect('video-edit-ruler').top),
          );
          expect(
            rect('video-edit-ruler').top - rect('video-edit-play').bottom,
            lessThan(8),
          );
          expect(size.height - rect('video-edit-song-add').bottom, 6);
          // The bars as wide as the ruler, the playhead over them.
          expect(
            rect('video-edit-take-bar').left,
            rect('video-edit-ruler').left,
          );
          expect(
            rect('video-edit-take-bar').right,
            rect('video-edit-ruler').right,
          );
          expect(find.byKey(const Key('video-edit-playhead')), findsOneWidget);
          // The picture keeps the video's shape, as large as its box allows.
          final preview = rect('video-edit-preview');
          final shown = tester
              .widget<AspectRatio>(
                find.ancestor(
                  of: find.byKey(const Key('video-edit-preview')),
                  matching: find.byType(AspectRatio),
                ),
              )
              .aspectRatio;
          expect(preview.width / preview.height, closeTo(shown, 0.02));
          // Reset and Download in the app bar.
          for (final key in ['video-edit-reset', 'video-edit-download']) {
            expect(
              find.descendant(
                of: find.byType(AppBar),
                matching: find.byKey(Key(key)),
              ),
              findsOneWidget,
              reason: key,
            );
          }
        });
      }
    }
  });

  testWidgets('with the keyboard open, the transport and the lanes give '
      'their room to the viewer; they come back as it closes', (tester) async {
    VideoPlayerPlatform.instance = VolumePlatform();
    sized(tester, const Size(390, 844));
    final (library, id) = await capture(tester);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    expect(find.byKey(const Key('video-edit-ruler')), findsOneWidget);
    final before = tester.getRect(find.byKey(const Key('video-edit-preview')));

    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    await _frames(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('video-edit-ruler')), findsNothing);
    expect(find.byKey(const Key('video-edit-play')), findsNothing);
    expect(
      tester.getRect(find.byKey(const Key('video-edit-preview'))).top,
      before.top,
    );

    tester.view.resetViewInsets();
    await _frames(tester);
    expect(find.byKey(const Key('video-edit-ruler')), findsOneWidget);
    expect(find.byKey(const Key('video-edit-play')), findsOneWidget);
  });

  testWidgets('the Song lane\'s name opens Change and Remove; empty, the '
      'lane is Add a song', (tester) async {
    VideoPlayerPlatform.instance = VolumePlatform();
    sized(tester, const Size(390, 844));
    final (library, id) = await capture(tester);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    expect(find.byKey(const Key('video-edit-song-add')), findsOneWidget);
    expect(find.byKey(const Key('video-edit-song-menu')), findsNothing);
    expect(find.byKey(const Key('video-edit-song-volume')), findsNothing);

    await tester.runAsync(
      () => library.setPageEdit(
        id,
        'k0',
        PageEdit(
          start: Duration.zero,
          end: s(180),
          song: SongMode.manual,
          trackId: 'k1',
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    expect(find.byKey(const Key('video-edit-song-add')), findsNothing);
    expect(find.byKey(const Key('video-edit-song-volume')), findsOneWidget);
    final menu = tester.getRect(find.byKey(const Key('video-edit-song-menu')));
    final bar = tester.getRect(find.byKey(const Key('video-edit-song-bar')));
    expect(menu.right, lessThan(bar.left));
    expect(menu.height, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const Key('video-edit-song-menu')));
    await _frames(tester);
    expect(find.byKey(const Key('video-edit-song-change')), findsOneWidget);
    await tester.tap(find.byKey(const Key('video-edit-song-remove')));
    await _settle(tester);
    expect(find.byKey(const Key('video-edit-song-add')), findsOneWidget);
    expect(find.byKey(const Key('video-edit-song-menu')), findsNothing);
  });
}
