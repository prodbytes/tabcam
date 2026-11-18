import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/video_edit.dart';
import 'package:tabcam_app/screens/edited_playback.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'mini_player_test.dart' show FakeVideoPlatform;

Duration s(double seconds) => Duration(milliseconds: (seconds * 1000).round());

/// [json] through a JSON string, as saved and loaded.
Object? _encoded(Object? json) => jsonDecode(jsonEncode(json));

PageEdit _read(Map<String, Object?> json) => PageEdit.fromJson(_encoded(json))!;

/// The fake platform, each player where a test puts it, with its volume,
/// its seeks, its plays and its pauses; the players in [unknown] can't
/// say how long their file is (the browser, for a take it recorded), and
/// those in [starting] are still starting to play until their hold is
/// let go (the browser's players, a moment).
class _Players extends FakeVideoPlatform {
  final positions = <int, Duration>{};
  final volumes = <int, double>{};
  final seeksOf = <int, List<Duration>>{};
  final plays = <int>[];
  final pauses = <int>[];
  final unknown = <int>{};
  final starting = <int, Completer<void>>{};

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

  @override
  Future<void> play(int playerId) async {
    plays.add(playerId);
    await starting[playerId]?.future;
    return super.play(playerId);
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    (seeksOf[playerId] ??= []).add(position);
    positions[playerId] = position;
  }

  @override
  Future<void> pause(int playerId) {
    pauses.add(playerId);
    return super.pause(playerId);
  }

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      volumes[playerId] = volume;
}

