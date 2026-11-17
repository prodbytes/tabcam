import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/capture/auto_pass.dart';
import 'package:tabcam_app/capture/media.dart';
import 'package:tabcam_app/capture/mp4_length.dart';
import 'package:tabcam_app/capture/take_log.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_io.dart';
import 'package:tabcam_app/library/library.dart';

/// A made-up riff's necklines (the third the same as the first).
const _riff = [
  'e|--0--3--|\nB|--1--1--|',
  'e|--5--7--|\nB|--5--8--|',
  'e|--0--3--|\nB|--1--1--|',
  'e|--12-10-|\nB|--13-12-|',
];

Duration _ms(int ms) => Duration(milliseconds: ms);

/// [json] through a JSON string, as saved and loaded.
Object? _encoded(Object? json) => jsonDecode(jsonEncode(json));

/// A whole log, every field set.
final _log = TakeLog(
  burned: true,
  lagMs: 180,
  lagFrom: LagFrom.bounds,
  lagRaw: const {
    'startCallMs': -240,
    'startReturnMs': -10,
    'stopCallMs': 61000,
    'stopReturnMs': 61310,
    'fileMs': 61420,
  },
  tab: TakeTab.of(_riff, [(_ms(0), 0), (_ms(4210), 1), (_ms(8380), 0)]),
  song: const [
    SongSegment(at: 2050, to: 31200, page: 'p7', from: 0),
    SongSegment(at: 51200, to: 61000, page: 'p7', from: 44800, speed: 0.75),
  ],
  songLink: true,
);

