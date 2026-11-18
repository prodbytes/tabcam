import 'dart:js_interop';
import 'dart:math';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'sound_reader.dart';
import 'webm_times.dart';

/// In the browser, a file's sound is read with Web Audio.
SoundReader? webSoundReader() => WebSoundReader();

/// Reads samples in the browser: the file's sound decoded whole
/// (decodeAudioData decodes all of a file, whatever part is wanted), at
/// the rate asked for (an offline context's: the browser resamples), its
/// channels mixed to one, and kept until [close], so the parts of one
/// file are decoded once. A WebM's sound is put where the file has it
/// start ([webmSoundStart]), as a player plays it.
class WebSoundReader implements SoundReader {
  /// A file longer than this in bytes isn't read: decoding takes it
  /// whole in memory, twice over while it's handed to the decoder.
  static const int largest = 600 * 1024 * 1024;

  final _decoded = <XFile, Future<Float32List?>>{};
  int? _rate;

  @override
  Future<Float32List?> samples(
    XFile file, {
    required Duration from,
    required Duration length,
    required int rate,
  }) async {
    // One rate at a time: what's kept was decoded at it.
    if (_rate != rate) {
      _decoded.clear();
      _rate = rate;
    }
    final all = await (_decoded[file] ??= _decode(file, rate));
    if (all == null) return null;
    final start = from.inMicroseconds * rate ~/ 1000000;
    final end = min(
      all.length,
      start + length.inMicroseconds * rate ~/ 1000000,
    );
    if (start < 0 || end <= start) return null;
    return Float32List.sublistView(all, start, end);
  }

  @override
  void close() => _decoded.clear();

  static Future<Float32List?> _decode(XFile file, int rate) async {
    try {
      if (await file.length() > largest) return null;
      final bytes = await file.readAsBytes();
      final decoder = web.OfflineAudioContext(1.toJS, 1, rate.toDouble());
      // A copy: decodeAudioData takes the buffer it's given away.
      final sound = await decoder
          .decodeAudioData(Uint8List.fromList(bytes).buffer.toJS)
          .toDart;
      final channels = sound.numberOfChannels;
      if (channels < 1 || sound.length < 1) return null;
      // A WebM's sound may start after the file does (a take's often
      // does, by some tens of ms): the decoder gives it from its first
      // sample, a player plays it from where it starts, so that much
      // silence goes first.
      final lead =
          (webmSoundStart(bytes)?.inMicroseconds ?? 0) * rate ~/ 1000000;
      if (lead > 10 * rate) return null;
      final mono = Float32List(lead + sound.length);
      for (var c = 0; c < channels; c++) {
        final samples = sound.getChannelData(c).toDart;
        for (var i = 0; i < samples.length; i++) {
          mono[lead + i] += samples[i] / channels;
        }
      }
      return mono;
    } on Object catch (e) {
      debugPrint('TabCam: sound: not read: $e');
      return null;
    }
  }
}
