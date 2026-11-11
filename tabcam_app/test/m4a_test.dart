import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/m4a.dart';

/// A box read back: its type, where its body starts, and its body.
typedef Box = ({String type, int at, Uint8List body});

/// The boxes one after another in [bytes] from [from] to [to].
List<Box> boxes(Uint8List bytes, [int from = 0, int? to]) {
  final end = to ?? bytes.length;
  final data = ByteData.sublistView(bytes);
  final out = <Box>[];
  var at = from;
  while (at < end) {
    final size = data.getUint32(at);
    expect(size, greaterThanOrEqualTo(8));
    expect(at + size, lessThanOrEqualTo(end));
    out.add((
      type: String.fromCharCodes(bytes.sublist(at + 4, at + 8)),
      at: at + 8,
      body: bytes.sublist(at + 8, at + size),
    ));
    at += size;
  }
  expect(at, end);
  return out;
}

/// The box at [path] (types, from the top), in [bytes]; a full box's body
/// starts with its version and flags. Boxes inside a sample entry or a
/// full box start [skip] bytes into their parent's body.
Box find(Uint8List bytes, List<String> path) {
  const skip = {'stsd': 8, 'dref': 8, 'mp4a': 28};
  Box? box;
  var children = boxes(bytes);
  for (final type in path) {
    box = children.firstWhere(
      (b) => b.type == type,
      orElse: () => fail('no $type in ${children.map((b) => b.type)}'),
    );
    final from = box.at + (skip[type] ?? 0);
    children =
        [
          'moov',
          'trak',
          'mdia',
          'minf',
          'stbl',
          'dinf',
          'edts',
          ...skip.keys,
        ].contains(type)
        ? boxes(bytes, from, box.at + box.body.length)
        : const [];
  }
  return box!;
}

int u32(Uint8List body, int at) => ByteData.sublistView(body).getUint32(at);
int u16(Uint8List body, int at) => ByteData.sublistView(body).getUint16(at);

