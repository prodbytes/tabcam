import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'web_video_editor_stub.dart'
    if (dart.library.js_interop) 'web_video_editor.dart';

/// What happens to a video's sound when it's edited.
enum EditSound {
  /// Its own sound stays.
  original,

  /// Its sound is taken out.
  none,

  /// A sound track takes its sound's place ([VideoEdit.track]).
  track,
}

/// A basic edit of a video: the part kept, from [start] to [end], and its
/// sound: kept, removed, or replaced by [track], a recording or sound
/// file that starts [offset] after the kept part's start (before it, when
/// negative), cut to fit the kept part.
@immutable
class VideoEdit {
  const VideoEdit({
    required this.start,
    required this.end,
    this.sound = EditSound.original,
    this.track,
    this.offset = Duration.zero,
  });

  final Duration start;
  final Duration end;
  final EditSound sound;

  /// The new sound track's file (a path on Android and iOS, bytes on the
  /// web), when [sound] is [EditSound.track].
  final XFile? track;

  /// Where [track] starts, from the kept part's start: positive, it starts
  /// that much after the video; negative, that much of its start is cut.
  final Duration offset;

  /// How long the kept part is.
  Duration get length => end - start;

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
      other.offset == offset;

  @override
  int get hashCode => Object.hash(start, end, sound, track, offset);

  @override
  String toString() => 'VideoEdit($start–$end, $sound, $track, $offset)';
}

/// The part of a track [trackLength] long that goes into a clip [clip]
/// long, with the track starting [offset] after the clip's start: the
/// silence before it ([gap]), and the part of the track itself, from
/// [from] to [to]. Null when none of the track falls within the clip.
({Duration gap, Duration from, Duration to})? trackSpan(
  Duration clip,
  Duration trackLength,
  Duration offset,
) {
  if (clip <= Duration.zero || trackLength <= Duration.zero) return null;
  final gap = offset > Duration.zero ? offset : Duration.zero;
  final from = offset < Duration.zero ? -offset : Duration.zero;
  if (gap >= clip || from >= trackLength) return null;
  final room = clip - gap;
  final to = from + room < trackLength ? from + room : trackLength;
  if (to <= from) return null;
  return (gap: gap, from: from, to: to);
}

/// Applies a [VideoEdit] to a video file, on the device.
abstract class VideoEditing {
  /// [video] with [edit] applied: a new file (the original is left as it
  /// is). [onProgress] gets how much is done, 0 to 1, where that's known.
  Future<XFile> apply(
    XFile video,
    VideoEdit edit, {
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
/// track, its path and offset in ms. It replies with the output path.
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
    void Function(double done)? onProgress,
  }) async {
    final track = edit.sound == EditSound.track ? edit.track : null;
    if (edit.sound == EditSound.track && track == null) {
      throw ArgumentError('A new sound track needs a file');
    }
    final dir = await getTemporaryDirectory();
    final output =
        '${dir.path}/edit-${DateTime.now().millisecondsSinceEpoch}.mp4';
    final path = await channel.invokeMethod<String>('edit', {
      'input': video.path,
      'output': output,
      'startMs': edit.start.inMilliseconds,
      'endMs': edit.end.inMilliseconds,
      'sound': edit.sound.name,
      'track': track?.path,
      'trackMs': edit.offset.inMilliseconds,
    });
    if (path == null) throw StateError('The video was not written');
    return XFile(path, mimeType: 'video/mp4');
  }
}
