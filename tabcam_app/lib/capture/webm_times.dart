import 'dart:typed_data';

/// When a WebM file's sound starts, on the file's own clock: its sound
/// track's first block's time; null when it isn't a WebM, has no sound,
/// or none is found in its first [most] bytes.
///
/// A take the browser records often has its sound start a little after
/// its picture (its first sound block some tens of ms in). A player
/// plays the sound from there, but a decoder handed the whole file
/// (Web Audio's decodeAudioData) gives the sound from its first sample,
/// as if it started with the file: by this much earlier than it plays.
///
/// Only what's needed is read (Matroska's EBML): the tracks' numbers and
/// kinds, the time scale, and the clusters' times and blocks up to the
/// first block of sound.
Duration? webmSoundStart(Uint8List bytes, {int most = 8 * 1024 * 1024}) {
  final end = bytes.length < most ? bytes.length : most;
  // EBML's magic number.
  if (end < 4 ||
      bytes[0] != 0x1a ||
      bytes[1] != 0x45 ||
      bytes[2] != 0xdf ||
      bytes[3] != 0xa3) {
    return null;
  }
  var at = 0;
  // An element's ID, its marker bits kept (1 to 4 bytes); -1 at the end.
  int id() {
    if (at >= end) return -1;
    final first = bytes[at];
    var length = 1;
    while (length <= 4 && first & (0x80 >> (length - 1)) == 0) {
      length++;
    }
    if (length > 4 || at + length > end) return -1;
    var value = 0;
    for (var i = 0; i < length; i++) {
      value = (value << 8) | bytes[at + i];
    }
    at += length;
    return value;
  }

  // A size, or a block's track number (1 to 8 bytes, the marker bit taken
  // out); -1: not known (all ones: a recording not closed), -2 at the end.
  int size() {
    if (at >= end) return -2;
    final first = bytes[at];
    var length = 1;
    while (length <= 8 && first & (0x80 >> (length - 1)) == 0) {
      length++;
    }
    if (length > 8 || at + length > end) return -2;
    var value = first & (0xff >> length);
    var ones = value == (0xff >> length);
    for (var i = 1; i < length; i++) {
      value = (value << 8) | bytes[at + i];
      ones = ones && bytes[at + i] == 0xff;
    }
    at += length;
    return ones ? -1 : value;
  }

  // A whole number, [length] bytes long.
  int? number(int length) {
    if (length < 1 || length > 8 || at + length > end) return null;
    var value = 0;
    for (var i = 0; i < length; i++) {
      value = (value << 8) | bytes[at + i];
    }
    return value;
  }

  // The parts looked into (their contents read on, not skipped).
  const segment = 0x18538067;
  const info = 0x1549a966;
  const tracks = 0x1654ae6b;
  const trackEntry = 0xae;
  const cluster = 0x1f43b675;
  const blockGroup = 0xa0;
  // The values read.
  const timeScale = 0x2ad7b1;
  const trackNumber = 0xd7;
  const trackType = 0x83;
  const clusterTime = 0xe7;
  const simpleBlock = 0xa3;
  const block = 0xa1;

  var scale = 1000000; // ns a tick
  int? entryNumber;
  int? entryType;
  int? sound;
  var time = 0;
  while (true) {
    final element = id();
    if (element < 0) return null;
    final length = size();
    if (length == -2) return null;
    switch (element) {
      case segment || info || tracks || cluster || blockGroup:
        continue;
      case trackEntry:
        entryNumber = entryType = null;
        continue;
    }
    // Only the parts looked into may not say their length.
    if (length < 0) return null;
    switch (element) {
      case timeScale:
        final value = number(length);
        if (value != null && value > 0) scale = value;
      case trackNumber:
        entryNumber = number(length);
      case trackType:
        entryType = number(length);
      case clusterTime:
        time = number(length) ?? time;
      case simpleBlock || block:
        final from = at;
        final track = size();
        if (track >= 0 && track == sound && at + 2 <= end) {
          // Its time after the cluster's: 16 bits, signed.
          final after = ((bytes[at] << 8) | bytes[at + 1]).toSigned(16);
          final ns = (time + after) * scale;
          return Duration(microseconds: ns < 0 ? 0 : ns ~/ 1000);
        }
        at = from;
    }
    // The first track of sound (kind 2).
    if (sound == null && entryType == 2 && entryNumber != null) {
      sound = entryNumber;
    }
    at += length;
  }
}
