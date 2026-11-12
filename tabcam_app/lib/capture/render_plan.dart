import 'dart:math';
import 'dart:ui' show Color, Rect, Size;

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

/// A neckline of the tab, [line], as a band along the bottom
/// (`bandPicture`'s look), looking as [style] says ([TabLayout]): drawn
/// [width] pixels wide (the frame's width, where it's known, so a
/// renderer never scales it up), and, grown past its default size, never
/// higher than [maxAspect] of its width (null: no such bound).
final class BandLook extends LayerLook {
  const BandLook(
    this.line, {
    this.style = EditTabStyle.standard,
    this.maxAspect,
    this.width = bandWidth,
  });

  final String line;
  final EditTabStyle style;
  final double? maxAspect;
  final int width;

  /// How many lines of text it has.
  int get lines => '\n'.allMatches(line).length + 1;

  @override
  bool operator ==(Object other) =>
      other is BandLook &&
      other.line == line &&
      other.style == style &&
      other.maxAspect == maxAspect &&
      other.width == width;

  @override
  int get hashCode => Object.hash(line, style, maxAspect, width);

  @override
  String toString() =>
      'BandLook($line${style.isStandard ? '' : ', $style'}, $width px)';
}

/// How wide a band is drawn by default, in pixels; the video scales it to
/// its own width.
const int bandWidth = TabLayout.width;

/// The tab's bands' sizes, as fractions of their width (the frame's):
/// their text at most [text] high (times its style's size; smaller when
/// a line wouldn't fit), each line [lineHeight] times that, [pad] above
/// and below (at a size under 1, that much less). A band grown past its
/// default size is never higher than [grownTo] of the frame's height (a
/// frame of unknown shape taken as a landscape 16:9 one), nor than it is
/// at its default size, if that's more. Drawn [width] pixels wide, or as
/// wide as the frame, up to [maxWidth]. Its text is outlined in its
/// background's colour as the background fades below [outlineBelow].
abstract final class TabLayout {
  static const width = 1280;
  static const maxWidth = 4096;
  static const text = 1 / 48;
  static const lineHeight = 1.2;
  static const pad = 1 / 64;
  static const grownTo = 0.4;
  static const landscape = 16 / 9;
  static const outlineBelow = 0.5;

  /// TabCam's gold (the app's seed colour).
  static const gold = Color(0xFFE0A030);

  /// [colors]' background and text.
  static (Color, Color) colorsOf(TabColors colors) => switch (colors) {
    TabColors.dark => (const Color(0xFF000000), const Color(0xFFFFFFFF)),
    TabColors.light => (const Color(0xFFFFFFFF), const Color(0xFF111111)),
    TabColors.gold => (const Color(0xFF000000), gold),
    TabColors.brand => (gold, const Color(0xFF111111)),
  };

  /// The padding above and below the text of a band at [size].
  static double padAt(double size) => pad * min(1, size);

  /// How high [band]'s text is drawn at most (a line too long for the
  /// band gets smaller), as a fraction of its width.
  static double textOf(BandLook band) {
    final size = band.style.size;
    final wanted = text * size;
    final most = band.maxAspect;
    if (most == null || size <= 1) return wanted;
    final fits = (most - 2 * padAt(size)) / (band.lines * lineHeight);
    return min(wanted, max(fits, text));
  }

  /// The bound on a band of [style] over a [frame] that size (null: not
  /// known): none at its default size or smaller.
  static double? maxAspectOf(EditTabStyle style, Size? frame) {
    if (style.size <= 1) return null;
    final known = frame != null && frame.width > 0 && frame.height > 0;
    return grownTo * (known ? frame.height / frame.width : 1 / landscape);
  }

  /// How wide a band is drawn over a [frame] that size (null: not known).
  static int widthOf(Size? frame) {
    if (frame == null || frame.width <= 0 || frame.height <= 0) return width;
    return frame.width.round().clamp(width, maxWidth);
  }
}

/// The video's title, at its top left: one or two [lines] (the first
/// larger), white on a see-through dark box ([TitleLayout]).
final class TitleLook extends LayerLook {
  const TitleLook(this.lines);

  final List<String> lines;

  @override
  bool operator ==(Object other) =>
      other is TitleLook && listEquals(other.lines, lines);

  @override
  int get hashCode => Object.hashAll(lines);

  @override
  String toString() => 'TitleLook($lines)';
}

