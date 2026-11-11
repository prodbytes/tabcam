import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/video_edit.dart';
import 'package:tabcam_app/export/download.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/file_screen.dart';
import 'package:tabcam_app/screens/video_edit_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'mini_player_test.dart' show FakeVideoPlatform;

/// An editor that records what it's asked and hands back a small file in
/// [formatsHere] (MP4 and M4A, as the phones and most browsers make).
class FakeEditor implements VideoEditing {
  FakeEditor([this.formatsHere = EditFormats.standard]);

  final EditFormats formatsHere;
  final rendered = <RenderPlan>[];

  /// The length it finds, where the player can't say (none: the phones'
  /// editors), and how many times it was asked.
  Duration? lengthHere;
  var lengthsAsked = 0;

  @override
  Future<Duration?> length(XFile file) async {
    lengthsAsked++;
    return lengthHere;
  }

  @override
  Future<EditFormats> formats() async => formatsHere;

  @override
  Future<XFile> render(
    RenderPlan plan, {
    void Function(double done)? onProgress,
  }) async {
    rendered.add(plan);
    onProgress?.call(0.5);
    final format = plan.format;
    return XFile.fromData(
      Uint8List.fromList([9, 9, 9]),
      name: '${plan.video ? 'edit' : 'sound'}.${format.extension}',
      mimeType: format.mimeType,
    );
  }
}

/// The fake platform, with each player's volume, and each pause.
class VolumePlatform extends FakeVideoPlatform {
  final volumes = <int, double>{};
  final paused = <int>[];

  @override
  Future<void> pause(int playerId) {
    paused.add(playerId);
    return super.pause(playerId);
  }

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      volumes[playerId] = volume;
}

/// The fake platform, where the players in [unknown] can't say how long
/// their file is (the browser, for a take it recorded: video_player_web's
/// unset duration).
class UnknownLengthPlatform extends VolumePlatform {
  UnknownLengthPlatform(this.unknown);

  final Set<int> unknown;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => unknown.contains(playerId)
      ? Stream.value(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(milliseconds: -9007199254740991),
            size: const Size(320, 240),
          ),
        )
      : super.videoEventsFor(playerId);
}

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => '/tmp/tabcam-test';
}

Duration s(double seconds) => Duration(milliseconds: (seconds * 1000).round());

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets the screens' players open (they do, off the test clock).
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await _frames(tester);
}

