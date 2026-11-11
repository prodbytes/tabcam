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

/// An editor that records what it's asked and hands back a small WebM.
class FakeEditor implements VideoEditing {
  final applied = <(XFile, VideoEdit, bool)>[];

  @override
  Future<Duration?> length(XFile file) async => null;

  @override
  Future<XFile> apply(
    XFile video,
    VideoEdit edit, {
    bool soundOnly = false,
    void Function(double done)? onProgress,
  }) async {
    applied.add((video, edit, soundOnly));
    onProgress?.call(0.5);
    return XFile.fromData(
      Uint8List.fromList([9, 9, 9]),
      name: 'edit.webm',
      mimeType: 'video/webm',
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

    test('an edit fits its track by its length', () {
      final edit = VideoEdit(
        start: s(1),
        end: s(6),
        sound: EditSound.track,
        trackLength: s(20),
        trackStart: s(2),
        offset: s(1),
      );
      expect(edit.trackPart, (gap: s(1), from: s(2), to: s(6)));
      expect(
        VideoEdit(start: s(1), end: s(6), sound: EditSound.track).trackPart,
        isNull,
      );
    });
  });

  group('a kept edit', () {
    test('goes to JSON and back with its video page', () {
      final edit = PageEdit(
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
        'startMs': 1000,
        'endMs': 2000,
        'sound': 'original',
      });
    });

    test('keeps its track\'s volume: in JSON only when not as it is, read '
        'defensively, through a clone and in ==', () {
      final edit = PageEdit(
        start: s(1),
        end: s(6),
        sound: EditSound.track,
        trackId: 'k1',
        trackVolume: 0.4,
      );
      expect(edit.toJson()['trackVolume'], 0.4);
      expect(PageEdit.fromJson(jsonDecode(jsonEncode(edit.toJson()))), edit);
      expect(edit, isNot(edit.withTrackVolume(1)));
      expect(
        edit.withTrackVolume(1).toJson().containsKey('trackVolume'),
        false,
      );
      expect(edit.withTrackId('k9').trackVolume, 0.4);
      expect(edit.withTrackVolume(0.4), edit);
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

    test('the phones\' editor gets the track\'s volume', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      PathProviderPlatform.instance = _Paths();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(ChannelVideoEditor.channel, (c) async {
        calls.add(c);
        return (c.arguments as Map)['output'];
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          ChannelVideoEditor.channel,
          null,
        ),
      );
      final edit = VideoEdit(
        start: Duration.zero,
        end: s(4),
        sound: EditSound.track,
        track: XFile('/tmp/riff.m4a'),
        trackLength: s(10),
        trackVolume: 0.35,
      );
      await const ChannelVideoEditor().apply(XFile('/tmp/take.mp4'), edit);
      await const ChannelVideoEditor().apply(
        XFile('/tmp/take.mp4'),
        edit,
        soundOnly: true,
      );
      // Without a track, there's no volume to send.
      await const ChannelVideoEditor().apply(
        XFile('/tmp/take.mp4'),
        VideoEdit(start: Duration.zero, end: s(4), trackVolume: 0.35),
      );
      final args = [for (final c in calls) c.arguments as Map];
      expect(args[0]['trackVolume'], 0.35);
      expect(args[0]['video'], isTrue);
      expect(args[1]['trackVolume'], 0.35);
      expect(args[1]['video'], isFalse);
      expect(args[2].containsKey('trackVolume'), isFalse);
    });

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

  /// A capture with a video (k0), a recording (k1) and an image (k2).
  Future<(Library, String)> capture(WidgetTester tester) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late String id;
    await tester.runAsync(() async {
      await library.load();
      var event = await library.create(const []);
      for (final (i, (kind, ext)) in [
        (PageKind.video, 'mp4'),
        (PageKind.audio, 'm4a'),
        (PageKind.image, 'jpg'),
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
    expect(editor.applied, isEmpty);
    expect(enabled(tester, 'video-edit-reset'), isTrue);

    // Download: the video, as edited, made on the device.
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    final (input, edit, soundOnly) = editor.applied.single;
    expect(await tester.runAsync(input.readAsBytes), [1, 2, 3]);
    expect(edit.start, Duration.zero);
    expect(edit.end, s(12));
    expect(edit.sound, EditSound.original);
    expect(soundOnly, isFalse);
    final (name, bytes, type) = saved.single;
    expect(name, 'Made-up riff.webm');
    expect(bytes, [9, 9, 9]);
    expect(type, 'video/webm');
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
    expect(editor.applied, isEmpty);
    final (name, bytes, _) = saved.single;
    expect(name, 'Made-up riff.mp4');
    expect(bytes, [1, 2, 3]);
  });

  testWidgets('the sound: None, or a new track from the capture\'s '
      'recordings, shifted along the video, played with the video muted; '
      'Download\'s menu has the video without sound and the sound alone', (
    tester,
  ) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);

    // None: kept as such; the preview is muted.
    await tester.tap(find.text('None'));
    await _settle(tester);
    expect(library.byId(id)!.pages.first.edit?.sound, EditSound.none);
    expect(platform.volumes[0], 0);
    expect(find.byKey(const Key('video-edit-track')), findsNothing);

    // New track: the sheet lists the recording (not the image or the
    // video), and a sound file.
    await tester.tap(find.text('New track'));
    await _settle(tester);
    expect(find.byKey(const Key('video-edit-tracks')), findsOneWidget);
    expect(find.byKey(const Key('video-edit-track-k1')), findsOneWidget);
    expect(find.byKey(const Key('video-edit-track-k2')), findsNothing);
    expect(find.byKey(const Key('video-edit-track-k0')), findsNothing);
    expect(find.byKey(const Key('video-edit-track-file')), findsOneWidget);
    await tester.tap(find.byKey(const Key('video-edit-track-k1')));
    await _settle(tester);
    expect(find.byKey(const Key('video-edit-tracks')), findsNothing);
    // Its name: on its row, and on its bar.
    expect(find.text('Recording 1'), findsNWidgets(2));
    expect(find.text('The track starts with the video'), findsOneWidget);

    // The track bar: the track (3 minutes, as long as the video) along
    // the kept part. Dragged, it moves later.
    final bar = find.byKey(const Key('video-edit-track-bar'));
    expect(bar, findsOneWidget);
    final barWidth = tester.getSize(bar).width;
    await tester.drag(
      find.byKey(const Key('video-edit-track-move')),
      Offset(barWidth / 6, 0),
    );
    await _frames(tester);
    expect(find.textContaining('after the video'), findsOneWidget);
    // Its start, dragged, trims it, and the rest stays put: its end moves
    // with it.
    await tester.drag(
      find.byKey(const Key('video-edit-track-left')),
      Offset(barWidth / 6, 0),
    );
    await _frames(tester);
    expect(find.byKey(const Key('video-edit-track-used')), findsOneWidget);
    // A tenth of a second earlier, twice.
    await tester.tap(find.byKey(const Key('video-edit-track-earlier')));
    await tester.tap(find.byKey(const Key('video-edit-track-earlier')));
    await _settle(tester);

    // Kept with the video: the recording by its ID, where it plays.
    final kept = library.byId(id)!.pages.first.edit!;
    expect(kept.sound, EditSound.track);
    expect(kept.trackId, 'k1');
    final dragged = kept.trackStart.inMilliseconds;
    // Moved about a sixth later (a drag loses its first few pixels to
    // the touch slop), then its start trimmed by the same drag, the
    // offset following, less two tenths.
    expect(dragged, inInclusiveRange(20000, 30000));
    expect(kept.trackEnd, isNull);
    expect(kept.offset.inMilliseconds, closeTo(2 * dragged - 200, 100));

    // Played: the video muted, the track along it once it comes in.
    platform.position = kept.offset + s(1);
    await tester.tap(find.byKey(const Key('video-edit-play')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await _frames(tester);
    expect(platform.volumes[0], 0);
    expect(platform.playing, containsAll([0, platform.lastPlayer]));
    await tester.tap(find.byKey(const Key('video-edit-play')));
    await _settle(tester);

    // Download: the video with the track.
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    final (_, edit, _) = editor.applied.single;
    expect(edit.sound, EditSound.track);
    expect(await tester.runAsync(edit.track!.readAsBytes), [1, 2, 3]);
    expect(edit.trackLength, s(180));
    expect(edit.trackStart, kept.trackStart);
    expect(edit.offset, kept.offset);
    final part = edit.trackPart!;
    expect(part.gap, edit.offset);
    expect(part.from, edit.trackStart);
    // To the kept part's end: the track from its start, less the gap.
    expect(part.to, edit.trackStart + (s(180) - edit.offset));

    // The menu: without sound, and the sound alone.
    await tester.tap(find.byKey(const Key('video-edit-download-more')));
    await _frames(tester);
    await tester.tap(find.byKey(const Key('video-edit-download-silent')));
    await _settle(tester);
    expect(editor.applied[1].$2.sound, EditSound.none);
    expect(editor.applied[1].$3, isFalse);
    await tester.tap(find.byKey(const Key('video-edit-download-more')));
    await _frames(tester);
    await tester.tap(find.byKey(const Key('video-edit-download-sound')));
    await _settle(tester);
    expect(editor.applied[2].$2.sound, EditSound.track);
    expect(editor.applied[2].$3, isTrue);
    expect(saved.length, 3);
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
    await tester.tap(find.text('New track'));
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
        PageEdit(
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
      'v': 2,
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
    expect(editor.applied, isEmpty);
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
        PageEdit(
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

  testWidgets('a cloned capture\'s video keeps its edit, naming the copy\'s '
      'track', (tester) async {
    final (library, id) = await capture(tester);
    final copy = await tester.runAsync(() async {
      await library.setPageEdit(
        id,
        'k0',
        PageEdit(start: s(1), end: s(2), sound: EditSound.track, trackId: 'k1'),
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

  testWidgets('the track\'s volume: at the left of its bar, on its row; '
      'set, it\'s kept with the edit, the preview plays the track at it '
      '(on, without stopping), Download gets it, and Reset puts it back', (
    tester,
  ) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    await tester.tap(find.text('New track'));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-track-k1')));
    await _settle(tester);
    final track = platform.lastPlayer;

    // At the left of the bar, on the same row.
    final control = tester.getRect(
      find.byKey(const Key('video-edit-track-volume')),
    );
    final bar = tester.getRect(find.byKey(const Key('video-edit-track-bar')));
    expect(control.right, lessThanOrEqualTo(bar.left));
    expect(control.center.dy, closeTo(bar.center.dy, 1));
    expect(bar.right - control.left, closeTo(900 - 32, 1));
    expect(find.text('100%'), findsOneWidget);
    expect(platform.volumes[track], 1);

    // Played: the video muted, the track along it.
    await tester.tap(find.byKey(const Key('video-edit-play')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await _frames(tester);
    expect(platform.playing, containsAll([0, track]));

    // Tapped, it opens its slider; at half, the track plays on, at half.
    await tester.tap(find.byKey(const Key('video-edit-track-volume')));
    await _frames(tester);
    final slider = find.byKey(const Key('video-edit-track-volume-slider'));
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

    // Muted, and back as loud as it was.
    await tester.tap(find.byKey(const Key('video-edit-track-mute')));
    await _settle(tester);
    expect(platform.volumes[track], 0);
    expect(library.byId(id)!.pages.first.edit!.trackVolume, 0);
    expect(find.text('0%'), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('video-edit-track-mute')));
    await _settle(tester);
    expect(platform.volumes[track], 0.5);
    expect(library.byId(id)!.pages.first.edit!.trackVolume, 0.5);
    await tester.tapAt(const Offset(450, 1500));
    await _frames(tester);
    expect(slider, findsNothing);
    await tester.tap(find.byKey(const Key('video-edit-play')));
    await _settle(tester);

    // Download: the track goes in at half.
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await _settle(tester);
    expect(editor.applied.single.$2.trackVolume, 0.5);

    // Reset: as it is again.
    await tester.tap(find.byKey(const Key('video-edit-reset')));
    await _settle(tester);
    expect(library.byId(id)!.pages.first.edit, isNull);
    await tester.tap(find.text('New track'));
    await _settle(tester);
    expect(find.text('100%'), findsOneWidget);
    expect(library.byId(id)!.pages.first.edit!.trackVolume, 1);
    expect(platform.volumes[track], 1);
  });

  testWidgets('a kept edit\'s track plays at its volume, on its file screen '
      'and in the editor', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.runAsync(
      () => library.setPageEdit(
        id,
        'k0',
        PageEdit(
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
    await tester.tap(find.byKey(const Key('video-edit-track-volume')));
    await _frames(tester);
    final slider = find.byKey(const Key('video-edit-track-volume-slider'));
    for (final v in [20.0, 10.0, 5.0, 0.0]) {
      if (v == 20) tester.widget<Slider>(slider).onChangeStart!(25);
      tester.widget<Slider>(slider).onChanged!(v);
      await _frames(tester);
    }
    tester.widget<Slider>(slider).onChangeEnd?.call(0);
    await _settle(tester);
    expect(library.byId(id)!.pages.first.edit!.trackVolume, 0);
    await tester.tap(find.byKey(const Key('video-edit-track-mute')));
    await _settle(tester);
    expect(library.byId(id)!.pages.first.edit!.trackVolume, 0.25);
    expect(platform.volumes[platform.lastPlayer], 0.25);
  });

  testWidgets('a muted edit, opened again, unmutes to 100%', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.runAsync(
      () => library.setPageEdit(
        id,
        'k0',
        PageEdit(
          start: s(10),
          end: s(20),
          sound: EditSound.track,
          trackId: 'k1',
          trackVolume: 0,
        ),
      ),
    );
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    expect(find.text('0%'), findsOneWidget);
    await tester.tap(find.byKey(const Key('video-edit-track-volume')));
    await _frames(tester);
    await tester.tap(find.byKey(const Key('video-edit-track-mute')));
    await _settle(tester);
    expect(library.byId(id)!.pages.first.edit!.trackVolume, 1);
  });

  testWidgets('the track\'s volume fits its bar at the largest text size', (
    tester,
  ) async {
    tall(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final (library, id) = await capture(tester);
    await tester.pumpWidget(editScreen(library, id));
    await _settle(tester);
    await tester.tap(find.text('New track'));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-track-k1')));
    await _settle(tester);
    // No overflow (which would fail the test), the level on one line,
    // within the control.
    final control = tester.getRect(
      find.byKey(const Key('video-edit-track-volume')),
    );
    final level = tester.getRect(
      find.byKey(const Key('video-edit-track-volume-level')),
    );
    expect(control.contains(level.topLeft), isTrue);
    expect(control.contains(level.bottomRight - const Offset(1, 1)), isTrue);
    expect(find.text('100%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