void main() {
  // Made-up AAC frames: their sizes vary, as an encoder's do.
  final frames = [
    for (var i = 0; i < 90; i++)
      Uint8List.fromList(List.filled(4 + (i * 37) % 300, i)),
  ];
  final file = m4aBytes(
    frames,
    sampleRate: 44100,
    channels: 2,
    config: Uint8List.fromList([0x12, 0x10]),
    priming: 2112,
    length: 88200,
  );

  test('an M4A: its brand, its index, then its data', () {
    expect([for (final b in boxes(file)) b.type], ['ftyp', 'moov', 'mdat']);
    final ftyp = find(file, ['ftyp']).body;
    expect(String.fromCharCodes(ftyp.sublist(0, 4)), 'M4A ');
    expect(String.fromCharCodes(ftyp.sublist(8)), 'M4A isommp42');
  });

  test('one sound track: mp4a, AAC, at its rate and channels', () {
    final path = ['moov', 'trak', 'mdia'];
    final handler = find(file, [...path, 'hdlr']).body;
    expect(String.fromCharCodes(handler.sublist(8, 12)), 'soun');
    final stbl = [...path, 'minf', 'stbl'];
    final stsd = find(file, [...stbl, 'stsd']).body;
    expect(u32(stsd, 4), 1);
    final mp4a = find(file, [...stbl, 'stsd', 'mp4a']).body;
    expect(u16(mp4a, 16), 2); // channels
    expect(u16(mp4a, 18), 16); // bits
    expect(u32(mp4a, 24) >> 16, 44100);
    // The ES descriptor: MPEG-4 audio (0x40), an audio stream, the AAC
    // config last.
    final esds = find(file, [...stbl, 'stsd', 'mp4a', 'esds']).body;
    expect(esds[4], 3);
    final decoder = esds.indexOf(4, 5);
    expect(esds[decoder + 2], 0x40);
    expect(esds[decoder + 3], 0x15);
    final info = esds.indexOf(5, decoder);
    expect(esds.sublist(info, info + 4), [5, 2, 0x12, 0x10]);
    expect(esds.sublist(esds.length - 3), [6, 1, 2]);
    expect(find(file, [...path, 'minf', 'smhd']).body, hasLength(8));
  });

  test('its frames: 1024 samples each, their sizes, where they are', () {
    final stbl = ['moov', 'trak', 'mdia', 'minf', 'stbl'];
    final stts = find(file, [...stbl, 'stts']).body;
    expect([u32(stts, 4), u32(stts, 8), u32(stts, 12)], [1, 90, 1024]);
    final stsz = find(file, [...stbl, 'stsz']).body;
    expect(u32(stsz, 4), 0);
    expect(u32(stsz, 8), 90);
    expect(
      [for (var i = 0; i < 90; i++) u32(stsz, 12 + i * 4)],
      [for (final f in frames) f.length],
    );
    final stsc = find(file, [...stbl, 'stsc']).body;
    expect([u32(stsc, 4), u32(stsc, 8), u32(stsc, 12)], [1, 1, 90]);
    final stco = find(file, [...stbl, 'stco']).body;
    expect(u32(stco, 4), 1);
    final offset = u32(stco, 8);
    final mdat = find(file, ['mdat']);
    expect(offset, mdat.at);
    expect(file.sublist(offset, offset + frames[0].length), frames[0]);
    expect(mdat.body, [for (final f in frames) ...f]);
  });

  test('each frame needs the one before it to decode (a roll of -1), as '
      'Apple writes AAC, so Apple\'s decoders cut only the edit list\'s '
      'delay', () {
    final stbl = ['moov', 'trak', 'mdia', 'minf', 'stbl'];
    final sgpd = find(file, [...stbl, 'sgpd']).body;
    expect(sgpd[0], 1); // version 1
    expect(String.fromCharCodes(sgpd.sublist(4, 8)), 'roll');
    expect([u32(sgpd, 8), u32(sgpd, 12)], [2, 1]);
    expect(ByteData.sublistView(sgpd).getInt16(16), -1);
    expect(sgpd, hasLength(18));
    final sbgp = find(file, [...stbl, 'sbgp']).body;
    expect(String.fromCharCodes(sbgp.sublist(4, 8)), 'roll');
    expect([u32(sbgp, 8), u32(sbgp, 12), u32(sbgp, 16)], [1, 90, 1]);
    // No frames: no group.
    final empty = m4aBytes(const [], sampleRate: 44100, channels: 2);
    final table = find(empty, stbl);
    expect(
      [
        for (final b in boxes(empty, table.at, table.at + table.body.length))
          b.type,
      ],
      ['stsd', 'stts', 'stsc', 'stsz', 'stco'],
    );
  });

  test('as long as the sound: the encoder\'s delay and padding cut by an '
      'edit list', () {
    final mvhd = find(file, ['moov', 'mvhd']).body;
    expect(u32(mvhd, 12), 44100); // timescale
    expect(u32(mvhd, 16), 88200); // 2 s
    final tkhd = find(file, ['moov', 'trak', 'tkhd']).body;
    expect(u32(tkhd, 0) & 0xffffff, 3); // enabled, in the movie
    expect(u32(tkhd, 20), 88200);
    final elst = find(file, ['moov', 'trak', 'edts', 'elst']).body;
    expect([u32(elst, 4), u32(elst, 8), u32(elst, 12)], [1, 88200, 2112]);
    final mdhd = find(file, ['moov', 'trak', 'mdia', 'mdhd']).body;
    expect(u32(mdhd, 12), 44100);
    expect(u32(mdhd, 16), 90 * 1024);
  });

  test('without a delay or length, all its samples; its config made from '
      'the rate and channels', () {
    final plain = m4aBytes(
      frames.sublist(0, 3),
      sampleRate: 48000,
      channels: 1,
    );
    final elst = find(plain, ['moov', 'trak', 'edts', 'elst']).body;
    expect([u32(elst, 8), u32(elst, 12)], [3 * 1024, 0]);
    final esds = find(plain, [
      'moov', 'trak', 'mdia', 'minf', 'stbl', 'stsd', 'mp4a', 'esds', //
    ]).body;
    final info = esds.indexOf(5, esds.indexOf(4, 5));
    expect(esds.sublist(info, info + 4), [5, 2, 0x11, 0x88]);
  });

  test('a long descriptor\'s size takes more bytes', () {
    // An AudioSpecificConfig (AAC LC first), however long.
    final config = Uint8List(200)..[0] = 0x12;
    final long = m4aBytes(
      frames.sublist(0, 1),
      sampleRate: 44100,
      channels: 2,
      config: config,
    );
    final esds = find(long, [
      'moov', 'trak', 'mdia', 'minf', 'stbl', 'stsd', 'mp4a', 'esds', //
    ]).body;
    // The ES descriptor's size, 7 bits a byte: 0x81 0x61 is 225 (its
    // ID and flags, the decoder's 219, the sync layer's 3).
    expect(esds.sublist(4, 7), [3, 0x81, 0x61]);
    expect(esds.length, 4 + 3 + 225);
    // The config's: 0x81 0x48 is 200.
    expect(esds.sublist(esds.length - 3 - 203, esds.length - 200 - 3), [
      5,
      0x81,
      0x48,
    ]);
  });

  // WebKit's AudioEncoder (Safari 26) describes its AAC with Apple's
  // magic cookie, a whole ES descriptor, not the AudioSpecificConfig
  // (Chrome's 12 10) in it.
  final webkit = Uint8List.fromList([
    0x03, 0x80, 0x80, 0x80, 0x22, 0x00, 0x00, 0x00, // ES, ID 0, no flags
    0x04, 0x80, 0x80, 0x80, 0x14, 0x40, 0x14, 0x00, 0x18, 0x00, //
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // decoder config
    0x05, 0x80, 0x80, 0x80, 0x02, 0x12, 0x10, // its AudioSpecificConfig
    0x06, 0x80, 0x80, 0x80, 0x01, 0x02, // sync layer
  ]);

  test('an encoder\'s description: an AudioSpecificConfig as it is, the '
      'one in an ES descriptor (WebKit\'s)', () {
    expect(isEsDescriptor(webkit), isTrue);
    expect(isEsDescriptor(Uint8List.fromList([0x12, 0x10])), isFalse);
    expect(audioSpecificConfig(webkit), [0x12, 0x10]);
    expect(audioSpecificConfig(Uint8List.fromList([0x12, 0x10])), [0x12, 0x10]);
    // Its flags say what comes before its decoder config: a stream it
    // depends on, a URL, an OCR stream.
    final flagged = Uint8List.fromList([
      0x03, 0x1e, 0x00, 0x01, 0xe0, 0x00, 0x02, // ID 1, all three flags
      0x03, 0x61, 0x62, 0x63, 0x00, 0x03, // the URL "abc", the OCR's ID
      0x04, 0x11, 0x40, 0x15, ...List.filled(11, 0), //
      0x05, 0x02, 0x11, 0x90,
    ]);
    expect(flagged[1], flagged.length - 2);
    expect(audioSpecificConfig(flagged), [0x11, 0x90]);
    // A decoder config, or the specific info, alone.
    expect(audioSpecificConfig(webkit.sublist(8, 33)), [0x12, 0x10]);
    expect(audioSpecificConfig(webkit.sublist(26, 33)), [0x12, 0x10]);
    // Cut short, or none in it: none.
    expect(audioSpecificConfig(webkit.sublist(0, 30)), isNull);
    expect(audioSpecificConfig(webkit.sublist(0, 26)), isNull);
    expect(
      audioSpecificConfig(Uint8List.fromList([3, 6, 0, 0, 0, 6, 1, 2])),
      isNull,
    );
    expect(audioSpecificConfig(Uint8List(0)), isNull);
  });

  test('an M4A of WebKit\'s frames holds the AudioSpecificConfig, not its '
      'whole ES descriptor (which says no audio type)', () {
    final made = m4aBytes(
      frames.sublist(0, 3),
      sampleRate: 44100,
      channels: 2,
      config: webkit,
    );
    final esds = find(made, [
      'moov', 'trak', 'mdia', 'minf', 'stbl', 'stsd', 'mp4a', 'esds', //
    ]).body;
    final info = esds.indexOf(5, esds.indexOf(4, 5));
    expect(esds.sublist(info, info + 4), [5, 2, 0x12, 0x10]);
    expect(esds.sublist(esds.length - 3), [6, 1, 2]);
    // One that holds none: made from the rate and channels.
    final none = m4aBytes(
      frames.sublist(0, 3),
      sampleRate: 48000,
      channels: 1,
      config: webkit.sublist(0, 26),
    );
    final noneEsds = find(none, [
      'moov', 'trak', 'mdia', 'minf', 'stbl', 'stsd', 'mp4a', 'esds', //
    ]).body;
    final noneInfo = noneEsds.indexOf(5, noneEsds.indexOf(4, 5));
    expect(noneEsds.sublist(noneInfo, noneInfo + 4), [5, 2, 0x11, 0x88]);
  });

  test('aacConfig: AAC LC, the rate\'s index, the channels', () {
    expect(aacConfig(44100, 2), [0x12, 0x10]);
    expect(aacConfig(44100, 1), [0x12, 0x08]);
    expect(aacConfig(48000, 2), [0x11, 0x90]);
    // A rate with no index: written out, in 24 bits.
    expect(aacConfig(44000, 2), [0x17, 0x80, 0x55, 0xf0, 0x10]);
  });

  test('no rate or channels: an error', () {
    expect(
      () => m4aBytes(frames, sampleRate: 0, channels: 2),
      throwsArgumentError,
    );
  });
}
