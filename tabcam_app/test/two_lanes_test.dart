import 'dart:convert';

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

/// The fake platform, each player where a test puts it, with its volume
/// and its seeks.
class _Players extends FakeVideoPlatform {
  final positions = <int, Duration>{};
  final volumes = <int, double>{};
  final seeksOf = <int, List<Duration>>{};
  final pauses = <int>[];

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

    testWidgets('the own lane at 0.6 plays the video at 0.6; the song '
        'drifting 200 ms is sought back, 100 ms is let be; a volume change '
        'seeks nothing', (tester) async {
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

      // 100 ms off: let be, even after a check.
      platform.positions[songId] = s(2.1);
      await ticks(tester, EditedPlayback.driftChecks + 2);
      expect(platform.seeksOf[songId], [s(2)]);

      // 200 ms off: sought back to where the plan has it.
      platform.positions[songId] = s(2.2);
      await ticks(tester, EditedPlayback.driftChecks + 2);
      expect(platform.seeksOf[songId], [s(2), s(2)]);

      // A volume (and a mute) change: heard at once, nothing sought or
      // paused.
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
      expect(platform.seeksOf[songId], [s(2), s(2)]);
      expect(platform.pauses, isNot(contains(songId)));
      expect(platform.playing, contains(songId));

      // Moved: the song finds its place again.
      await playback.set(previewOf(edit.copyWith(offset: s(2))), song: song);
      await ticks(tester, 3);
      expect(platform.seeksOf[songId]!.last, s(1));
      await take.pause();
      await ticks(tester, 2);
    });
  });
}
