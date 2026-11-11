import 'dart:math';
import 'dart:ui' show Rect, Size;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

import '../library/page_edit.dart';
import 'edit_formats.dart';
import 'take_log.dart';

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

/// Where a layer sits on the frame: by a corner, a margin in from it
/// ([PlanLayer.marginU]), or along the whole bottom, as wide as the frame
/// (the tab's bands).
enum LayerAnchor { topLeft, bottomRight, bottomFull }

/// What a layer shows: drawn by the app, the same in the preview
/// (`EditLayers`) and in the file (as a PNG, `layerImages`), so the
/// preview is what Download makes. Equal looks are one image.
@immutable
sealed class LayerLook {
  const LayerLook();
}

/// A neckline of the tab, as a band along the bottom (`renderBand`'s
/// look).
final class BandLook extends LayerLook {
  const BandLook(this.line);

  final String line;

  @override
  bool operator ==(Object other) => other is BandLook && other.line == line;

  @override
  int get hashCode => line.hashCode;

  @override
  String toString() => 'BandLook($line)';
}

/// Something drawn over the video ([look]), from [from] to [to] in the
/// output (null: to its end), placed by [anchor]: [heightU] high (for a
/// corner's; a bottom band is as wide as the frame, as high as its image
/// makes it), [marginU] in from the corner and the watermark [liftU]
/// higher, all as fractions of the frame's short side, so they're the
/// same on a portrait and a landscape video, and no one but the renderer
/// needs the frame's size. It fades in over [fadeIn] from [from], to
/// [opacity]. Layers of one [id] (`tab`; later `title`, `mark`) never
/// overlap in time.
@immutable
class PlanLayer {
  const PlanLayer({
    required this.id,
    required this.look,
    required this.anchor,
    this.heightU = 0,
    this.marginU = 0,
    this.liftU = 0,
    this.from = Duration.zero,
    this.to,
    this.fadeIn = Duration.zero,
    this.opacity = 1,
  });

  final String id;
  final LayerLook look;
  final LayerAnchor anchor;
  final double heightU;
  final double marginU;
  final double liftU;
  final Duration from;
  final Duration? to;
  final Duration fadeIn;
  final double opacity;

  /// How opaque it is at [at] in the output, 0 to [opacity]: 0 outside
  /// it, rising from 0 over [fadeIn] from its start.
  double alphaAt(Duration at) {
    if (at < from || (to != null && at >= to!)) return 0;
    if (fadeIn <= Duration.zero) return opacity;
    final faded = (at - from).inMicroseconds / fadeIn.inMicroseconds;
    return opacity * min(1.0, faded);
  }

  /// Where it's drawn on a [frame] (upright, as it shows), an [image] that
  /// size drawn into it (scaled, its shape kept).
  Rect rectIn(Size frame, Size image) {
    final short = min(frame.width, frame.height);
    if (image.width <= 0 || image.height <= 0) return Rect.zero;
    if (anchor == LayerAnchor.bottomFull) {
      final height = frame.width * image.height / image.width;
      return Rect.fromLTWH(0, frame.height - height, frame.width, height);
    }
    final height = heightU * short;
    final width = height * image.width / image.height;
    final margin = marginU * short;
    return switch (anchor) {
      LayerAnchor.topLeft => Rect.fromLTWH(margin, margin, width, height),
      _ => Rect.fromLTWH(
        frame.width - margin - width,
        frame.height - margin - liftU * short - height,
        width,
        height,
      ),
    };
  }

  /// The method channel's description of it, its look being the plan's
  /// [image]th image.
  Map<String, Object?> toChannel(int image) => {
    'id': id,
    'image': image,
    'anchor': anchor.name,
    'heightU': heightU,
    'marginU': marginU,
    'liftU': liftU,
    'fromMs': from.inMilliseconds,
    'toMs': to?.inMilliseconds,
    'fadeInMs': fadeIn.inMilliseconds,
    'opacity': opacity,
  };

  @override
  bool operator ==(Object other) =>
      other is PlanLayer &&
      other.id == id &&
      other.look == look &&
      other.anchor == anchor &&
      other.heightU == heightU &&
      other.marginU == marginU &&
      other.liftU == liftU &&
      other.from == from &&
      other.to == to &&
      other.fadeIn == fadeIn &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(
    id,
    look,
    anchor,
    heightU,
    marginU,
    liftU,
    from,
    to,
    fadeIn,
    opacity,
  );

  @override
  String toString() => 'PlanLayer($id $look, $from–$to)';
}

/// A build that draws the tab over takes it's already in the picture of
/// (`--dart-define=TABCAM_TAB_OVER_BURNED=true`): to check by eye that
/// the bands drawn sit over the burned ones, at the same frames (the
/// time base and the lag). Never on in a release.
const tabOverBurned = bool.fromEnvironment('TABCAM_TAB_OVER_BURNED');

