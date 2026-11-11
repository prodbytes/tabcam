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
import 'package:tabcam_app/capture/take_overlay.dart';
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
}
