import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/media.dart';
import 'package:tabcam_app/capture/song_sync.dart';
import 'package:tabcam_app/capture/sound_reader.dart';
import 'package:tabcam_app/capture/take_log.dart';
import 'package:tabcam_app/capture/take_priority.dart';
import 'package:tabcam_app/capture/take_syncer.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_io.dart';
import 'package:tabcam_app/library/library.dart';

const rate = SongSync.rate;

/// A made-up riff, [seconds] long: plucked notes (a few harmonics each,
/// dying away) on a beat, with a noise burst on every other one, from
/// [seed].
Float32List riff(double seconds, int seed, {double bpm = 96}) {
  final random = Random(seed);
  final out = Float32List((seconds * rate).round());
  const scale = [110.0, 123.5, 130.8, 146.8, 164.8, 196.0, 220.0, 246.9];
  final beat = (60 / bpm / 2 * rate).round();
  for (var start = 0, n = 0; start < out.length; start += beat, n++) {
    if (random.nextDouble() < 0.2) continue;
    final f = scale[random.nextInt(scale.length)] * (random.nextBool() ? 1 : 2);
    final length = beat * (1 + random.nextInt(3));
    for (var i = 0; i < length && start + i < out.length; i++) {
      final t = i / rate;
      final env = exp(-3 * t);
      out[start + i] +=
          0.3 *
          env *
          (sin(2 * pi * f * t) +
              0.5 * sin(2 * pi * 2 * f * t) +
              0.25 * sin(2 * pi * 3 * f * t));
    }
    if (n.isOdd) {
      for (var i = 0; i < rate ~/ 20 && start + i < out.length; i++) {
        out[start + i] +=
            0.2 * (random.nextDouble() * 2 - 1) * exp(-60 * i / rate);
      }
    }
  }
  return out;
}

/// A made-up riff as [riff]'s, [seconds] long, its rhythm (which beats
/// rest, how long each note rings) from [grid], its notes (pitch,
/// octave, the noise bursts' grain) from [seed]: two riffs on one grid
/// are played in time with each other, in other notes. Each note starts
/// up to [jitterMs] either side of its beat (a player's hands).
Float32List riffOn(
  double seconds,
  int seed, {
  required int grid,
  double bpm = 96,
  double jitterMs = 0,
}) {
  final rhythm = Random(grid);
  final notes = Random(seed);
  final out = Float32List((seconds * rate).round());
  const scale = [110.0, 123.5, 130.8, 146.8, 164.8, 196.0, 220.0, 246.9];
  final beat = 60 / bpm / 2 * rate;
  for (var n = 0; n * beat < out.length; n++) {
    final rest = rhythm.nextDouble() < 0.2;
    final length = (beat * (1 + rhythm.nextInt(3))).round();
    final f = scale[notes.nextInt(scale.length)] * (notes.nextBool() ? 1 : 2);
    final jitter = (notes.nextDouble() * 2 - 1) * jitterMs * rate / 1000;
    if (rest) continue;
    final start = (n * beat + jitter).round();
    for (var i = 0; i < length && start + i < out.length; i++) {
      if (start + i < 0) continue;
      final t = i / rate;
      final env = exp(-3 * t);
      out[start + i] +=
          0.3 *
          env *
          (sin(2 * pi * f * t) +
              0.5 * sin(2 * pi * 2 * f * t) +
              0.25 * sin(2 * pi * 3 * f * t));
    }
    if (n.isOdd) {
      for (var i = 0; i < rate ~/ 20 && start + i < out.length; i++) {
        if (start + i < 0) continue;
        out[start + i] +=
            0.2 * (notes.nextDouble() * 2 - 1) * exp(-60 * i / rate);
      }
    }
  }
  return out;
}

/// [sound] from [atMs] in a take [seconds] long (silence around it).
Float32List placed(Float32List sound, int atMs, {double seconds = 40}) {
  final out = Float32List((seconds * rate).round());
  final start = atMs * rate ~/ 1000;
  for (var i = 0; i < sound.length; i++) {
    if (start + i >= 0 && start + i < out.length) out[start + i] = sound[i];
  }
  return out;
}