void main() {
  group('the tab\'s bands (bandsOf)', () {
    test('each neckline until the next', () {
      expect(bandsOf([(_ms(0), 0), (_ms(4000), 1), (_ms(9000), 2)]), [
        TabBand(0, _ms(0), _ms(4000)),
        TabBand(1, _ms(4000), _ms(9000)),
        TabBand(2, _ms(9000)),
      ]);
    });

    test('moved twice at once: only the last counts', () {
      expect(bandsOf([(_ms(0), 0), (_ms(3000), 1), (_ms(3000), 2)]), [
        TabBand(0, _ms(0), _ms(3000)),
        TabBand(2, _ms(3000)),
      ]);
    });

    test('back to the same neckline: one band', () {
      expect(bandsOf([(_ms(0), 1), (_ms(2000), 2), (_ms(2000), 1)]), [
        TabBand(1, _ms(0)),
      ]);
    });

    test('a take that never moved: one band', () {
      expect(bandsOf([(_ms(0), 3)]), [TabBand(3, _ms(0))]);
    });
  });

  group('the tab\'s turns', () {
    test('are kept as they came: Auto-pass off, back to the same line, at '
        'the same time, with the tab hidden (Cam notes them all alike)', () {
      // A turn to the line showing, two at once, and a turn made with
      // Auto-pass off (the 4th): bands and phrase passes leave some out,
      // the log none.
      final marks = [
        (_ms(0), 0),
        (_ms(1000), 1),
        (_ms(1000), 0),
        (_ms(1500), 0),
        (_ms(2000), 1),
      ];
      final tab = TakeTab.of(_riff, marks);
      expect(tab.marks, [(0, 0), (1000, 1), (1000, 0), (1500, 0), (2000, 1)]);
      expect(bandsOf(marks), hasLength(lessThan(marks.length)));
      expect(
        takePhrases(marks, skip: {4}).passes.length,
        lessThan(marks.length - 1),
      );
    });

    test('keep each neckline\'s text once, the turns pointing at it; the '
        'necklines never shown aren\'t kept', () {
      final tab = TakeTab.of(_riff, [
        (_ms(0), 0),
        (_ms(1000), 2),
        (_ms(2000), 3),
        (_ms(3000), 2),
      ]);
      expect(tab.lines, [_riff[0], _riff[3]]);
      expect(tab.marks, [(0, 0), (1000, 0), (2000, 1), (3000, 0)]);
    });

    test('are at their time plus the lag in the file, the start at its '
        'start; the neckline at a moment is the last turn\'s', () {
      final tab = TakeTab.of(_riff, [
        (_ms(0), 0),
        (_ms(4210), 1),
        (_ms(8380), 0),
      ]);
      expect(tab.fileMarks(180), [
        (Duration.zero, 0),
        (_ms(4390), 1),
        (_ms(8560), 0),
      ]);
      final log = TakeLog(burned: false, lagMs: 180, tab: tab);
      expect(log.lineAt(Duration.zero), _riff[0]);
      expect(log.lineAt(_ms(4389)), _riff[0]);
      expect(log.lineAt(_ms(4390)), _riff[1]);
      expect(log.lineAt(_ms(8559)), _riff[1]);
      expect(log.lineAt(const Duration(minutes: 9)), _riff[0]);
      expect(const TakeLog(burned: false).lineAt(Duration.zero), isNull);
    });

    test('played back in Cam, a neckline the tab has twice is the copy '
        'that showed: exact for the take recorded there, else the copy '
        'nearest the line before (of two as near, the way it went)', () {
      // Forward through the riff, its third line the first's text.
      final forward = [
        (_ms(0), 0),
        (_ms(1000), 1),
        (_ms(2000), 2),
        (_ms(3000), 3),
      ];
      final tab = TakeTab.of(_riff, forward);
      expect(tab.marks.map((m) => m.$2), [0, 1, 0, 2]);
      expect(TakeTab.placesOf(_riff, forward), [0, 1, 2, 3]);
      expect(tab.placesIn(_riff), [0, 1, 2, 3]);
      expect(tab.markAt(_ms(2500), 0), 2);
      expect(tab.markAt(_ms(2500), 600), 1);

      // Back from the last: the third is nearer than the first; from the
      // second, both are as near, and the take was going back.
      final back = [
        (_ms(0), 3),
        (_ms(1000), 2),
        (_ms(2000), 1),
        (_ms(3000), 0),
      ];
      expect(TakeTab.placesOf(_riff, back), [3, 2, 1, 0]);
      expect(TakeTab.of(_riff, back).placesIn(_riff), [3, 2, 1, 0]);
      // Only a guess: back to the second, then forward again, it can't
      // tell, and keeps going back; Cam's own lines are exact.
      final turned = [
        (_ms(0), 3),
        (_ms(1000), 2),
        (_ms(2000), 1),
        (_ms(3000), 2),
        (_ms(4000), 3),
      ];
      expect(TakeTab.placesOf(_riff, turned), [3, 2, 1, 2, 3]);
      expect(TakeTab.of(_riff, turned).placesIn(_riff), [3, 2, 1, 0, 3]);

      // Out of range or past the most kept: left out of both alike.
      final odd = [(_ms(0), 3), (_ms(500), 9), (_ms(1000), 2), (_ms(1500), -1)];
      expect(TakeTab.placesOf(_riff, odd), [3, 2]);
      expect(TakeTab.of(_riff, odd).placesIn(_riff), [3, 2]);

      // A neckline the capture's tab no longer has: -1; the next is
      // placed from the one before it.
      final changed = [_riff[0], _riff[1], _riff[0]];
      expect(tab.placesIn(changed), [0, 1, 2, -1]);
      expect(
        const TakeTab(lines: [], marks: []).markAt(Duration.zero, 0),
        isNull,
      );
    });

    test('are at most a few thousand', () {
      final tab = TakeTab.of(_riff, [
        for (var i = 0; i < TakeTab.maxMarks + 10; i++) (_ms(i * 100), i % 2),
      ]);
      expect(tab.marks, hasLength(TakeTab.maxMarks));
      expect(utf8.encode(jsonEncode(tab.toJson())).length, lessThan(60000));
    });
  });

  group('the lag', () {
    test('on the phones: the middle of where the start\'s and the stop\'s '
        'bounds agree', () {
      // First frame within the start call: 10 to 240 ms before the clock.
      // Last within the stop call: the file 61420 ms long, so 110 to 420.
      final lag = lagFromBounds(
        startCallMs: -240,
        startReturnMs: -10,
        stopCallMs: 61000,
        stopReturnMs: 61310,
        fileMs: 61420,
      );
      expect(lag.lagMs, 175); // (110 + 240) / 2
      expect(lag.from, LagFrom.bounds);
      expect(lag.raw, {
        'startCallMs': -240,
        'startReturnMs': -10,
        'stopCallMs': 61000,
        'stopReturnMs': 61310,
        'fileMs': 61420,
      });
    });

    test('where they don\'t agree, or the file\'s length is unknown, the '
        'middle of the start\'s', () {
      final apart = lagFromBounds(
        startCallMs: -240,
        startReturnMs: 0,
        stopCallMs: 61000,
        stopReturnMs: 61310,
        fileMs: 62000, // 690 to 1000: past the start's 0 to 240
      );
      expect(apart.lagMs, 120);
      final unknown = lagFromBounds(
        startCallMs: -300,
        startReturnMs: -100,
        stopCallMs: 5000,
        stopReturnMs: 5100,
      );
      expect(unknown.lagMs, 200);
      expect(unknown.raw.containsKey('fileMs'), isFalse);
    });

    test('on the web: how long the recorder had recorded', () {
      final lag = lagFromRecorder(86.6, startCallMs: -120, startReturnMs: -2);
      expect(lag.lagMs, 87);
      expect(lag.from, LagFrom.recorder);
      expect(lag.raw['recorderStartMs'], -87);
    });
  });

  group('the log\'s JSON', () {
    test('round-trips, and keeps keys a newer app wrote', () {
      final json = _encoded(_log.toJson());
      expect(json, {
        'v': 1,
        'burned': true,
        'lagMs': 180,
        'lagFrom': 'bounds',
        'lagRaw': {
          'startCallMs': -240,
          'startReturnMs': -10,
          'stopCallMs': 61000,
          'stopReturnMs': 61310,
          'fileMs': 61420,
        },
        'tab': {
          'lines': [_riff[0], _riff[1]],
          'marks': [
            [0, 0],
            [4210, 1],
            [8380, 0],
          ],
        },
        'song': [
          {'at': 2050, 'to': 31200, 'page': 'p7', 'from': 0, 'speed': 1},
          {
            'at': 51200,
            'to': 61000,
            'page': 'p7',
            'from': 44800,
            'speed': 0.75,
          },
        ],
        'songLink': true,
      });
      expect(TakeLog.fromJson(json), _log);
      final newer = {...json as Map<String, Object?>, 'pitch': 'A440'};
      final read = TakeLog.fromJson(_encoded(newer))!;
      expect(read.extra, {'pitch': 'A440'});
      expect(_encoded(read.toJson()), newer);
    });

    test('where the song was found in the take\'s sound (sync): added '
        'once, the rest as it came; a clone\'s names the copy\'s song', () {
      const sync = TakeSync(
        page: 'p7',
        from: SyncFrom.sound,
        ms: 38,
        clips: [SyncClip(at: 2050, ms: 38, score: 21.4)],
      );
      // A log Cam made, and one read back with a newer app's key in it.
      final newer = TakeLog.fromJson(
        _encoded({..._log.toJson(), 'pitch': 'A440'}),
      )!;
      for (final log in [_log, newer]) {
        expect(log.sync, isNull);
        final synced = log.withSync(sync);
        expect(synced.sync, sync);
        final json = _encoded(synced.toJson()) as Map<String, Object?>;
        expect(json['sync'], {
          'v': 1,
          'page': 'p7',
          'from': 'sound',
          'ms': 38,
          'clips': [
            {'at': 2050, 'ms': 38, 'score': 21.4},
          ],
        });
        // Nothing else changed.
        expect({...json}..remove('sync'), _encoded(log.toJson()));
        expect(TakeLog.fromJson(json), synced);
        expect(TakeLog.fromJson(json)!.sync, sync);
        // The segment measured, its own shift; another, the song's.
        expect(synced.songFileMs(synced.song.first), 2050 + 180 + 38);
        expect(sync.shiftAt(2050), 38);
        expect(sync.shiftAt(9000), 38);
        // A clone: the song it names is the copy's.
        final copy = synced.withPages({'p7': 'q1'});
        expect(copy.sync!.page, 'q1');
        expect((copy.toJson()['sync'] as Map)['page'], 'q1');
        expect(copy.song.first.page, 'q1');
        expect(copy.sync!.clips, sync.clips);
      }
      // Looked for and not found: said so, no shift.
      const none = TakeSync(page: 'p7', from: SyncFrom.none);
      expect(_encoded(none.toJson()), {
        'v': 1,
        'page': 'p7',
        'from': 'none',
        'ms': 0,
      });
      expect(TakeSync.fromJson(_encoded(none.toJson())), none);
      expect(_log.withSync(none).songFileMs(_log.song.first), 2050 + 180);
      // Another song's: not this segment's.
      expect(
        _log
            .withSync(const TakeSync(page: 'p9', from: SyncFrom.sound, ms: 70))
            .songFileMs(_log.song.first),
        2050 + 180,
      );
      // A way this version doesn't know: not read, written back as it came.
      final later = {
        ..._log.toJson(),
        'sync': {'v': 2, 'page': 'p7', 'from': 'beats', 'ms': 12},
      };
      final read = TakeLog.fromJson(_encoded(later))!;
      expect(read.sync, isNull);
      expect(_encoded(read.toJson()), _encoded(later));
      // Read leniently.
      expect(TakeSync.fromJson('sound'), isNull);
      expect(TakeSync.fromJson({'from': 'sound'}), isNull);
      expect(
        TakeSync.fromJson({
          'page': 'p7',
          'from': 'sound',
          'ms': 'x',
          'clips': [
            {'at': 1, 'ms': 2},
            {'at': 'x'},
            7,
          ],
        }),
        const TakeSync(
          page: 'p7',
          from: SyncFrom.sound,
          clips: [SyncClip(at: 1, ms: 2)],
        ),
      );
    });

    test('the song it lines up: the one played longest, at its own '
        'speed', () {
      expect(_log.linedSong, [_log.song.first]);
      expect(const TakeLog(burned: false).linedSong, isEmpty);
      const two = TakeLog(
        burned: false,
        song: [
          SongSegment(at: 0, to: 1000, page: 'a', from: 0),
          SongSegment(at: 1000, to: 3000, page: 'b', from: 0),
          SongSegment(at: 3000, to: 4500, page: 'a', from: 1000),
        ],
      );
      expect([for (final s in two.linedSong) s.at], [0, 3000]);
    });

    test('as Cam saves it with no tab and no song', () {
      const log = TakeLog(burned: false, lagFrom: LagFrom.recorder);
      expect(_encoded(log.toJson()), {
        'v': 1,
        'burned': false,
        'lagMs': 0,
        'lagFrom': 'recorder',
        'song': <Object?>[],
      });
    });

    test('read leniently: what isn\'t as expected is left out; no say on '
        'burned is burned (the tab never drawn twice)', () {
      expect(TakeLog.fromJson(null), isNull);
      expect(TakeLog.fromJson('log'), isNull);
      final log = TakeLog.fromJson({
        'lagMs': 'soon',
        'lagFrom': 'guess',
        'lagRaw': {'startCallMs': -20.4, 'x': 'y'},
        'tab': {
          'lines': [_riff[0], 3, _riff[1]],
          'marks': [
            [0, 0],
            [500, 9],
            'turn',
            [1000, 1],
            [800, 0],
          ],
        },
        'song': [
          {'at': 0, 'to': 10, 'page': 'p1', 'from': 0, 'speed': 0},
          {'at': 0, 'to': 10, 'page': 'p1', 'from': 0},
        ],
      })!;
      expect(log.burned, isTrue);
      expect(log.lagMs, 0);
      expect(log.lagFrom, LagFrom.none);
      expect(log.lagRaw, {'startCallMs': -20});
      expect(log.tab!.lines, [_riff[0], _riff[1]]);
      expect(log.tab!.marks, [(0, 0), (1000, 1)]);
      expect(log.song, [const SongSegment(at: 0, to: 10, page: 'p1', from: 0)]);
    });

    test('a newer app\'s is written back as it came, through a rename and '
        'a clone: what this version can\'t read included', () {
      final newer = _encoded({
        'v': 2,
        'burned': false,
        'lagMs': 140,
        'lagFrom': 'sound',
        'lagRaw': {'startCallMs': -200, 'peak': 1.5, 'note': 'x'},
        'tab': {
          'lines': [_riff[0], _riff[1]],
          'anchor': 'bottom',
          'marks': [
            [0, 0, 'tap'],
            [900, 1],
            [600, 0],
          ],
        },
        'song': [
          {
            'at': 0,
            'to': 900,
            'page': 'p7',
            'from': 0,
            'speed': 1,
            'gain': 0.8,
          },
          {'at': 900, 'to': 1800, 'page': 'p8', 'from': 0, 'speed': 'fast'},
          {'at': 1800, 'to': 2000, 'page': 'p9', 'from': 0},
        ],
        'pitch': 'A440',
      }) as Map;
      final page = EventPage.fromJson(
        (_encoded({
          'id': 'p1',
          'kind': 'video',
          'extension': 'mp4',
          'take': true,
          'takeLog': newer,
        }) as Map).cast(),
      );
      final log = page.takeLog!;
      // Read as this version can,
      expect(log.lagFrom, LagFrom.none);
      expect(log.lagRaw, {'startCallMs': -200, 'peak': 2});
      expect(log.tab!.marks, [(0, 0), (900, 1)]);
      expect(log.song.map((s) => s.page), ['p7', 'p9']);
      // written back as it came.
      final renamed = page.copyWith(title: () => 'Take 1');
      expect((_encoded(renamed.toJson()) as Map)['takeLog'], newer);
      expect(TakeLog.fromJson(newer), log);

      // A clone's: only the pages its segments name change, those this
      // version can't read too.
      final copy = log.withPages({'p7': 'q7', 'p8': 'q8'});
      final song = (_encoded(copy.toJson()) as Map)['song'] as List;
      expect(song.map((s) => (s as Map)['page']), ['q7', 'q8', 'p9']);
      expect((song.first as Map)['gain'], 0.8);
      expect((song[1] as Map)['speed'], 'fast');
      expect(copy.song.map((s) => s.page), ['q7', 'p9']);
      expect(
        {...(_encoded(copy.toJson()) as Map)}..remove('song'),
        {...newer}..remove('song'),
      );
      expect(identical(log.withPages({'p1': 'q1'}), log), isTrue);
    });
  });

  group('a take\'s page', () {
    test('keeps its log through JSON and every change', () {
      final page = EventPage.fromJson(
        (_encoded({
          'id': 'p1',
          'kind': 'video',
          'extension': 'mp4',
          'take': true,
          'takeLog': _log.toJson(),
        }) as Map).cast(),
      );
      expect(page.takeLog, _log);
      expect(page.extra, isEmpty);
      final renamed = page.copyWith(title: () => 'Take 1');
      expect(renamed.takeLog, _log);
      expect(
        _encoded(renamed.toJson()),
        containsPair('takeLog', _encoded(_log.toJson())),
      );
      const plain = EventPage(id: 'p2', kind: PageKind.video);
      expect(plain.toJson().containsKey('takeLog'), isFalse);
      expect(EventPage.fromJson(plain.toJson()).takeLog, isNull);
    });

    group('in the library', () {
      late Directory root;
      setUp(() async => root = await Directory.systemTemp.createTemp('tabcam'));
      tearDown(() => root.delete(recursive: true));

      test('is saved with the take, kept when renamed, and a clone\'s '
          'names the copy\'s songs', () async {
        final library = Library(PlatformEventStore(root));
        await library.load();
        var event = await library.create([
          img.encodeJpg(img.Image(width: 8, height: 8)),
        ]);
        event = await library.addMedia(event, [
          Media(
            XFile.fromData(Uint8List.fromList([1, 2]), name: 'song.m4a'),
            PageKind.audio,
            'm4a',
          ),
        ]);
        final song = event.pages.last;
        final log = TakeLog(
          burned: false,
          tab: _log.tab,
          song: [SongSegment(at: 100, to: 900, page: song.id, from: 0)],
        );
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
          takeLog: log,
        );
        final take = event.pages.last;
        expect(take.take, isTrue);
        expect(take.takeLog, log);
        // Only the take gets it.
        expect(song.takeLog, isNull);

        final renamed = await library.renamePage(event.id, take.id, 'Take 1');
        expect(renamed!.pages.last.takeLog, log);
        final reopened = Library(PlatformEventStore(root));
        await reopened.load();
        expect(reopened.byId(event.id)!.pages.last.takeLog, log);

        final copy = await library.clone(library.byId(event.id)!);
        final copied = copy.pages.last.takeLog!;
        expect(copied.song.single.page, copy.pages[1].id);
        expect(copied.song.single.page, isNot(song.id));
        expect(copied.tab, log.tab);
      });

      test('where its song was found is kept with it, once', () async {
        final library = Library(PlatformEventStore(root));
        await library.load();
        var event = await library.create([
          img.encodeJpg(img.Image(width: 8, height: 8)),
        ]);
        const log = TakeLog(
          burned: false,
          song: [SongSegment(at: 100, to: 9000, page: 'song', from: 0)],
        );
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
          takeLog: log,
        );
        final take = event.pages.last;
        const sync = TakeSync(page: 'song', from: SyncFrom.sound, ms: 41);
        final synced = await library.setTakeSync(event.id, take.id, sync);
        expect(synced!.pages.last.takeLog, log.withSync(sync));
        // Its name, and the other pages, as they were.
        expect(synced.pages.last.title, take.title);
        expect(synced.pages.first.takeLog, isNull);
        // One it has already stays: measured once.
        await library.setTakeSync(
          event.id,
          take.id,
          const TakeSync(page: 'song', from: SyncFrom.none),
        );
        expect(library.byId(event.id)!.pages.last.takeLog!.sync, sync);
        // A page without a log gets none.
        await library.setTakeSync(event.id, event.pages.first.id, sync);
        expect(library.byId(event.id)!.pages.first.takeLog, isNull);
        final reopened = Library(PlatformEventStore(root));
        await reopened.load();
        expect(reopened.byId(event.id)!.pages.last.takeLog!.sync, sync);
      });
    });
  });

  group('a take\'s length', () {
    /// An MP4 box of [type] holding [body].
    Uint8List box(String type, List<int> body) {
      final out = BytesBuilder()
        ..add((ByteData(4)..setUint32(0, body.length + 8)).buffer.asUint8List())
        ..add(ascii.encode(type))
        ..add(body);
      return out.toBytes();
    }

    /// An `mvhd` or `mdhd` (version 0 or 1) with [scale] and [duration].
    Uint8List header(String type, int scale, int duration, {int v = 0}) {
      final data = ByteData(v == 1 ? 32 : 20)..setUint8(0, v);
      if (v == 1) {
        data
          ..setUint32(20, scale)
          ..setUint32(24, duration ~/ 0x100000000)
          ..setUint32(28, duration % 0x100000000);
      } else {
        data
          ..setUint32(12, scale)
          ..setUint32(16, duration);
      }
      return box(type, data.buffer.asUint8List());
    }

    Uint8List trak(String handler, Uint8List mdhd) => box(
      'trak',
      box('mdia', [
        ...mdhd,
        ...box('hdlr', [0, 0, 0, 0, 0, 0, 0, 0, ...ascii.encode(handler)]),
      ]),
    );

    Future<int?> lengthOf(Uint8List bytes) => mp4VideoMsOf(
      (start, end) async =>
          bytes.sublist(min(start, bytes.length), min(end, bytes.length)),
      bytes.length,
    );

    test('is its video track\'s, read from its index wherever it is', () async {
      final mp4 = Uint8List.fromList([
        ...box('ftyp', ascii.encode('isom')),
        ...box('mdat', List.filled(5000, 7)),
        ...box('moov', [
          ...header('mvhd', 1000, 62000),
          ...trak('soun', header('mdhd', 48000, 48000 * 62)),
          ...trak('vide', header('mdhd', 90000, 90000 * 61420 ~/ 1000, v: 1)),
        ]),
      ]);
      expect(await lengthOf(mp4), 61420);
      expect(await mp4VideoMs(XFile.fromData(mp4)), 61420);
    });

    test('is the movie\'s without a video track; unknown when it isn\'t '
        'an MP4', () async {
      final sound = Uint8List.fromList([
        ...box('ftyp', ascii.encode('M4A ')),
        ...box('moov', [
          ...header('mvhd', 600, 600 * 3),
          ...trak('soun', header('mdhd', 44100, 44100 * 3)),
        ]),
      ]);
      expect(await lengthOf(sound), 3000);
      // A WebM's header, and a few bytes.
      expect(
        await lengthOf(Uint8List.fromList([0x1A, 0x45, 0xDF, 0xA3, 1, 2])),
        isNull,
      );
      expect(
        await mp4VideoMs(XFile.fromData(Uint8List.fromList([9, 1]))),
        isNull,
      );
    });
  });

  group('SongNotes', () {
    SongSegment seg(int at, int to, int from, {String page = 'k1'}) =>
        SongSegment(at: at, to: to, page: page, from: from);

    test('a song played and paused: one segment, from where it was', () {
      final notes = SongNotes();
      notes.note(0, page: 'k1', playing: false, position: 2000);
      expect(
        notes.note(500, page: 'k1', playing: true, position: 2000),
        isTrue,
      );
      // Playing on, as its player says now and then (a little late).
      for (var t = 1000; t <= 4000; t += 500) {
        expect(
          notes.note(t, page: 'k1', playing: true, position: 2000 + t - 700),
          isFalse,
        );
      }
      notes.note(4500, page: 'k1', playing: false, position: 5800);
      expect(notes.finish(9000), [seg(500, 4500, 2000)]);
    });

    test('a jump (a seek, Repeat, a section over again) starts another', () {
      final notes = SongNotes();
      notes.note(0, page: 'k1', playing: true, position: 0);
      notes.note(3000, page: 'k1', playing: true, position: 3000);
      // Back to its start.
      expect(notes.note(3200, page: 'k1', playing: true, position: 0), isTrue);
      // A skip ahead.
      notes.note(4200, page: 'k1', playing: true, position: 1000);
      expect(
        notes.note(4300, page: 'k1', playing: true, position: 6100),
        isTrue,
      );
      expect(notes.finish(5000), [
        seg(0, 3200, 0),
        seg(3200, 4300, 0),
        seg(4300, 5000, 6100),
      ]);
    });

    test('another song, another speed, or a link: another segment', () {
      final notes = SongNotes();
      notes.note(0, page: 'k1', playing: true, position: 0);
      notes.note(1000, page: 'k2', playing: true, position: 500);
      notes.note(2000, page: 'k2', playing: true, position: 1250, speed: 0.75);
      // A link playing: no page, no position; the song before ends.
      notes.noteLink();
      notes.note(3000, page: null, playing: true, position: 0);
      expect(notes.link, isTrue);
      expect(notes.finish(4000), [
        seg(0, 1000, 0),
        seg(1000, 2000, 500, page: 'k2'),
        const SongSegment(
          at: 2000,
          to: 3000,
          page: 'k2',
          from: 1250,
          speed: 0.75,
        ),
      ]);
    });

    test('a fresh reading tells the segment playing where it started', () {
      final notes = SongNotes();
      // Playing as the take starts: its player's position half a second
      // old.
      notes.note(0, page: 'k1', playing: true, position: 9500);
      notes.anchor(40, page: 'k1', position: 10040);
      // Another song's reading, or one from before: nothing.
      notes.anchor(60, page: 'k2', position: 0);
      expect(notes.finish(1000), [seg(0, 1000, 10000)]);
      // Nothing playing: nothing to tell.
      final idle = SongNotes()..anchor(10, page: 'k1', position: 5);
      expect(idle.finish(100), isEmpty);
    });

    test('nothing played: no segments; one ended as it started: none', () {
      final notes = SongNotes();
      notes.note(0, page: 'k1', playing: false, position: 0);
      notes.note(100, page: 'k1', playing: true, position: 0);
      notes.note(100, page: 'k1', playing: false, position: 0);
      expect(notes.finish(500), isEmpty);
      expect(notes.link, isFalse);
    });

    test('kept in the log, and read back', () {
      final notes = SongNotes()
        ..note(0, page: 'k1', playing: true, position: 0)
        ..note(2000, page: 'k1', playing: false, position: 2000);
      final log = TakeLog(burned: false, song: notes.finish(3000));
      final back = TakeLog.fromJson(jsonDecode(jsonEncode(log.toJson())))!;
      expect(back.song, [seg(0, 2000, 0)]);
    });
  });
}
