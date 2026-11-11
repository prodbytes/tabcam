import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// The samples in an AAC-LC frame.
const aacFrameLength = 1024;

/// AAC-LC [frames] (raw access units, as WebCodecs' AudioEncoder makes
/// them, [aacFrameLength] samples each) at [sampleRate] with [channels],
/// in an M4A file (ISO base media, `M4A ` brand, one `mp4a` track, its
/// index before its data so it plays as it loads).
///
/// [config] is the AAC AudioSpecificConfig (the encoder's decoder
/// description; made from the rate and channels when null). The first
/// [priming] samples are the encoder's delay and [length] the samples
/// that are sound (all the rest when null): an edit list plays those
/// only, so the file is as long as the sound put in.
Uint8List m4aBytes(
  List<Uint8List> frames, {
  required int sampleRate,
  required int channels,
  Uint8List? config,
  int priming = 0,
  int? length,
}) {
  if (sampleRate <= 0 || channels <= 0) {
    throw ArgumentError('A sound needs a rate and channels');
  }
  final asc = config ?? aacConfig(sampleRate, channels);
  final media = frames.length * aacFrameLength;
  final shown = (length ?? media - priming)
      .clamp(0, max(0, media - priming))
      .toInt();
  final data = frames.fold<int>(0, (n, f) => n + f.length);
  if (data > 0xffffffff - 0x100000) {
    throw StateError('The sound is too long for one M4A');
  }

  // Bits a second, on average and at most over any second.
  final seconds = media / sampleRate;
  final average = seconds == 0 ? 0 : (data * 8 / seconds).round();
  final window = max(1, (sampleRate / aacFrameLength).ceil());
  var most = 0;
  var sum = 0;
  for (var i = 0; i < frames.length; i++) {
    sum += frames[i].length;
    if (i >= window) sum -= frames[i - window].length;
    most = max(most, sum);
  }
  final largest = frames.fold<int>(0, (n, f) => max(n, f.length));

  final esds = _full('esds', [
    _descriptor(3, [
      _u(0, 2), // ES_ID
      _u(0, 1), // no dependency, URL or OCR stream
      _descriptor(4, [
        _u(0x40, 1), // MPEG-4 audio
        _u(0x15, 1), // an audio stream
        _u(largest, 3),
        _u(max(most * 8, average), 4),
        _u(average, 4),
        _descriptor(5, [asc]),
      ]),
      _descriptor(6, [_u(2, 1)]), // MP4's sync layer
    ]),
  ]);
  final mp4a = _box('mp4a', [
    _u(0, 6),
    _u(1, 2), // its data reference
    _u(0, 8),
    _u(channels, 2),
    _u(16, 2), // sample size
    _u(0, 4),
    _u(sampleRate < 0x10000 ? sampleRate << 16 : 0, 4),
    esds,
  ]);

  Uint8List moov(int offset) => _box('moov', [
    _full('mvhd', [
      _u(0, 8), // created, modified
      _u(sampleRate, 4),
      _u(shown, 4),
      _u(0x10000, 4), // rate 1
      _u(0x100, 2), // volume 1
      _u(0, 10),
      _matrix,
      _u(0, 24),
      _u(2, 4), // the next track's ID
    ]),
    _box('trak', [
      _full('tkhd', flags: 3, [
        _u(0, 8),
        _u(1, 4), // its ID
        _u(0, 4),
        _u(shown, 4),
        _u(0, 8),
        _u(0, 4), // layer, alternate group
        _u(0x100, 2), // volume 1
        _u(0, 2),
        _matrix,
        _u(0, 8), // no width or height
      ]),
      _box('edts', [
        _full('elst', [
          _u(1, 4),
          _u(shown, 4),
          _u(priming, 4),
          _u(0x10000, 4), // rate 1
        ]),
      ]),
      _box('mdia', [
        _full('mdhd', [
          _u(0, 8),
          _u(sampleRate, 4),
          _u(media, 4),
          _u(0x55c4, 2), // 'und'
          _u(0, 2),
        ]),
        _full('hdlr', [
          _u(0, 4),
          ascii.encode('soun'),
          _u(0, 12),
          ascii.encode('SoundHandler\x00'),
        ]),
        _box('minf', [
          _full('smhd', [_u(0, 4)]),
          _box('dinf', [
            _full('dref', [
              _u(1, 4),
              _full('url ', flags: 1, []), // its data is in this file
            ]),
          ]),
          _box('stbl', [
            _full('stsd', [_u(1, 4), mp4a]),
            _full('stts', [
              _u(frames.isEmpty ? 0 : 1, 4),
              if (frames.isNotEmpty) ...[
                _u(frames.length, 4),
                _u(aacFrameLength, 4),
              ],
            ]),
            _full('stsc', [
              _u(frames.isEmpty ? 0 : 1, 4),
              if (frames.isNotEmpty) ...[
                _u(1, 4),
                _u(frames.length, 4),
                _u(1, 4),
              ],
            ]),
            _full('stsz', [
              _u(0, 4),
              _u(frames.length, 4),
              for (final f in frames) _u(f.length, 4),
            ]),
            // One chunk: all the frames, in the data box.
            _full('stco', [
              _u(frames.isEmpty ? 0 : 1, 4),
              if (frames.isNotEmpty) _u(offset, 4),
            ]),
          ]),
        ]),
      ]),
    ]),
  ]);

  final ftyp = _box('ftyp', [
    ascii.encode('M4A '),
    _u(0, 4),
    ascii.encode('M4A '),
    ascii.encode('isom'),
    ascii.encode('mp42'),
  ]);
  final index = moov(0).length;
  final out = BytesBuilder(copy: false)
    ..add(ftyp)
    ..add(moov(ftyp.length + index + 8))
    ..add(_u(8 + data, 4))
    ..add(ascii.encode('mdat'));
  for (final f in frames) {
    out.add(f);
  }
  return out.takeBytes();
}