/// [song] as a microphone in a room hears it from a speaker: [delay]
/// samples late, with a few echoes after, at [level].
Float32List heardFrom(
  Float32List song, {
  required int length,
  required double delay,
  double level = 0.3,
}) {
  final out = Float32List(length);
  // The direct sound, then the room's echoes: (samples later, level).
  const echoes = [(0, 1.0), (37, -0.5), (113, 0.35), (290, 0.25), (731, -0.15)];
  final whole = delay.floor();
  final part = delay - whole;
  for (final (later, gain) in echoes) {
    for (var i = 0; i < song.length; i++) {
      final at = i + whole + later;
      if (at < 0 || at + 1 >= length) continue;
      // Between two samples: shared by both.
      out[at] += song[i] * gain * level * (1 - part);
      out[at + 1] += song[i] * gain * level * part;
    }
  }
  return out;
}

Float32List mixed(List<Float32List> sounds) {
  final out = Float32List(sounds.first.length);
  for (final s in sounds) {
    for (var i = 0; i < out.length && i < s.length; i++) {
      out[i] += s[i];
    }
  }
  return out;
}

Float32List hiss(int length, int seed, double level) {
  final random = Random(seed);
  return Float32List.fromList([
    for (var i = 0; i < length; i++) (random.nextDouble() * 2 - 1) * level,
  ]);
}

/// Files that are samples in memory, by path (or its end: a page's file
/// in a library is `…/<page>.<extension>`), or, for a file in memory
/// (which has no path), by its type.
class FakeReader implements SoundReader {
  FakeReader(this.files);

  final Map<String, Float32List> files;
  final asked = <(String, Duration, Duration)>[];
  bool closed = false;

  @override
  Future<Float32List?> samples(
    XFile file, {
    required Duration from,
    required Duration length,
    required int rate,
  }) async {
    asked.add((file.path, from, length));
    final all =
        files[file.path] ??
        files.entries
            .where((e) => file.path.endsWith(e.key))
            .firstOrNull
            ?.value ??
        files[file.mimeType];
    if (all == null) return null;
    final start = from.inMicroseconds * rate ~/ 1000000;
    final end = min(
      all.length,
      start + length.inMicroseconds * rate ~/ 1000000,
    );
    if (end <= start) return null;
    return Float32List.sublistView(all, start, end);
  }

  @override
  void close() => closed = true;
}

