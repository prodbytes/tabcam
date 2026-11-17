import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'web_sound_reader_stub.dart'
    if (dart.library.js_interop) 'web_sound_reader.dart';

/// Reads a sound or video file's sound as samples, to compare one with
/// another ([SongSync]): on the device, with its own decoders.
abstract class SoundReader {
  /// [file]'s sound from [from], [length] long (less where it ends: what
  /// there is), mixed to one channel, [rate] samples a second, each from
  /// -1 to 1; its first sample is the sound at [from] in the file, as a
  /// player plays it. Null where it can't be read (no sound in it, or a
  /// format the device doesn't decode).
  Future<Float32List?> samples(
    XFile file, {
    required Duration from,
    required Duration length,
    required int rate,
  });

  /// Lets go of what it kept to read faster (the web's decoded files).
  void close();

  /// A reader for this platform: the browser's ([webSoundReader]), or
  /// the platform's own decoders on Android and iOS
  /// ([ChannelSoundReader]); null elsewhere.
  static SoundReader? open() => (opener ?? _forPlatform)();

  /// Tests put their own in.
  @visibleForTesting
  static SoundReader? Function()? opener;

  static SoundReader? _forPlatform() {
    if (kIsWeb) return webSoundReader();
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return const ChannelSoundReader();
    }
    return null;
  }
}

/// Reads samples with the platform's own decoders (MediaCodec on
/// Android, AVAssetReader on iOS) over the method channel
/// `tabcam/video_edit`, method `samples`: `path`, `fromMs`, `lengthMs`
/// and `rate`; it replies with the samples (32-bit floats, one channel),
/// or the error `failed`.
class ChannelSoundReader implements SoundReader {
  const ChannelSoundReader();

  static const channel = MethodChannel('tabcam/video_edit');

  @override
  Future<Float32List?> samples(
    XFile file, {
    required Duration from,
    required Duration length,
    required int rate,
  }) async {
    try {
      final samples = await channel.invokeMethod<Object>('samples', {
        'path': file.path,
        'fromMs': from.inMilliseconds,
        'lengthMs': length.inMilliseconds,
        'rate': rate,
      });
      return samples is Float32List && samples.isNotEmpty ? samples : null;
    } on Object catch (e) {
      debugPrint('TabCam: sound: not read: $e');
      return null;
    }
  }

  @override
  void close() {}
}