/// The AAC-LC AudioSpecificConfig for [sampleRate] and [channels] (1 to
/// 7, or 0 when the stream says).
Uint8List aacConfig(int sampleRate, int channels) {
  const rates = [
    96000, 88200, 64000, 48000, 44100, 32000, 24000, //
    22050, 16000, 12000, 11025, 8000, 7350,
  ];
  final index = rates.indexOf(sampleRate);
  final bits = <(int, int)>[
    (2, 5), // AAC LC
    if (index >= 0) (index, 4) else ...[(15, 4), (sampleRate, 24)],
    (channels, 4),
    (0, 3), // 1024 samples a frame, no core coder, no extension
  ];
  final count = bits.fold<int>(0, (n, b) => n + b.$2);
  final out = Uint8List((count + 7) ~/ 8);
  var at = 0;
  for (final (value, width) in bits) {
    for (var b = width - 1; b >= 0; b--) {
      if ((value >> b) & 1 == 1) out[at ~/ 8] |= 0x80 >> (at % 8);
      at++;
    }
  }
  return out;
}

final _matrix = Uint8List.fromList([
  ..._u(0x10000, 4), ..._u(0, 4), ..._u(0, 4), //
  ..._u(0, 4), ..._u(0x10000, 4), ..._u(0, 4), //
  ..._u(0, 4), ..._u(0, 4), ..._u(0x40000000, 4),
]);

/// [value] as [bytes] big-endian bytes.
Uint8List _u(int value, int bytes) {
  final out = Uint8List(bytes);
  for (var i = bytes - 1; i >= 0; i--) {
    out[i] = value & 0xff;
    value >>= 8;
  }
  return out;
}

Uint8List _join(List<Uint8List> parts) {
  final out = BytesBuilder(copy: false);
  for (final p in parts) {
    out.add(p);
  }
  return out.takeBytes();
}

/// A box: its size, its [type], then [parts].
Uint8List _box(String type, List<Uint8List> parts) {
  final body = _join(parts);
  return _join([_u(8 + body.length, 4), ascii.encode(type), body]);
}

/// A full box: a box whose body starts with a version (0) and [flags].
Uint8List _full(String type, List<Uint8List> parts, {int flags = 0}) =>
    _box(type, [_u(flags, 4), ...parts]);

/// An MPEG-4 descriptor: its [tag], its size (7 bits a byte), [parts].
Uint8List _descriptor(int tag, List<Uint8List> parts) {
  final body = _join(parts);
  final size = <int>[];
  var n = body.length;
  do {
    size.insert(0, (n & 0x7f) | (size.isEmpty ? 0 : 0x80));
    n >>= 7;
  } while (n > 0);
  return _join([
    Uint8List.fromList([tag, ...size]),
    body,
  ]);
}
