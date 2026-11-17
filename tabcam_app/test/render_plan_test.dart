import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/take_log.dart';
import 'package:tabcam_app/capture/video_edit.dart';

Duration s(double seconds) => Duration(milliseconds: (seconds * 1000).round());

/// The one plan that Download renders and the preview plays, from today's
/// edits: the same output as before (the kept part, the sound kept, taken
/// out, or replaced by a track placed by `trackSpan`), as clips of a song
/// lane in output time.
void main() {
  final video = XFile('/tmp/made-up-take.mp4');
  final riff = XFile('/tmp/made-up-riff.m4a');

  RenderPlan plan(
    PageEdit? edit, {
    Duration songLength = Duration.zero,
    RenderKind kind = RenderKind.video,
    EditFormats formats = EditFormats.standard,
    String extension = 'mp4',
    Duration duration = const Duration(seconds: 20),
  }) => RenderPlan.of(
    edit,
    input: video,
    duration: duration,
    inputExtension: extension,
    songFile: riff,
    songLength: songLength,
    kind: kind,
    formats: formats,
  );

  /// The whole video, [end] long, without fades.
  PageEdit still(Duration end) => PageEdit(
    start: Duration.zero,
    end: end,
    fadeIn: Duration.zero,
    fadeOut: Duration.zero,
  );

  group('a plan of today\'s edits', () {
    test('Original: the kept part with its own sound as it is', () {
      final p = plan(PageEdit(start: s(2), end: s(8)));
      expect(p.start, s(2));
      expect(p.end, s(8));
      expect(p.length, s(6));
      expect(p.own, const OwnLane());
      expect(p.song, isNull);
      expect(p.video, isTrue);
      expect(p.format, EditFormat.mp4);
      expect(p.hasSound, isTrue);
    });

    test('None: no lane at all', () {
      final p = plan(
        PageEdit.fromSound(start: s(2), end: s(8), sound: EditSound.none),
      );
      expect(p.own, isNull);
      expect(p.song, isNull);
      expect(p.hasSound, isFalse);
    });

    test('a track replaces the own sound, as one clip where trackSpan puts '
        'it, for every case it has', () {
      // (kept part, track length, offset, track start, track end): the
      // same cases as trackSpan's own tests, and a track at −2 s and +3 s
      // with trims.
      final cases = [
        (s(0), s(10), s(4), s(0), s(0), null),
        (s(0), s(10), s(20), s(0), s(0), null),
        (s(0), s(10), s(4), s(3), s(0), null),
        (s(0), s(10), s(4), s(8), s(0), null),
        (s(0), s(10), s(4), s(-1), s(0), null),
        (s(0), s(2), s(4), s(-1), s(0), null),
        (s(0), s(10), s(4), s(10), s(0), null),
        (s(0), s(10), s(4), s(-4), s(0), null),
        (s(0), s(10), s(4), s(2), s(1), s(3)),
        (s(0), s(10), s(4), s(-0.5), s(1), s(3)),
        (s(0), s(2), s(4), s(0), s(1), s(9)),
        (s(0), s(10), s(4), s(-3), s(1), s(3)),
        // Trimmed, a track at −2 s and at +3 s, trimmed too.
        (s(3), s(15), s(30), s(-2), s(1), s(20)),
        (s(3), s(15), s(30), s(3), s(1), s(20)),
        (s(3), s(15), s(30), s(3), s(5), s(8)),
        (s(4.5), s(6), s(30), s(-2), s(0), null),
        (s(4.5), s(6), s(30), s(3), s(0), null),
      ];
      for (final (start, end, length, offset, from, to) in cases) {
        final edit = PageEdit.fromSound(
          start: start,
          end: end,
          sound: EditSound.track,
          trackId: 'k1',
          trackStart: from,
          trackEnd: to,
          offset: offset,
          trackVolume: 0.5,
        );
        final span = trackSpan(
          end - start,
          length,
          offset,
          trackStart: from,
          trackEnd: to,
        );
        final p = plan(edit, songLength: length);
        final reason = '$start–$end, $length at $offset, $from–$to';
        expect(p.own, isNull, reason: reason);
        expect(p.song!.page, 'k1', reason: reason);
        expect(p.song!.file, riff, reason: reason);
        expect(p.song!.volume, 0.5, reason: reason);
        expect(p.song!.clips, [
          if (span != null)
            SongClip(at: span.gap, from: span.from, to: span.to),
        ], reason: reason);
        // Where the song is along the output: in its clip only.
        if (span != null) {
          expect(p.songAt(span.gap), span.from, reason: reason);
          expect(
            p.songAt(span.gap + (span.to - span.from) - s(0.001)),
            span.to - s(0.001),
            reason: reason,
          );
          expect(p.songAt(span.gap + (span.to - span.from)), isNull);
          if (span.gap > Duration.zero) {
            expect(p.songAt(span.gap - s(0.001)), isNull, reason: reason);
          }
        }
      }
    });

    test('a track at −2 s and at +3 s: the gaps and spans of before', () {
      // Kept 3–9 s (6 s); a 30 s track, its 1–20 s used.
      PageEdit at(double offset) => PageEdit.fromSound(
        start: s(3),
        end: s(9),
        sound: EditSound.track,
        trackId: 'k1',
        trackStart: s(1),
        trackEnd: s(20),
        offset: s(offset),
      );
      // 2 s of its used part cut before the video: 3–9 s of the track.
      expect(plan(at(-2), songLength: s(30)).song!.clips, [
        SongClip(at: Duration.zero, from: s(3), to: s(9)),
      ]);
      // 3 s of silence, then 1–4 s of it.
      expect(plan(at(3), songLength: s(30)).song!.clips, [
        SongClip(at: s(3), from: s(1), to: s(4)),
      ]);
      // Its length unknown: nothing fits, the song lane is silent.
      final unknown = plan(at(3));
      expect(unknown.song!.clips, isEmpty);
      expect(unknown.hasSound, isFalse);
    });

    test('without sound: neither lane, the rest kept', () {
      final edit = PageEdit.fromSound(
        start: s(1),
        end: s(5),
        sound: EditSound.track,
        trackId: 'k1',
      );
      final p = plan(edit, songLength: s(10), kind: RenderKind.silent);
      expect(p.video, isTrue);
      expect(p.start, s(1));
      expect(p.end, s(5));
      expect(p.own, isNull);
      expect(p.song, isNull);
      expect(
        plan(
          PageEdit(start: s(1), end: s(5)),
          kind: RenderKind.silent,
        ).own,
        isNull,
      );
    });

    test('the sound alone: no picture, in the sound\'s format', () {
      final p = plan(
        PageEdit(start: s(1), end: s(5)),
        kind: RenderKind.sound,
        formats: const EditFormats(
          video: EditFormat.webm,
          sound: EditFormat.wav,
        ),
      );
      expect(p.video, isFalse);
      expect(p.format, EditFormat.wav);
      expect(p.own, const OwnLane());
      expect(p.passthrough, isFalse);
    });

    test('no edit: the whole video as it is, fading in and out over 3 s', () {
      final p = plan(null);
      expect(p.start, Duration.zero);
      expect(p.end, s(20));
      expect(p.own, const OwnLane());
      expect((p.fadeIn, p.fadeOut), (s(3), s(3)));
      expect(p.passthrough, isFalse);
      expect(plan(still(s(20))).passthrough, isTrue);
    });
  });

  group('clips', () {
    test('are cut to the kept length, the song with them', () {
      expect(
        clampClips([
          // Starting before the output: its start cut.
          SongClip(at: s(-1), from: s(2), to: s(5)),
          // Past the end: cut there.
          SongClip(at: s(8), from: s(0), to: s(5)),
          // Wholly outside: dropped.
          SongClip(at: s(10), from: s(0), to: s(1)),
          SongClip(at: s(-3), from: s(0), to: s(2)),
          // Empty: dropped.
          SongClip(at: s(4), from: s(3), to: s(3)),
        ], s(10)),
        [
          SongClip(at: Duration.zero, from: s(3), to: s(5)),
          SongClip(at: s(8), from: s(0), to: s(2)),
        ],
      );
      // At another speed (to come), the song's part scales.
      expect(
        clampClips([
          SongClip(at: s(-1), from: s(0), to: s(10), speed: 0.5),
        ], s(4)),
        [SongClip(at: Duration.zero, from: s(0.5), to: s(2.5), speed: 0.5)],
      );
    });

    test('songAt finds the clip by a binary search, null in the gaps', () {
      final clips = [
        SongClip(at: s(1), from: s(10), to: s(12)),
        SongClip(at: s(4), from: s(0), to: s(1)),
        SongClip(at: s(6), from: s(30), to: s(34), speed: 2),
      ];
      expect(songAtIn(clips, s(0.5)), isNull);
      expect(songAtIn(clips, s(1)), s(10));
      expect(songAtIn(clips, s(2.5)), s(11.5));
      expect(songAtIn(clips, s(3)), isNull);
      expect(songAtIn(clips, s(4.5)), s(0.5));
      expect(songAtIn(clips, s(5)), isNull);
      expect(songAtIn(clips, s(7)), s(32));
      expect(songAtIn(clips, s(8)), isNull);
      expect(songAtIn(const [], s(1)), isNull);
    });
  });

  group('passthrough', () {
    test('only for an untouched edit, already in the format made', () {
      expect(plan(still(s(20))).passthrough, isTrue);
      // An end past the video's is the whole video.
      expect(plan(still(s(21))).passthrough, isTrue);
      // MPEG-4 is kept wherever; a WebM only where WebM is made.
      expect(plan(still(s(20)), extension: 'm4v').passthrough, isTrue);
      expect(plan(still(s(20)), extension: 'webm').passthrough, isFalse);
      expect(plan(still(s(20)), extension: 'mov').passthrough, isFalse);
      expect(
        plan(
          still(s(20)),
          extension: 'webm',
          formats: const EditFormats(video: EditFormat.webm),
        ).passthrough,
        isTrue,
      );
      // Trimmed, silent, with a track, or fading: made.
      expect(plan(still(s(20)).copyWith(start: s(1))).passthrough, isFalse);
      expect(plan(still(s(19))).passthrough, isFalse);
      expect(plan(still(s(20)).copyWith(fadeOut: s(0.5))).passthrough, isFalse);
      expect(
        plan(PageEdit(start: Duration.zero, end: s(20))).passthrough,
        isFalse,
      );
      expect(
        plan(
          PageEdit.fromSound(
            start: Duration.zero,
            end: s(20),
            sound: EditSound.none,
          ),
        ).passthrough,
        isFalse,
      );
      expect(
        plan(
          PageEdit.fromSound(
            start: Duration.zero,
            end: s(20),
            sound: EditSound.track,
            trackId: 'k1',
          ),
          songLength: s(5),
        ).passthrough,
        isFalse,
      );
      // Without sound, or the sound alone: always made.
      expect(plan(null, kind: RenderKind.silent).passthrough, isFalse);
      expect(plan(null, kind: RenderKind.sound).passthrough, isFalse);
    });
  });

  test('the timeline moves only with what moves sound, not volumes', () {
    final edit = PageEdit.fromSound(
      start: s(1),
      end: s(5),
      sound: EditSound.track,
      trackId: 'k1',
      offset: s(1),
    );
    final timeline = plan(edit, songLength: s(10)).timeline;
    expect(
      plan(edit.copyWith(trackVolume: 0.3), songLength: s(10)).timeline,
      timeline,
    );
    expect(
      plan(
        PageEdit.fromSound(
          start: s(1),
          end: s(5),
          sound: EditSound.track,
          trackId: 'k1',
          offset: s(2),
        ),
        songLength: s(10),
      ).timeline,
      isNot(timeline),
    );
    expect(plan(PageEdit(start: s(1), end: s(4))).timeline, isNot(timeline));
  });

  group('a take\'s song, lined up by itself', () {
    SongSegment seg(int at, int to, int from, {String page = 'k1'}) =>
        SongSegment(at: at, to: to, page: page, from: from);
    SongClip clip(double at, double from, double to) =>
        SongClip(at: s(at), from: s(from), to: s(to));
    TakeLog log(List<SongSegment> song, {int lagMs = 200}) =>
        TakeLog(burned: false, lagMs: lagMs, song: song);

    test('the song played longest, at its times in the file', () {
      final logged = LoggedSong.of(
        log([
          seg(1000, 5000, 0),
          seg(5000, 6000, 0, page: 'k2'),
          seg(8000, 12000, 4000),
          // At another speed: no renderer plays it yet.
          const SongSegment(
            at: 12000,
            to: 30000,
            page: 'k3',
            from: 0,
            speed: 0.5,
          ),
        ]),
      )!;
      expect(logged.page, 'k1');
      // The lag after the take's clock.
      expect(logged.clips, [clip(1.2, 0, 4), clip(8.2, 4, 8)]);
      expect(LoggedSong.of(log(const [])), isNull);
      expect(LoggedSong.of(null), isNull);
    });

    test('playing as the take started: from the file\'s first frame', () {
      expect(LoggedSong.of(log([seg(0, 3000, 10000)]))!.clips, [
        clip(0, 9.8, 13),
      ]);
      // Nearer its start than the lag: from its start, a little later.
      expect(LoggedSong.of(log([seg(0, 3000, 50)]))!.clips, [
        clip(0.15, 0, 3.05),
      ]);
    });

    test('the default, unless the edit places a song or takes it out', () {
      final logged = LoggedSong.of(log([seg(1000, 5000, 0)]))!;
      final none = withLoggedSong(null, logged, duration: s(20))!;
      expect(none.trackId, 'k1');
      expect(none.song, isNull);
      expect(none.songMode, SongMode.auto);
      // Its track keys: the first clip, for older apps.
      expect(
        (none.trackStart, none.trackEnd, none.offset),
        (Duration.zero, s(4), s(1.2)),
      );
      expect(withLoggedSong(null, logged, duration: Duration.zero), isNull);
      expect(withLoggedSong(null, null, duration: s(20)), isNull);
      // Trimmed, no song said: lined up, from the kept part's start.
      final trimmed = withLoggedSong(
        PageEdit(start: s(1), end: s(10)),
        logged,
        duration: s(20),
      )!;
      expect((trimmed.trackId, trimmed.offset), ('k1', s(0.2)));
      // Taken out, or placed by hand: as it is.
      final off = PageEdit(start: s(1), end: s(10), song: SongMode.off);
      expect(withLoggedSong(off, logged, duration: s(20)), off);
      final manual = PageEdit(
        start: Duration.zero,
        end: s(10),
        song: SongMode.manual,
        trackId: 'k2',
      );
      expect(withLoggedSong(manual, logged, duration: s(20)), manual);
      // Written without `song`: older apps play its first clip.
      expect(none.toJson().containsKey('song'), isFalse);
      expect(none.toJson()['trackId'], 'k1');
    });

    RenderPlan taken(PageEdit? edit, TakeLog log, {Duration? songLength}) =>
        RenderPlan.of(
          edit,
          duration: s(20),
          songLength: songLength ?? s(60),
          takeLog: log,
          preview: true,
        );

    test('plays its clips, silent between them, moved and cut as the edit '
        'says', () {
      final take = log([seg(1000, 5000, 0), seg(8000, 12000, 4000)]);
      final logged = LoggedSong.of(take)!;
      final lined = withLoggedSong(null, logged, duration: s(20))!;
      expect(taken(lined, take).song!.clips, [
        clip(1.2, 0, 4),
        clip(8.2, 4, 8),
      ]);
      expect(taken(lined, take).songAt(s(6)), isNull);
      expect(taken(lined, take).songAt(s(9.2)), s(5));
      // Trimmed: the song stays where it is along the video.
      final trimmed = withLoggedSong(
        PageEdit(start: s(2), end: s(10)),
        logged,
        duration: s(20),
      )!;
      expect(taken(trimmed, take).song!.clips, [
        clip(0, 0.8, 4),
        clip(6.2, 4, 5.8),
      ]);
      // Moved a tenth of a second later: all of it.
      final later = lined.copyWith(offset: lined.offset + s(0.1));
      expect(taken(later, take).song!.clips, [
        clip(1.3, 0, 4),
        clip(8.3, 4, 8),
      ]);
      // A song shorter than it was noted: none past its end.
      expect(taken(lined, take, songLength: s(6)).song!.clips, [
        clip(1.2, 0, 4),
        clip(8.2, 4, 6),
      ]);
      // Placed by hand: one clip, as its track keys say.
      final manual = lined.copyWith(song: SongMode.manual);
      expect(taken(manual, take).song!.clips, [clip(1.2, 0, 4)]);
      // Another song picked (no song said, an older app's): its keys.
      final other = lined.copyWith(trackId: 'k2');
      expect(taken(other, take).song!.clips, [clip(1.2, 0, 4)]);
    });

    test('found in the take\'s sound: where it was found, each clip its '
        'own; an edit kept where the log had it follows, one moved by hand '
        'stays', () {
      final noted = log([seg(1000, 5000, 0), seg(8000, 12000, 4000)]);
      final take = noted.withSync(
        const TakeSync(
          page: 'k1',
          from: SyncFrom.sound,
          ms: 60,
          clips: [SyncClip(at: 1000, ms: 60), SyncClip(at: 8000, ms: 80)],
        ),
      );
      final logged = LoggedSong.of(take)!;
      expect(logged.measured, isTrue);
      expect(LoggedSong.of(noted)!.measured, isFalse);
      expect(logged.clips, [clip(1.26, 0, 4), clip(8.28, 4, 8)]);
      final lined = withLoggedSong(null, logged, duration: s(20))!;
      expect(lined.offset, s(1.26));
      expect(logged.shiftOf(lined), Duration.zero);
      expect(taken(lined, take).song!.clips, logged.clips);
      // Kept before it was found, where the log alone had it: not moved,
      // so it plays where it was found.
      final before = withLoggedSong(
        PageEdit(start: s(1), end: s(10)),
        LoggedSong.of(noted),
        duration: s(20),
      )!;
      expect(before.offset, s(0.2));
      expect(logged.shiftOf(before), Duration.zero);
      expect(taken(before, take).song!.clips, [
        clip(0.26, 0, 4),
        clip(7.28, 4, 5.72),
      ]);
      // Moved by hand before it was found: it stays where it was put.
      final moved = before.copyWith(offset: before.offset + s(0.1));
      expect(logged.shiftOf(moved), s(0.04));
      expect(taken(moved, take).song!.clips.first, clip(0.3, 0, 4));
      // Looked for and not found, or another song's: the log's line-up.
      for (final sync in const [
        TakeSync(page: 'k1', from: SyncFrom.none),
        TakeSync(page: 'k2', from: SyncFrom.sound, ms: 90),
      ]) {
        final plain = LoggedSong.of(noted.withSync(sync))!;
        expect(plain.measured, isFalse);
        expect(plain.clips, [clip(1.2, 0, 4), clip(8.2, 4, 8)]);
      }
      // Found before the file starts: cut there, the song from further in.
      final early = LoggedSong.of(
        log([
          seg(100, 5000, 0),
        ]).withSync(const TakeSync(page: 'k1', from: SyncFrom.sound, ms: -400)),
      )!;
      expect(early.clips, [clip(0, 0.1, 4.9)]);
    });

    test('its marks: where it starts and stops in the take, as the edit '
        'has it', () {
      final take = log([seg(1000, 5000, 0), seg(8000, 12000, 4000)]);
      final logged = LoggedSong.of(take)!;
      final lined = withLoggedSong(null, logged, duration: s(20))!;
      expect(logged.marksIn(lined, s(20)), [s(1.2), s(5.2), s(8.2), s(12.2)]);
      // Trimmed: still the video's times. Moved: with it.
      final trimmed = withLoggedSong(
        PageEdit(start: s(2), end: s(10)),
        logged,
        duration: s(20),
      )!;
      expect(logged.marksIn(trimmed, s(20)), [s(1.2), s(5.2), s(8.2), s(12.2)]);
      final later = lined.copyWith(offset: lined.offset + s(0.5));
      expect(logged.marksIn(later, s(20)).first, s(1.7));
      // None past the video's end, nor past the song's.
      expect(logged.marksIn(lined, s(10)), [s(1.2), s(5.2), s(8.2)]);
      expect(logged.marksIn(lined, s(20), songLength: s(6)), [
        s(1.2),
        s(5.2),
        s(8.2),
        s(10.2),
      ]);
    });
  });
}
