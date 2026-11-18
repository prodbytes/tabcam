import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/song_sync.dart';
import 'package:tabcam_app/capture/sound_reader.dart';
import 'package:tabcam_app/capture/take_log.dart';
import 'package:tabcam_app/capture/take_syncer.dart';
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
import 'song_sync_test.dart' show FakeReader, heardFrom, mixed, rate, riff;

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

/// The fake platform, where every player but the first (the video
/// edited) plays a file [length] long (a short song).
class ShortTrackPlatform extends VolumePlatform {
  ShortTrackPlatform(this.length);

  final Duration length;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => playerId == 0
      ? super.videoEventsFor(playerId)
      : Stream.value(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: length,
            size: const Size(320, 240),
          ),
        );
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
    Downloads.now = () => DateTime(2026, 11, 17, 18, 5, 9);
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
    TakeLog? log,
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
          takeLog: i == 0 ? log : null,
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

  /// Waits for the take's song to be found in its sound (the editor has
  /// it measured as it opens, off the test clock), and shown.
  Future<void> measured(WidgetTester tester, Library library, String id) async {
    for (var i = 0; i < 50; i++) {
      await _settle(tester);
      if (library.byId(id)!.pages.first.takeLog?.sync != null) break;
    }
    await _settle(tester);
  }

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<ButtonStyleButton>(find.byKey(Key(key))).enabled;

  /// Turns the watermark off, as a build without Premium's service (no
  /// CloudOcr, as here) can, and the fades (on by default): the video as
  /// it is can then be saved as it is.
  Future<void> asItIs(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('video-edit-watermark')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-fades')));
    await _settle(tester);
  }

  testWidgets('beside a recording, the sidebar\'s takes have Edit, its '
      'other videos none: it opens the editor on that take, as the take\'s '
      'own file screen does', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester, withTake: true);
    await tester.pumpWidget(
      host(FileScreen(library: library, eventId: id, pageId: 'k1')),
    );
    await _settle(tester);
    // k4 is a take; k0 and k3 are videos that aren't.
    final edit = find.byKey(const ValueKey('cam-along-edit-k4'));
    expect(edit, findsOneWidget);
    expect(find.byKey(const ValueKey('cam-along-edit-k0')), findsNothing);
    expect(find.byKey(const ValueKey('cam-along-edit-k3')), findsNothing);
    expect(find.byKey(const ValueKey('cam-along-delete-k3')), findsOneWidget);

    await tester.tap(edit);
    await _settle(tester);
    final editor = tester.widget<VideoEditScreen>(find.byType(VideoEditScreen));
    expect(editor.page.id, 'k4');
    expect(editor.eventId, id);
    expect(platform.playing, isEmpty);

    await tester.pageBack();
    await _settle(tester);
    expect(find.byType(VideoEditScreen), findsNothing);
    expect(find.byType(FileScreen), findsOneWidget);
    expect(edit, findsOneWidget);
  });

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
    expect(name, 'Made-up riff_20261117-180509.mp4');
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

  testWidgets('a video as it is is made with its watermark and fades; '
      'without them, it downloads as it is', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    // The edit is none, Reset has nothing to do, yet Download makes it:
    // the watermark and the fades are on by default.
    expect(library.byId(id)!.pages.first.edit, isNull);
    expect(enabled(tester, 'video-edit-reset'), isFalse);
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    final plan = editor.rendered.single;
    expect(plan.passthrough, isFalse);
    expect(plan.layers.map((l) => l.look), const [WatermarkLook('tabs.cam')]);
    expect((plan.fadeIn, plan.fadeOut), (s(3), s(3)));

    await asItIs(tester);
    saved.clear();
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    expect(editor.rendered, hasLength(1));
    final (name, bytes, _) = saved.single;
    expect(name, 'Made-up riff_20261117-180509.mp4');
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
        ('Made-up riff_20261117-180509.mp4', 'video/mp4'),
        ('Made-up riff_20261117-180509.mp4', 'video/mp4'),
        ('Made-up riff_20261117-180509.m4a', 'audio/mp4'),
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
    expect(name, 'Made-up riff_20261117-180509.wav');
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
    expect(name, 'Made-up riff_20261117-180509.mp4');
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
    await asItIs(tester);
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    expect(editor.rendered, isEmpty);
    expect(saved.single.$1, 'Made-up riff_20261117-180509.webm');
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
    await asItIs(tester);
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    expect(editor.rendered, isEmpty);
    expect(saved.single.$1, 'Made-up riff_20261117-180509.mp4');
    expect(saved.single.$2, [1, 2, 3]);

    // An M4V (MPEG-4 too), where MP4 is made: as it is, not made again.
    VideoEditor.instance = editor = FakeEditor();
    saved.clear();
    final (library2, id2) = await capture(tester, video: 'm4v');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(editScreen(library2, id2));
    await _settle(tester);
    await asItIs(tester);
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    expect(editor.rendered, isEmpty);
    expect(saved.single.$1, 'Made-up riff_20261117-180509.m4v');
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

  testWidgets('a take opens with the song lined up as it played while it '
      'recorded: nothing to reset or keep; moved, it all moves; Reset puts '
      'it back; Download plays its clips', (tester) async {
    tall(tester);
    // Played from its start a second in (the lag, 0.2 s, after), paused,
    // then on from 4 s.
    final (library, id) = await capture(
      tester,
      editTake: true,
      log: const TakeLog(
        burned: false,
        lagMs: 200,
        song: [
          SongSegment(at: 1000, to: 5000, page: 'k1', from: 0),
          SongSegment(at: 8000, to: 12000, page: 'k1', from: 4000),
        ],
      ),
    );
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    expect(find.text('Recording 1'), findsNWidgets(2));
    expect(
      find.text('Lined up as it played while you recorded'),
      findsOneWidget,
    );
    // In two clips: moved as one, not trimmed.
    expect(find.byKey(const Key('video-edit-song-bar')), findsOneWidget);
    expect(find.byKey(const Key('video-edit-song-left')), findsNothing);
    expect(enabled(tester, 'video-edit-reset'), isFalse);
    expect(library.byId(id)!.pages.first.edit, isNull);

    // A twentieth of a second earlier (‹'s step): all of it, still lined
    // up; again, a tenth.
    await tester.tap(find.byKey(const Key('video-edit-song-earlier')));
    await _settle(tester);
    expect(
      find.text('Lined up as recorded, moved 0:00.05 earlier'),
      findsOneWidget,
    );
    expect(
      find.text('The song starts 0:01.15 after the video'),
      findsOneWidget,
    );
    expect(find.byTooltip('0.05 s earlier'), findsOneWidget);
    expect(find.byTooltip('0.05 s later'), findsOneWidget);
    await tester.tap(find.byKey(const Key('video-edit-song-earlier')));
    await _settle(tester);
    expect(
      find.text('Lined up as recorded, moved 0:00.1 earlier'),
      findsOneWidget,
    );
    expect(enabled(tester, 'video-edit-reset'), isTrue);
    var edit = library.byId(id)!.pages.first.edit!;
    expect(edit.song, isNull);
    expect(edit.toJson().containsKey('song'), isFalse);
    expect((edit.trackId, edit.offset), ('k1', s(1.1)));

    // Reset: lined up as recorded again, and the edit is none.
    await tester.tap(find.byKey(const Key('video-edit-reset')));
    await _settle(tester);
    expect(
      find.text('Lined up as it played while you recorded'),
      findsOneWidget,
    );
    expect(enabled(tester, 'video-edit-reset'), isFalse);
    expect(library.byId(id)!.pages.first.edit, isNull);

    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    expect(editor.rendered.single.song!.page, 'k1');
    expect(editor.rendered.single.song!.clips, [
      SongClip(at: s(1.2), from: Duration.zero, to: s(4)),
      SongClip(at: s(8.2), from: s(4), to: s(8)),
    ]);

    // Taken out: it stays out.
    await tester.tap(find.byKey(const Key('video-edit-song-menu')));
    await _settle(tester);
    await tester.tap(find.text('Remove'));
    await _settle(tester);
    edit = library.byId(id)!.pages.first.edit!;
    expect(edit.song, SongMode.off);
    expect(find.byKey(const Key('video-edit-song-add')), findsOneWidget);
  });

  testWidgets('a take whose song was found in its sound: lined up there, '
      'its starts and stops marked; Cut to the song keeps from its start '
      'to its stop; a grip dragged near a mark is on it', (tester) async {
    tall(tester);
    final (library, id) = await capture(
      tester,
      editTake: true,
      log: const TakeLog(
        burned: false,
        lagMs: 200,
        song: [
          SongSegment(at: 1000, to: 5000, page: 'k1', from: 0),
          SongSegment(at: 8000, to: 12000, page: 'k1', from: 4000),
        ],
        sync: TakeSync(
          page: 'k1',
          from: SyncFrom.sound,
          ms: 60,
          clips: [SyncClip(at: 1000, ms: 60), SyncClip(at: 8000, ms: 80)],
        ),
      ),
    );
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    expect(find.text('Lined up by its sound in the take'), findsOneWidget);
    // Where the song starts and stops, clip by clip, on the Take lane.
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(Key('video-edit-take-mark-$i')), findsOneWidget);
    }
    expect(find.byKey(const Key('video-edit-take-mark-4')), findsNothing);
    final bar = tester.getRect(find.byKey(const Key('video-edit-take-bar')));
    double x(String key) => tester.getRect(find.byKey(Key(key))).center.dx;
    expect(
      x('video-edit-take-mark-0'),
      closeTo(bar.left + bar.width * 1.26 / 180, 0.01),
    );
    expect(
      x('video-edit-take-mark-3'),
      closeTo(bar.left + bar.width * 12.28 / 180, 0.01),
    );
    expect(library.byId(id)!.pages.first.edit, isNull);

    // Cut to the song: from its first start to its last stop, to the ms.
    expect(enabled(tester, 'video-edit-cut-to-song'), isTrue);
    await tester.tap(find.byKey(const Key('video-edit-cut-to-song')));
    await _settle(tester);
    var edit = library.byId(id)!.pages.first.edit!;
    expect((edit.start, edit.end), (s(1.26), s(12.28)));
    // The song where it was along the video: it starts with the kept part.
    expect(edit.offset, Duration.zero);
    expect(find.text('Lined up by its sound in the take'), findsOneWidget);
    expect(enabled(tester, 'video-edit-cut-to-song'), isFalse);

    // Reset, then the grips: dragged near a mark, on it.
    await tester.tap(find.byKey(const Key('video-edit-reset')));
    await _settle(tester);
    expect(library.byId(id)!.pages.first.edit, isNull);
    // A grip dragged: first away from every mark, where it's dragged;
    // then to a second from a mark (within a hundredth of the 3 minutes):
    // on the mark.
    final perMs = bar.width / 180000;
    final start = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('video-edit-take-start'))),
    );
    await start.moveBy(const Offset(40, 0));
    await start.moveBy(const Offset(80, 0));
    await _settle(tester);
    edit = library.byId(id)!.pages.first.edit!;
    expect(edit.start, greaterThan(s(15)));
    await start.moveBy(Offset((2260 - edit.start.inMilliseconds) * perMs, 0));
    await _settle(tester);
    expect(library.byId(id)!.pages.first.edit!.start, s(1.26));
    // On past it, and back to within reach from the other side.
    await start.moveBy(Offset(3000 * perMs, 0));
    await _settle(tester);
    expect(
      library.byId(id)!.pages.first.edit!.start.inMilliseconds,
      closeTo(5260, 300),
    );
    await start.up();
    await _settle(tester);
    // That one is the second mark's (5.26 s), a little further than the
    // third's reach.
    expect(library.byId(id)!.pages.first.edit!.start, s(5.26));

    // The end, dragged back to near the last mark.
    final end = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('video-edit-take-end'))),
    );
    await end.moveBy(const Offset(-40, 0));
    await end.moveBy(const Offset(-80, 0));
    await _settle(tester);
    edit = library.byId(id)!.pages.first.edit!;
    expect(edit.end, lessThan(s(165)));
    await end.moveBy(Offset((13300 - edit.end.inMilliseconds) * perMs, 0));
    await end.up();
    await _settle(tester);
    edit = library.byId(id)!.pages.first.edit!;
    expect(edit.end, s(12.28));

    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    // The kept part: from the first clip's stop to the second's.
    expect(editor.rendered.single.song!.clips, [
      SongClip(at: s(3.02), from: s(4), to: s(8)),
    ]);
  });

  testWidgets('a take not measured yet is as the editor opens: its song '
      'found in its sound, the Song lane follows; one moved by hand stays '
      'where it was put', (tester) async {
    tall(tester);
    SongSync.inline = true;
    // Other tests' takes, left unmeasured when their clocks stopped.
    TakeSyncer.reset();
    addTearDown(() {
      SongSync.inline = false;
      SoundReader.opener = null;
    });
    // The song played from 5 s on the take's clock (the lag 0.2 s); the
    // take's sound has it 83 ms after that.
    const log = TakeLog(
      burned: false,
      lagMs: 200,
      song: [SongSegment(at: 5000, to: 35000, page: 'k1', from: 0)],
    );
    final song = riff(30, 11);
    final reader = FakeReader({
      // The test's library keeps files in memory: told apart by type.
      'video/mp4': mixed([
        heardFrom(song, length: 40 * rate, delay: 5283 * rate / 1000),
        riff(40, 12, bpm: 103),
      ]),
      'audio/mp4': song,
    });
    SoundReader.opener = () => reader;

    final (library, id) = await capture(tester, editTake: true, log: log);
    await tester.pumpWidget(editScreen(library, id));
    await measured(tester, library, id);
    expect(find.text('Lined up by its sound in the take'), findsOneWidget);
    final sync = library.byId(id)!.pages.first.takeLog!.sync!;
    expect((sync.found, sync.ms), (true, 83));
    // Still the defaults: nothing kept, nothing to reset.
    expect(library.byId(id)!.pages.first.edit, isNull);
    expect(enabled(tester, 'video-edit-reset'), isFalse);
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    expect(editor.rendered.single.song!.clips, [
      SongClip(at: s(5.283), from: Duration.zero, to: s(30)),
    ]);
    await tester.pumpWidget(const SizedBox());
    await _settle(tester);

    // Another, moved by hand before it's measured (the reader has no
    // files yet): where it was put, it stays.
    final sounds = {...reader.files};
    reader.files.clear();
    final (library2, id2) = await capture(tester, editTake: true, log: log);
    await tester.pumpWidget(editScreen(library2, id2));
    await _settle(tester);
    expect(
      find.text('Lined up as it played while you recorded'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('video-edit-song-later')));
    await _settle(tester);
    expect(library2.byId(id2)!.pages.first.edit!.offset, s(5.25));
    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
    reader.files.addAll(sounds);
    await tester.pumpWidget(editScreen(library2, id2));
    await measured(tester, library2, id2);
    expect(library2.byId(id2)!.pages.first.takeLog!.sync!.ms, 83);
    // 5.25 s, 33 ms before where it was found (5.283 s): to the
    // hundredth.
    expect(
      find.text('Lined up as recorded, moved 0:00.03 earlier'),
      findsOneWidget,
    );
    expect(library2.byId(id2)!.pages.first.edit!.offset, s(5.25));
  });

  testWidgets('the cut\'s ends step a twentieth of a second: ‹ and › under '
      'the lanes move the start and the end, shown to the hundredth, the '
      'song staying where it is along the video', (tester) async {
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
    String at(String end) =>
        tester.widget<Text>(find.byKey(Key('video-edit-$end-at'))).data!;
    PageEdit edit() => library.byId(id)!.pages.first.edit!;
    expect((at('start'), at('end')), ('Start 0:02.0', 'End 0:12.0'));
    expect(find.byTooltip('Start 0.05 s earlier'), findsOneWidget);
    expect(find.byTooltip('End 0.05 s later'), findsOneWidget);

    // The start a step later, then two earlier.
    await tester.tap(find.byKey(const Key('video-edit-start-later')));
    await _settle(tester);
    expect(at('start'), 'Start 0:02.05');
    expect(find.text('Keep 0:02.05–0:12.0'), findsOneWidget);
    expect(edit().start, s(2.05));
    // The song where it was along the video (3.5 s in).
    expect(edit().offset, s(1.45));
    expect(platform.seeks, contains(s(2.05)));
    await tester.tap(find.byKey(const Key('video-edit-start-earlier')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('video-edit-start-earlier')));
    await _settle(tester);
    expect(at('start'), 'Start 0:01.95');
    expect((edit().start, edit().offset), (s(1.95), s(1.55)));

    // The end a step earlier, then two later: the preview at the frame
    // it cuts at.
    await tester.tap(find.byKey(const Key('video-edit-end-earlier')));
    await _settle(tester);
    expect(at('end'), 'End 0:11.95');
    expect(edit().end, s(11.95));
    expect(platform.seeks, contains(s(11.95)));
    await tester.tap(find.byKey(const Key('video-edit-end-later')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('video-edit-end-later')));
    await _settle(tester);
    expect((at('end'), edit().end), ('End 0:12.05', s(12.05)));
    expect(edit().offset, s(1.55));

    // At the video's ends there's no further to step.
    await tester.tap(find.byKey(const Key('video-edit-reset')));
    await _settle(tester);
    IconButton button(String key) =>
        tester.widget<IconButton>(find.byKey(Key(key)));
    expect((at('start'), at('end')), ('Start 0:00.0', 'End 3:00.0'));
    expect(button('video-edit-start-earlier').onPressed, isNull);
    expect(button('video-edit-end-later').onPressed, isNull);
    expect(button('video-edit-start-later').onPressed, isNotNull);
    expect(button('video-edit-end-earlier').onPressed, isNotNull);
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
      'fades': {'inMs': 500, 'outMs': 800},
    };
    await tester.runAsync(
      () => library.setPageEdit(
        id,
        'k0',
        PageEdit.fromJson({
          'startMs': 2000,
          'endMs': 20000,
          'watermark': false,
          ...newer,
        }),
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

    // Reset: the whole video, its own sound, the watermark; the newer keys
    // stay, so the edit does; without the watermark and the fades, the
    // video downloads as it is.
    await tester.tap(find.byKey(const Key('video-edit-reset')));
    await _settle(tester);
    edit = library.byId(id)!.pages.first.edit!;
    expect((edit.start, edit.end), (Duration.zero, s(180)));
    expect(edit.watermark, isTrue);
    expect(edit.extra, newer);
    expect(enabled(tester, 'video-edit-reset'), isFalse);
    await asItIs(tester);
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

  testWidgets('a lane\'s Channels and Balance are kept with the edit, '
      'and say only Download has them', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester, editTake: true);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    PageEdit? edit() => library.byId(id)!.pages.first.edit;

    await tester.tap(find.byKey(const Key('video-edit-take-volume')));
    await _frames(tester);
    expect(find.text('Centre'), findsOneWidget);
    expect(find.byKey(const Key('video-edit-take-stereo-note')), findsNothing);

    // The left channel on both sides.
    await tester.tap(find.byKey(const Key('video-edit-take-left')));
    await _settle(tester);
    expect(edit()!.ownStereo.channels, LaneChannels.left);
    expect(edit()!.toJson()['ownChannels'], 'left');
    expect(
      find.byKey(const Key('video-edit-take-stereo-note')),
      findsOneWidget,
    );

    // Leaning right: the left turned down.
    tester
        .widget<Slider>(find.byKey(const Key('video-edit-take-balance')))
        .onChanged!(30);
    await _settle(tester);
    expect(edit()!.ownStereo.balance, 0.3);
    expect(find.text('R 30'), findsOneWidget);

    // Opened again: as it was left.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-take-volume')));
    await _frames(tester);
    expect(
      tester
          .widget<SegmentedButton<LaneChannels>>(
            find.byKey(const Key('video-edit-take-channels')),
          )
          .selected,
      {LaneChannels.left},
    );
    expect(find.text('R 30'), findsOneWidget);

    // Back to Stereo, in the middle: as recorded, nothing kept for it.
    await tester.tap(find.byKey(const Key('video-edit-take-stereo')));
    await _settle(tester);
    tester
        .widget<Slider>(find.byKey(const Key('video-edit-take-balance')))
        .onChanged!(0);
    await _settle(tester);
    expect(edit()?.ownStereo ?? LaneStereo.standard, LaneStereo.standard);
    expect(edit()?.toJson().containsKey('ownChannels') ?? false, isFalse);
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
    // is. A take's sheet and the song's details say "song", as its lane.
    await tester.tap(find.byKey(const Key('video-edit-song-add')));
    await _settle(tester);
    expect(find.text('Pick a song'), findsOneWidget);
    expect(find.text('Pick a track'), findsNothing);
    await tester.tap(find.byKey(const Key('video-edit-track-k1')));
    await _settle(tester);
    expect(find.text('Song · '), findsOneWidget);
    expect(find.text('The song starts with the video'), findsOneWidget);
    expect(find.textContaining('The track'), findsNothing);
    await tester.tap(find.byKey(const Key('video-edit-song-later')));
    await _settle(tester);
    expect(
      find.text('The song starts 0:00.05 after the video'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('video-edit-song-later')));
    await _settle(tester);
    expect(find.text('The song starts 0:00.1 after the video'), findsOneWidget);
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

  testWidgets('a song picked shorter than the kept part goes at the '
      'timeline\'s end: it ends where the kept part ends', (tester) async {
    tall(tester);
    VideoPlayerPlatform.instance = platform = ShortTrackPlatform(s(40));
    final (library, id) = await capture(tester);
    PageEdit? edit() => library.byId(id)!.pages.first.edit;
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-song-add')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-track-k1')));
    await _settle(tester);
    // 40 s in a 3 min video: it starts 2:20 in.
    expect(edit()!.offset, s(140));
    expect(
      find.text('The track starts 2:20.0 after the video'),
      findsOneWidget,
    );
    final take = tester.getRect(find.byKey(const Key('video-edit-take-bar')));
    final song = tester.getRect(find.byKey(const Key('video-edit-song-move')));
    expect(song.right, closeTo(take.right, 1));

    // Trimmed to 0:10–1:00, the song changed: it ends at 1:00 again.
    await tester.runAsync(
      () => library.setPageEdit(id, 'k0', PageEdit(start: s(10), end: s(60))),
    );
    await tester.pumpWidget(const SizedBox());
    // A new platform: the video opened again is its first player.
    VideoPlayerPlatform.instance = platform = ShortTrackPlatform(s(40));
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-song-add')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-track-k1')));
    await _settle(tester);
    expect(edit()!.offset, s(10));
  });

  testWidgets('a click on either lane places the preview there, as the '
      'ruler does; a drag of the song still moves it', (tester) async {
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
        ),
      ),
    );
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    final take = tester.getRect(find.byKey(const Key('video-edit-take-bar')));
    final song = tester.getRect(find.byKey(const Key('video-edit-song-bar')));

    // A quarter in on the Take lane: 0:45.
    await tester.tapAt(Offset(take.left + take.width / 4, take.center.dy));
    await _settle(tester);
    expect(platform.seeks.last.inMilliseconds, closeTo(45000, 500));

    // Halfway on the Song lane: 1:30.
    await tester.tapAt(Offset(song.left + song.width / 2, song.center.dy));
    await _settle(tester);
    expect(platform.seeks.last.inMilliseconds, closeTo(90000, 500));

    // Dragged, the song moves, as before.
    await tester.drag(
      find.byKey(const Key('video-edit-song-move')),
      Offset(song.width / 6, 0),
    );
    await _settle(tester);
    expect(
      library.byId(id)!.pages.first.edit!.offset.inMilliseconds,
      // A sixth of the bar, less the drag's slop.
      inInclusiveRange(15000, 30000),
    );
  });

  testWidgets('a take the browser recorded, whose player can\'t say how '
      'long it is, goes where the ruler and the lanes are clicked (its '
      'player told the length the editor finds)', (tester) async {
    // video_player_web's unset duration, far below zero: until the player
    // is told the length, video_player keeps every seek within it.
    VideoPlayerPlatform.instance = platform = UnknownLengthPlatform({0});
    editor.lengthHere = s(180);
    tall(tester);
    final (library, id) = await capture(tester, editTake: true);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    expect(find.text('Keep 0:00.0–3:00.0'), findsOneWidget);

    // A quarter along the ruler: 0:45.
    final ruler = tester.getRect(find.byKey(const Key('video-edit-ruler')));
    await tester.tapAt(Offset(ruler.left + ruler.width / 4, ruler.center.dy));
    await _settle(tester);
    expect(platform.seeks.last.inMilliseconds, closeTo(45000, 500));

    // Halfway along the Take lane: 1:30.
    final take = tester.getRect(find.byKey(const Key('video-edit-take-bar')));
    await tester.tapAt(Offset(take.left + take.width / 2, take.center.dy));
    await _settle(tester);
    expect(platform.seeks.last.inMilliseconds, closeTo(90000, 500));
  });

  testWidgets('the space bar plays and pauses the preview, as Play does; '
      'not while the title is typed in', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    Future<void> space() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _settle(tester);
    }

    expect(platform.playing, isNot(contains(0)));
    await space();
    expect(platform.playing, contains(0));
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await space();
    expect(platform.playing, isNot(contains(0)));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    // Typing the title: a space is the title's.
    await tester.tap(find.byKey(const Key('video-edit-title-1')));
    await _settle(tester);
    await space();
    expect(platform.playing, isNot(contains(0)));

    // A click elsewhere (which, on a computer, leaves the title) gives
    // the editor the keyboard back.
    await tester.tap(
      find.byKey(const Key('video-edit-times')),
      kind: PointerDeviceKind.mouse,
    );
    await _settle(tester);
    await space();
    expect(platform.playing, contains(0));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

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

  testWidgets('a muted song of unknown length doesn\'t hold back Download '
      '(it\'s left out of it); heard, it does', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    // As an older app's Original with a track picked: the song lane
    // muted; its file one neither the player nor the editor can say the
    // length of.
    VideoPlayerPlatform.instance = platform = UnknownLengthPlatform({1});
    await tester.runAsync(
      () => library.setPageEdit(
        id,
        'k0',
        PageEdit.fromSound(
          start: s(1),
          end: s(9),
          sound: EditSound.original,
          trackId: 'k1',
        ),
      ),
    );
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    expect(find.text('Recording 1'), findsWidgets);
    expect(enabled(tester, 'video-edit-download'), isTrue);
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    final plan = editor.rendered.single;
    expect(plan.own, const OwnLane());
    expect(plan.song, isNull);

    // Heard, it can't be fitted: Download waits.
    await tester.tap(find.byKey(const Key('video-edit-song-volume')));
    await _frames(tester);
    await tester.tap(find.byKey(const Key('video-edit-song-mute')));
    await _settle(tester);
    await tester.tapAt(const Offset(450, 1500));
    await _frames(tester);
    expect(library.byId(id)!.pages.first.edit!.songMuted, isFalse);
    expect(enabled(tester, 'video-edit-download'), isFalse);
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
    // Both lanes' levels, and the master's.
    expect(find.text('100%'), findsNWidgets(3));
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
    // Both lanes' levels, and the master's.
    expect(find.text('100%'), findsNWidgets(3));
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
      // Both lanes' levels, and the master's.
      expect(find.text('100%'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the song\'s delay: steps of 1 and 10 ms either way, a value '
      'typed, kept with the edit; Reset clears it', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester, withTake: true);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-song-add')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-track-k1')));
    await _settle(tester);

    String shown() => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const Key('video-edit-delay-value')),
            matching: find.byType(Text),
          ),
        )
        .data!;
    Duration kept() => library.byId(id)!.pages.first.edit!.offset;
    expect(find.byKey(const Key('video-edit-delay')), findsOneWidget);
    expect(shown(), '0 ms');
    expect(
      find.textContaining("Bluetooth speaker's or headphones' delay"),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('video-edit-delay-plus10')));
    await tester.tap(find.byKey(const Key('video-edit-delay-plus1')));
    await _settle(tester);
    expect(shown(), '+11 ms');
    expect(kept(), const Duration(milliseconds: 11));
    await tester.tap(find.byKey(const Key('video-edit-delay-minus1')));
    await _settle(tester);
    expect(shown(), '+10 ms');
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('video-edit-delay-minus10')),
          )
          .tooltip,
      '10 ms earlier',
    );

    // Typed: −35 ms, the song that much earlier.
    await tester.tap(find.byKey(const Key('video-edit-delay-value')));
    await _settle(tester);
    expect(find.text('Song delay'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('video-edit-delay-field')),
      '-35',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Set'));
    await _settle(tester);
    expect(shown(), '−35 ms');
    expect(kept(), const Duration(milliseconds: -35));

    // Reset: no song, so no delay, and no edit.
    await tester.tap(find.byKey(const Key('video-edit-reset')));
    await _settle(tester);
    expect(find.byKey(const Key('video-edit-delay')), findsNothing);
    expect(library.byId(id)!.pages.first.edit, isNull);
  });

  testWidgets('the timeline zooms in and out: the ruler and both lanes '
      'together, scrolled sideways, a tap and a drag as precise as the zoom',
      (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    Rect rect(String key) => tester.getRect(find.byKey(Key(key)));
    final whole = rect('video-edit-take-bar');
    expect(find.byKey(const Key('video-edit-zoom')), findsNothing);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('video-edit-zoom-out'))).onPressed,
      isNull,
    );

    // Zoomed in twice: 4×, the lanes and the ruler four times as wide,
    // on one axis, starting where they did.
    await tester.tap(find.byKey(const Key('video-edit-zoom-in')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-zoom-in')));
    await _settle(tester);
    expect(find.text('4×'), findsOneWidget);
    final take = rect('video-edit-take-bar');
    expect(take.width, closeTo(whole.width * 4, 1));
    expect(rect('video-edit-ruler').width, closeTo(take.width, 0.5));
    expect(take.left, closeTo(whole.left, 0.5));

    // A tap a quarter across the view is a sixteenth of the video in:
    // 0:11.25 of 3 minutes.
    await tester.tapAt(
      Offset(whole.left + whole.width / 4, take.center.dy),
    );
    await _settle(tester);
    expect(platform.seeks.last.inMilliseconds, closeTo(11250, 200));

    // The start grip dragged a tenth of the view: a fortieth of the video.
    final grip = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('video-edit-take-start'))),
    );
    // (Past the touch slop first, then measured.)
    await grip.moveBy(const Offset(30, 0));
    await _settle(tester);
    // Where the cut starts, as the Keep label says it (m:ss.hh).
    int keptFrom() {
      final label = tester
          .widgetList<Text>(find.textContaining('Keep '))
          .first
          .data!;
      final m = RegExp(r'(\d+):(\d+)(?:\.(\d+))?').firstMatch(label)!;
      final frac = (m.group(3) ?? '0').padRight(3, '0');
      return int.parse(m.group(1)!) * 60000 +
          int.parse(m.group(2)!) * 1000 +
          int.parse(frac.substring(0, 3));
    }

    final from = keptFrom();
    await grip.moveBy(Offset(whole.width / 10, 0));
    await _settle(tester);
    expect(keptFrom() - from, closeTo(4500, 100));
    await grip.up();
    await _settle(tester);

    // Scrolled sideways, the bars move under the headers, which stay.
    final header = rect('video-edit-take-volume');
    tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('video-edit-timeline-scroll')),
            matching: find.byType(Scrollable),
          ),
        )
        .position
        .jumpTo(whole.width);
    await _settle(tester);
    expect(rect('video-edit-take-bar').left, closeTo(whole.left - whole.width, 1));
    expect(rect('video-edit-take-volume'), header);

    // Zoomed out all the way: the whole video again, no scroll.
    await tester.tap(find.byKey(const Key('video-edit-zoom-out')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-zoom-out')));
    await _settle(tester);
    expect(find.byKey(const Key('video-edit-zoom')), findsNothing);
    expect(rect('video-edit-take-bar'), whole);
    expect(find.byKey(const Key('video-edit-timeline-scroll')), findsNothing);
  });
}
