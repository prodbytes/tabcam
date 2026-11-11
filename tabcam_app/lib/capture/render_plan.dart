import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

import '../library/page_edit.dart';
import 'edit_formats.dart';

/// What Download makes of an edit.
enum RenderKind {
  /// The video as edited.
  video,

  /// The video as edited, without any sound (everything else kept).
  silent,

  /// The sound alone, as edited (the picture and what's drawn over it
  /// left out).
  sound,
}

/// A piece of the song lane: from [at] in the output (0 is the kept
/// part's start), the song from [from] to [to], played at [speed] (1 for
/// now: songs played at another speed come later).
@immutable
class SongClip {
  const SongClip({
    required this.at,
    required this.from,
    required this.to,
    this.speed = 1,
  });

  final Duration at;
  final Duration from;
  final Duration to;
  final double speed;

  /// How long it plays in the output.
  Duration get length => (to - from) * (1 / speed);

  /// Where it ends in the output.
  Duration get end => at + length;

  Map<String, Object?> toJson() => {
    'atMs': at.inMilliseconds,
    'fromMs': from.inMilliseconds,
    'toMs': to.inMilliseconds,
    'speed': speed,
  };

  @override
  bool operator ==(Object other) =>
      other is SongClip &&
      other.at == at &&
      other.from == from &&
      other.to == to &&
      other.speed == speed;

  @override
  int get hashCode => Object.hash(at, from, to, speed);

  @override
  String toString() => 'SongClip(at $at: $from–$to×$speed)';
}

/// The video's own sound, at [volume] (0 to 1; 0 only in a preview's
/// plan, for a lane that isn't heard).
@immutable
class OwnLane {
  const OwnLane({this.volume = 1});

  final double volume;

  @override
  bool operator ==(Object other) => other is OwnLane && other.volume == volume;

  @override
  int get hashCode => volume.hashCode;

  @override
  String toString() => 'OwnLane($volume)';
}

/// The song lane: the capture's page [page], its [file] (left out of a
/// preview's plan), at [volume] (0 to 1), heard in [clips], in output
/// order, silent between them.
@immutable
class SongLane {
  const SongLane({
    this.file,
    this.page,
    this.volume = 1,
    this.clips = const [],
  });

  final XFile? file;
  final String? page;
  final double volume;
  final List<SongClip> clips;

  @override
  bool operator ==(Object other) =>
      other is SongLane &&
      other.file == file &&
      other.page == page &&
      other.volume == volume &&
      listEquals(other.clips, clips);

  @override
  int get hashCode => Object.hash(file, page, volume, Object.hashAll(clips));

  @override
  String toString() => 'SongLane($page, $volume, $clips)';
}

/// What moves sound in a plan: what the preview's players must seek again
/// for when it changes (a volume alone doesn't move anything).
@immutable
class PlanTimeline {
  const PlanTimeline(this.start, this.end, this.song, this.clips);

  final Duration start;
  final Duration end;
  final String? song;
  final List<SongClip> clips;

  @override
  bool operator ==(Object other) =>
      other is PlanTimeline &&
      other.start == start &&
      other.end == end &&
      other.song == song &&
      listEquals(other.clips, clips);

  @override
  int get hashCode => Object.hash(start, end, song, Object.hashAll(clips));
}

/// How an edit is rendered: the one description that Download hands to
/// the platform's renderer (`VideoEditing.render`) and that the preview
/// plays (`EditedPlayback`). Derived from the edit, never stored. Times
/// are in the output, where 0 is the kept part's start, except [start]
/// and [end], the kept part of [input].
///
/// The two lanes are mixed: the video's own sound ([own]) and the song
/// ([song]), each at its volume. Layers drawn over the video (the tab, a
/// title, a watermark) and the fades in and out (the picture from and to
/// black, both lanes' volumes ramping with it) come in later steps; for
/// now a plan has none, and each lane's volume is one level throughout.
@immutable
class RenderPlan {
  const RenderPlan({
    required this.start,
    required this.end,
    this.input,
    this.duration = Duration.zero,
    this.format = EditFormat.mp4,
    this.video = true,
    this.own = const OwnLane(),
    this.song,
    this.keepsFormat = false,
  });

