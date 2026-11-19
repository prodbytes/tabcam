import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/backing_track.dart';
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

  /// A track with a recording of a capture's own loaded, paused.
  Future<(BackingTrack, CaptureEvent)> loaded(
    WidgetTester tester, {
    Library? library,
    ValueListenable<bool>? recording,
  }) async {
    final lib =
        library ?? Library(PlatformEventStore(), null, (_) async => null);
    late CaptureEvent event;
    await tester.runAsync(() async {
      if (library == null) await lib.load();
      event = await lib.addMedia(await lib.create(const []), [
        Media(
          XFile.fromData(Uint8List.fromList([1]), name: 'riff.m4a'),
          PageKind.audio,
          'm4a',
        ),
      ]);
    });
    final track = BackingTrack(
      lib,
      recording: recording ?? ValueNotifier(false),
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
    return (track, event);
  }

  testWidgets('play waits two seconds in silence first, then plays', (
    tester,
  ) async {
    final (track, _) = await loaded(tester);
    expect(track.countIn, isTrue);

    await track.toggle();
    expect(track.countingIn, isTrue);
    expect(track.playing, isFalse);
    expect(video.playing, isEmpty);

    await tester.pump(const Duration(milliseconds: 1900));
    expect(video.playing, isEmpty);
    await tester.pump(const Duration(milliseconds: 100));
    expect(track.countingIn, isFalse);
    expect(track.playing, isTrue);
    expect(video.playing, hasLength(1));

    // Playing, a press pauses at once.
    await track.toggle();
    expect(track.playing, isFalse);
    track.dispose();
  });

  testWidgets('play pressed again, Pause or Stop while it counts in: it '
      "doesn't play", (tester) async {
    final (track, _) = await loaded(tester);
    for (final cancel in [track.toggle, track.pause, track.stop]) {
      await track.toggle();
      expect(track.countingIn, isTrue);
      await cancel();
      expect(track.countingIn, isFalse);
      await tester.pump(const Duration(seconds: 3));
      expect(track.playing, isFalse);
      expect(video.playing, isEmpty);
    }
    track.dispose();
  });

  testWidgets('off, play plays at once (and a count-in under way plays '
      'now); kept on the device for the next player', (tester) async {
    final (track, _) = await loaded(tester);
    await track.toggle();
    expect(track.countingIn, isTrue);
    await tester.runAsync(() => track.setCountIn(false));
    expect(track.countingIn, isFalse);
    expect(track.playing, isTrue);
    await track.toggle();
    await track.toggle();
    expect(track.playing, isTrue);
    track.dispose();

    final (next, _) = await loaded(tester, library: track.library);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    expect(next.countIn, isFalse);
    next.dispose();
  });

  testWidgets('the progress bar\'s line starts with the count-in: its '
      'button, then its seconds in amber, counting down while it counts '
      'in; off, the seconds go', (tester) async {
    final (track, event) = await loaded(tester);
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
                onToggle: track.toggle,
                onStop: () {},
                onSkip: (_) {},
                onRepeat: () {},
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
    final countIn = find.byKey(const Key('cam-along-count-in'));
    final progress = find.byType(VideoProgressIndicator);
    final seconds = find.byKey(const Key('cam-along-count-in-seconds'));
    // On one line, before the progress bar.
    expect(
      tester.getCenter(countIn).dy,
      closeTo(tester.getCenter(progress).dy, 1),
    );
    expect(
      tester.getTopRight(countIn).dx,
      lessThanOrEqualTo(tester.getTopLeft(progress).dx),
    );
    expect(tester.widget<Text>(seconds).data, '2s');
    expect(
      tester.widget<Text>(seconds).style!.color!.toARGB32(),
      Colors.amber.withValues(alpha: 0.7).toARGB32(),
    );
    LinearProgressIndicator bar() =>
        tester.widget(find.byKey(const Key('cam-along-count-in-bar')));
    expect(bar().value, 0);
    expect(bar().color, Colors.amber);

    await tester.tap(find.byKey(const Key('cam-along-toggle')));
    await tester.pump();
    // Pause, to stop the count-in.
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<Text>(seconds).data, '2s');
    expect(bar().value, closeTo(0.25, 0.01));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.widget<Text>(seconds).data, '1s');
    await tester.pump(const Duration(milliseconds: 1000));
    expect(track.playing, isTrue);
    expect(bar().value, 0);

    await tester.tap(find.byKey(const Key('cam-along-count-in-toggle')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    expect(track.countIn, isFalse);
    expect(seconds, findsNothing);
    expect(find.byIcon(Icons.timer_off_outlined), findsOneWidget);
    await track.pause();
    track.dispose();
  });

  testWidgets('0 while it plays or counts in: back to the start, counting '
      'in again before it plays; paused, it stays paused there', (
    tester,
  ) async {
    final (track, _) = await loaded(tester);
    // Paused: back to the start, still paused, with no count-in.
    await track.restart();
    expect(video.seeks.last, Duration.zero);
    expect(track.countingIn, isFalse);
    await tester.pump(const Duration(seconds: 3));
    expect(track.playing, isFalse);

    // Playing: silent at the start while it counts in, then it plays.
    await track.toggle();
    await tester.pump(BackingTrack.countInLength);
    expect(track.playing, isTrue);
    final run = track.countInRun;
    video.seeks.clear();
    await track.restart();
    expect(video.seeks, const [Duration.zero]);
    expect(track.countingIn, isTrue);
    expect(track.countInRun, run + 1);
    expect(video.playing, isEmpty);
    await tester.pump(BackingTrack.countInLength);
    expect(track.countingIn, isFalse);
    expect(track.playing, isTrue);

    // Counting in: the count starts over.
    await track.toggle();
    await track.toggle();
    expect(track.countingIn, isTrue);
    await tester.pump(const Duration(milliseconds: 1500));
    await track.restart();
    expect(track.countingIn, isTrue);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(track.playing, isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    expect(track.playing, isTrue);

    // With the count-in off, it plays on from the start.
    await tester.runAsync(() => track.setCountIn(false));
    video.seeks.clear();
    await track.restart();
    expect(video.seeks, const [Duration.zero]);
    expect(track.countingIn, isFalse);
    expect(track.playing, isTrue);
    await track.pause();
    track.dispose();
  });

  testWidgets('space starts the count-in', (tester) async {
    final (track, _) = await loaded(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayAlongKeys(
          track: track,
          child: const SizedBox(
            key: Key('sidebar'),
            width: 200,
            height: 200,
            child: ColoredBox(color: Colors.black),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('sidebar')));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(track.countingIn, isTrue);
    await tester.pump(BackingTrack.countInLength);
    expect(track.playing, isTrue);
    await track.pause();
    track.dispose();
  });

  testWidgets('← and → skip 10 seconds back and on, as « and »; held, '
      'again and again', (tester) async {
    final (track, _) = await loaded(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayAlongKeys(
          track: track,
          child: const SizedBox(
            key: Key('sidebar'),
            width: 200,
            height: 200,
            child: ColoredBox(color: Colors.black),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('sidebar')));
    video.seeks.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(video.seeks, [const Duration(seconds: 10)]);
    // Held: the repeats skip too.
    video.seeks.clear();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(video.seeks, const [
      Duration(seconds: 20),
      Duration(seconds: 30),
    ]);
    video.seeks.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(video.seeks, const [Duration(seconds: 20)]);
    // Alt + ← is the browser's Back, left to it.
    video.seeks.clear();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(video.seeks, isEmpty);
    track.dispose();
  });

  testWidgets('while a take records it always counts in, the count-in off '
      'or not; the take over, off plays at once again', (tester) async {
    final recording = ValueNotifier(false);
    final (track, _) = await loaded(tester, recording: recording);
    await tester.runAsync(() => track.setCountIn(false));
    expect(track.countsIn, isFalse);

    recording.value = true;
    expect(track.countsIn, isTrue);
    await track.toggle();
    expect(track.countingIn, isTrue);
    expect(video.playing, isEmpty);
    // Switching it off doesn't cut a take's count-in short.
    await tester.runAsync(() => track.setCountIn(false));
    expect(track.countingIn, isTrue);
    await tester.pump(BackingTrack.countInLength);
    expect(track.playing, isTrue);
    await track.pause();

    recording.value = false;
    await track.toggle();
    expect(track.countingIn, isFalse);
    expect(track.playing, isTrue);
    await track.pause();
    track.dispose();
  });

  testWidgets('a take starting counts in afresh: one under way counts from '
      'now again; playing already, it plays on', (tester) async {
    final recording = ValueNotifier(false);
    final (track, _) = await loaded(tester, recording: recording);
    await track.toggle();
    await tester.pump(const Duration(milliseconds: 1500));
    recording.value = true;
    await track.playWithTake();
    expect(track.countingIn, isTrue);
    await tester.pump(const Duration(milliseconds: 1900));
    expect(video.playing, isEmpty);
    await tester.pump(const Duration(milliseconds: 100));
    expect(track.playing, isTrue);

    final run = track.countInRun;
    await track.playWithTake();
    expect(track.countInRun, run);
    expect(track.playing, isTrue);
    await track.pause();
    track.dispose();
  });

  testWidgets('Repeat starts it over after a count-in too: the player\'s '
      'own looping off meanwhile, at the file\'s end and a section\'s; with '
      'the count-in off it starts over at once, the player looping', (
    tester,
  ) async {
    final recording = ValueNotifier(false);
    final (track, _) = await loaded(tester, recording: recording);
    final player = video.lastPlayer;
    expect(track.repeat, isTrue);
    expect(video.looping[player], isFalse);
    // Its end watched on the test's clock (it was opened on the real one).
    await track.setRepeat(true);

    await track.toggle();
    await tester.pump(BackingTrack.countInLength);
    expect(track.playing, isTrue);
    // The file's end: a breath, then from its start.
    video.seeks.clear();
    // (Its events come on the real clock, as it was opened there.)
    await tester.runAsync(() async {
      video.complete(player);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 200));
    expect(video.seeks.last, Duration.zero);
    expect(track.countingIn, isTrue);
    expect(video.playing, isEmpty);
    await tester.pump(BackingTrack.countInLength);
    expect(track.playing, isTrue);

    // A section's end, the same.
    await track.setSection(
      const Duration(seconds: 10),
      const Duration(seconds: 20),
    );
    video.position = const Duration(seconds: 15);
    await tester.pump(const Duration(milliseconds: 200));
    video.seeks.clear();
    video.position = const Duration(seconds: 20);
    await tester.pump(const Duration(milliseconds: 200));
    expect(video.seeks, [const Duration(seconds: 10)]);
    video.position = const Duration(seconds: 10); // the seek landed
    expect(track.countingIn, isTrue);
    expect(video.playing, isEmpty);
    await tester.pump(BackingTrack.countInLength);
    expect(track.playing, isTrue);
    await track.clearSection();

    // Off: the player loops by itself, at once; a take recording, it
    // counts in again.
    await tester.runAsync(() => track.setCountIn(false));
    expect(video.looping[player], isTrue);
    recording.value = true;
    await tester.pump();
    expect(video.looping[player], isFalse);
    recording.value = false;
    await tester.pump();
    expect(video.looping[player], isTrue);
    await track.pause();
    track.dispose();
  });
}
