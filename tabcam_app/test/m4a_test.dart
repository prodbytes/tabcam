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
    final config = Uint8List(200);
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