  /// The plan of [edit] (null: the whole video as it is) for [kind], made
  /// in [formats]: [input] is the video, [duration] long, a file with
  /// [inputExtension]; [songFile] the song lane's file, [songLength]
  /// long. A [preview]'s plan leaves the files out, and keeps a lane that
  /// isn't heard (muted, or at 0%) at volume 0, so muting and unmuting
  /// only change a volume and move nothing; Download's leaves it out.
  factory RenderPlan.of(
    PageEdit? edit, {
    XFile? input,
    Duration duration = Duration.zero,
    String? inputExtension,
    XFile? songFile,
    Duration songLength = Duration.zero,
    RenderKind kind = RenderKind.video,
    EditFormats formats = EditFormats.standard,
    bool preview = false,
  }) {
    final start = edit?.start ?? Duration.zero;
    final end = edit?.end ?? duration;
    final length = end - start;
    final audible = kind != RenderKind.silent;
    OwnLane? own;
    if (audible && (edit == null || edit.ownAudible)) {
      own = OwnLane(volume: edit?.ownVolume ?? 1);
    } else if (audible && preview) {
      own = const OwnLane(volume: 0);
    }
    SongLane? song;
    if (audible &&
        edit != null &&
        edit.hasSong &&
        (preview || edit.songAudible)) {
      // The manual song lane (an auto one too, for now, as the one clip
      // its track keys approximate it by): one clip, as the bar places it.
      final span = trackSpan(
        length,
        songLength,
        edit.offset,
        trackStart: edit.trackStart,
        trackEnd: edit.trackEnd,
      );
      song = SongLane(
        file: songFile,
        page: edit.trackId,
        volume: edit.songAudible ? edit.trackVolume : 0,
        clips: clampClips([
          if (span != null)
            SongClip(at: span.gap, from: span.from, to: span.to),
        ], length),
      );
    }
    return RenderPlan(
      start: start,
      end: end,
      input: input,
      duration: duration,
      format: kind == RenderKind.sound ? formats.sound : formats.video,
      video: kind != RenderKind.sound,
      own: own,
      song: song,
      keepsFormat:
          kind != RenderKind.sound && formats.keepsAsIs(inputExtension),
    );
  }

  /// The video (a path on Android and iOS, bytes on the web); left out of
  /// a preview's plan.
  final XFile? input;

  /// How long [input] is (zero: not known).
  final Duration duration;

  /// The part of [input] kept.
  final Duration start;
  final Duration end;

  /// The file made.
  final EditFormat format;

  /// Whether the picture goes in: false for the sound alone.
  final bool video;

  /// The video's own sound; null: left out.
  final OwnLane? own;

  /// The song lane; null: none.
  final SongLane? song;

  /// Whether [input] is already a file in [format] (or MPEG-4), so one
  /// the plan doesn't change can be saved as it is.
  final bool keepsFormat;

  /// How long the output is.
  Duration get length => end - start;

  /// Whether the output has any sound in it.
  bool get hasSound =>
      (own != null && own!.volume > 0) ||
      (song != null && song!.volume > 0 && song!.clips.isNotEmpty);

  /// Whether Download can save [input] as it is: the whole video, its own
  /// sound as it is and nothing else, already in the format made. Only
  /// then is no file made.
  bool get passthrough =>
      video &&
      keepsFormat &&
      start <= Duration.zero &&
      end >= duration &&
      own?.volume == 1 &&
      song == null;

  /// What moves sound in it ([PlanTimeline]).
  PlanTimeline get timeline =>
      PlanTimeline(start, end, song?.page, song?.clips ?? const []);

  /// Where the song is at [at] in the output; null in a gap.
  Duration? songAt(Duration at) =>
      song == null ? null : songAtIn(song!.clips, at);

  /// The method channel's arguments for `render`
  /// (`tabcam/video_edit`): writing to [output], its progress reported
  /// as [job].
  Map<String, Object?> toChannel({required String output, int? job}) => {
    'input': input?.path,
    'output': output,
    'video': video,
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
    if (own case final own?) 'own': {'volume': own.volume},
    if (song case final song?)
      'song': {
        'path': song.file?.path,
        'volume': song.volume,
        'clips': [for (final c in song.clips) c.toJson()],
      },
    'job': ?job,
  };

  @override
  bool operator ==(Object other) =>
      other is RenderPlan &&
      other.input == input &&
      other.duration == duration &&
      other.start == start &&
      other.end == end &&
      other.format == format &&
      other.video == video &&
      other.own == own &&
      other.song == song &&
      other.keepsFormat == keepsFormat;

  @override
  int get hashCode => Object.hash(
    input,
    duration,
    start,
    end,
    format,
    video,
    own,
    song,
    keepsFormat,
  );

  @override
  String toString() =>
      'RenderPlan($start–$end of ${input?.name}, ${format.label}, '
      'video $video, own $own, song $song)';
}

/// Where the song is at [at] in the output, from [clips] (in output
/// order); null in a gap between them, or past them.
Duration? songAtIn(List<SongClip> clips, Duration at) {
  var low = 0;
  var high = clips.length - 1;
  SongClip? found;
  // The last clip that starts at or before [at].
  while (low <= high) {
    final mid = (low + high) >> 1;
    if (clips[mid].at <= at) {
      found = clips[mid];
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  if (found == null || at >= found.end) return null;
  return found.from + (at - found.at) * found.speed;
}

/// [clips] cut to the output, [length] long: what falls before its start
/// or after its end is cut off (from the song too), what's left of none is
/// dropped; in output order. No renderer ever plays past the video's end.
List<SongClip> clampClips(List<SongClip> clips, Duration length) {
  final kept = <SongClip>[];
  for (final clip in clips) {
    if (clip.speed <= 0 || clip.to <= clip.from) continue;
    var at = clip.at;
    var from = clip.from;
    var to = clip.to;
    if (at < Duration.zero) {
      from += -at * clip.speed;
      at = Duration.zero;
    }
    final room = length - at;
    if (room <= Duration.zero) continue;
    final most = from + room * clip.speed;
    if (to > most) to = most;
    if (to <= from) continue;
    kept.add(SongClip(at: at, from: from, to: to, speed: clip.speed));
  }
  kept.sort((a, b) => a.at.compareTo(b.at));
  return kept;
}