/// The watermark, at the bottom right: [text], one small line, white and
/// see-through ([WatermarkLayout]).
final class WatermarkLook extends LayerLook {
  const WatermarkLook(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      other is WatermarkLook && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'WatermarkLook($text)';
}

/// The title's sizes, as fractions of the frame's short side: its first
/// line's text [line1] high, its second's [line2] (80% of it), each line
/// [lineHeight] times its text; the box [padV] above and below them and
/// [padH] either side, [margin] in from the top left. It fades in over
/// [fadeIn] from the kept part's start, then stays. Lines are at most
/// [maxChars] long, and there are at most [maxLines].
abstract final class TitleLayout {
  static const line1 = 0.05;
  static const line2 = 0.04;
  static const lineHeight = 1.25;
  static const padV = 0.0125;
  static const padH = 0.02;
  static const margin = 0.035;
  static const fadeIn = Duration(seconds: 3);
  static const maxLines = EditTitle.maxLines;
  static const maxChars = EditTitle.maxChars;

  /// How high the box is, for [lines] lines (one or two).
  static double heightU(int lines) =>
      2 * padV + line1 * lineHeight + (lines > 1 ? line2 * lineHeight : 0);
}

/// The watermark's sizes, as fractions of the frame's short side: its
/// text [text] high, in a strip [heightU] high, [margin] in from the
/// bottom right (and above the tab's bands, where they're drawn).
abstract final class WatermarkLayout {
  static const text = 0.022;
  static const heightU = 0.03;
  static const margin = 0.03;
}

/// Something drawn over the video ([look]), from [from] to [to] in the
/// output (null: to its end), placed by [anchor]: [heightU] high (for a
/// corner's; a bottom band is as wide as the frame, as high as its image
/// makes it), [marginU] in from the corner and the watermark [liftU]
/// higher, all as fractions of the frame's short side, so they're the
/// same on a portrait and a landscape video, and no one but the renderer
/// needs the frame's size; and [liftW] higher still, as a fraction of the
/// frame's width (what a band's height goes by: it's as wide as the
/// frame), so the watermark sits above the tab's tallest band. It fades
/// in over [fadeIn] from [from], to [opacity]. Layers of one [id] (`tab`,
/// `title`, `mark`) never overlap in time.
@immutable
class PlanLayer {
  const PlanLayer({
    required this.id,
    required this.look,
    required this.anchor,
    this.heightU = 0,
    this.marginU = 0,
    this.liftU = 0,
    this.liftW = 0,
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
  final double liftW;
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
        frame.height - margin - liftU * short - liftW * frame.width - height,
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
    'liftW': liftW,
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
      other.liftW == liftW &&
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
    liftW,
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
/// the output, cut to it (what falls outside is left out); looking as
/// [style] says, over a [frame] that size (null: not known; [BandLook]).
List<PlanLayer> tabLayers(
  TakeTab tab,
  int lagMs,
  Duration start,
  Duration end, {
  EditTabStyle style = EditTabStyle.standard,
  Size? frame,
}) {
  final length = end - start;
  if (length <= Duration.zero) return const [];
  final layers = <PlanLayer>[];
  final maxAspect = TabLayout.maxAspectOf(style, frame);
  final width = TabLayout.widthOf(frame);
  for (final band in bandsOf(tab.fileMarks(lagMs))) {
    var from = band.start - start;
    var to = (band.end ?? end) - start;
    if (from < Duration.zero) from = Duration.zero;
    if (to > length) to = length;
    if (to <= from) continue;
    layers.add(
      PlanLayer(
        id: 'tab',
        look: BandLook(
          tab.lines[band.line],
          style: style,
          maxAspect: maxAspect,
          width: width,
        ),
        anchor: LayerAnchor.bottomFull,
        from: from,
        to: to,
      ),
    );
  }
  return layers;
}

/// How high a [band] is drawn, as a fraction of its width (as wide as
/// the frame): `bandAspect` in edit_layers.dart measures it.
typedef BandAspect = double Function(BandLook band);

/// The most a [band] can be high, as a fraction of its width, without
/// measuring it: its text at the largest it draws it ([TabLayout.textOf]:
/// 1/48 of its width at its default size, each line 1.2 times that),
/// padded above and below ([TabLayout.padAt]: 1/64 of its width at its
/// default size; `bandPicture`'s look).
double bandAspectBound(BandLook band) =>
    band.lines * TabLayout.lineHeight * TabLayout.textOf(band) +
    2 * TabLayout.padAt(band.style.size);

/// The title over the video, showing [lines] (as [titleText] cleans
/// them): at the top left, fading in over the kept part's first 3 s, then
/// staying to its end ([TitleLayout]). Null when there's nothing to show.
PlanLayer? titleLayer(List<String> lines) {
  final text = titleText(lines);
  if (text.isEmpty) return null;
  return PlanLayer(
    id: 'title',
    look: TitleLook(text),
    anchor: LayerAnchor.topLeft,
    heightU: TitleLayout.heightU(text.length),
    marginU: TitleLayout.margin,
    fadeIn: TitleLayout.fadeIn,
  );
}

/// [lines] as a title shows them: each trimmed and at most
/// [TitleLayout.maxChars] long ([clipChars]), the empty ones left out, at most
/// [TitleLayout.maxLines].
List<String> titleText(List<String> lines) => [
  for (final line in lines)
    if (line.trim() case final t when t.isNotEmpty)
      clipChars(t, TitleLayout.maxChars),
].take(TitleLayout.maxLines).toList();

/// The watermark, [text], at the bottom right, the whole video through,
/// lifted [liftW] (of the frame's width) above the bottom margin: above
/// the tab's tallest band, where they're drawn ([WatermarkLayout]).
PlanLayer watermarkLayer(String text, {double liftW = 0}) => PlanLayer(
  id: 'mark',
  look: WatermarkLook(text),
  anchor: LayerAnchor.bottomRight,
  heightU: WatermarkLayout.heightU,
  marginU: WatermarkLayout.margin,
  liftW: liftW,
);

/// The default title of a capture named [title], by [artist]: the name
/// (a copy's " (copy)" left off) and the artist, two lines; with no
/// artist, a name like "Blue Riff by Made-up Band" (or with " – " or
/// " - ") split into the two. A name the app gave it ("Tab 2026-11-11
/// 10:00", `defaultTitle`) is no title.
List<String> captureTitleLines(String title, String artist) {
  var name = title.trim();
  const copy = ' (copy)';
  while (name.endsWith(copy)) {
    name = name.substring(0, name.length - copy.length).trimRight();
  }
  if (_appTitle.hasMatch(name)) name = '';
  final by = artist.trim();
  if (by.isEmpty && name.isNotEmpty) {
    for (final separator in const [' by ', ' – ', ' - ']) {
      final at = name.indexOf(separator);
      if (at <= 0) continue;
      final song = name.substring(0, at).trim();
      final band = name.substring(at + separator.length).trim();
      if (song.isNotEmpty && band.isNotEmpty) return titleText([song, band]);
    }
  }
  if (name.isEmpty) return const [];
  return titleText([name, by]);
}

/// A name the app gives a new capture (`defaultTitle`).
final _appTitle = RegExp(r'^Tab \d{4}-\d{2}-\d{2} \d{2}:\d{2}$');

/// The fades of an output [length] long: in from black (and silence)
/// over [fadeIn] from its start, out to black over [fadeOut] to its end,
/// both straight lines; the picture (with what's drawn over it) is as
/// bright, and both lanes as loud, as [levelAt] says.
@immutable
class Fades {
  const Fades({
    this.fadeIn = Duration.zero,
    this.fadeOut = Duration.zero,
    this.length = Duration.zero,
  });

  static const none = Fades();

  final Duration fadeIn;
  final Duration fadeOut;
  final Duration length;

  /// Whether there's any.
  bool get any => fadeIn > Duration.zero || fadeOut > Duration.zero;

  /// How much of the picture and the sound comes through at [at] in the
  /// output, 0 (black and silent) to 1: rising from 0 at its start over
  /// [fadeIn], falling to 0 at its end over [fadeOut]. Before its start
  /// it's as at its start, after its end as at its end: black and silent
  /// only on a side that fades, so a frame drawn a little past a hard cut
  /// (a fade of 0) isn't.
  double levelAt(Duration time) {
    if (!any) return 1;
    final at = time < Duration.zero
        ? Duration.zero
        : time > length
        ? length
        : time;
    var level = 1.0;
    if (fadeIn > Duration.zero && at < fadeIn) {
      level = at.inMicroseconds / fadeIn.inMicroseconds;
    }
    final left = length - at;
    if (fadeOut > Duration.zero && left < fadeOut) {
      level = min(level, left.inMicroseconds / fadeOut.inMicroseconds);
    }
    return level.clamp(0.0, 1.0);
  }

  /// How dark the black drawn over the picture is at [at]: 1 − [levelAt].
  double blackAt(Duration at) => 1 - levelAt(at);

  @override
  bool operator ==(Object other) =>
      other is Fades &&
      other.fadeIn == fadeIn &&
      other.fadeOut == fadeOut &&
      other.length == length;

  @override
  int get hashCode => Object.hash(fadeIn, fadeOut, length);

  @override
  String toString() => 'Fades($fadeIn in, $fadeOut out of $length)';
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
/// ([song]), each at its volume. Over the picture, its [layers]: the tab,
/// as it showed while a take recorded (from the take's log), the
/// watermark and the title. It fades in from black over [fadeIn] and
/// out to black over [fadeOut] ([fades]): the picture, with what's drawn
/// over it, and both lanes' volumes ramping with it.
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
    this.fadeIn = Duration.zero,
    this.fadeOut = Duration.zero,
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
  /// default), looking as the edit says ([PageEdit.tabStyle]) over the
  /// video's [frame] (its size as shown, in pixels; null: not known). The
  /// [title] is the capture's ([captureTitleLines]): the title's text
  /// unless the edit has its own ([PageEdit.title]), drawn unless it's
  /// turned off. The [watermark] (its text; null: none, as in
  /// the file screen's player) is drawn unless the edit turns it off
  /// ([PageEdit.watermark]) and the one downloading has Premium now
  /// ([premium], or a build without the service): an edit a Premium user
  /// made downloads with it for anyone else. With the tab, it's lifted
  /// above its tallest band in this output ([bandAspect]). The sound alone
  /// has no layers. It fades in and out as the edit says (3 s each by
  /// default, none at most half the kept part long:
  /// [PageEdit.fadeWithin]), unless not [fades] (the file screen's player,
  /// which loops the video, leaves them to Download).
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
    List<String> title = const [],
    String? watermark,
    bool premium = false,
    BandAspect bandAspect = bandAspectBound,
    bool preview = false,
    bool fades = true,
    Size? frame,
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
    final layers = <PlanLayer>[];
    if (video) {
      if (tabOffered(takeLog) && (edit?.tab ?? true)) {
        layers.addAll(
          tabLayers(
            takeLog!.tab!,
            takeLog.lagMs,
            start,
            end,
            style: edit?.tabStyle ?? EditTabStyle.standard,
            frame: frame,
          ),
        );
      }
      if (watermark != null && !(edit?.watermark == false && premium)) {
        var lift = 0.0;
        for (final band in layers) {
          if (band.look case final BandLook look) {
            lift = max(lift, bandAspect(look));
          }
        }
        layers.add(watermarkLayer(watermark, liftW: lift));
      }
      final shown = edit?.title;
      if (titleLayer(shown == null ? title : shown.linesOr(title))
          case final layer?) {
        layers.add(layer);
      }
    }
    return RenderPlan(
      start: start,
      end: end,
      input: input,
      duration: duration,
      format: video ? formats.video : formats.sound,
      video: video,
      own: own,
      song: song,
      layers: layers,
      keepsFormat:
          kind != RenderKind.sound && formats.keepsAsIs(inputExtension),
      fadeIn: fades
          ? PageEdit.fadeWithin(edit?.fadeIn ?? PageEdit.defaultFade, length)
          : Duration.zero,
      fadeOut: fades
          ? PageEdit.fadeWithin(edit?.fadeOut ?? PageEdit.defaultFade, length)
          : Duration.zero,
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

  /// How long it fades in from black (and silence) at its start, and out
  /// to black at its end ([fades]); 0: none. At most half its [length]
  /// each.
  final Duration fadeIn;
  final Duration fadeOut;

  /// Its fades, over its [length].
  Fades get fades => Fades(fadeIn: fadeIn, fadeOut: fadeOut, length: length);

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
  /// sound as it is and nothing else (nothing drawn over it, no fades),
  /// already in the format made. Only then is no file made.
  bool get passthrough =>
      video &&
      keepsFormat &&
      layers.isEmpty &&
      !fades.any &&
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
      if (fadeIn > Duration.zero) 'fadeInMs': fadeIn.inMilliseconds,
      if (fadeOut > Duration.zero) 'fadeOutMs': fadeOut.inMilliseconds,
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
      other.keepsFormat == keepsFormat &&
      other.fadeIn == fadeIn &&
      other.fadeOut == fadeOut;

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
    fadeIn,
    fadeOut,
  );

  @override
  String toString() =>
      'RenderPlan($start–$end of ${input?.name}, ${format.label}, '
      'video $video, own $own, song $song, ${layers.length} layers, '
      'fades $fadeIn/$fadeOut)';
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