/// Whether a take with [log] (none: not a take, or one saved before
/// takes kept one) can have its tab drawn over it: it has a tab, and it
/// isn't in its picture already ([TakeLog.burned]).
bool tabOffered(TakeLog? log) =>
    log?.tab != null && (!log!.burned || tabOverBurned);

/// The tab's bands over the kept part, from [start] to [end] in the
/// file, of a take whose log has [tab] and [lagMs]: each neckline from
/// when it showed until the next ([bandsOf], a turn back to the same one
/// carrying it on), at its time in the file ([TakeTab.fileMarks]), in
/// the output, cut to it (what falls outside is left out).
List<PlanLayer> tabLayers(
  TakeTab tab,
  int lagMs,
  Duration start,
  Duration end,
) {
  final length = end - start;
  if (length <= Duration.zero) return const [];
  final layers = <PlanLayer>[];
  for (final band in bandsOf(tab.fileMarks(lagMs))) {
    var from = band.start - start;
    var to = (band.end ?? end) - start;
    if (from < Duration.zero) from = Duration.zero;
    if (to > length) to = length;
    if (to <= from) continue;
    layers.add(
      PlanLayer(
        id: 'tab',
        look: BandLook(tab.lines[band.line]),
        anchor: LayerAnchor.bottomFull,
        from: from,
        to: to,
      ),
    );
  }
  return layers;
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
/// ([song]), each at its volume. Over the picture, its [layers]: for now
/// the tab, as it showed while a take recorded (from the take's log); a
/// title and a watermark come in a later step, as do the fades in and out
/// (the picture from and to black, both lanes' volumes ramping with it):
/// each lane's volume is one level throughout.
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
    this.layers = const [],
    this.keepsFormat = false,
  });

  /// The plan of [edit] (null: the whole video as it is) for [kind], made
  /// in [formats]: [input] is the video, [duration] long, a file with
  /// [inputExtension]; [songFile] the song lane's file, [songLength]
  /// long. A [preview]'s plan leaves the files out, and keeps a lane that
  /// isn't heard (muted, or at 0%) at volume 0, so muting and unmuting
  /// only change a volume and move nothing; Download's leaves it out.
  /// The video's [takeLog] (one of Cam's takes) puts its tab over it
  /// ([tabLayers]), where it can be ([tabOffered]) and the edit doesn't
  /// turn it off ([PageEdit.tab]), even with no edit (the tab is on by
  /// default); the sound alone has no layers.
  factory RenderPlan.of(
    PageEdit? edit, {
    XFile? input,
    Duration duration = Duration.zero,
    String? inputExtension,
    XFile? songFile,
    Duration songLength = Duration.zero,
    RenderKind kind = RenderKind.video,
    EditFormats formats = EditFormats.standard,
    TakeLog? takeLog,
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
    final video = kind != RenderKind.sound;
    return RenderPlan(
      start: start,
      end: end,
      input: input,
      duration: duration,
      format: video ? formats.video : formats.sound,
      video: video,
      own: own,
      song: song,
      layers: [
        if (video && tabOffered(takeLog) && (edit?.tab ?? true))
          ...tabLayers(takeLog!.tab!, takeLog.lagMs, start, end),
      ],
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

  /// What's drawn over the picture, in the order drawn (none for the
  /// sound alone).
  final List<PlanLayer> layers;

  /// Whether [input] is already a file in [format] (or MPEG-4), so one
  /// the plan doesn't change can be saved as it is.
  final bool keepsFormat;

  /// The [layers]' looks, each once, in the order first used: the images
  /// the renderers are given ([toChannel]'s `images`).
  List<LayerLook> get looks => {for (final l in layers) l.look}.toList();

  /// How long the output is.
  Duration get length => end - start;

  /// Whether the output has any sound in it.
  bool get hasSound =>
      (own != null && own!.volume > 0) ||
      (song != null && song!.volume > 0 && song!.clips.isNotEmpty);

  /// Whether Download can save [input] as it is: the whole video, its own
  /// sound as it is and nothing else (nothing drawn over it), already in
  /// the format made. Only then is no file made.
  bool get passthrough =>
      video &&
      keepsFormat &&
      layers.isEmpty &&
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
  /// as [job]; the layers' [images] (PNGs, one per look, as [looks]
  /// orders them; `layerImages`).
  Map<String, Object?> toChannel({
    required String output,
    int? job,
    List<Uint8List> images = const [],
  }) {
    if (layers.isNotEmpty && images.length != looks.length) {
      throw ArgumentError('A plan with layers needs their images');
    }
    final index = {for (final (i, look) in looks.indexed) look: i};
    return {
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
      if (layers.isNotEmpty) ...{
        'images': images,
        'layers': [for (final l in layers) l.toChannel(index[l.look]!)],
      },
      'job': ?job,
    };
  }

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
      listEquals(other.layers, layers) &&
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
    Object.hashAll(layers),
    keepsFormat,
  );

  @override
  String toString() =>
      'RenderPlan($start–$end of ${input?.name}, ${format.label}, '
      'video $video, own $own, song $song, ${layers.length} layers)';
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
