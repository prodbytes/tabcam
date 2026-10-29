import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
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

  /// A track with a capture's two recordings, the first loaded, paused.
  Future<(BackingTrack, CaptureEvent)> loaded(WidgetTester tester) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late CaptureEvent event;
    await tester.runAsync(() async {
      await library.load();
      event = await library.create(const []);
      event = await library.addMedia(event, [
        for (final name in ['riff.m4a', 'lick.m4a'])
          Media(
            XFile.fromData(Uint8List.fromList([1]), name: name),
            PageKind.audio,
            'm4a',
          ),
      ]);
    });
    final track = BackingTrack(
      library,
      open: (_, _, page) async {
        final media = VideoPlayerController.networkUrl(
          Uri.parse('https://example.com/${page.fileName}'),
        );
        await media.initialize();
        return media;
      },
    );
    await tester.runAsync(
      () => track.choose(event, event.pages.first, play: false),
    );
    await tester.pump();
    return (track, event);
  }

  testWidgets('the speed reaches the player, is kept within its bounds '
      'and for the next file', (tester) async {
    final (track, event) = await loaded(tester);
    expect(track.speed, 1);
    expect(video.speeds, isEmpty);

    await tester.runAsync(() => track.setSpeed(0.75));
    expect(track.speed, 0.75);
    // The player applies a speed once it plays (iOS would start playing).
    await tester.runAsync(() => track.toggle());
    expect(video.speeds.values.last, 0.75);

    await tester.runAsync(() => track.setSpeed(0.1));
    expect(track.speed, BackingTrack.minSpeed);
    await tester.runAsync(() => track.setSpeed(3));
    expect(track.speed, BackingTrack.maxSpeed);

    // The next file plays at the same speed.
    await tester.runAsync(() => track.setSpeed(0.5));
    video.speeds.clear();
    await tester.runAsync(() => track.choose(event, event.pages.last));
    expect(track.speed, 0.5);
    expect(video.speeds.values.last, 0.5);
    track.dispose();
  });

  testWidgets('the sidebar shows the speed under the section: the slider '
      'and the speed, which goes back to 1× tapped', (tester) async {
    final (track, event) = await loaded(tester);
    final calls = <double>[];
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
                onSection: (_, _) {},
                onSectionHere: ({required bool end}) {},
                onSectionClear: () {},
                onSpeed: (speed) {
                  calls.add(speed);
                  track.setSpeed(speed);
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('cam-along-speed')), findsOneWidget);
    expect(find.text('1×'), findsOneWidget);
    // Under the section.
    final section = tester.getBottomLeft(
      find.byKey(const Key('cam-along-section')),
    );
    final speed = tester.getTopLeft(find.byKey(const Key('cam-along-speed')));
    expect(speed.dy, greaterThanOrEqualTo(section.dy));

    // Dragging the slider left slows it down.
    final slider = find.byKey(const Key('cam-along-speed-slider'));
    await tester.drag(slider, const Offset(-40, 0), warnIfMissed: false);
    await tester.pump();
    expect(calls, isNotEmpty);
    expect(track.speed, lessThan(1));
    expect(find.text('1×'), findsNothing);

    await tester.runAsync(() => track.setSpeed(0.75));
    await tester.pump();
    expect(find.text('0.75×'), findsOneWidget);

    // A tap on the speed goes back to normal.
    await tester.tap(find.byKey(const Key('cam-along-speed-label')));
    await tester.pump();
    expect(calls.last, 1);
    expect(find.text('1×'), findsOneWidget);
    track.dispose();
  });
}
