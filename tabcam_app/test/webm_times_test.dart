import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/webm_times.dart';

/// An EBML element: its ID's bytes, its size (one byte; null: not known,
/// as a recording's segment and clusters), its contents.
List<int> el(List<int> id, List<int> content, {bool sized = true}) => [
  ...id,
  if (sized) 0x80 | content.length else 0xff,
  ...content,
];

const _header = [0x1a, 0x45, 0xdf, 0xa3];
const _segment = [0x18, 0x53, 0x80, 0x67];
const _info = [0x15, 0x49, 0xa9, 0x66];
const _scale = [0x2a, 0xd7, 0xb1];
const _tracks = [0x16, 0x54, 0xae, 0x6b];
const _entry = [0xae];
const _number = [0xd7];
const _type = [0x83];
const _cluster = [0x1f, 0x43, 0xb6, 0x75];
const _time = [0xe7];
const _simple = [0xa3];
const _group = [0xa0];
const _block = [0xa1];

/// A track's entry: its number and kind (1 picture, 2 sound).
List<int> track(int number, int type) => el(_entry, [
  ...el(_number, [number]),
  // Something this doesn't read (a codec's name), skipped.
  ...el([0x86], [0x41, 0x5f, 0x4f]),
  ...el(_type, [type]),
]);

/// A block of [track], [after] ticks after its cluster's time.
List<int> block(int track, int after, {List<int> id = _simple}) =>
    el(id, [0x80 | track, (after >> 8) & 0xff, after & 0xff, 0x80, 1, 2, 3]);

/// A WebM as the browser records one: its segment and clusters without
/// their lengths, the picture as track 1, the sound as track 2.
Uint8List webm(List<int> clusters, {List<int> info = const []}) =>
    Uint8List.fromList([
      ...el(_header, [0x42, 0x82, 0x84, 0x77, 0x65, 0x62, 0x6d]),
      ..._segment,
      0x01,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      ...el(_info, info),
      ...el(_tracks, [...track(1, 1), ...track(2, 2)]),
      ...clusters,
    ]);

void main() {
  test('the sound track\'s first block\'s time', () {
    // The picture at 0 and 33 ms, the sound from 72 ms.
    expect(
      webmSoundStart(
        webm(
          el(_cluster, [
            ...el(_time, [0]),
            ...block(1, 0),
            ...block(1, 33),
            ...block(2, 72),
            ...block(2, 132),
          ], sized: false),
        ),
      ),
      const Duration(milliseconds: 72),
    );
    // With the file: none before it.
    expect(
      webmSoundStart(
        webm(
          el(_cluster, [
            ...el(_time, [0]),
            ...block(2, 0),
            ...block(1, 7),
          ], sized: false),
        ),
      ),
      Duration.zero,
    );
  });

  test('in a later cluster, after its time; in a block group; at another '
      'time scale', () {
    final later = [
      ...el(_cluster, [
        ...el(_time, [0]),
        ...block(1, 0),
      ], sized: false),
      ...el(_cluster, [
        ...el(_time, [0x03, 0xe8]),
        ...block(1, 5),
        ...el(_group, block(2, 20, id: _block)),
      ], sized: false),
    ];
    expect(webmSoundStart(webm(later)), const Duration(milliseconds: 1020));
    // A tick of half a millisecond.
    expect(
      webmSoundStart(webm(later, info: el(_scale, [0x07, 0xa1, 0x20]))),
      const Duration(milliseconds: 510),
    );
    // Before its cluster's time (a negative step): never before the file.
    expect(
      webmSoundStart(
        webm(
          el(_cluster, [
            ...el(_time, [2]),
            ...block(2, 0xfffb),
          ], sized: false),
        ),
      ),
      Duration.zero,
    );
  });

  test('none: not a WebM, no sound track, no block of it, or cut short', () {
    expect(webmSoundStart(Uint8List(0)), isNull);
    expect(webmSoundStart(Uint8List.fromList([0, 0, 0, 0x20, 1, 2])), isNull);
    // Only a picture.
    expect(
      webmSoundStart(
        Uint8List.fromList([
          ...el(_header, []),
          ..._segment,
          0xff,
          ...el(_tracks, track(1, 1)),
          ...el(_cluster, [
            ...el(_time, [0]),
            ...block(1, 0),
          ], sized: false),
        ]),
      ),
      isNull,
    );
    expect(
      webmSoundStart(
        webm(
          el(_cluster, [
            ...el(_time, [0]),
            ...block(1, 0),
          ], sized: false),
        ),
      ),
      isNull,
    );
    final whole = webm(
      el(_cluster, [
        ...el(_time, [0]),
        ...block(1, 0),
        ...block(2, 40),
      ], sized: false),
    );
    expect(webmSoundStart(whole), const Duration(milliseconds: 40));
    // Cut anywhere before the sound's block: none, and nothing thrown.
    for (var length = 0; length < whole.length - 7; length++) {
      expect(webmSoundStart(Uint8List.sublistView(whole, 0, length)), isNull);
    }
    // Looked for only so far in.
    expect(webmSoundStart(whole, most: whole.length - 8), isNull);
  });
}
