import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
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
import 'package:tabcam_app/screens/sidebar_widths.dart';
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
    ValueListenable<bool>? recording,
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
      recording: recording,
      open: (_, _, _) async {
        final media = VideoPlayerController.networkUrl(
          Uri.parse('https://example.com/riff.m4a'),
        );
        await media.initialize();
        return media;
      },
    );
    // Play plays at once (the count-in has tests of its own).
    await tester.runAsync(() => track.setCountIn(false));
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

  testWidgets('a seek (the main row tapped) stays within the file, and '
      'within the section once there is one; a link stays', (tester) async {
    final (track, _, _) = await loaded(tester);
    video.seeks.clear();
    await tester.runAsync(() => track.seek(const Duration(seconds: 50)));
    await tester.runAsync(() => track.seek(-const Duration(seconds: 5)));
    await tester.runAsync(() => track.seek(const Duration(minutes: 9)));
    expect(video.seeks, const [
      Duration(seconds: 50),
      Duration.zero,
      Duration(minutes: 3),
    ]);

    await tester.runAsync(
      () => track.setSection(
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ),
    );
    video.seeks.clear();
    await tester.runAsync(() => track.seek(const Duration(seconds: 15)));
    await tester.runAsync(() => track.seek(const Duration(seconds: 2)));
    await tester.runAsync(() => track.seek(const Duration(seconds: 50)));
    expect(video.seeks, const [
      Duration(seconds: 15),
      Duration(seconds: 10),
      Duration(seconds: 20),
    ]);
    track.dispose();

    // A link straight to a sound file plays in the app: it seeks.
    final (file, _, _) = await loaded(tester, link: true);
    video.seeks.clear();
    await tester.runAsync(() => file.seek(const Duration(seconds: 15)));
    expect(video.seeks, const [Duration(seconds: 15)]);
    file.dispose();

    // A page in a frame can't be taken to a time.
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
    final link = BackingTrack(library);
    await tester.runAsync(() => link.choose(event, event.pages.last));
    final commands = <LinkCommand>[];
    link.link!.command = (command) async => commands.add(command);
    await tester.runAsync(() => link.seek(const Duration(seconds: 15)));
    expect(commands, isEmpty);
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

  /// A screen with a field to type in and the sidebar's keys around a
  /// stand-in for it.
  Widget keysHost(
    BackingTrack track,
    TextEditingController field, {
    bool active = true,
  }) => MaterialApp(
    home: Scaffold(
      body: Row(
        children: [
          Expanded(child: TextField(controller: field)),
          PlayAlongKeys(
            track: track,
            active: active,
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
  );

  testWidgets('with the sidebar showing, wherever the keyboard is: 0 goes '
      'back to the start, space and 1 play and pause; not with Ctrl, nor '
      'typing in a field, until a tap in the sidebar', (tester) async {
    final (track, _, _) = await loaded(tester);
    final field = TextEditingController();
    await tester.pumpWidget(keysHost(track, field));
    Future<bool> press(LogicalKeyboardKey key) async =>
        (await tester.runAsync(() => tester.sendKeyEvent(key)))!;

    // No tap in the sidebar first: the keys are the player's already.
    video.seeks.clear();
    expect(await press(LogicalKeyboardKey.digit0), isTrue);
    expect(video.seeks, const [Duration.zero]);
    expect(await press(LogicalKeyboardKey.numpad0), isTrue);
    expect(video.seeks, hasLength(2));

    for (final key in [
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.numpad1,
    ]) {
      expect(await press(key), isTrue);
      await tester.pump();
      expect(track.playing, isTrue, reason: '$key plays');
      expect(await press(key), isTrue);
      await tester.pump();
      expect(track.playing, isFalse, reason: '$key pauses');
    }

    // Ctrl + 0 and Ctrl + 1 are the browser's.
    await tester.runAsync(() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });
    expect(video.seeks, hasLength(2));
    expect(track.playing, isFalse);

    // In the field, 0, 1 and space are typed.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '');
    for (final key in [
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.space,
    ]) {
      await press(key);
    }
    expect(video.seeks, hasLength(2));
    expect(track.playing, isFalse);

    // A tap in the sidebar takes the keyboard out of the field.
    await tester.tap(find.byKey(const Key('sidebar')));
    await tester.pump();
    expect(await press(LogicalKeyboardKey.digit0), isTrue);
    expect(video.seeks, hasLength(3));
    expect(await press(LogicalKeyboardKey.digit1), isTrue);
    await tester.pump();
    expect(track.playing, isTrue);
    await tester.runAsync(() => track.pause());
    track.dispose();
  });

  testWidgets('the keys are not the player\'s with the sidebar hidden, nor '
      'under a dialog', (tester) async {
    final (track, _, _) = await loaded(tester);
    final field = TextEditingController();
    Future<bool> press(LogicalKeyboardKey key) async =>
        (await tester.runAsync(() => tester.sendKeyEvent(key)))!;
    video.seeks.clear();

    // Hidden: none of them.
    await tester.pumpWidget(keysHost(track, field, active: false));
    for (final key in [
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.space,
    ]) {
      expect(await press(key), isFalse);
    }
    expect(video.seeks, isEmpty);
    expect(track.playing, isFalse);

    // Showing, the keys are the player's: 0 goes back, 1 and space play
    // and pause.
    await tester.pumpWidget(keysHost(track, field));
    await tester.pump();
    expect(await press(LogicalKeyboardKey.digit0), isTrue);
    expect(video.seeks, hasLength(1));
    expect(await press(LogicalKeyboardKey.numpad1), isTrue);
    await tester.pump();
    expect(track.playing, isTrue);
    expect(await press(LogicalKeyboardKey.space), isTrue);
    await tester.pump();
    expect(track.playing, isFalse);
    expect(await press(LogicalKeyboardKey.digit1), isTrue);
    await tester.pump();
    expect(track.playing, isTrue);

    // Under a dialog, the keys are the dialog's.
    await tester.pumpWidget(keysHost(track, field));
    unawaited(
      showDialog<void>(
        context: tester.element(find.byKey(const Key('sidebar'))),
        builder: (_) => const AlertDialog(content: Text('Sure?')),
      ),
    );
    await tester.pump();
    await press(LogicalKeyboardKey.digit0);
    await press(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(video.seeks, hasLength(1));
    expect(track.playing, isTrue);

    // The dialog gone, they're the player's again.
    Navigator.of(tester.element(find.text('Sure?'))).pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(await press(LogicalKeyboardKey.digit1), isTrue);
    await tester.pump();
    expect(track.playing, isFalse);
    track.dispose();
  });

  testWidgets('the sidebar\'s back-to-the-start button does what 0 does: '
      'paused, to the start; playing, to the section\'s start, playing on; '
      'it fits the narrowest sidebar', (tester) async {
    final (track, event, _) = await loaded(tester);
    final field = TextEditingController();
    Future<bool> press(LogicalKeyboardKey key) async =>
        (await tester.runAsync(() => tester.sendKeyEvent(key)))!;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Row(
            children: [
              Expanded(child: TextField(controller: field)),
              PlayAlongKeys(
                track: track,
                // The narrowest it's dragged to: its buttons still fit.
                child: PlayAlongSidebar(
                  width: SidebarWidths.min,
                  library: track.library,
                  eventId: event.id,
                  track: track,
                  linkFrame: (_) => const SizedBox(),
                  onChoose: (_) {},
                  onToggle: () {},
                  onStop: () {},
                  onSkip: (_) {},
                  onRepeat: () {},
                  onSection: (_, _) {},
                  onSectionHere: ({required bool end}) {},
                  onSectionClear: () {},
                  onSpeed: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final restart = find.byKey(const Key('cam-along-restart'));
    expect(restart, findsOneWidget);
    expect(find.byTooltip('Back to the start (0)'), findsOneWidget);
    Future<void> tap() async {
      await tester.runAsync(() async {
        await tester.tap(restart);
        // Its restart runs on: let it seek.
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
    }

    // Paused: 0 and the button each go back to the start, staying paused.
    video.seeks.clear();
    expect(await press(LogicalKeyboardKey.digit0), isTrue);
    final byKey = [...video.seeks];
    video.seeks.clear();
    await tap();
    expect(video.seeks, byKey);
    expect(video.seeks, const [Duration.zero]);
    expect(track.playing, isFalse);

    // Playing a section: back to its start, playing on, as with 0.
    await tester.runAsync(
      () => track.setSection(
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ),
    );
    await tester.runAsync(() => track.toggle());
    await tester.pump();
    video.seeks.clear();
    expect(await press(LogicalKeyboardKey.digit0), isTrue);
    expect(video.seeks, const [Duration(seconds: 10)]);
    expect(track.playing, isTrue);
    video.seeks.clear();
    await tap();
    expect(video.seeks, const [Duration(seconds: 10)]);
    expect(track.playing, isTrue);
    await tester.runAsync(() => track.pause());
    track.dispose();
  });

  testWidgets('given onRestart, the button calls it (the screen\'s own, '
      'as PlayAlongBeside passes)', (tester) async {
    final (track, event, _) = await loaded(tester);
    var restarts = 0;
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
                onRestart: () => restarts++,
                onSection: (_, _) {},
                onSectionHere: ({required bool end}) {},
                onSectionClear: () {},
                onSpeed: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    video.seeks.clear();
    await tester.tap(find.byKey(const Key('cam-along-restart')));
    expect(restarts, 1);
    expect(video.seeks, isEmpty);
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

  testWidgets('the part played is the primary colour, red while a take '
      'records, and the section secondary', (tester) async {
    final recording = ValueNotifier(false);
    final (track, event, _) = await loaded(tester, recording: recording);
    final theme = ThemeData(colorSchemeSeed: Colors.indigo);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
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
                onSection: track.setSection,
                onSectionHere: ({required bool end}) {},
                onSectionClear: track.clearSection,
                onSpeed: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    Color played() => tester
        .widget<VideoProgressIndicator>(
          find.byKey(const Key('cam-along-progress')),
        )
        .colors
        .playedColor;
    final scheme = theme.colorScheme;
    // See-through, so a section's band over it still shows.
    expect(played(), scheme.primary.withValues(alpha: 0.75));

    recording.value = true;
    await tester.pump();
    expect(track.recording, isTrue);
    expect(played(), scheme.error.withValues(alpha: 0.75));

    recording.value = false;
    await tester.pump();
    expect(played(), scheme.primary.withValues(alpha: 0.75));

    // A section (Repeat on): its band over the bar, and its range, in the
    // secondary colour, as see-through.
    await tester.runAsync(
      () => track.setSection(
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ),
    );
    await tester.pump();
    final band = scheme.secondary.withValues(alpha: 0.75);
    expect(
      tester
          .widget<ColoredBox>(find.byKey(const Key('cam-along-section-mark')))
          .color,
      band,
    );
    expect(
      SliderTheme.of(
        tester.element(find.byKey(const Key('cam-along-section-range'))),
      ).activeTrackColor,
      band,
    );
    track.dispose();
  });

  testWidgets('with repeat off, while the range is dragged, the section '
      'shows over the progress bar, from its start to its end; let go, it '
      'is gone', (tester) async {
    final (track, event, _) = await loaded(tester);
    await tester.runAsync(() => track.setRepeat(false));
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
                onSection: track.setSection,
                onSectionHere: ({required bool end}) {},
                onSectionClear: track.clearSection,
                onSpeed: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => track.setSection(
        const Duration(seconds: 45),
        const Duration(seconds: 90),
      ),
    );
    await tester.pump();
    final mark = find.byKey(const Key('cam-along-section-mark'));
    // Set, but not being dragged: the range under the bar shows it.
    expect(mark, findsNothing);

    // Past the end thumb, so the drag takes that one, towards the start.
    final range = tester.getRect(
      find.byKey(const Key('cam-along-section-range')),
    );
    final gesture = await tester.startGesture(
      Offset(range.left + range.width * 0.9, range.center.dy),
    );
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    final section = track.section!;
    expect(section.start, const Duration(seconds: 45));
    expect(section.end, isNot(const Duration(seconds: 90)));

    // Over the progress bar, as far along it as the section is in the file.
    final bar = tester.getRect(find.byType(VideoProgressIndicator));
    final band = tester.getRect(mark);
    const length = Duration(minutes: 3);
    double at(Duration d) =>
        bar.left + bar.width * d.inMilliseconds / length.inMilliseconds;
    expect(band.left, closeTo(at(section.start), 0.5));
    expect(band.right, closeTo(at(section.end), 0.5));
    // As high as the bar's line (inside its padding of 4 above and below).
    expect(band.top, bar.top + 4);
    expect(band.bottom, bar.bottom - 4);

    // Both see-through: where the section and the part played overlap,
    // each shows through the other.
    final bandColor = tester.widget<ColoredBox>(mark).color;
    expect(bandColor.a, closeTo(0.75, 0.01));
    final played = tester
        .widget<VideoProgressIndicator>(find.byType(VideoProgressIndicator))
        .colors
        .playedColor;
    expect(played.a, lessThan(1));
    expect(played.a, greaterThan(0));

    // It follows the drag.
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    expect(track.section!.end, lessThan(section.end));
    expect(tester.getRect(mark).right, closeTo(at(track.section!.end), 0.5));

    await gesture.up();
    await tester.pump();
    expect(mark, findsNothing);
    expect(track.section, isNotNull);
    track.dispose();
  });

  testWidgets('while repeat is on, the section stays over the progress '
      'bar; repeat off, it goes', (tester) async {
    final (track, event, _) = await loaded(tester);
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
                onSection: track.setSection,
                onSectionHere: ({required bool end}) {},
                onSectionClear: track.clearSection,
                onSpeed: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    final mark = find.byKey(const Key('cam-along-section-mark'));
    expect(track.repeat, isTrue);
    // No section, nothing to show.
    expect(mark, findsNothing);

    await tester.runAsync(
      () => track.setSection(
        const Duration(seconds: 45),
        const Duration(seconds: 90),
      ),
    );
    await tester.pump();
    // Set and repeating: shown without a drag, where it falls on the bar.
    expect(mark, findsOneWidget);
    final bar = tester.getRect(find.byType(VideoProgressIndicator));
    final band = tester.getRect(mark);
    const length = Duration(minutes: 3);
    double at(Duration d) =>
        bar.left + bar.width * d.inMilliseconds / length.inMilliseconds;
    expect(band.left, closeTo(at(const Duration(seconds: 45)), 0.5));
    expect(band.right, closeTo(at(const Duration(seconds: 90)), 0.5));

    await tester.runAsync(() => track.setRepeat(false));
    await tester.pump();
    expect(mark, findsNothing);

    await tester.runAsync(() => track.setRepeat(true));
    await tester.pump();
    expect(mark, findsOneWidget);

    await tester.runAsync(track.clearSection);
    await tester.pump();
    expect(mark, findsNothing);
    track.dispose();
  });
}