void main() {
  setUp(() => SongSync.inline = true);
  tearDown(() => SongSync.inline = false);

  test('the transform, and back again', () {
    final re = Float64List.fromList([1, 2, 3, 4, 0, -1, -2, 5]);
    final im = Float64List(8);
    final was = [...re];
    SongSync.fft(re, im);
    // Its first term is the sum.
    expect(re[0], closeTo(12, 1e-9));
    SongSync.fft(re, im, inverse: true);
    for (var i = 0; i < 8; i++) {
      expect(re[i] / 8, closeTo(was[i], 1e-9));
      expect(im[i] / 8, closeTo(0, 1e-9));
    }
  });

  group('a song found in a take', () {
    final song = riff(12, 1);
    const reach = 600 * rate ~/ 1000;

    SoundOffset? found(double delay, {double level = 0.3, int guitar = 2}) {
      final length = song.length + 2 * reach;
      final heard = mixed([
        heardFrom(song, length: length, delay: reach + delay, level: level),
        if (guitar > 0) riff(length / rate, guitar, bpm: 103),
        hiss(length, 9, 0.01),
      ]);
      return SongSync.offsetOf(heard, song, expected: reach, reach: reach);
    }

    test('where it is, to a fraction of a millisecond', () {
      for (final delay in [0.0, 37.0, -212.0, 1900.5, -3333.25]) {
        final at = found(delay)!;
        expect(at.samples, closeTo(delay, 0.5), reason: '$delay');
        expect(at.score, greaterThan(SongSync.clear * 2), reason: '$delay');
      }
    });

    test('quiet under a loud guitar', () {
      final at = found(480, level: 0.12)!;
      expect(at.samples, closeTo(480, 1));
      expect(at.score, greaterThan(SongSync.clear));
      expect(at.lead, greaterThan(SongSync.ahead));
    });

    test('not there (headphones): no clear match', () {
      for (final guitar in [2, 3, 4, 5, 6]) {
        final at = found(0, level: 0, guitar: guitar);
        expect(
          at == null || at.score < SongSync.clear * 0.75,
          isTrue,
          reason: '$guitar: $at',
        );
      }
    });

    test('further out than it\'s looked for: no clear match', () {
      // 0.7 s late, 0.6 s looked through.
      final at = found(5600);
      expect(at == null || at.score < SongSync.clear * 0.75, isTrue);
      // Right at the edge of it: the top may be further out, so none.
      expect(
        SongSync.offsetOf(
          heardFrom(song, length: song.length + 2 * reach, delay: 2.0 * reach),
          song,
          expected: reach,
          reach: reach,
        ),
        isNull,
      );
    });

    test('silence, or too little, is none', () {
      expect(
        SongSync.offsetOf(
          Float32List(song.length + 2 * reach),
          song,
          expected: reach,
          reach: reach,
        ),
        isNull,
      );
      expect(
        SongSync.offsetOf(
          Float32List(100),
          Float32List(100),
          expected: 0,
          reach: reach,
        ),
        isNull,
      );
    });
  });

  group('a take measured', () {
    // A take 40 s long; the song (30 s) played from 5 s on the take's
    // clock, the file 200 ms ahead of the clock (the lag), and the
    // speaker 83 ms late on top.
    final song = riff(30, 11);
    const lag = 200;
    Float32List take({int late = 83, double level = 0.3}) => mixed([
      heardFrom(
        song,
        length: 40 * rate,
        delay: (5000 + lag + late) * rate / 1000,
        level: level,
      ),
      riff(40, 12, bpm: 103),
      hiss(40 * rate, 13, 0.01),
    ]);
    const log = TakeLog(
      burned: false,
      lagMs: lag,
      song: [SongSegment(at: 5000, to: 35000, page: 'song', from: 0)],
    );

    test('the shift, from the middle of the segment', () async {
      final reader = FakeReader({'take': take(), 'song': song});
      final sync = await SongSync.measure(
        log: log,
        take: XFile('take'),
        song: XFile('song'),
        reader: reader,
      );
      expect(sync!.found, isTrue);
      expect(sync.page, 'song');
      expect(sync.ms, 83);
      expect(sync.clips.single.at, 5000);
      expect(sync.clips.single.ms, 83);
      expect(sync.clips.single.score, greaterThan(SongSync.clear));
      // Four windows of 8 s spread along the 30 s: 0, 7.333, 14.666 and
      // 22 s into it (5.2 s on into the file), and 0.6 s more of the take
      // either side of each.
      expect(reader.asked, [
        for (final skip in [0, 7333, 14666, 22000]) ...[
          (
            'take',
            Duration(milliseconds: 5200 + skip - 600),
            const Duration(milliseconds: 9200),
          ),
          ('song', Duration(milliseconds: skip), const Duration(seconds: 8)),
        ],
      ]);
      // The segment then starts where it's heard.
      expect(log.withSync(sync).songFileMs(log.song.single), 5283);
      expect(
        log.withSync(sync).songFileMs(log.song.single, synced: false),
        5200,
      );
    });

    test('earlier than noted', () async {
      final sync = await SongSync.measure(
        log: log,
        take: XFile('take'),
        song: XFile('song'),
        reader: FakeReader({'take': take(late: -141), 'song': song}),
      );
      expect(sync!.ms, -141);
    });

    test('not heard in the take: said so, and no shift', () async {
      final sync = await SongSync.measure(
        log: log,
        take: XFile('take'),
        song: XFile('song'),
        reader: FakeReader({'take': take(level: 0), 'song': song}),
      );
      expect(sync, const TakeSync(page: 'song', from: SyncFrom.none));
      expect(log.withSync(sync!).songFileMs(log.song.single), 5200);
    });

    test('a file that can\'t be read: not told', () async {
      final sync = await SongSync.measure(
        log: log,
        take: XFile('take'),
        song: XFile('song'),
        reader: FakeReader({'song': song}),
      );
      expect(sync, isNull);
    });

    test('each segment its own, short ones the song\'s', () async {
      // Paused and played on: two segments, the second 20 ms later than
      // the first; a third too short to measure.
      const paused = TakeLog(
        burned: false,
        lagMs: lag,
        song: [
          SongSegment(at: 2000, to: 12000, page: 'song', from: 0),
          SongSegment(at: 14000, to: 26000, page: 'song', from: 10000),
          SongSegment(at: 27000, to: 28500, page: 'song', from: 22000),
        ],
      );
      Float32List part(int from, int to) =>
          Float32List.sublistView(song, from * rate ~/ 1000, to * rate ~/ 1000);
      Float32List placed(Float32List sound, int at) {
        final out = Float32List(40 * rate);
        final start = at * rate ~/ 1000;
        for (var i = 0; i < sound.length && start + i < out.length; i++) {
          out[start + i] = sound[i];
        }
        return out;
      }

      final heard = mixed([
        heardFrom(
          placed(part(0, 10000), 2000 + lag),
          length: 40 * rate,
          delay: 50 * rate / 1000,
        ),
        heardFrom(
          placed(part(10000, 22000), 14000 + lag),
          length: 40 * rate,
          delay: 70 * rate / 1000,
        ),
        riff(40, 12, bpm: 103),
      ]);
      final sync = await SongSync.measure(
        log: paused,
        take: XFile('take'),
        song: XFile('song'),
        reader: FakeReader({'take': heard, 'song': song}),
      );
      expect(
        [for (final c in sync!.clips) (c.at, c.ms)],
        [(2000, 50), (14000, 70)],
      );
      expect(sync.ms, 50);
      final synced = paused.withSync(sync);
      expect(
        [for (final s in paused.song) synced.songFileMs(s)],
        [2250, 14270, 27250],
      );
    });

    test('no song noted: nothing to measure', () async {
      final reader = FakeReader({'take': take(), 'song': song});
      final sync = await SongSync.measure(
        log: const TakeLog(burned: false),
        take: XFile('take'),
        song: XFile('song'),
        reader: reader,
      );
      expect(sync, isNull);
      expect(reader.asked, isEmpty);
    });
  });
  group('a take in the library (TakeSyncer)', () {
    late Directory root;
    late Library library;
    late FakeReader reader;
    var opened = 0;
    final song = riff(30, 11);

    setUp(() async {
      root = await Directory.systemTemp.createTemp('tabcam');
      library = Library(PlatformEventStore(root));
      await library.load();
      opened = 0;
      TakeSyncer.reset();
      SoundReader.opener = () {
        opened++;
        return reader;
      };
    });
    tearDown(() async {
      SoundReader.opener = null;
      TakePriority.recording.value = false;
      await root.delete(recursive: true);
    });

    /// A capture with a song and a take that noted it from 5 s on its
    /// clock (the lag 200 ms), heard [late] ms after that in its sound.
    Future<(String, EventPage, EventPage)> capture({int late = 83}) async {
      var event = await library.create(const []);
      event = await library.addMedia(event, [
        Media(
          XFile.fromData(Uint8List.fromList([1, 2]), name: 'song.m4a'),
          PageKind.audio,
          'm4a',
        ),
      ]);
      final songPage = event.pages.last;
      event = await library.addMedia(
        event,
        [
          Media(
            XFile.fromData(Uint8List.fromList([3, 4]), name: 'take.mp4'),
            PageKind.video,
            'mp4',
          ),
        ],
        take: true,
        takeLog: TakeLog(
          burned: false,
          lagMs: 200,
          song: [SongSegment(at: 5000, to: 35000, page: songPage.id, from: 0)],
        ),
      );
      final take = event.pages.last;
      reader = FakeReader({
        take.fileName: mixed([
          heardFrom(
            song,
            length: 40 * rate,
            delay: (5200 + late) * rate / 1000,
          ),
          riff(40, 12, bpm: 103),
        ]),
        songPage.fileName: song,
      });
      return (event.id, take, songPage);
    }

    test('is measured once, and what\'s found kept with its log', () async {
      final (id, take, songPage) = await capture();
      final log = await TakeSyncer.sync(library, id, take.id);
      expect(log!.sync!.found, isTrue);
      expect(log.sync!.page, songPage.id);
      expect(log.sync!.ms, 83);
      expect(library.byId(id)!.pages.last.takeLog, log);
      expect(reader.closed, isTrue);
      // Again: as it is, nothing read.
      reader.asked.clear();
      expect(await TakeSyncer.sync(library, id, take.id), log);
      expect(reader.asked, isEmpty);
      expect(opened, 1);
      // Kept through a restart.
      final reopened = Library(PlatformEventStore(root));
      await reopened.load();
      expect(reopened.byId(id)!.pages.last.takeLog!.sync!.ms, 83);
    });

    test('asked twice at once: measured once', () async {
      final (id, take, _) = await capture();
      final both = await Future.wait([
        TakeSyncer.sync(library, id, take.id),
        TakeSyncer.sync(library, id, take.id),
      ]);
      expect(both.first!.sync!.ms, 83);
      expect(both.last, both.first);
      expect(opened, 1);
    });

    test('waits while a take records', () async {
      final (id, take, _) = await capture();
      TakePriority.recording.value = true;
      var done = false;
      final syncing = TakeSyncer.sync(
        library,
        id,
        take.id,
      ).whenComplete(() => done = true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(done, isFalse);
      expect(reader.asked, isEmpty);
      TakePriority.recording.value = false;
      expect((await syncing)!.sync!.ms, 83);
    });

    test(
      'files that can\'t be read here: not told, asked again later',
      () async {
        final (id, take, _) = await capture();
        final sounds = {...reader.files};
        reader.files.clear();
        expect((await TakeSyncer.sync(library, id, take.id))!.sync, isNull);
        expect(library.byId(id)!.pages.last.takeLog!.sync, isNull);
        reader.files.addAll(sounds);
        expect((await TakeSyncer.sync(library, id, take.id))!.sync!.ms, 83);
      },
    );

    test('no reader here, the song deleted, or not a take: nothing', () async {
      final (id, take, songPage) = await capture();
      SoundReader.opener = () => null;
      expect((await TakeSyncer.sync(library, id, take.id))!.sync, isNull);
      SoundReader.opener = () => reader;
      expect(await TakeSyncer.sync(library, id, songPage.id), isNull);
      expect(await TakeSyncer.sync(library, 'gone', take.id), isNull);
      await library.deletePage(library.byId(id)!, songPage);
      expect((await TakeSyncer.sync(library, id, take.id))!.sync, isNull);
      expect(reader.asked, isEmpty);
    });
  });

  group('harder takes: the windows added up, the drift taken out', () {
    // A take 50 s long, a 40 s song from 5 s on its clock, 200 ms lag.
    final song = riff(40, 21);
    const lag = 200;
    const log = TakeLog(
      burned: false,
      lagMs: lag,
      song: [SongSegment(at: 5000, to: 45000, page: 'song', from: 0)],
    );

    /// [sound] played [ppm] parts per million fast (its clock ahead).
    Float32List stretched(Float32List sound, double ppm) {
      final factor = 1 + ppm / 1e6;
      final out = Float32List((sound.length / factor).floor());
      for (var i = 0; i < out.length; i++) {
        final x = i * factor;
        final j = x.floor();
        final f = x - j;
        out[i] = j + 1 < sound.length
            ? sound[j] * (1 - f) + sound[j + 1] * f
            : sound[j];
      }
      return out;
    }

    Float32List take({
      required int late,
      double level = 0.3,
      double guitar = 1,
      double ppm = 0,
    }) => mixed([
      heardFrom(
        ppm == 0 ? song : stretched(song, ppm),
        length: 50 * rate,
        delay: (5000 + lag + late) * rate / 1000,
        level: level,
      ),
      Float32List.fromList([
        for (final v in riff(50, 22, bpm: 103)) v * guitar,
      ]),
      hiss(50 * rate, 23, 0.02),
    ]);

    /// The old way, for comparison: one 12 s window from the middle.
    SoundOffset? oldWay(Float32List heard) {
      const reach = 600 * rate ~/ 1000;
      const inFile = 5200 + 14000; // the 40 s segment's middle 12 s
      final from = (inFile - 600) * rate ~/ 1000;
      return SongSync.offsetOf(
        Float32List.sublistView(heard, from, from + 13200 * rate ~/ 1000),
        Float32List.sublistView(
          song,
          14000 * rate ~/ 1000,
          26000 * rate ~/ 1000,
        ),
        expected: reach,
        reach: reach,
      );
    }

    Future<int?> newWay(Float32List heard) async {
      final sync = await SongSync.measure(
        log: log,
        take: XFile('take'),
        song: XFile('song'),
        reader: FakeReader({'take': heard, 'song': song}),
      );
      return sync!.found ? sync.ms : null;
    }

    String said(SoundOffset? at) => at == null
        ? 'none'
        : '${(at.samples * 1000 / rate).toStringAsFixed(1)} ms '
              '(score ${at.score.toStringAsFixed(1)}, '
              'lead ${at.lead.toStringAsFixed(2)})';

    test('a quiet song under a loud guitar: found, to the millisecond, '
        'where one window alone wasn\'t clear', () async {
      final heard = take(late: 117, level: 0.06, guitar: 1.6);
      final old = oldWay(heard)!;
      // ignore: avoid_print
      print('quiet: old ${said(old)}, new ${await newWay(heard)} ms');
      expect(old.score, lessThan(SongSync.clear));
      expect(await newWay(heard), 117);
    });

    test('clocks 150 ppm apart (6 ms over the song): the middle\'s shift, '
        'clear', () async {
      // The song's player 150 ppm fast: 20 s into it, its middle, is
      // heard 3 ms sooner than at its start, 114 ms rather than 117.
      final heard = take(late: 117, ppm: 150);
      final old = oldWay(heard)!;
      // ignore: avoid_print
      print('drift: old ${said(old)}, new ${await newWay(heard)} ms');
      expect(old.score, lessThan(SongSync.clear));
      expect(await newWay(heard), 114);
    });

    test('a speaker\'s Bluetooth delay, a quarter of a second', () async {
      final heard = take(late: 263, level: 0.15, guitar: 1.2);
      final now = await newWay(heard);
      // ignore: avoid_print
      print('bluetooth: old ${said(oldWay(heard))}, new $now ms');
      expect(now!, closeTo(263, 1));
    });

    test('headphones (no song in the take): none, as before', () async {
      final heard = take(late: 0, level: 0, guitar: 1.6);
      expect(await newWay(heard), isNull);
    });
  });

  group('align: Auto-align, around where the Song lane is', () {
    // A take 40 s long, the song (30 s) where the lane has it from 5.2 s
    // in its file; heard [late] ms after that.
    final song = riff(30, 11);
    const lane = (fileMs: 5200, songMs: 0, lengthMs: 30000);
    Float32List take({int late = 83, double level = 0.3}) => mixed([
      heardFrom(
        song,
        length: 40 * rate,
        delay: (5200 + late) * rate / 1000,
        level: level,
      ),
      riff(40, 12, bpm: 103),
      hiss(40 * rate, 13, 0.01),
    ]);

    Future<SongAlign?> align(
      Float32List heard,
      Float32List played, {
      List<LaneClip> clips = const [lane],
      FakeReader? reader,
      void Function(int, int)? progress,
    }) => SongSync.align(
      take: XFile('take'),
      song: XFile('song'),
      reader: reader ?? FakeReader({'take': heard, 'song': played}),
      clips: clips,
      progress: progress,
    );

    test(
      'by the sound: where it is against the lane, to the millisecond',
      () async {
        final found = (await align(take(), song))!;
        expect(found.from, AlignFrom.sound);
        expect(found.ms, closeTo(83, 1));
        expect(found.spreadMs, lessThanOrEqualTo(2));
        expect(found.rough, isFalse);
        expect(found.score, greaterThan(SongSync.alignClear));
      },
    );

    test('further either way than the measure looks: up to 2 s', () async {
      for (final late in [1500, -1300]) {
        final found = (await align(take(late: late), song))!;
        expect(found.from, AlignFrom.sound, reason: '$late');
        expect(found.ms, closeTo(late, 1), reason: '$late');
      }
      // 2.5 s: out of reach, not by the sound.
      final far = (await align(take(late: 2500), song))!;
      expect(far.from, isNot(AlignFrom.sound));
    });

    test('a long clip: four windows spread along it, 2 s more of the take '
        'either side; progress told', () async {
      final long = riff(60, 31);
      final reader = FakeReader({
        'take': mixed([
          heardFrom(long, length: 70 * rate, delay: (5200 + 40) * rate / 1000),
          riff(70, 12, bpm: 103),
          hiss(70 * rate, 13, 0.01),
        ]),
        'song': long,
      });
      final told = <(int, int)>[];
      final found = (await align(
        Float32List(0),
        long,
        clips: const [(fileMs: 5200, songMs: 0, lengthMs: 60000)],
        reader: reader,
        progress: (done, of) => told.add((done, of)),
      ))!;
      expect(found.ms, closeTo(40, 1));
      expect(reader.asked, [
        for (final skip in [0, 17333, 34666, 52000]) ...[
          (
            'take',
            Duration(milliseconds: 5200 + skip - 2000),
            const Duration(seconds: 12),
          ),
          ('song', Duration(milliseconds: skip), const Duration(seconds: 8)),
        ],
      ]);
      expect(told, [(0, 4), (1, 4), (2, 4), (3, 4), (4, 4)]);
    });

    test('two clips, each its own; one too short left out', () async {
      final reader = FakeReader({'take': take(late: 61), 'song': song});
      final found = (await align(
        Float32List(0),
        song,
        reader: reader,
        clips: const [
          (fileMs: 5200, songMs: 0, lengthMs: 12000),
          (fileMs: 19200, songMs: 14000, lengthMs: 12000),
          (fileMs: 33200, songMs: 28000, lengthMs: 2000),
        ],
      ))!;
      expect((found.from, found.ms), (AlignFrom.sound, 61));
      // Two windows each, none of the short one.
      expect(reader.asked.where((a) => a.$1 == 'song'), hasLength(4));
    });

    test('its parts disagree: rough, and by how much', () async {
      // The song's second half heard 60 ms later than its first.
      Float32List part(int from, int to) =>
          Float32List.sublistView(song, from * rate ~/ 1000, to * rate ~/ 1000);
      final heard = mixed([
        heardFrom(
          placed(part(0, 15000), 5200),
          length: 40 * rate,
          delay: 83 * rate / 1000,
        ),
        heardFrom(
          placed(part(15000, 30000), 5200 + 15000),
          length: 40 * rate,
          delay: 143 * rate / 1000,
        ),
        riff(40, 12, bpm: 103),
        hiss(40 * rate, 13, 0.01),
      ]);
      final found = (await align(heard, song))!;
      expect(found.from, AlignFrom.sound);
      // Somewhere from the one to the other (their sum's, the drift
      // fitted through them as far as it's believed).
      expect(found.ms, inInclusiveRange(81, 145), reason: '$found');
      expect(found.spreadMs, closeTo(60, 3), reason: '$found');
      expect(found.rough, isTrue);
    });

    group('headphones (the song not in the take): by the rhythm', () {
      // The song, and the guitar played along it on the same riff's
      // rhythm in other notes, each note up to 20 ms off the beat.
      final played = riffOn(30, 22, grid: 11);
      Float32List guitar(int late) => mixed([
        placed(riffOn(30, 21, grid: 11, jitterMs: 20), 5200 + late),
        hiss(40 * rate, 13, 0.01),
      ]);

      test('a little late: found, near enough', () async {
        final found = (await align(guitar(180), played))!;
        expect(found.from, AlignFrom.rhythm);
        expect(found.ms, closeTo(180, 25));
      });

      test('the lane 420 ms off: still found there, not a beat off', () async {
        for (final late in [420, -420]) {
          final found = (await align(guitar(late), played))!;
          expect(found.from, AlignFrom.rhythm, reason: '$late');
          expect(found.ms, closeTo(late, 25), reason: '$late');
        }
      });

      test('a guitar in another tempo, or hiss: not found', () async {
        for (final (seed, grid, bpm) in [
          (31, 41, 103.0),
          (32, 42, 88.0),
          (33, 43, 120.0),
        ]) {
          final other = mixed([
            placed(riffOn(30, seed, grid: grid, bpm: bpm, jitterMs: 15), 5200),
            hiss(40 * rate, 13, 0.01),
          ]);
          final found = (await align(other, played))!;
          expect(found.found, isFalse, reason: '$bpm: $found');
        }
        final found = (await align(hiss(40 * rate, 14, 0.02), played))!;
        expect(found.found, isFalse, reason: '$found');
      });
    });

    test('nothing that can be read, or no clip long enough: null', () async {
      expect(
        await align(take(), song, reader: FakeReader({'song': song})),
        isNull,
      );
      expect(
        await align(
          take(),
          song,
          clips: const [(fileMs: 5200, songMs: 0, lengthMs: 2000)],
        ),
        isNull,
      );
    });

    test('onsets: where it gets louder, a hundred a second', () {
      // A click every half second from 0.25 s, over a little hiss.
      final clicks = hiss(3 * rate, 5, 0.001);
      for (var at = rate ~/ 4; at < clicks.length; at += rate ~/ 2) {
        for (var i = 0; i < 40; i++) {
          clicks[at + i] += 0.5 * exp(-i / 10);
        }
      }
      final o = SongSync.onsets(clicks);
      expect(o, hasLength(300));
      var length = 0.0;
      for (final v in o) {
        length += v * v;
      }
      expect(length, closeTo(1, 1e-6));
      final tops = [
        for (var i = 1; i < o.length - 1; i++)
          if (o[i] > 0.2 && o[i] >= o[i - 1] && o[i] >= o[i + 1]) i,
      ];
      expect(tops, [25, 75, 125, 175, 225, 275]);
      expect(SongSync.onsets(Float32List(rate)), everyElement(0));
    });

    test('onsetAlign: the same onsets 17 frames on, 170 ms', () {
      final random = Random(3);
      final played = Float32List.fromList([
        for (var i = 0; i < 800; i++) random.nextDouble() < 0.1 ? 1.0 : 0.0,
      ]);
      // The take's from 200 frames before (its reach), the song 17 later.
      final heard = Float32List(1200)..setAll(200 + 17, played);
      final found = SongSync.onsetAlign(
        [(heard: heard, played: played, expected: 200)],
        reach: 200,
        prior: 70,
      )!;
      expect(found.ms, closeTo(170, 5));
      expect(found.match, greaterThan(0.5));
      expect(found.lead, greaterThan(1.5));
    });
  });
}