void main() {
  final video = XFile('/tmp/made-up-take.mp4');
  final riff = XFile('/tmp/made-up-riff.m4a');

  RenderPlan plan(
    PageEdit? edit, {
    RenderKind kind = RenderKind.video,
    bool preview = false,
  }) => RenderPlan.of(
    edit,
    input: preview ? null : video,
    duration: s(20),
    inputExtension: 'mp4',
    songFile: preview ? null : riff,
    songLength: s(30),
    kind: kind,
    preview: preview,
  );

  group('an edit from before the two lanes', () {
    test('Original, without a track: the own sound, no song; downloads as '
        'before', () {
      final edit = _read({'startMs': 1000, 'endMs': 9000, 'sound': 'original'});
      expect(edit.ownAudible, isTrue);
      expect(edit.ownVolume, 1);
      expect(edit.song, isNull);
      expect(edit.hasSong, isFalse);
      final p = plan(edit);
      expect(p.own, const OwnLane());
      expect(p.song, isNull);
      expect(edit.toJson(), {
        'v': 2,
        'startMs': 1000,
        'endMs': 9000,
        'sound': 'original',
      });
    });

    test('Original with a track picked: the track stays, a manual song '
        'lane, muted, its settings kept; downloads as before', () {
      final edit = _read({
        'startMs': 1000,
        'endMs': 9000,
        'sound': 'original',
        'trackId': 'k1',
        'offsetMs': 1500,
        'trackStartMs': 500,
        'trackVolume': 0.4,
      });
      expect(edit.ownAudible, isTrue);
      expect(edit.song, SongMode.manual);
      expect(edit.songMuted, isTrue);
      expect(edit.trackId, 'k1');
      expect(edit.offset, s(1.5));
      expect(edit.trackStart, s(0.5));
      expect(edit.trackVolume, 0.4);
      expect(edit.sound, EditSound.original);
      final p = plan(edit);
      expect(p.own, const OwnLane());
      expect(p.song, isNull);
    });

    test('None: both lanes muted; downloads silent, as before', () {
      for (final track in [null, 'k1']) {
        final edit = _read({
          'startMs': 0,
          'endMs': 9000,
          'sound': 'none',
          'trackId': ?track,
        });
        expect(edit.ownMuted, isTrue, reason: '$track');
        expect(edit.ownVolume, 1, reason: '$track');
        expect(edit.sound, EditSound.none, reason: '$track');
        final p = plan(edit);
        expect(p.own, isNull, reason: '$track');
        expect(p.song, isNull, reason: '$track');
        expect(p.hasSound, isFalse, reason: '$track');
      }
    });

    test('Track: the own sound muted, the track heard at its volume, where '
        'it was; downloads as before', () {
      final json = {
        'startMs': 2000,
        'endMs': 8000,
        'sound': 'track',
        'trackId': 'k1',
        'offsetMs': -2000,
        'trackStartMs': 1000,
        'trackEndMs': 20000,
        'trackVolume': 0.5,
      };
      final edit = _read(json);
      expect(edit.ownMuted, isTrue);
      expect(edit.song, SongMode.manual);
      expect(edit.songMuted, isFalse);
      expect(edit.sound, EditSound.track);
      final p = plan(edit);
      expect(p.own, isNull);
      // What step 2's plan made of it: one clip, where trackSpan puts it.
      final span = trackSpan(
        s(6),
        s(30),
        s(-2),
        trackStart: s(1),
        trackEnd: s(20),
      )!;
      expect(p.song!.page, 'k1');
      expect(p.song!.volume, 0.5);
      expect(p.song!.clips, [
        SongClip(at: span.gap, from: span.from, to: span.to),
      ]);
      // Written back: the same old keys, and the lanes.
      final back = _encoded(edit.toJson()) as Map;
      for (final MapEntry(:key, :value) in json.entries) {
        expect(back[key], value, reason: key);
      }
      expect(back['v'], 2);
      expect(back['ownMuted'], isTrue);
      expect(back['song'], 'manual');
      expect(PageEdit.fromJson(back), edit);
    });

    test('Original, None and Track as the old constructor made them', () {
      expect(
        PageEdit.fromSound(start: s(0), end: s(1), sound: EditSound.none).sound,
        EditSound.none,
      );
      expect(
        PageEdit.fromSound(
          start: s(0),
          end: s(1),
          sound: EditSound.track,
          trackId: 'k1',
        ).sound,
        EditSound.track,
      );
      expect(
        PageEdit.fromSound(start: s(0), end: s(1)),
        PageEdit(start: s(0), end: s(1)),
      );
    });
  });

  group('the sound older apps read is worked out from the lanes', () {
    PageEdit lanes({
      double own = 1,
      bool ownMuted = false,
      double song = 1,
      bool songMuted = false,
      String? trackId = 'k1',
      SongMode? mode = SongMode.manual,
    }) => PageEdit(
      start: s(0),
      end: s(10),
      ownVolume: own,
      ownMuted: ownMuted,
      song: mode,
      songMuted: songMuted,
      trackId: trackId,
      trackVolume: song,
    );

    test('both heard: original (their safe fallback)', () {
      expect(lanes().sound, EditSound.original);
      expect(lanes().toJson()['sound'], 'original');
      expect(lanes(own: 0.3, song: 0.6).sound, EditSound.original);
      // Both in the download, mixed.
      final p = plan(lanes(own: 0.3, song: 0.6));
      expect(p.own, const OwnLane(volume: 0.3));
      expect(p.song!.volume, 0.6);
      expect(p.song!.clips, isNotEmpty);
    });

    test('only the song heard: track', () {
      expect(lanes(ownMuted: true).sound, EditSound.track);
      expect(lanes(own: 0).sound, EditSound.track);
    });

    test('neither heard: none', () {
      expect(lanes(ownMuted: true, songMuted: true).sound, EditSound.none);
      expect(lanes(ownMuted: true, song: 0).sound, EditSound.none);
      expect(lanes(ownMuted: true, trackId: null).sound, EditSound.none);
      expect(lanes(ownMuted: true, mode: SongMode.off).sound, EditSound.none);
    });

    test('only the own sound heard: original', () {
      expect(lanes(songMuted: true).sound, EditSound.original);
      expect(lanes(mode: null, trackId: null).sound, EditSound.original);
    });
  });

  group('an edit an older app changed since', () {
    /// A two-lane edit as this app writes it, with keys a newer one added.
    Map<String, Object?> written(PageEdit edit) => {
      ...edit.toJson(),
      'fades': {'inMs': 500, 'outMs': 800},
    };

    final both = PageEdit(
      start: s(1),
      end: s(9),
      ownVolume: 0.6,
      song: SongMode.manual,
      trackId: 'k1',
      offset: s(2),
      trackVolume: 0.8,
    );

    test('read as written when the old keys are as written', () {
      final json = written(both);
      final edit = _read(json);
      expect(edit.copyWith(extra: const {}), both);
      expect(edit.extra.keys, ['fades']);
    });

    test('Track picked there: its meaning wins, the own sound muted; the '
        'volumes and the newer keys kept', () {
      final edit = _read({...written(both), 'sound': 'track'});
      expect(edit.ownMuted, isTrue);
      expect(edit.ownVolume, 0.6);
      expect(edit.song, SongMode.manual);
      expect(edit.songMuted, isFalse);
      expect(edit.trackVolume, 0.8);
      expect(edit.sound, EditSound.track);
      expect(edit.extra['fades'], isNotNull);
      final p = plan(edit);
      expect(p.own, isNull);
      expect(p.song!.volume, 0.8);
    });

    test('None picked there: both muted, their levels kept', () {
      final edit = _read({...written(both), 'sound': 'none'});
      expect(edit.ownMuted, isTrue);
      expect(edit.songMuted, isTrue);
      expect(edit.ownVolume, 0.6);
      expect(edit.trackVolume, 0.8);
      expect(plan(edit).hasSound, isFalse);
    });

    test('Original picked there, after Track: the own sound heard, the '
        'track not (as that app plays it)', () {
      final songOnly = both.copyWith(ownMuted: true);
      expect(songOnly.sound, EditSound.track);
      final edit = _read({...written(songOnly), 'sound': 'original'});
      expect(edit.ownMuted, isFalse);
      expect(edit.ownVolume, 0.6);
      expect(edit.songMuted, isTrue);
      final p = plan(edit);
      expect(p.own, const OwnLane(volume: 0.6));
      expect(p.song, isNull);
    });

    test('its track moved there: the manual lane is where it put it', () {
      final edit = _read({...written(both), 'offsetMs': 4500});
      expect(edit.offset, s(4.5));
      expect(edit.ownVolume, 0.6);
      expect(edit.sound, EditSound.original);
    });
  });

  group('a newer app\'s edit, `song` left out as the page\'s default', () {
    // A later step writes `song` only when it isn't the default (a take's
    // song lined up by itself, a legacy take's placed at the start).
    final json = {
      'v': 2,
      'startMs': 0,
      'endMs': 9000,
      'sound': 'original',
      'trackId': 'p7',
      'offsetMs': 1500,
      'trackVolume': 0.8,
    };

    test('with a track picked: the song lane is auto, heard as its track '
        'keys approximate it, both lanes in the download', () {
      final edit = _read(json);
      expect(edit.song, isNull);
      expect(edit.songMode, SongMode.auto);
      expect(edit.hasSong, isTrue);
      expect(edit.songAudible, isTrue);
      expect(edit.sound, EditSound.original);
      final p = plan(edit);
      expect(p.own, const OwnLane());
      expect(p.song!.volume, 0.8);
      expect(p.song!.clips, [
        SongClip(at: s(1.5), from: Duration.zero, to: s(7.5)),
      ]);
      // Written back as it came: `song` still left out.
      expect(edit.toJson(), json);
    });

    test('without one: no song', () {
      final edit = _read({...json}..remove('trackId'));
      expect(edit.songMode, SongMode.off);
      expect(edit.hasSong, isFalse);
      expect(plan(edit).song, isNull);
    });
  });

  test('mute keeps the level, through JSON (a reopen)', () {
    final edit = PageEdit(
      start: s(0),
      end: s(10),
      ownVolume: 0.6,
      ownMuted: true,
      song: SongMode.manual,
      songMuted: true,
      trackId: 'k1',
      trackVolume: 0.4,
    );
    final back = _read(edit.toJson());
    expect(back, edit);
    expect(back.ownVolume, 0.6);
    expect(back.trackVolume, 0.4);
    expect(back.ownMuted, isTrue);
    expect(back.songMuted, isTrue);
    expect(back.ownAudible, isFalse);
    expect(back.songAudible, isFalse);
  });

  test('every field round-trips, and each one counts in ==', () {
    final edit = PageEdit(
      start: s(1),
      end: s(9),
      ownVolume: 0.55,
      ownMuted: true,
      song: SongMode.manual,
      songMuted: true,
      trackId: 'k1',
      trackStart: s(0.5),
      trackEnd: s(7),
      offset: s(-1.5),
      trackVolume: 0.35,
      tab: false,
      extra: const {'nudgeMs': -120},
    );
    expect(_read(edit.toJson()), edit);
    expect(_read(edit.toJson()).hashCode, edit.hashCode);
    final changed = [
      edit.copyWith(start: s(2)),
      edit.copyWith(end: s(8)),
      edit.copyWith(ownVolume: 0.5),
      edit.copyWith(ownMuted: false),
      edit.copyWith(song: SongMode.off),
      edit.copyWith(song: null),
      edit.copyWith(songMuted: false),
      edit.copyWith(trackId: 'k2'),
      edit.copyWith(trackId: null),
      edit.copyWith(trackStart: s(1)),
      edit.copyWith(trackEnd: s(6)),
      edit.copyWith(trackEnd: null),
      edit.copyWith(offset: s(1)),
      edit.copyWith(trackVolume: 0.3),
      edit.copyWith(tab: true),
      edit.copyWith(extra: const {}),
    ];
    for (final other in changed) {
      expect(other, isNot(edit), reason: '$other');
      expect(_read(other.toJson()), other, reason: '$other');
    }
    // Nothing given: the same.
    expect(edit.copyWith(), edit);
    // Volumes as a lane's: within 0–1, to the hundredth.
    expect(edit.copyWith(ownVolume: 1.7).ownVolume, 1);
    expect(edit.copyWith(trackVolume: 0.333).trackVolume, 0.33);
    expect(
      _read({'v': 2, 'startMs': 0, 'endMs': 10, 'ownVolume': 'loud'}).ownVolume,
      1,
    );
  });

  group('the preview\'s plan', () {
    final edit = PageEdit(
      start: s(1),
      end: s(9),
      song: SongMode.manual,
      trackId: 'k1',
      offset: s(1),
      trackVolume: 0.8,
    );

    test('keeps a muted lane at 0, so muting moves nothing', () {
      final heard = plan(edit, preview: true);
      final muted = plan(
        edit.copyWith(ownMuted: true, songMuted: true),
        preview: true,
      );
      expect(heard.own, const OwnLane());
      expect(heard.song!.volume, 0.8);
      expect(muted.own, const OwnLane(volume: 0));
      expect(muted.song!.volume, 0);
      expect(muted.timeline, heard.timeline);
      expect(muted.hasSound, isFalse);
      // Download's leaves them out.
      final download = plan(edit.copyWith(ownMuted: true, songMuted: true));
      expect(download.own, isNull);
      expect(download.song, isNull);
    });
  });

  group('the master', () {
    final edit = PageEdit(
      start: s(1),
      end: s(9),
      ownVolume: 0.6,
      song: SongMode.manual,
      trackId: 'k1',
      offset: s(1),
      trackVolume: 0.8,
    );

    test('is written only when not 100% or muted, read back, and kept '
        'within 0–200% to the hundredth', () {
      expect(edit.toJson().containsKey('masterVolume'), isFalse);
      expect(edit.toJson().containsKey('masterMuted'), isFalse);
      final louder = edit.copyWith(masterVolume: 1.5, masterMuted: true);
      final json = louder.toJson();
      expect(json['masterVolume'], 1.5);
      expect(json['masterMuted'], isTrue);
      expect(_read(json), louder);
      expect(edit.copyWith(masterVolume: 3).masterVolume, 2);
      expect(edit.copyWith(masterVolume: -1).masterVolume, 0);
      expect(edit.copyWith(masterVolume: 1.234).masterVolume, 1.23);
      expect(_read({...edit.toJson(), 'masterVolume': 'loud'}).masterVolume, 1);
    });

    test('muted (or at 0%), no lane is heard: older apps read no sound; '
        'one that gives it sound back unmutes it', () {
      final muted = edit.copyWith(masterMuted: true);
      expect(muted.ownAudible, isFalse);
      expect(muted.songAudible, isFalse);
      expect(muted.sound, EditSound.none);
      expect(edit.copyWith(masterVolume: 0).sound, EditSound.none);
      final changed = _read({...muted.toJson(), 'sound': 'original'});
      expect(changed.masterMuted, isFalse);
      expect(changed.ownAudible, isTrue);
      final atZero = _read({
        ...edit.copyWith(masterVolume: 0).toJson(),
        'sound': 'original',
      });
      expect(atZero.masterVolume, 1);
    });

    test('lifts or lowers both lanes in the plan, up to 200%', () {
      final louder = plan(edit.copyWith(masterVolume: 1.5));
      expect(louder.own, const OwnLane(volume: 0.9));
      expect(louder.song!.volume, 1.2);
      final channel = louder.toChannel(output: '/tmp/out.mp4');
      expect(channel['own'], {'volume': 0.9});
      expect((channel['song']! as Map)['volume'], 1.2);
      expect(plan(edit.copyWith(masterVolume: 0.5)).own!.volume, 0.3);
      // The whole video at 200%: rendered, not saved as it is.
      final whole = PageEdit(
        start: Duration.zero,
        end: s(20),
        fadeIn: Duration.zero,
        fadeOut: Duration.zero,
      );
      expect(plan(whole).passthrough, isTrue);
      expect(plan(whole.copyWith(masterVolume: 2)).own!.volume, 2);
      expect(plan(whole.copyWith(masterVolume: 2)).passthrough, isFalse);
    });

    test('muted: Download leaves both lanes out; the preview keeps them '
        'at 0, so muting moves nothing', () {
      final muted = edit.copyWith(masterMuted: true);
      final download = plan(muted);
      expect(download.own, isNull);
      expect(download.song, isNull);
      expect(download.hasSound, isFalse);
      final preview = plan(muted, preview: true);
      expect(preview.own, const OwnLane(volume: 0));
      expect(preview.song!.volume, 0);
      expect(preview.timeline, plan(edit, preview: true).timeline);
    });
  });

  group('EditedPlayback with fake players', () {
    late _Players platform;
    setUp(() => VideoPlayerPlatform.instance = platform = _Players());

    Future<(VideoPlayerController, VideoPlayerController)> players(
      WidgetTester tester,
    ) async {
      final pair = await tester.runAsync(() async {
        final take = VideoPlayerController.networkUrl(
          Uri.parse('https://example.com/made-up-take.mp4'),
        );
        final song = VideoPlayerController.networkUrl(
          Uri.parse('https://example.com/made-up-riff.m4a'),
        );
        await take.initialize();
        await song.initialize();
        return (take, song);
      });
      addTearDown(() async {
        await pair!.$1.dispose();
        await pair.$2.dispose();
      });
      // Opened, each player is told it's paused: no pause of a test's.
      platform.pauses.clear();
      return pair!;
    }

    // Kept 1–9 s; the song from its start, 1 s into the kept part.
    final edit = PageEdit(
      start: s(1),
      end: s(9),
      ownVolume: 0.6,
      song: SongMode.manual,
      trackId: 'k1',
      offset: s(1),
    );
    RenderPlan? previewOf(PageEdit e) =>
        EditedPlayback.planOf(e, songLength: s(30));

    Future<void> ticks(WidgetTester tester, int n) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('the own lane at 0.6 plays the video at 0.6; the song kept '
        'in step: a few ms off let be, up to 250 ms nudged by its speed and '
        'put back once in step, further sought back; a late start is sought '
        'that much ahead the next time; a volume change seeks nothing', (
      tester,
    ) async {
      final (take, song) = await players(tester);
      final takeId = take.playerId;
      final songId = song.playerId;
      final playback = EditedPlayback(take);
      addTearDown(playback.dispose);
      await playback.set(previewOf(edit), song: song);
      expect(platform.volumes[takeId], 0.6);
      expect(platform.volumes[songId], 1);

      // 4 s into the video: 2 s into the song.
      await take.seekTo(s(4));
      await take.play();
      await ticks(tester, 3);
      expect(platform.playing, contains(songId));
      expect(platform.seeksOf[songId], [s(2)]);

      // 5 ms off: in step, at its speed.
      platform.positions[songId] = s(2.005);
      await ticks(tester, 2);
      expect(platform.seeksOf[songId], [s(2)]);
      expect(platform.speeds[songId] ?? 1, 1);

      // 100 ms ahead: a little slower (5% at most), not sought.
      platform.positions[songId] = s(2.1);
      await ticks(tester, 2);
      expect(platform.seeksOf[songId], [s(2)]);
      expect(platform.speeds[songId], 0.95);
      // 20 ms behind: a little faster.
      platform.positions[songId] = s(1.98);
      await ticks(tester, 2);
      expect(platform.speeds[songId], closeTo(1.02, 0.001));
      // Back in step: at its speed again.
      platform.positions[songId] = s(2);
      await ticks(tester, 2);
      expect(platform.speeds[songId], 1);
      expect(platform.seeksOf[songId], [s(2)]);

      // 400 ms off: sought back to where the plan has it.
      platform.positions[songId] = s(2.4);
      await ticks(tester, 2);
      expect(platform.seeksOf[songId], [s(2), s(2)]);

      // Started late: 120 ms behind at its first check; the next start
      // is sought that much ahead.
      await take.pause();
      await ticks(tester, 2);
      await take.play();
      platform.starting[songId] = Completer<void>();
      await ticks(tester, 1);
      platform.positions[songId] = s(1.88);
      platform.starting.remove(songId)!.complete();
      await ticks(tester, 3);
      await take.pause();
      await ticks(tester, 2);
      await take.play();
      await ticks(tester, 2);
      expect(platform.seeksOf[songId]!.last, s(2.12));
      platform.positions[songId] = s(2);
      await ticks(tester, 2);

      // A volume (and a mute) change: heard at once, nothing sought or
      // paused.
      final sought = [...platform.seeksOf[songId]!];
      platform.pauses.clear();
      await playback.set(
        previewOf(edit.copyWith(ownVolume: 0.3, trackVolume: 0.5)),
        song: song,
      );
      await playback.set(
        previewOf(edit.copyWith(ownMuted: true, songMuted: true)),
        song: song,
      );
      await ticks(tester, 3);
      expect(platform.volumes[takeId], 0);
      expect(platform.volumes[songId], 0);
      expect(platform.seeksOf[songId], sought);
      expect(platform.pauses, isNot(contains(songId)));
      expect(platform.playing, contains(songId));

      // Through the master at 200%: the video (60%) at 100%, as loud as
      // a player plays; the song (100%) too.
      await playback.set(previewOf(edit.copyWith(masterVolume: 2)), song: song);
      expect(platform.volumes[takeId], 1);
      expect(platform.volumes[songId], 1);
      await playback.set(
        previewOf(edit.copyWith(masterVolume: 0.5)),
        song: song,
      );
      expect(platform.volumes[takeId], 0.3);
      expect(platform.volumes[songId], 0.5);

      // Moved: the song finds its place again.
      await playback.set(previewOf(edit.copyWith(offset: s(2))), song: song);
      await ticks(tester, 3);
      expect(platform.seeksOf[songId]!.last, s(1));
      await take.pause();
      await ticks(tester, 2);
    });

    testWidgets('the editor\'s player plays from where it is in a cut '
        'part: no seek to the kept start, the own lane at its level; the '
        'fades and the song begin at the kept part\'s start', (tester) async {
      final (take, song) = await players(tester);
      final takeId = take.playerId;
      final songId = song.playerId;
      final playback = EditedPlayback(take, whole: true);
      addTearDown(playback.dispose);
      await playback.set(previewOf(edit), song: song);

      // 0.4 s in: cut off, before the kept part.
      await playback.seek(s(0.4));
      platform.seeksOf[takeId]!.clear();
      await playback.playPause();
      expect(platform.playing, contains(takeId));
      expect(platform.seeksOf[takeId], isEmpty);
      expect(platform.volumes[takeId], 0.6);

      // It plays on there: not brought to the kept part, not faded, no
      // song.
      for (final at in [0.5, 0.7, 0.9]) {
        platform.positions[takeId] = s(at);
        await ticks(tester, 2);
        expect(platform.seeksOf[takeId], isEmpty, reason: '$at');
        expect(platform.volumes[takeId], 0.6, reason: '$at');
      }
      expect(platform.pauses, isEmpty);
      expect(platform.playing, isNot(contains(songId)));

      // 1.5 s into the kept part: half way up its fade in, the song from
      // where the plan has it.
      platform.positions[takeId] = s(2.5);
      await ticks(tester, 3);
      expect(platform.volumes[takeId], closeTo(0.3, 1e-9));
      expect(platform.seeksOf[songId], [s(0.5)]);
      expect(platform.playing, contains(songId));
      expect(platform.seeksOf[takeId], isEmpty);
      await take.pause();
      await ticks(tester, 2);
    });

    testWidgets('reaching the kept part\'s end it pauses there; Play then '
        'starts at the kept start', (tester) async {
      final (take, song) = await players(tester);
      final takeId = take.playerId;
      final songId = song.playerId;
      final playback = EditedPlayback(take, whole: true);
      addTearDown(playback.dispose);
      await playback.set(previewOf(edit), song: song);

      await playback.seek(s(8.5));
      await playback.playPause();
      await ticks(tester, 2);
      expect(platform.playing, containsAll([takeId, songId]));
      platform.positions[takeId] = s(8.95);
      await ticks(tester, 2);
      expect(platform.pauses, isEmpty);

      // Past the end, 9 s: paused, both, and shown at the end.
      platform.positions[takeId] = s(9.05);
      await ticks(tester, 3);
      expect(platform.playing, isEmpty);
      expect(platform.pauses, containsAll([takeId, songId]));
      expect(platform.seeksOf[takeId]!.last, s(9));
      expect(take.value.position, s(9));

      // Play: from the kept part's start.
      await playback.playPause();
      expect(platform.seeksOf[takeId]!.last, s(1));
      expect(platform.playing, contains(takeId));
      await ticks(tester, 2);
      await take.pause();
      await ticks(tester, 2);

      // Paused 30 ms before the end, then played: the end is still seen
      // passed at the first check.
      await playback.seek(s(8.97));
      await playback.playPause();
      platform.positions[takeId] = s(9.07);
      await ticks(tester, 3);
      expect(platform.playing, isNot(contains(takeId)));
      expect(platform.seeksOf[takeId]!.last, s(9));

      // The kept part made longer since (the edit reset): where it
      // stopped is inside it now, and Play plays on from there.
      await playback.set(previewOf(edit.copyWith(end: s(20))), song: song);
      await playback.playPause();
      expect(platform.seeksOf[takeId]!.last, s(9));
      expect(platform.playing, contains(takeId));
      await take.pause();
      await ticks(tester, 2);
    });

    testWidgets('sought past the kept end, it plays on to the video\'s '
        'end; Play there starts at the kept start', (tester) async {
      final (take, song) = await players(tester);
      final takeId = take.playerId;
      final songId = song.playerId;
      final playback = EditedPlayback(take, whole: true);
      addTearDown(playback.dispose);
      await playback.set(previewOf(edit), song: song);

      await playback.seek(s(8));
      await playback.playPause();
      await ticks(tester, 3);
      expect(platform.playing, containsAll([takeId, songId]));

      // Sought over the end while it plays: it plays on, as the video
      // is (at its lane's level, the song paused).
      await playback.seek(s(9.5));
      await ticks(tester, 3);
      platform.positions[takeId] = s(10.5);
      await ticks(tester, 3);
      expect(platform.pauses, isNot(contains(takeId)));
      expect(platform.playing, contains(takeId));
      expect(platform.playing, isNot(contains(songId)));
      expect(platform.volumes[takeId], 0.6);
      expect(platform.seeksOf[takeId]!.last, s(9.5));

      // The video's end: its player stops by itself, there.
      platform.complete(takeId);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await ticks(tester, 2);
      expect(platform.playing, isNot(contains(takeId)));
      expect(take.value.position, const Duration(minutes: 3));

      await playback.playPause();
      expect(platform.seeksOf[takeId]!.last, s(1));
      expect(platform.playing, contains(takeId));
      await take.pause();
      await ticks(tester, 2);
    });

    testWidgets('a seek while it plays keeps it playing, the song found '
        'again once', (tester) async {
      final (take, song) = await players(tester);
      final takeId = take.playerId;
      final songId = song.playerId;
      final playback = EditedPlayback(take, whole: true);
      addTearDown(playback.dispose);
      await playback.set(previewOf(edit), song: song);

      // 4 s into the video: 2 s into the song.
      await playback.seek(s(4));
      await playback.playPause();
      await ticks(tester, 3);
      expect(platform.seeksOf[songId], [s(2)]);
      platform.pauses.clear();

      // Half a second on, less than a check takes for a seek.
      await playback.seek(s(4.5));
      await ticks(tester, 3);
      expect(platform.pauses, isNot(contains(takeId)));
      expect(platform.playing, containsAll([takeId, songId]));
      expect(platform.seeksOf[songId], [s(2), s(2.5)]);

      // Further on: once, too.
      await playback.seek(s(7));
      await ticks(tester, 3);
      expect(platform.pauses, isNot(contains(takeId)));
      expect(platform.playing, containsAll([takeId, songId]));
      expect(platform.seeksOf[songId], [s(2), s(2.5), s(5)]);
      expect(platform.seeksOf[takeId], [s(4), s(4.5), s(7)]);
      await take.pause();
      await ticks(tester, 2);
    });

    testWidgets('a video whose length isn\'t known never stops by itself', (
      tester,
    ) async {
      // The take is the first player made.
      platform.unknown.add(0);
      final (take, _) = await players(tester);
      final takeId = take.playerId;
      expect(take.value.duration, lessThan(Duration.zero));
      for (final plan in [
        null,
        // As the editor plans it then: nothing kept, no length to keep.
        RenderPlan.of(
          PageEdit(start: Duration.zero, end: Duration.zero, ownVolume: 0.6),
          preview: true,
        ),
      ]) {
        final playback = EditedPlayback(take, whole: true);
        await playback.set(plan);
        await playback.playPause();
        for (final at in [0.1, 5.0, 60.0]) {
          platform.positions[takeId] = s(at);
          await ticks(tester, 3);
        }
        expect(platform.playing, contains(takeId), reason: '$plan');
        expect(platform.pauses, isEmpty, reason: '$plan');
        await playback.playPause();
        await ticks(tester, 2);
        expect(platform.pauses, [takeId], reason: '$plan');
        platform.pauses.clear();
        playback.dispose();
      }
    });

    testWidgets('the file screen\'s player still starts at the kept start '
        'when outside it', (tester) async {
      final (take, song) = await players(tester);
      final takeId = take.playerId;
      final playback = EditedPlayback(take);
      addTearDown(playback.dispose);
      await playback.set(previewOf(edit), song: song);

      // 0.4 s in, before the kept part: Play starts at 1 s.
      await take.seekTo(s(0.4));
      await playback.playPause();
      expect(platform.seeksOf[takeId], [s(0.4), s(1)]);
      expect(platform.playing, contains(takeId));

      // Found before it while it plays: brought back, playing on.
      platform.positions[takeId] = s(0.2);
      await ticks(tester, 2);
      expect(platform.seeksOf[takeId], [s(0.4), s(1), s(1)]);
      expect(platform.playing, contains(takeId));

      // At its end: back to its start, paused.
      platform.positions[takeId] = s(9.05);
      await ticks(tester, 2);
      expect(platform.seeksOf[takeId], [s(0.4), s(1), s(1), s(1)]);
      expect(platform.playing, isNot(contains(takeId)));
      await ticks(tester, 2);
    });

    testWidgets('Play pressed twice at once plays once', (tester) async {
      final (take, song) = await players(tester);
      final takeId = take.playerId;
      for (final whole in [true, false]) {
        final playback = EditedPlayback(take, whole: whole);
        await playback.set(previewOf(edit), song: song);
        await take.seekTo(s(4));
        platform.plays.clear();
        platform.pauses.clear();
        await Future.wait([playback.playPause(), playback.playPause()]);
        expect(platform.plays, [takeId], reason: '$whole');
        expect(platform.pauses, isEmpty, reason: '$whole');
        expect(platform.playing, contains(takeId), reason: '$whole');
        // Pressed again once it plays: paused.
        await playback.playPause();
        expect(platform.pauses, contains(takeId), reason: '$whole');
        await ticks(tester, 2);
        playback.dispose();
      }
    });

    testWidgets('a player still starting to play isn\'t paused: Play '
        'pressed again is dropped, until it has waited 3 s; the song is '
        'paused once it has started', (tester) async {
      final (take, song) = await players(tester);
      final takeId = take.playerId;
      final songId = song.playerId;
      final playback = EditedPlayback(take, whole: true);
      addTearDown(playback.dispose);
      await playback.set(previewOf(edit), song: song);
      await playback.seek(s(4));

      // The video's player takes its time to start: a second press does
      // nothing meanwhile.
      platform.starting[takeId] = Completer();
      final played = playback.playPause();
      await ticks(tester, 2);
      await playback.playPause();
      expect(platform.plays.where((id) => id == takeId), hasLength(1));
      expect(platform.pauses, isNot(contains(takeId)));
      // It started: the next press pauses it.
      platform.starting.remove(takeId)!.complete();
      await played;
      await playback.playPause();
      expect(platform.pauses, contains(takeId));
      await ticks(tester, 2);

      // One that doesn't start in 3 s can be paused all the same.
      platform.pauses.clear();
      final stuck = platform.starting[takeId] = Completer();
      unawaited(playback.playPause());
      await ticks(tester, 20);
      await playback.playPause();
      expect(platform.pauses, isNot(contains(takeId)));
      await ticks(tester, 12);
      await playback.playPause();
      expect(platform.pauses, contains(takeId));
      platform.starting.remove(takeId);
      stuck.complete();
      await take.pause();
      await ticks(tester, 2);

      // The song's player takes its time to start: sought meanwhile, it's
      // paused only once it has, then found again where the video is.
      platform.pauses.clear();
      platform.starting[songId] = Completer();
      await playback.playPause();
      await ticks(tester, 3);
      expect(platform.plays.last, songId);
      expect(platform.playing, isNot(contains(songId)));
      final sought = playback.seek(s(6));
      await ticks(tester, 2);
      expect(platform.pauses, isNot(contains(songId)));
      platform.starting.remove(songId)!.complete();
      await sought;
      expect(platform.pauses, contains(songId));
      await ticks(tester, 3);
      expect(platform.seeksOf[songId]!.last, s(4));
      expect(platform.playing, containsAll([takeId, songId]));
      await take.pause();
      await ticks(tester, 2);
    });
  });
}
