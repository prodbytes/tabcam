import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/backing_track.dart';
import 'package:tabcam_app/capture/link_frame.dart';
import 'package:tabcam_app/capture/media.dart';
import 'package:tabcam_app/capture/play_along_sidebar.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'mini_player_test.dart' show FakeVideoPlatform;

void main() {
  late FakeVideoPlatform video;
  setUp(() => VideoPlayerPlatform.instance = video = FakeVideoPlatform());

  /// A track playing a 3-minute recording of a capture's own, or a link.
  Future<(BackingTrack, CaptureEvent, EventPage)> loaded(
    WidgetTester tester, {
    bool link = false,
  }) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late CaptureEvent event;
    await tester.runAsync(() async {
      await library.load();
      event = await library.create(const []);
      event = link
          ? await library.addLink(
              event,
              Uri.parse('https://example.com/riff.mp3'),
              title: 'Riff',
            )
          : await library.addMedia(event, [
              Media(
                XFile.fromData(Uint8List.fromList([1]), name: 'riff.m4a'),
                PageKind.audio,
                'm4a',
              ),
            ]);
    });
    final track = BackingTrack(
      library,
      open: (_, _, _) async {
        final media = VideoPlayerController.networkUrl(
          Uri.parse('https://example.com/riff.m4a'),
        );
        await media.initialize();
        return media;
      },
    );
    await tester.runAsync(
      () => track.choose(event, event.pages.last, play: false),
    );
    await tester.pump();
    return (track, event, event.pages.last);
  }

  testWidgets('a section is kept within the file and at least half a '
      'second; covering the file, it is the whole file again', (tester) async {
    final (track, _, _) = await loaded(tester);
    expect(track.canSection, isTrue);
    expect(track.section, isNull);

    await tester.runAsync(
      () => track.setSection(
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ),
    );
    expect(track.section, (
      start: const Duration(seconds: 10),
      end: const Duration(seconds: 20),
    ));
    // The player's own looping (back to the file's start) is off.
    expect(video.looping.values.last, isFalse);

    await tester.runAsync(
      () => track.setSection(
        const Duration(seconds: 30),
        const Duration(seconds: 30),
      ),
    );
    expect(track.section!.end - track.section!.start, BackingTrack.minSection);

    await tester.runAsync(
      () => track.setSection(
        -const Duration(seconds: 1),
        const Duration(hours: 1),
      ),
    );
    expect(track.section, isNull);
    expect(video.looping.values.last, isTrue);
    track.dispose();
  });

  testWidgets('playing past the end: back to the start with repeat, '
      'paused there without', (tester) async {
    final (track, _, _) = await loaded(tester);
    await tester.runAsync(
      () => track.setSection(
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ),
    );
    // Setting it moved the player into it (it was at 12 s: inside).
    video.seeks.clear();
    await tester.runAsync(() => track.toggle());
    expect(track.playing, isTrue);

    video.position = const Duration(seconds: 15);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    expect(video.seeks, isEmpty);

    video.position = const Duration(seconds: 20, milliseconds: 50);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    expect(video.seeks, contains(const Duration(seconds: 10)));
    expect(video.playing, isNotEmpty);

    await tester.runAsync(() => track.setRepeat(false));
    video.seeks.clear();
    video.position = const Duration(seconds: 21);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    expect(video.seeks, contains(const Duration(seconds: 10)));
    expect(video.playing, isEmpty);
    track.dispose();
  });

  testWidgets('a section ending at the file\'s end: the player completes, '
      'and it still starts over with repeat, pauses at the start without', (
    tester,
  ) async {
    final (track, _, _) = await loaded(tester);
    await tester.runAsync(
      () => track.setSection(
        const Duration(minutes: 2, seconds: 50),
        const Duration(minutes: 3), // the file's end
      ),
    );
    expect(track.section?.end, const Duration(minutes: 3));
    video.seeks.clear();
    await tester.runAsync(() => track.toggle());
    expect(track.playing, isTrue);

    // The file ends: the player pauses itself at the end. With repeat on,
    // back to the section's start, playing.
    await tester.runAsync(() async {
      video.complete(video.lastPlayer);
      await Future<void>.delayed(const Duration(milliseconds: 350));
    });
    expect(video.seeks, contains(const Duration(minutes: 2, seconds: 50)));
    expect(video.playing, isNotEmpty);
    expect(track.playing, isTrue);

    // Without repeat: back to the section's start, paused there.
    await tester.runAsync(() => track.setRepeat(false));
    video.seeks.clear();
    await tester.runAsync(() async {
      video.complete(video.lastPlayer);
      await Future<void>.delayed(const Duration(milliseconds: 350));
    });
    expect(video.seeks, contains(const Duration(minutes: 2, seconds: 50)));
    expect(video.playing, isEmpty);
    expect(track.playing, isFalse);
    track.dispose();
  });

  testWidgets('Stop, skips and Play stay in the section; each file keeps '
      'its own; a link has none', (tester) async {
    final (track, event, page) = await loaded(tester);
    await tester.runAsync(
      () => track.setSection(
        const Duration(seconds: 30),
        const Duration(seconds: 40),
      ),
    );
    video.seeks.clear();
    await tester.runAsync(() => track.stop());
    expect(video.seeks.last, const Duration(seconds: 30));
    await tester.runAsync(() => track.skip(const Duration(minutes: 1)));
    expect(video.seeks.last, const Duration(seconds: 40));

    // Closed and chosen again: the section is still there.
    await tester.runAsync(() => track.close());
    await tester.runAsync(() => track.choose(event, page, play: false));
    expect(track.section?.start, const Duration(seconds: 30));
    await tester.runAsync(() => track.clearSection());
    expect(track.section, isNull);
    track.dispose();

    final (link, _, _) = await loaded(tester, link: true);
    expect(link.canSection, isFalse);
    link.dispose();
  });

  testWidgets('restart goes back to the section\'s start (the file\'s '
      'without one), playing on or staying paused', (tester) async {
    final (track, _, _) = await loaded(tester);
    video.seeks.clear();
    await tester.runAsync(() => track.restart());
    expect(video.seeks.last, Duration.zero);
    expect(track.playing, isFalse);

    await tester.runAsync(
      () => track.setSection(
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ),
    );
    await tester.runAsync(() => track.toggle());
    video.seeks.clear();
    await tester.runAsync(() => track.restart());
    expect(video.seeks, const [Duration(seconds: 10)]);
    expect(track.playing, isTrue);
    track.dispose();
  });

  testWidgets('a link restarts by Stop, played again if it played', (
    tester,
  ) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late CaptureEvent event;
    await tester.runAsync(() async {
      await library.load();
      event = await library.addLink(
        await library.create(const []),
        Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        title: 'Riff',
      );
    });
    final track = BackingTrack(library);
    await tester.runAsync(() => track.choose(event, event.pages.last));
    final commands = <LinkCommand>[];
    track.link!.command = (command) async => commands.add(command);
    await tester.runAsync(() => track.restart());
    expect(commands, [LinkCommand.stop, LinkCommand.play]);
    commands.clear();
    await tester.runAsync(() => track.pause());
    commands.clear();
    await tester.runAsync(() => track.restart());
    expect(commands, [LinkCommand.stop]);
    track.dispose();
  });

  testWidgets('in the sidebar, 0 goes back to the start and space plays '
      'and pauses, once a tap gives it the keyboard; not Ctrl+0, nor '
      'typing in a field', (tester) async {
    final (track, _, _) = await loaded(tester);
    final field = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(child: TextField(controller: field)),
              PlayAlongKeys(
                track: track,
                child: const SizedBox(
                  key: Key('sidebar'),
                  width: 200,
                  height: 200,
                  child: ColoredBox(color: Colors.black),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('sidebar')));
    await tester.pump();
    video.seeks.clear();
    await tester.runAsync(() => tester.sendKeyEvent(LogicalKeyboardKey.digit0));
    expect(video.seeks, const [Duration.zero]);
    await tester.runAsync(
      () => tester.sendKeyEvent(LogicalKeyboardKey.numpad0),
    );
    expect(video.seeks, hasLength(2));

    await tester.runAsync(() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });
    expect(video.seeks, hasLength(2));

    await tester.runAsync(() => tester.sendKeyEvent(LogicalKeyboardKey.space));
    await tester.pump();
    expect(track.playing, isTrue);
    await tester.runAsync(() => tester.sendKeyEvent(LogicalKeyboardKey.space));
    await tester.pump();
    expect(track.playing, isFalse);

    // In the field, 0 and space are typed.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '');
    await tester.runAsync(() => tester.sendKeyEvent(LogicalKeyboardKey.digit0));
    expect(video.seeks, hasLength(2));
    expect(track.playing, isFalse);
    track.dispose();
  });

  testWidgets('the start and end can be set where it plays now', (
    tester,
  ) async {
    final (track, _, _) = await loaded(tester);
    // The fake reports 12 s once the player asks.
    await tester.runAsync(
      () => track.media!.seekTo(const Duration(seconds: 12)),
    );
    await tester.runAsync(() => track.sectionHere());
    expect(track.section?.start, const Duration(seconds: 12));
    expect(track.section?.end, const Duration(minutes: 3));
    track.dispose();
  });

  testWidgets('the sidebar shows the section for a recording: the range, '
      'its times, start / end here and Play all of it', (tester) async {
    final (track, event, _) = await loaded(tester);
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Row(
            children: [
              const Expanded(child: SizedBox()),
              PlayAlongSidebar(
                library: track.library,
                eventId: event.id,
                track: track,
                linkFrame: (_) => const SizedBox(),
                onChoose: (_) {},
                onToggle: () {},
                onStop: () {},
                onSkip: (_) {},
                onRepeat: () {},
                onSection: (start, end) {
                  calls.add('range');
                  track.setSection(start, end);
                },
                onSectionHere: ({required bool end}) =>
                    calls.add(end ? 'end' : 'start'),
                onSectionClear: () {
                  calls.add('clear');
                  track.clearSection();
                },
                onSpeed: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('cam-along-section')), findsOneWidget);
    expect(find.text('Section 0:00.0–3:00.0'), findsOneWidget);
    expect(find.byKey(const Key('cam-along-section-clear')), findsNothing);

    await tester.tap(find.byKey(const Key('cam-along-section-start')));
    await tester.tap(find.byKey(const Key('cam-along-section-end')));
    expect(calls, ['start', 'end']);

    await tester.runAsync(
      () => track.setSection(
        const Duration(seconds: 12, milliseconds: 340),
        const Duration(seconds: 45),
      ),
    );
    await tester.pump();
    expect(find.text('Section 0:12.3–0:45.0'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cam-along-section-clear')));
    await tester.pump();
    expect(calls.last, 'clear');
    expect(find.text('Section 0:00.0–3:00.0'), findsOneWidget);

    // Dragging the range's start thumb sets the section.
    final range = find.byKey(const Key('cam-along-section-range'));
    await tester.drag(range, const Offset(30, 0), warnIfMissed: false);
    await tester.pump();
    expect(calls, contains('range'));
    track.dispose();
  });
}