void main() {
  group('trackSpan', () {
    test('a track starting with the clip, cut to the clip', () {
      expect(trackSpan(s(10), s(4), Duration.zero), (
        gap: Duration.zero,
        from: Duration.zero,
        to: s(4),
      ));
      expect(trackSpan(s(10), s(20), Duration.zero), (
        gap: Duration.zero,
        from: Duration.zero,
        to: s(10),
      ));
    });

    test('a track starting later: silence first, then what fits', () {
      expect(trackSpan(s(10), s(4), s(3)), (
        gap: s(3),
        from: Duration.zero,
        to: s(4),
      ));
      expect(trackSpan(s(10), s(4), s(8)), (
        gap: s(8),
        from: Duration.zero,
        to: s(2),
      ));
    });

    test('a track starting earlier: its start is cut', () {
      expect(trackSpan(s(10), s(4), s(-1)), (
        gap: Duration.zero,
        from: s(1),
        to: s(4),
      ));
      expect(trackSpan(s(2), s(4), s(-1)), (
        gap: Duration.zero,
        from: s(1),
        to: s(3),
      ));
    });

    test('a track outside the clip is nothing', () {
      expect(trackSpan(s(10), s(4), s(10)), isNull);
      expect(trackSpan(s(10), s(4), s(-4)), isNull);
      expect(trackSpan(Duration.zero, s(4), Duration.zero), isNull);
      expect(trackSpan(s(10), Duration.zero, Duration.zero), isNull);
    });

    test('a track trimmed: its used part, where it starts', () {
      // 1–3 s of the track, starting 2 s into the clip.
      expect(trackSpan(s(10), s(4), s(2), trackStart: s(1), trackEnd: s(3)), (
        gap: s(2),
        from: s(1),
        to: s(3),
      ));
      // Starting before the clip: more of its start cut.
      expect(
        trackSpan(s(10), s(4), s(-0.5), trackStart: s(1), trackEnd: s(3)),
        (gap: Duration.zero, from: s(1.5), to: s(3)),
      );
      // Cut to the clip; an end past the track's is the track's.
      expect(
        trackSpan(s(2), s(4), Duration.zero, trackStart: s(1), trackEnd: s(9)),
        (gap: Duration.zero, from: s(1), to: s(3)),
      );
      // Nothing of the used part in the clip.
      expect(
        trackSpan(s(10), s(4), s(-3), trackStart: s(1), trackEnd: s(3)),
        isNull,
      );
    });
  });

  group('a kept edit', () {
    test('goes to JSON and back with its video page', () {
      final edit = PageEdit.fromSound(
        start: s(1),
        end: s(6),
        sound: EditSound.track,
        trackId: 'k1',
        trackStart: s(2),
        trackEnd: s(9),
        offset: s(-0.5),
      );
      final page = EventPage(
        id: 'k0',
        kind: PageKind.video,
        extension: 'mp4',
        edit: edit,
      );
      final back = EventPage.fromJson(
        jsonDecode(jsonEncode(page.toJson())) as Map<String, Object?>,
      );
      expect(back.edit, edit);
      // Cleared.
      expect(
        page.copyWith(edit: () => null).toJson().containsKey('edit'),
        isFalse,
      );
      // A trim alone keeps only what it needs.
      expect(PageEdit(start: s(1), end: s(2)).toJson(), {
        'v': 2,
        'startMs': 1000,
        'endMs': 2000,
        'sound': 'original',
      });
    });

    test('keeps its track\'s volume: in JSON only when not as it is, read '
        'defensively, through a clone and in ==', () {
      final edit = PageEdit.fromSound(
        start: s(1),
        end: s(6),
        sound: EditSound.track,
        trackId: 'k1',
        trackVolume: 0.4,
      );
      expect(edit.toJson()['trackVolume'], 0.4);
      expect(PageEdit.fromJson(jsonDecode(jsonEncode(edit.toJson()))), edit);
      expect(edit, isNot(edit.copyWith(trackVolume: 1)));
      expect(
        edit.copyWith(trackVolume: 1).toJson().containsKey('trackVolume'),
        false,
      );
      expect(edit.copyWith(trackId: 'k9').trackVolume, 0.4);
      expect(edit.copyWith(trackVolume: 0.4), edit);
      // As it is, by default: an older edit has none.
      expect(PageEdit(start: s(1), end: s(2)).trackVolume, 1);
      expect(PageEdit.fromJson({'startMs': 0, 'endMs': 1000})!.trackVolume, 1);
      // Anything else: within 0–1, to the hundredth, or as it is.
      for (final (json, volume) in [
        ('loud', 1.0),
        (null, 1.0),
        (2.5, 1.0),
        (-1, 0.0),
        (0.333, 0.33),
        (0, 0.0),
      ]) {
        expect(
          PageEdit.fromJson({'startMs': 0, 'endMs': 1000, 'trackVolume': json})!
              .trackVolume,
          volume,
          reason: '$json',
        );
      }
    });

    test(
      'the phones\' editor gets the plan, and reports its progress',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        PathProviderPlatform.instance = _Paths();
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(ChannelVideoEditor.channel, (
          c,
        ) async {
          calls.add(c);
          final args = c.arguments as Map;
          // The platform reports how far along it is, by job.
          if (args['job'] != null) {
            await messenger.handlePlatformMessage(
              ChannelVideoEditor.channel.name,
              const StandardMethodCodec().encodeMethodCall(
                MethodCall('progress', {'job': args['job'], 'done': 0.4}),
              ),
              (_) {},
            );
          }
          return args['output'];
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(ChannelVideoEditor.channel, null);
          ChannelVideoEditor.reset();
        });
        final edit = PageEdit.fromSound(
          start: s(1),
          end: s(5),
          sound: EditSound.track,
          trackId: 'k1',
          offset: s(-2),
          trackVolume: 0.35,
        );
        RenderPlan plan(RenderKind kind) => RenderPlan.of(
          edit,
          input: XFile('/tmp/take.mp4'),
          duration: s(10),
          songFile: XFile('/tmp/riff.m4a'),
          songLength: s(10),
          kind: kind,
        );
        final progress = <double>[];
        final video = await const ChannelVideoEditor().render(
          plan(RenderKind.video),
          onProgress: progress.add,
        );
        final sound = await const ChannelVideoEditor().render(
          plan(RenderKind.sound),
        );
        await const ChannelVideoEditor().render(plan(RenderKind.silent));
        expect(calls.map((c) => c.method).toSet(), {'render'});
        final args = [for (final c in calls) c.arguments as Map];
        expect(args[0]['input'], '/tmp/take.mp4');
        expect(args[0]['video'], isTrue);
        expect(args[0]['startMs'], 1000);
        expect(args[0]['endMs'], 5000);
        expect(args[0].containsKey('own'), isFalse);
        expect(args[0]['song'], {
          'path': '/tmp/riff.m4a',
          'volume': 0.35,
          'clips': [
            {'atMs': 0, 'fromMs': 2000, 'toMs': 6000, 'speed': 1.0},
          ],
        });
        expect(progress, [0.4]);
        expect(video.path, endsWith('.mp4'));
        expect(video.mimeType, 'video/mp4');
        // The sound alone: no picture, an M4A; no job without a listener.
        expect(args[1]['video'], isFalse);
        expect(args[1].containsKey('job'), isFalse);
        expect(sound.path, endsWith('.m4a'));
        expect(sound.mimeType, 'audio/mp4');
        // Without sound: neither lane.
        expect(args[2].containsKey('own'), isFalse);
        expect(args[2].containsKey('song'), isFalse);
        // Its own sound, as it is.
        await const ChannelVideoEditor().render(
          RenderPlan.of(
            PageEdit(start: Duration.zero, end: s(4)),
            input: XFile('/tmp/take.mp4'),
          ),
        );
        expect((calls.last.arguments as Map)['own'], {'volume': 1.0});
        // Nothing to make: no sound to save, or a song with no file.
        await expectLater(
          const ChannelVideoEditor().render(
            RenderPlan.of(
              PageEdit.fromSound(
                start: Duration.zero,
                end: s(4),
                sound: EditSound.none,
              ),
              input: XFile('/tmp/take.mp4'),
              kind: RenderKind.sound,
            ),
          ),
          throwsArgumentError,
        );
        await expectLater(
          const ChannelVideoEditor().render(
            RenderPlan.of(
              edit,
              input: XFile('/tmp/take.mp4'),
              songLength: s(10),
            ),
          ),
          throwsArgumentError,
        );
        expect(calls, hasLength(4));
      },
    );

    test('broken or on a page that\'s not a video, is none', () {
      expect(PageEdit.fromJson({'startMs': 5000, 'endMs': 1000}), isNull);
      expect(PageEdit.fromJson('cut'), isNull);
      expect(
        EventPage.fromJson({
          'id': 'k1',
          'kind': 'audio',
          'extension': 'm4a',
          'edit': {'startMs': 0, 'endMs': 1000},
        }).edit,
        isNull,
      );
    });
  });

  test('wavBytes: a 16-bit PCM WAV of the samples', () {
    final wav = wavBytes([
      Float32List.fromList([0, 1, -1]),
      Float32List.fromList([0.5, 0, 2]),
    ], 8000);
    final data = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 16)), 'WAVEfmt ');
    expect(data.getUint16(22, Endian.little), 2);
    expect(data.getUint32(24, Endian.little), 8000);
    expect(data.getUint32(40, Endian.little), 12);
    expect(wav.length, 44 + 12);
    expect(
      [for (var i = 0; i < 6; i++) data.getInt16(44 + i * 2, Endian.little)],
      [0, 16384, 32767, 0, -32768, 32767],
    );
  });

  late VolumePlatform platform;
  late FakeEditor editor;
  final saved = <(String, Uint8List, String)>[];
  setUp(() {
    VideoPlayerPlatform.instance = platform = VolumePlatform();
    VideoEditor.instance = editor = FakeEditor();
    saved.clear();
    Downloads.save = (name, bytes, type) async {
      saved.add((name, bytes, type));
      return true;
    };
  });
  tearDown(() => VideoEditor.instance = null);

  /// A capture with a video (k0, a [video] file; one of Cam's takes when
  /// [editTake]), a recording (k1) and an image (k2); [withTake]: another
  /// video (k3) and a take (k4) too.
  Future<(Library, String)> capture(
    WidgetTester tester, {
    String video = 'mp4',
    bool editTake = false,
    bool withTake = false,
  }) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late String id;
    await tester.runAsync(() async {
      await library.load();
      var event = await library.create(const []);
      for (final (i, (kind, ext)) in [
        (PageKind.video, video),
        (PageKind.audio, 'm4a'),
        (PageKind.image, 'jpg'),
        if (withTake) ...[(PageKind.video, 'mp4'), (PageKind.video, 'mp4')],
      ].indexed) {
        final page = EventPage(
          id: 'k$i',
          kind: kind,
          extension: ext,
          title: i == 0 ? 'Made-up riff' : null,
          take: (i == 0 && editTake) || i == 4,
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

  /// A tall phone, so the edit screen's controls are all on it.
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget host(Widget home) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  Widget editScreen(
    Library library,
    String id, {
    Future<XFile?> Function()? pick,
  }) => host(
    VideoEditScreen(
      library: library,
      eventId: id,
      page: library.byId(id)!.pages.first,
      pickFile: pick ?? () async => null,
    ),
  );

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<ButtonStyleButton>(find.byKey(Key(key))).enabled;

  testWidgets('Edit is a video\'s tool, not an image\'s; it opens the '
      'editor with the whole video kept and nothing to reset', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.pumpWidget(
      host(
        FileScreen(
          key: const Key('k2'),
          library: library,
          eventId: id,
          pageId: 'k2',
        ),
      ),
    );
    await _settle(tester);
    expect(find.byKey(const Key('edit-video')), findsNothing);

    await tester.pumpWidget(
      host(
        FileScreen(
          key: const Key('k0'),
          library: library,
          eventId: id,
          pageId: 'k0',
        ),
      ),
    );
    await _settle(tester);
    expect(find.byKey(const Key('edit-video')), findsOneWidget);
    await tester.tap(find.byKey(const Key('edit-video')));
    await _settle(tester);
    expect(find.byType(VideoEditScreen), findsOneWidget);
    expect(find.text('Made-up riff'), findsOneWidget);
    expect(find.text('Keep 0:00.0–3:00.0'), findsOneWidget);
    expect(enabled(tester, 'video-edit-reset'), isFalse);
    expect(enabled(tester, 'video-edit-download'), isTrue);
    expect(find.byKey(const Key('video-edit-save')), findsNothing);
    // Nothing plays until asked; no play button over the frame, only the
    // one under it.
    expect(platform.playing, isEmpty);
    expect(find.byIcon(Icons.play_circle_fill), findsNothing);
    expect(find.byKey(const Key('video-edit-play')), findsOneWidget);

    // Back goes to the file, as it was.
    await tester.pageBack();
    await _settle(tester);
    expect(find.byType(VideoEditScreen), findsNothing);
    expect(find.byType(FileScreen), findsOneWidget);
    final page = library.byId(id)!.pages.first;
    expect(page.id, 'k0');
    expect(page.edit, isNull);
  });

  testWidgets('End here trims to where the preview is, kept with the video '
      'at once, without making a file; Download makes one of it', (
    tester,
  ) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);

    // The preview is 12 s in (the fake's position).
    await tester.tap(find.byKey(const Key('video-edit-end-here')));
    await _settle(tester);
    expect(find.text('Keep 0:00.0–0:12.0'), findsOneWidget);
    final page = library.byId(id)!.pages.first;
    expect(page.id, 'k0');
    expect(page.edit, PageEdit(start: Duration.zero, end: s(12)));
    expect(editor.rendered, isEmpty);
    expect(enabled(tester, 'video-edit-reset'), isTrue);

    // Download: the video, as edited, made on the device.
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    final plan = editor.rendered.single;
    expect(await tester.runAsync(plan.input!.readAsBytes), [1, 2, 3]);
    expect(plan.start, Duration.zero);
    expect(plan.end, s(12));
    expect(plan.duration, s(180));
    expect(plan.own, const OwnLane());
    expect(plan.song, isNull);
    expect(plan.video, isTrue);
    expect(plan.format, EditFormat.mp4);
    expect(plan.passthrough, isFalse);
    final (name, bytes, type) = saved.single;
    expect(name, 'Made-up riff.mp4');
    expect(bytes, [9, 9, 9]);
    expect(type, 'video/mp4');
    // The video's own file is as it was.
    expect(library.byId(id)!.pages.first.extension, 'mp4');

    // Reset: the whole video again, no edit kept.
    await tester.tap(find.byKey(const Key('video-edit-reset')));
    await _settle(tester);
    expect(find.text('Keep 0:00.0–3:00.0'), findsOneWidget);
    expect(library.byId(id)!.pages.first.edit, isNull);
  });

  testWidgets('a video as it is downloads as it is', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    expect(editor.rendered, isEmpty);
    final (name, bytes, _) = saved.single;
    expect(name, 'Made-up riff.mp4');
    expect(bytes, [1, 2, 3]);
  });

  testWidgets('two lanes, mixed: the video\'s own sound and a track picked '
      'from the capture\'s recordings, videos and takes, moved along the '
      'video; Download has both, its menu the video without sound and the '
      'sound alone', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester, withTake: true);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);

    // A video that isn't a take: its lanes are its sound and a track. No
    // sound choice and no trim section: the lanes are the edit.
    expect(find.text('Video sound'), findsOneWidget);
    expect(find.text('Add a track'), findsOneWidget);
    expect(find.byKey(const Key('video-edit-take-volume')), findsOneWidget);
    expect(find.byKey(const Key('video-edit-song-volume')), findsNothing);
    expect(find.byKey(const Key('video-edit-ruler')), findsOneWidget);
    expect(find.byKey(const Key('video-edit-sound')), findsNothing);
    expect(find.byKey(const Key('video-edit-range')), findsNothing);

    // The sheet lists the recording, the other video and the take (not
    // the image, nor the video edited), and a sound file.
    await tester.tap(find.byKey(const Key('video-edit-song-add')));
    await _settle(tester);
    expect(find.byKey(const Key('video-edit-tracks')), findsOneWidget);
    expect(find.byKey(const Key('video-edit-track-k1')), findsOneWidget);
    expect(find.byKey(const Key('video-edit-track-k3')), findsOneWidget);
    expect(find.byKey(const Key('video-edit-track-k4')), findsOneWidget);
    expect(find.byKey(const Key('video-edit-track-k2')), findsNothing);
    expect(find.byKey(const Key('video-edit-track-k0')), findsNothing);
    expect(find.byKey(const Key('video-edit-track-file')), findsOneWidget);
    await tester.tap(find.byKey(const Key('video-edit-track-k1')));
    await _settle(tester);
    expect(find.byKey(const Key('video-edit-tracks')), findsNothing);
    // Its name: on its bar, and in its details under the lanes.
    expect(find.text('Recording 1'), findsNWidgets(2));
    expect(find.text('The track starts with the video'), findsOneWidget);

    // A volume at the left of each lane's bar; the bars on one time axis.
    Rect rect(String key) => tester.getRect(find.byKey(Key(key)));
    final takeBar = rect('video-edit-take-bar');
    final songBar = rect('video-edit-song-bar');
    expect(
      rect('video-edit-take-volume').right,
      lessThanOrEqualTo(takeBar.left),
    );
    expect(
      rect('video-edit-song-volume').right,
      lessThanOrEqualTo(songBar.left),
    );
    expect(
      rect('video-edit-take-volume').center.dy,
      closeTo(takeBar.center.dy, 1),
    );
    expect(
      rect('video-edit-song-volume').center.dy,
      closeTo(songBar.center.dy, 1),
    );
    expect(songBar.left, closeTo(takeBar.left, 0.5));
    expect(songBar.right, closeTo(takeBar.right, 0.5));
    expect(rect('video-edit-ruler').left, closeTo(takeBar.left, 0.5));
    expect(rect('video-edit-ruler').right, closeTo(takeBar.right, 0.5));

    // The track (3 minutes, as long as the video) along the whole video.
    // Dragged, it moves later; its start, dragged, trims it, and the rest
    // stays put: its end moves with it.
    final barWidth = songBar.width;
    await tester.drag(
      find.byKey(const Key('video-edit-song-move')),
      Offset(barWidth / 6, 0),
    );
    await _frames(tester);
    expect(find.textContaining('after the video'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('video-edit-song-left')),
      Offset(barWidth / 6, 0),
    );
    await _frames(tester);
    expect(find.byKey(const Key('video-edit-song-used')), findsOneWidget);
    // A tenth of a second earlier, twice.
    await tester.tap(find.byKey(const Key('video-edit-song-earlier')));
    await tester.tap(find.byKey(const Key('video-edit-song-earlier')));
    await _settle(tester);

    // Kept with the video: the recording by its ID, where it plays, both
    // lanes heard (older apps play the video's own sound then).
    final kept = library.byId(id)!.pages.first.edit!;
    expect(kept.song, SongMode.manual);
    expect(kept.trackId, 'k1');
    expect(kept.ownAudible, isTrue);
    expect(kept.songAudible, isTrue);
    expect(kept.toJson()['sound'], 'original');
    final dragged = kept.trackStart.inMilliseconds;
    // Moved about a sixth later (a drag loses its first few pixels to
    // the touch slop), then its start trimmed by the same drag, the
    // offset following, less two tenths.
    expect(dragged, inInclusiveRange(20000, 30000));
    expect(kept.trackEnd, isNull);
    expect(kept.offset.inMilliseconds, closeTo(2 * dragged - 200, 100));

    // Played: the video at its own volume, the track along it once it
    // comes in.
    platform.position = kept.offset + s(1);
    await tester.tap(find.byKey(const Key('video-edit-play')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await _frames(tester);
    expect(platform.volumes[0], 1);
    expect(platform.playing, containsAll([0, platform.lastPlayer]));
    await tester.tap(find.byKey(const Key('video-edit-play')));
    await _settle(tester);

    // Download: the video with both, mixed.
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    final plan = editor.rendered.single;
    expect(plan.own, const OwnLane());
    final song = plan.song!;
    expect(song.page, 'k1');
    expect(await tester.runAsync(song.file!.readAsBytes), [1, 2, 3]);
    expect(song.volume, 1);
    // One clip: from its shift, the track from its start, to the kept
    // part's end (the track's start, less the gap).
    expect(song.clips, [
      SongClip(
        at: kept.offset,
        from: kept.trackStart,
        to: kept.trackStart + (s(180) - kept.offset),
      ),
    ]);

    // The menu: without sound, and the sound alone.
    await tester.tap(find.byKey(const Key('video-edit-download-more')));
    await _frames(tester);
    await tester.tap(find.byKey(const Key('video-edit-download-silent')));
    await _settle(tester);
    // Without sound: the same video, neither lane.
    expect(editor.rendered[1].video, isTrue);
    expect(editor.rendered[1].own, isNull);
    expect(editor.rendered[1].song, isNull);
    expect(editor.rendered[1].end, plan.end);
    await tester.tap(find.byKey(const Key('video-edit-download-more')));
    await _frames(tester);
    await tester.tap(find.byKey(const Key('video-edit-download-sound')));
    await _settle(tester);
    // The sound alone: both lanes mixed, no picture.
    expect(editor.rendered[2].video, isFalse);
    expect(editor.rendered[2].own, const OwnLane());
    expect(editor.rendered[2].song, song);
    expect(editor.rendered[2].format, EditFormat.m4a);
    // Each as its format: the videos MP4, the sound alone M4A.
    expect(
      [for (final (name, _, type) in saved) (name, type)],
      [
        ('Made-up riff.mp4', 'video/mp4'),
        ('Made-up riff.mp4', 'video/mp4'),
        ('Made-up riff.m4a', 'audio/mp4'),
      ],
    );
  });

  testWidgets('Download\'s menu says each file\'s format: MP4 and M4A, or '
      'what the browser makes instead', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-download-more')));
    await _frames(tester);
    expect(find.text('The video (MP4)'), findsOneWidget);
    expect(find.text('The video without sound (MP4)'), findsOneWidget);
    expect(find.text('The sound only (M4A)'), findsOneWidget);

    // A browser that records WebM and can't make AAC (Firefox).
    VideoEditor.instance = FakeEditor(
      const EditFormats(video: EditFormat.webm, sound: EditFormat.wav),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-download-more')));
    await _frames(tester);
    expect(find.text('The video (WebM)'), findsOneWidget);
    expect(find.text('The video without sound (WebM)'), findsOneWidget);
    expect(find.text('The sound only (WAV)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('video-edit-download-sound')));
    await _settle(tester);
    final (name, _, type) = saved.single;
    expect(name, 'Made-up riff.wav');
    expect(type, 'audio/wav');
  });

  testWidgets('a video as it is, not in the format Download makes, is made '
      'again in it', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester, video: 'webm');
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    // Unchanged, but not in the format made: rendered, not passed through.
    final plan = editor.rendered.single;
    expect(plan.start, Duration.zero);
    expect(plan.end, s(180));
    expect(plan.own, const OwnLane());
    expect(plan.song, isNull);
    expect(plan.keepsFormat, isFalse);
    expect(plan.passthrough, isFalse);
    final (name, bytes, type) = saved.single;
    expect(name, 'Made-up riff.mp4');
    expect(bytes, [9, 9, 9]);
    expect(type, 'video/mp4');

    // Where the browser makes WebM, a WebM as it is downloads as it is.
    VideoEditor.instance = editor = FakeEditor(
      const EditFormats(video: EditFormat.webm, sound: EditFormat.wav),
    );
    saved.clear();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    expect(editor.rendered, isEmpty);
    expect(saved.single.$1, 'Made-up riff.webm');
    expect(saved.single.$2, [1, 2, 3]);
  });

  testWidgets('an MPEG-4 video as it is downloads as it is, even where the '
      'browser records WebM', (tester) async {
    tall(tester);
    // A browser that records WebM (Firefox): an MP4 isn't made again as a
    // WebM.
    VideoEditor.instance = editor = FakeEditor(
      const EditFormats(video: EditFormat.webm, sound: EditFormat.wav),
    );
    final (library, id) = await capture(tester);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    expect(editor.rendered, isEmpty);
    expect(saved.single.$1, 'Made-up riff.mp4');
    expect(saved.single.$2, [1, 2, 3]);

    // An M4V (MPEG-4 too), where MP4 is made: as it is, not made again.
    VideoEditor.instance = editor = FakeEditor();
    saved.clear();
    final (library2, id2) = await capture(tester, video: 'm4v');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(editScreen(library2, id2));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    expect(editor.rendered, isEmpty);
    expect(saved.single.$1, 'Made-up riff.m4v');
    expect(saved.single.$2, [1, 2, 3]);
  });

  testWidgets('a sound file picked as the track is added to the capture\'s '
      'files, and the edit names it', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    final picked = (await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('tabcam-track');
      addTearDown(() => dir.delete(recursive: true));
      return File('${dir.path}/Made-up backing.mp3')
        ..writeAsBytesSync([4, 5, 6]);
    }))!;
    await tester.pumpWidget(
      editScreen(
        library,
        id,
        pick: () async => XFile(picked.path, mimeType: 'audio/mpeg'),
      ),
    );
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-song-add')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-track-file')));
    // The file is read off the test clock.
    for (var i = 0; i < 5; i++) {
      await _settle(tester);
    }

    final event = library.byId(id)!;
    expect(event.pages, hasLength(4));
    final added = event.pages.last;
    expect(added.kind, PageKind.audio);
    expect(added.extension, 'mp3');
    expect(added.title, 'Made-up backing');
    expect(await tester.runAsync(() => library.original(event, added)), [
      4,
      5,
      6,
    ]);
    expect(event.pages.first.edit?.trackId, added.id);
    expect(find.text('Made-up backing'), findsNWidgets(2));
  });

  testWidgets('a kept edit opens as it was, its track too', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.runAsync(
      () => library.setPageEdit(
        id,
        'k0',
        PageEdit.fromSound(
          start: s(2),
          end: s(12),
          sound: EditSound.track,
          trackId: 'k1',
          offset: s(1.5),
        ),
      ),
    );
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    expect(find.text('Keep 0:02.0–0:12.0'), findsOneWidget);
    expect(find.text('Recording 1'), findsNWidgets(2));
    expect(
      find.text('The track starts 0:01.5 after the video'),
      findsOneWidget,
    );
    expect(enabled(tester, 'video-edit-reset'), isTrue);
  });

  testWidgets('an edit keeps the keys a newer app wrote: trimmed, reset, '
      'and downloaded as it is when they\'re all it has', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    const newer = {
      'nudgeMs': -120,
      'title': {
        'on': true,
        'lines': ['Blue Riff', 'Made-up Band'],
      },
    };
    await tester.runAsync(
      () => library.setPageEdit(
        id,
        'k0',
        PageEdit.fromJson({'startMs': 2000, 'endMs': 20000, ...newer}),
      ),
    );
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    expect(find.text('Keep 0:02.0–0:20.0'), findsOneWidget);

    await tester.tap(find.byKey(const Key('video-edit-end-here')));
    await _settle(tester);
    var edit = library.byId(id)!.pages.first.edit!;
    expect(edit.end, s(12));
    expect(edit.extra, newer);

    // Reset: the whole video, its own sound; the newer keys stay, so the
    // edit does, and the video downloads as it is.
    await tester.tap(find.byKey(const Key('video-edit-reset')));
    await _settle(tester);
    edit = library.byId(id)!.pages.first.edit!;
    expect((edit.start, edit.end), (Duration.zero, s(180)));
    expect(edit.extra, newer);
    expect(enabled(tester, 'video-edit-reset'), isFalse);
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    expect(editor.rendered, isEmpty);
    expect(saved.single.$2, [1, 2, 3]);
  });

  testWidgets('the file screen plays a video as its edit says: from the '
      'kept part\'s start, muted, its track along it', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.runAsync(
      () => library.setPageEdit(
        id,
        'k0',
        PageEdit.fromSound(
          start: s(10),
          end: s(20),
          sound: EditSound.track,
          trackId: 'k1',
        ),
      ),
    );
    await tester.pumpWidget(
      host(FileScreen(library: library, eventId: id, pageId: 'k0')),
    );
    await _settle(tester);
    await tester.tap(find.byIcon(Icons.play_circle_fill));
    await _settle(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await _frames(tester);
    // The video (the first player) and its track (the second).
    expect(platform.seeks, contains(s(10)));
    expect(platform.volumes[0], 0);
    expect(platform.playing, containsAll([0, 1]));
  });

  /// The file screen, playing [id]'s video as [edit] says, its track
  /// (the second player) not knowing its length.
  Future<void> playWithUnknownTrackLength(
    WidgetTester tester,
    Library library,
    String id,
    PageEdit edit,
  ) async {
    VideoPlayerPlatform.instance = platform = UnknownLengthPlatform({1});
    await tester.runAsync(() => library.setPageEdit(id, 'k0', edit));
    await tester.pumpWidget(
      host(FileScreen(library: library, eventId: id, pageId: 'k0')),
    );
    await _settle(tester);
    await tester.tap(find.byIcon(Icons.play_circle_fill));
    await _settle(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await _frames(tester);
  }

  testWidgets('the file screen plays a track whose player can\'t say how '
      'long it is: the editor\'s length, as in the editor', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    editor.lengthHere = s(40);
    await playWithUnknownTrackLength(
      tester,
      library,
      id,
      PageEdit.fromSound(
        start: s(10),
        end: s(20),
        sound: EditSound.track,
        trackId: 'k1',
      ),
    );
    expect(editor.lengthsAsked, 1);
    expect(platform.volumes[0], 0);
    expect(platform.playing, containsAll([0, 1]));
  });

  testWidgets('the file screen plays a track nothing can say the length of '
      'up to the end its edit keeps', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await playWithUnknownTrackLength(
      tester,
      library,
      id,
      PageEdit.fromSound(
        start: s(10),
        end: s(20),
        sound: EditSound.track,
        trackId: 'k1',
        trackEnd: s(30),
      ),
    );
    expect(editor.lengthsAsked, 1);
    expect(platform.playing, containsAll([0, 1]));
  });

  testWidgets('a cloned capture\'s video keeps its edit, naming the copy\'s '
      'track', (tester) async {
    final (library, id) = await capture(tester);
    final copy = await tester.runAsync(() async {
      await library.setPageEdit(
        id,
        'k0',
        PageEdit.fromSound(
          start: s(1),
          end: s(2),
          sound: EditSound.track,
          trackId: 'k1',
        ),
      );
      return library.clone(library.byId(id)!);
    });
    final edit = copy!.pages.first.edit!;
    expect(edit.start, s(1));
    expect(edit.trackId, copy.pages[1].id);
    expect(edit.trackId, isNot('k1'));
  });

  testWidgets('the current time shows beside the preview\'s progress', (
    tester,
  ) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    expect(find.byKey(const Key('video-edit-time')), findsOneWidget);
    expect(find.text('0:00.0'), findsOneWidget);
    // Played, the player says where it is (12 s in, the fake's position).
    await tester.tap(find.byKey(const Key('video-edit-play')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 700)),
    );
    await _frames(tester);
    expect(find.text('0:12.0'), findsOneWidget);
  });

  testWidgets('a take\'s lanes are Take and Song; its own sound\'s volume '
      'and Mute are kept with the edit (muted, its level too, across a '
      'reopen) and played; muting both lanes turns Sound only off', (
    tester,
  ) async {
    tall(tester);
    final (library, id) = await capture(tester, editTake: true);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    expect(find.text('Take'), findsOneWidget);
    expect(find.text('Add a song'), findsOneWidget);
    expect(find.text('Video sound'), findsNothing);

    Future<bool> soundOnly() async {
      await tester.tap(find.byKey(const Key('video-edit-download-more')));
      await _frames(tester);
      final on =
          tester
              .widget<MenuItemButton>(
                find.byKey(const Key('video-edit-download-sound')),
              )
              .onPressed !=
          null;
      await tester.tap(find.byKey(const Key('video-edit-download-more')));
      await _frames(tester);
      return on;
    }

    PageEdit? edit() => library.byId(id)!.pages.first.edit;

    // At 60%: kept, and the preview plays the video at it.
    await tester.tap(find.byKey(const Key('video-edit-take-volume')));
    await _frames(tester);
    final slider = find.byKey(const Key('video-edit-take-volume-slider'));
    tester.widget<Slider>(slider).onChanged!(60);
    await _settle(tester);
    expect(platform.volumes[0], 0.6);
    expect(edit()!.ownVolume, 0.6);
    expect(edit()!.ownMuted, isFalse);

    // Muted: silent, its level kept; nothing left to hear, so no sound
    // alone.
    await tester.tap(find.byKey(const Key('video-edit-take-mute')));
    await _settle(tester);
    expect(platform.volumes[0], 0);
    expect(edit()!.ownMuted, isTrue);
    expect(edit()!.ownVolume, 0.6);
    expect(edit()!.toJson()['sound'], 'none');
    await tester.tapAt(const Offset(450, 1500));
    await _frames(tester);
    expect(await soundOnly(), isFalse);

    // Opened again: still muted, at 60%; Unmute plays it at 60%.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    final video = platform.lastPlayer;
    expect(platform.volumes[video], 0);
    expect(find.text('60%'), findsOneWidget);
    await tester.tap(find.byKey(const Key('video-edit-take-volume')));
    await _frames(tester);
    await tester.tap(find.byKey(const Key('video-edit-take-mute')));
    await _settle(tester);
    expect(platform.volumes[video], 0.6);
    expect(edit()!.ownMuted, isFalse);
    expect(edit()!.ownVolume, 0.6);
    await tester.tapAt(const Offset(450, 1500));
    await _frames(tester);
    expect(await soundOnly(), isTrue);

    // With a song too: both muted, no sound alone; the song heard, there
    // is.
    await tester.tap(find.byKey(const Key('video-edit-song-add')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-track-k1')));
    await _settle(tester);
    expect(find.text('Song · '), findsOneWidget);
    for (final lane in ['take', 'song']) {
      await tester.tap(find.byKey(Key('video-edit-$lane-volume')));
      await _frames(tester);
      await tester.tap(find.byKey(Key('video-edit-$lane-mute')));
      await _settle(tester);
      await tester.tapAt(const Offset(450, 1500));
      await _frames(tester);
    }
    expect(edit()!.ownMuted, isTrue);
    expect(edit()!.songMuted, isTrue);
    expect(await soundOnly(), isFalse);
    await tester.tap(find.byKey(const Key('video-edit-song-volume')));
    await _frames(tester);
    await tester.tap(find.byKey(const Key('video-edit-song-mute')));
    await _settle(tester);
    await tester.tapAt(const Offset(450, 1500));
    await _frames(tester);
    expect(edit()!.toJson()['sound'], 'track');
    expect(await soundOnly(), isTrue);
  });

  testWidgets('the Take lane\'s grips trim the video and both sounds with '
      'it: the song stays where it is along the video, cut where the '
      'video is', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.runAsync(
      () => library.setPageEdit(
        id,
        'k0',
        PageEdit(
          start: Duration.zero,
          end: s(180),
          song: SongMode.manual,
          trackId: 'k1',
          offset: s(10),
        ),
      ),
    );
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    final block = tester.getRect(find.byKey(const Key('video-edit-song-move')));
    final width = tester
        .getSize(find.byKey(const Key('video-edit-take-bar')))
        .width;

    // Its start, a sixth in (30 s).
    await tester.drag(
      find.byKey(const Key('video-edit-take-start')),
      Offset(width / 6, 0),
    );
    await _settle(tester);
    // Its end, a sixth back.
    await tester.drag(
      find.byKey(const Key('video-edit-take-end')),
      Offset(-width / 6, 0),
    );
    await _settle(tester);
    final kept = library.byId(id)!.pages.first.edit!;
    expect(kept.start.inMilliseconds, inInclusiveRange(20000, 30000));
    expect(kept.end.inMilliseconds, inInclusiveRange(150000, 160000));
    // The song where it was along the video: it starts 10 s into it, so
    // its start before the part kept is cut.
    expect(kept.offset, s(10) - kept.start);
    expect(
      tester.getRect(find.byKey(const Key('video-edit-song-move'))).left,
      closeTo(block.left, 1),
    );
    // While paused, the preview went to the end moved, exactly once let go.
    expect(platform.seeks.last, kept.end);

    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    final plan = editor.rendered.single;
    expect((plan.start, plan.end), (kept.start, kept.end));
    expect(plan.own, const OwnLane());
    // The song from the kept part's start, 10 s from where the video
    // starts, to its end.
    expect(plan.song!.clips, [
      SongClip(
        at: Duration.zero,
        from: kept.start - s(10),
        to: kept.end - s(10),
      ),
    ]);
  });

  testWidgets('⋮ Remove takes the song out (song: off); Reset gives no '
      'edit at all', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.runAsync(
      () => library.setPageEdit(
        id,
        'k0',
        PageEdit(
          start: s(2),
          end: s(12),
          song: SongMode.manual,
          trackId: 'k1',
          offset: s(1.5),
          trackVolume: 0.7,
        ),
      ),
    );
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    expect(find.text('Recording 1'), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('video-edit-song-menu')));
    await _frames(tester);
    expect(find.byKey(const Key('video-edit-song-change')), findsOneWidget);
    await tester.tap(find.byKey(const Key('video-edit-song-remove')));
    await _settle(tester);
    var edit = library.byId(id)!.pages.first.edit!;
    expect(edit.song, SongMode.off);
    expect(edit.toJson()['song'], 'off');
    expect(edit.trackId, isNull);
    expect(edit.start, s(2));
    expect(find.text('Recording 1'), findsNothing);
    expect(find.text('Add a track'), findsOneWidget);
    expect(find.byKey(const Key('video-edit-song-volume')), findsNothing);
    expect(enabled(tester, 'video-edit-reset'), isTrue);

    await tester.tap(find.byKey(const Key('video-edit-reset')));
    await _settle(tester);
    expect(library.byId(id)!.pages.first.edit, isNull);
    expect(enabled(tester, 'video-edit-reset'), isFalse);
    expect(find.text('Keep 0:00.0–3:00.0'), findsOneWidget);
  });

  testWidgets('the track\'s volume: at the left of its bar, on its row; '
      'set, it\'s kept with the edit, the preview plays the track at it '
      '(on, without stopping), Mute keeps its level, Download gets it, and '
      'Reset puts it back', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-song-add')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-track-k1')));
    await _settle(tester);
    final track = platform.lastPlayer;
    expect(find.text('100%'), findsNWidgets(2));
    expect(platform.volumes[track], 1);

    // Played: the video, and the track along it.
    await tester.tap(find.byKey(const Key('video-edit-play')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await _frames(tester);
    expect(platform.playing, containsAll([0, track]));

    // Tapped, it opens its slider; at half, the track plays on, at half.
    await tester.tap(find.byKey(const Key('video-edit-song-volume')));
    await _frames(tester);
    final slider = find.byKey(const Key('video-edit-song-volume-slider'));
    expect(slider, findsOneWidget);
    platform.paused.clear();
    tester.widget<Slider>(slider).onChanged!(50);
    await _settle(tester);
    expect(platform.volumes[track], 0.5);
    expect(platform.playing, contains(track));
    expect(platform.paused, isNot(contains(track)));
    expect(library.byId(id)!.pages.first.edit!.trackVolume, 0.5);
    expect(find.text('50%'), findsNWidgets(2));
    expect(tester.widget<Slider>(slider).value, 50);

    // Muted: silent, its level kept (and still shown); then heard again.
    await tester.tap(find.byKey(const Key('video-edit-song-mute')));
    await _settle(tester);
    expect(platform.volumes[track], 0);
    expect(platform.paused, isNot(contains(track)));
    expect(library.byId(id)!.pages.first.edit!.trackVolume, 0.5);
    expect(library.byId(id)!.pages.first.edit!.songMuted, isTrue);
    expect(find.text('50%'), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('video-edit-song-mute')));
    await _settle(tester);
    expect(platform.volumes[track], 0.5);
    expect(library.byId(id)!.pages.first.edit!.songMuted, isFalse);
    await tester.tapAt(const Offset(450, 1500));
    await _frames(tester);
    expect(slider, findsNothing);
    await tester.tap(find.byKey(const Key('video-edit-play')));
    await _settle(tester);

    // Download: the track goes in at half.
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    expect(editor.rendered.single.song!.volume, 0.5);

    // Reset: no song, no edit; picked again, at 100%.
    await tester.tap(find.byKey(const Key('video-edit-reset')));
    await _settle(tester);
    expect(library.byId(id)!.pages.first.edit, isNull);
    expect(find.byKey(const Key('video-edit-song-add')), findsOneWidget);
    await tester.tap(find.byKey(const Key('video-edit-song-add')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-track-k1')));
    await _settle(tester);
    expect(find.text('100%'), findsNWidgets(2));
    expect(library.byId(id)!.pages.first.edit!.trackVolume, 1);
    expect(platform.volumes[platform.lastPlayer], 1);
  });

  testWidgets('a kept edit\'s track plays at its volume, on its file screen '
      'and in the editor', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.runAsync(
      () => library.setPageEdit(
        id,
        'k0',
        PageEdit.fromSound(
          start: s(10),
          end: s(20),
          sound: EditSound.track,
          trackId: 'k1',
          trackVolume: 0.25,
        ),
      ),
    );
    await tester.pumpWidget(
      host(FileScreen(library: library, eventId: id, pageId: 'k0')),
    );
    await _settle(tester);
    await tester.tap(find.byIcon(Icons.play_circle_fill));
    await _settle(tester);
    expect(platform.volumes[1], 0.25);

    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    expect(find.text('25%'), findsOneWidget);
    expect(platform.volumes[platform.lastPlayer], 0.25);

    // Slid down to 0%, Unmute puts back the level it had as it was
    // opened.
    await tester.tap(find.byKey(const Key('video-edit-song-volume')));
    await _frames(tester);
    final slider = find.byKey(const Key('video-edit-song-volume-slider'));
    for (final v in [20.0, 10.0, 5.0, 0.0]) {
      if (v == 20) tester.widget<Slider>(slider).onChangeStart!(25);
      tester.widget<Slider>(slider).onChanged!(v);
      await _frames(tester);
    }
    tester.widget<Slider>(slider).onChangeEnd?.call(0);
    await _settle(tester);
    expect(library.byId(id)!.pages.first.edit!.trackVolume, 0);
    await tester.tap(find.byKey(const Key('video-edit-song-mute')));
    await _settle(tester);
    expect(library.byId(id)!.pages.first.edit!.trackVolume, 0.25);
    expect(platform.volumes[platform.lastPlayer], 0.25);
  });

  testWidgets('an edit an older app saved muted (at 0%) unmutes to 100%; one '
      'muted here keeps its level', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    Future<void> open(PageEdit edit) async {
      await tester.runAsync(() => library.setPageEdit(id, 'k0', edit));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(editScreen(library, id));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('video-edit-song-volume')));
      await _frames(tester);
      await tester.tap(find.byKey(const Key('video-edit-song-mute')));
      await _settle(tester);
    }

    await open(
      PageEdit.fromSound(
        start: s(10),
        end: s(20),
        sound: EditSound.track,
        trackId: 'k1',
        trackVolume: 0,
      ),
    );
    expect(library.byId(id)!.pages.first.edit!.trackVolume, 1);

    await open(
      PageEdit(
        start: s(10),
        end: s(20),
        song: SongMode.manual,
        songMuted: true,
        trackId: 'k1',
        trackVolume: 0.4,
      ),
    );
    final edit = library.byId(id)!.pages.first.edit!;
    expect(edit.songMuted, isFalse);
    expect(edit.trackVolume, 0.4);
  });

  for (final (name, size) in [
    ('a phone', const Size(400, 900)),
    ('a wide screen', const Size(1280, 900)),
  ]) {
    testWidgets('both lanes fit at the largest text size, on $name', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final (library, id) = await capture(tester);
      await tester.pumpWidget(editScreen(library, id));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('video-edit-song-add')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('video-edit-track-k1')));
      await _settle(tester);
      // No overflow (which would fail the test); each lane one row, its
      // level on one line within its control.
      for (final lane in ['take', 'song']) {
        final control = tester.getRect(
          find.byKey(Key('video-edit-$lane-volume')),
        );
        final level = tester.getRect(
          find.byKey(Key('video-edit-$lane-volume-level')),
        );
        final bar = tester.getRect(find.byKey(Key('video-edit-$lane-bar')));
        expect(control.contains(level.topLeft), isTrue, reason: lane);
        expect(
          control.contains(level.bottomRight - const Offset(1, 1)),
          isTrue,
          reason: lane,
        );
        expect(control.center.dy, closeTo(bar.center.dy, 1), reason: lane);
        expect(bar.height, greaterThanOrEqualTo(44), reason: lane);
      }
      expect(find.text('100%'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }
}
