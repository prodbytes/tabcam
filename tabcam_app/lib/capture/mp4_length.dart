import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// How long [file]'s video is, in ms, as its MP4 (or MOV) index says: its
/// video track's length (the `mdhd` of the `trak` whose `hdlr` is
/// `vide`), else the movie's (`mvhd`). Null when it isn't one, or doesn't
/// say (a fragmented MP4, a WebM). Only the boxes' headers and the few
/// that say it are read, never the file's media, so a long take costs as
/// little as a short one.
Future<int?> mp4VideoMs(XFile file) async {
  try {
    final length = await file.length();
    return await mp4VideoMsOf((start, end) async {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in file.openRead(start, end)) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    }, length);
  } on Object catch (e) {
    debugPrint('TabCam: cam: the take\'s length unread: $e');
    return null;
  }
}

/// [mp4VideoMs] for a file [length] bytes long, read by [read] (its bytes
/// from `start` to `end`, fewer at its end).
Future<int?> mp4VideoMsOf(
  Future<Uint8List> Function(int start, int end) read,
  int length,
) async {
  final top = await _boxes(read, 0, length);
  final moov = top['moov']?.firstOrNull;
  if (moov == null) return null;
  final inMoov = await _boxes(read, moov.body, moov.end);
  for (final trak in inMoov['trak'] ?? const <_Box>[]) {
    final mdia = (await _boxes(read, trak.body, trak.end))['mdia']?.firstOrNull;
    if (mdia == null) continue;
    final inMdia = await _boxes(read, mdia.body, mdia.end);
    final hdlr = inMdia['hdlr']?.firstOrNull;
    final mdhd = inMdia['mdhd']?.firstOrNull;
    if (hdlr == null || mdhd == null) continue;
    // Version and flags, pre-defined, then the handler's type.
    final type = await read(hdlr.body + 8, min(hdlr.body + 12, hdlr.end));
    if (type.length < 4 || String.fromCharCodes(type) != 'vide') continue;
    if (await _durationMs(read, mdhd) case final ms?) return ms;
  }
  final mvhd = inMoov['mvhd']?.firstOrNull;
  return mvhd == null ? null : _durationMs(read, mvhd);
}

/// An `mvhd`'s or `mdhd`'s duration in ms (the two start alike: version
/// and flags, created and modified times, the time scale, the duration).
Future<int?> _durationMs(
  Future<Uint8List> Function(int start, int end) read,
  _Box box,
) async {
  final bytes = await read(box.body, min(box.body + 32, box.end));
  if (bytes.isEmpty) return null;
  final data = ByteData.sublistView(bytes);
  final int scale;
  final int duration;
  if (bytes[0] == 1) {
    if (bytes.length < 32) return null;
    scale = data.getUint32(20);
    duration = _uint64(data, 24);
  } else {
    if (bytes.length < 20) return null;
    scale = data.getUint32(12);
    duration = data.getUint32(16);
  }
  // All ones: not known.
  if (scale == 0 || duration <= 0 || duration == 0xFFFFFFFF) return null;
  return (duration * 1000 / scale).round();
}

/// A box: where its contents start ([body]) and where it ends.
typedef _Box = ({int body, int end});

/// The boxes from [start] to [end], by type.
Future<Map<String, List<_Box>>> _boxes(
  Future<Uint8List> Function(int start, int end) read,
  int start,
  int end,
) async {
  final boxes = <String, List<_Box>>{};
  var at = start;
  // No index has more (a guard against a file that isn't one).
  for (var n = 0; n < 4096 && at + 8 <= end; n++) {
    final head = await read(at, min(at + 16, end));
    if (head.length < 8) break;
    final data = ByteData.sublistView(head);
    var size = data.getUint32(0);
    final type = String.fromCharCodes(head, 4, 8);
    var header = 8;
    if (size == 1) {
      if (head.length < 16) break;
      size = _uint64(data, 8);
      header = 16;
    } else if (size == 0) {
      size = end - at;
    }
    if (size < header || at + size > end) break;
    (boxes[type] ??= []).add((body: at + header, end: at + size));
    at += size;
  }
  return boxes;
}

/// A big-endian 64-bit number (`getUint64` isn't there on the web).
int _uint64(ByteData data, int at) =>
    data.getUint32(at) * 0x100000000 + data.getUint32(at + 4);
