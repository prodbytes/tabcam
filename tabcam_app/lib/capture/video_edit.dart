import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../library/page_edit.dart';
import 'web_video_editor_stub.dart'
    if (dart.library.js_interop) 'web_video_editor.dart';

export '../library/page_edit.dart' show EditSound, trackSpan;

/// A basic edit of a video: the part kept, from [start] to [end], and its
/// sound: kept, removed, or replaced by [track], a recording or sound
/// file, of which the part from [trackStart] to [trackEnd] is used,
/// starting [offset] after the kept part's start (before it, when
/// negative), cut to fit the kept part ([trackPart]), at [trackVolume].
@immutable
class VideoEdit {
  const VideoEdit({
    required this.start,
    required this.end,
    this.sound = EditSound.original,
    this.track,
    this.trackLength = Duration.zero,
    this.trackStart = Duration.zero,
    this.trackEnd,
    this.offset = Duration.zero,
    this.trackVolume = 1,
  });

  final Duration start;
  final Duration end;
  final EditSound sound;

  /// The new sound track's file (a path on Android and iOS, bytes on the
  /// web), when [sound] is [EditSound.track].
  final XFile? track;

  /// How long [track] is (zero: not known, and nothing of it can be fitted).
  final Duration trackLength;

  /// The part of [track] used: from [trackStart] to [trackEnd] (null: to
  /// its end).
  final Duration trackStart;
  final Duration? trackEnd;

  /// Where the used part of [track] starts, from the kept part's start:
  /// positive, it starts that much after the video; negative, that much
  /// more of its start is cut.
  final Duration offset;

  /// How loud [track] goes in: a gain from 0 (silent) to 1 (as it is).
  final double trackVolume;

  /// How long the kept part is.
  Duration get length => end - start;

  /// The part of [track] that goes into the kept part, as [trackSpan]
  /// fits it: null when none does (or the track's length isn't known).
  ({Duration gap, Duration from, Duration to})? get trackPart => trackSpan(
    length,
    trackLength,
    offset,
    trackStart: trackStart,
    trackEnd: trackEnd,
  );

  /// The shortest part that can be kept.
  static const minLength = Duration(milliseconds: 500);

  /// Whether the edit changes anything of a video [duration] long.
  bool changes(Duration duration) =>
      start > Duration.zero || end < duration || sound != EditSound.original;

  @override
  bool operator ==(Object other) =>
      other is VideoEdit &&
      other.start == start &&
      other.end == end &&
      other.sound == sound &&
      other.track == track &&
      other.trackLength == trackLength &&
      other.trackStart == trackStart &&
      other.trackEnd == trackEnd &&
      other.offset == offset &&
      other.trackVolume == trackVolume;

  @override
  int get hashCode => Object.hash(
    start,
    end,
    sound,
    track,
    trackLength,
    trackStart,
    trackEnd,
    offset,
    trackVolume,
  );

  @override
  String toString() =>
      'VideoEdit($start–$end, $sound, $track $trackStart–$trackEnd, $offset, '
      '$trackVolume)';
}

/// Applies a [VideoEdit] to a video file, on the device.
abstract class VideoEditing {
  /// [video] with [edit] applied: a new file (the original is left as it
  /// is); with [soundOnly], its sound alone, as edited (a sound file).
  /// [onProgress] gets how much is done, 0 to 1, where that's known.
  Future<XFile> apply(
    XFile video,
    VideoEdit edit, {
    bool soundOnly = false,
    void Function(double done)? onProgress,
  });

  /// How long [file] (a video or sound file) is, where the player can't
  /// say (the browser, for a file it recorded itself: a take); null where
  /// the player knows.
  Future<Duration?> length(XFile file);
}

/// The video editor for this platform: the browser's ([webVideoEditor]),
/// or the platform's own video tools on Android and iOS
/// ([ChannelVideoEditor]); none elsewhere.
abstract final class VideoEditor {
  /// The editor here; null where videos can't be edited.
  static VideoEditing? get instance => _instance ??= _forPlatform();
  static VideoEditing? _instance;

  /// Tests put their own in.
  @visibleForTesting
  static set instance(VideoEditing? editor) => _instance = editor;

  static bool get supported => instance != null;

  static VideoEditing? _forPlatform() {
    if (kIsWeb) return webVideoEditor();
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return const ChannelVideoEditor();
    }
    return null;
  }
}

/// Edits a video with the platform's own tools (Media3 Transformer on
/// Android, AVFoundation on iOS) over the method channel
/// `tabcam/video_edit`, method `edit`: the input and output paths, the
/// part kept in ms, the sound (`original`, `none`, `track`) and, for a
/// track, its path and the part of it that goes in (`gapMs` of silence,
/// then the track from `fromMs` to `toMs`, at `trackVolume`, a gain from
/// 0 to 1); `video` false for the sound alone (an `.m4a`). It replies with
/// the output path.
class ChannelVideoEditor implements VideoEditing {
  const ChannelVideoEditor();

  static const channel = MethodChannel('tabcam/video_edit');

  /// The platforms' players know every file's length.
  @override
  Future<Duration?> length(XFile file) async => null;

  @override
  Future<XFile> apply(
    XFile video,
    VideoEdit edit, {
    bool soundOnly = false,
    void Function(double done)? onProgress,
  }) async {
    if (soundOnly && edit.sound == EditSound.none) {
      throw ArgumentError('A video without sound has no sound to save');
    }
    final track = edit.sound == EditSound.track ? edit.track : null;
    if (edit.sound == EditSound.track && track == null) {
      throw ArgumentError('A new sound track needs a file');
    }
    final part = track == null ? null : edit.trackPart;
    final dir = await getTemporaryDirectory();
    final output =
        '${dir.path}/edit-${DateTime.now().millisecondsSinceEpoch}'
        '.${soundOnly ? 'm4a' : 'mp4'}';
    final path = await channel.invokeMethod<String>('edit', {
      'input': video.path,
      'output': output,
      'startMs': edit.start.inMilliseconds,
      'endMs': edit.end.inMilliseconds,
      'sound': edit.sound.name,
      'video': !soundOnly,
      'track': track?.path,
      if (track != null) 'trackVolume': PageEdit.volume(edit.trackVolume),
      if (part != null) ...{
        'gapMs': part.gap.inMilliseconds,
        'fromMs': part.from.inMilliseconds,
        'toMs': part.to.inMilliseconds,
      },
    });
    if (path == null) throw StateError('The video was not written');
    return XFile(path, mimeType: soundOnly ? 'audio/mp4' : 'video/mp4');
  }
}

/// [channels] (one or two, of samples from -1 to 1, all as long) as a
/// 16-bit PCM WAV file at [sampleRate].
Uint8List wavBytes(List<Float32List> channels, int sampleRate) {
  final count = channels.length;
  final frames = count == 0 ? 0 : channels.first.length;
  final data = frames * count * 2;
  final bytes = ByteData(44 + data);
  void text(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, 36 + data, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, count, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * count * 2, Endian.little);
  bytes.setUint16(32, count * 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, data, Endian.little);
  var at = 44;
  for (var f = 0; f < frames; f++) {
    for (final channel in channels) {
      final v = channel[f].clamp(-1.0, 1.0);
      bytes.setInt16(
        at,
        (v < 0 ? v * 0x8000 : v * 0x7fff).round(),
        Endian.little,
      );
      at += 2;
    }
  }
  return bytes.buffer.asUint8List();
}
