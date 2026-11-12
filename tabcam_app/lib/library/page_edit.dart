import 'package:characters/characters.dart';

import 'json_extra.dart';

/// An edit's sound as apps before the two lanes read it (`sound`): still
/// written, worked out from the lanes ([PageEdit.sound]), and read from an
/// edit those apps wrote ([PageEdit.fromSound]).
enum EditSound {
  /// Its own sound stays.
  original,

  /// Its sound is taken out.
  none,

  /// A sound track takes its sound's place.
  track;

  static EditSound byName(Object? name) => values.firstWhere(
    (s) => s.name == name,
    orElse: () => EditSound.original,
  );
}

/// How the song lane is placed.
enum SongMode {
  /// Lined up by itself from the take's log (a later step of the editor's
  /// redesign). This version plays it as the one clip its track keys
  /// approximate it by (what older apps play), and a change to it here
  /// makes it [manual].
  auto,

  /// Placed by hand: the track keys ([PageEdit.trackId] and the rest).
  manual,

  /// No song.
  off;

  /// Null when [name] isn't one (none given, or a newer app's).
  static SongMode? byName(Object? name) =>
      values.where((m) => m.name == name).firstOrNull;
}

/// [text] at most [max] characters long, as a person counts them and a
/// text field's `maxLength` does (grapheme clusters: an emoji, even one
/// made of several, is one), never cut inside one; the end trimmed when
/// cut.
String clipChars(String text, int max) {
  final chars = text.characters;
  return chars.length > max ? chars.take(max).toString().trimRight() : text;
}

/// The title drawn over an edited video (`title` in its edit): whether
/// it's [on], and the text typed for it ([lines], at most two, each
/// trimmed and at most 80 characters ([clipChars]); null: the capture's name, as it is
/// now, so renaming the capture changes it). Turned off, the text typed
/// is kept.
class EditTitle {
  const EditTitle({this.on = true, this.lines});

  /// The title as [on] and [lines] make it; null when that's the default
  /// (on, with the capture's name), which isn't kept.
  static EditTitle? of({bool on = true, List<String>? lines}) =>
      on && lines == null ? null : EditTitle(on: on, lines: clean(lines));

  final bool on;
  final List<String>? lines;

  /// The most lines, and characters in each.
  static const maxLines = 2;
  static const maxChars = 80;

  /// [lines] as kept: each trimmed and at most [maxChars] long, at most
  /// [maxLines], the empty ones at the end left off.
  static List<String>? clean(List<String>? lines) {
    if (lines == null) return null;
    final kept = [
      for (final line in lines.take(maxLines)) clipChars(line.trim(), maxChars),
    ];
    while (kept.isNotEmpty && kept.last.isEmpty) {
      kept.removeLast();
    }
    return kept;
  }

  /// What it shows, with [name] as the capture's name: nothing when off.
  List<String> linesOr(List<String> name) => on ? lines ?? name : const [];

  Map<String, Object?> toJson() => {'on': on, 'lines': ?lines};

  /// Null when [json] isn't one, or is the default.
  static EditTitle? fromJson(Object? json) {
    if (json is! Map) return null;
    final lines = json['lines'];
    return of(
      on: json['on'] != false,
      lines: lines is List ? [for (final l in lines) '$l'] : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EditTitle &&
      other.on == on &&
      (other.lines == null) == (lines == null) &&
      (lines == null || _same(other.lines!, lines!));

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(on, lines == null ? null : Object.hashAll(lines!));

  @override
  String toString() => 'EditTitle(${on ? 'on' : 'off'}, $lines)';
}

/// A video page's edit, kept with the page (and synced with it): the part
/// kept, from [start] to [end], and its sound in two lanes, mixed: the
/// video's own (at [ownVolume], unless [ownMuted]) and a song (one of the
/// capture's files, [trackId], of which the part from [trackStart] to
/// [trackEnd] (null: its end) is used, starting [offset] after the kept
/// part's start (before it, when negative), at [trackVolume], unless
/// [songMuted]; placed as [song] says). Muting a lane keeps its level.
/// Over the picture: the tab of one of Cam's takes, unless [tab] is off;
/// a title ([title]; null: the capture's name), and the watermark, unless
/// [watermark] is off (which only a Premium user can do, and only a
/// Premium user's download obeys). It fades in from black at the kept
/// part's start over [fadeIn], and out to black at its end over
/// [fadeOut], both lanes' sound with it (3 s each by default; 0: none;
/// never more than half the kept part, [fadeWithin]).
/// The video's file stays as it is: players play it as edited, and a
/// download makes a file of it.
///
/// Written as version 2 (`v`), with the `sound` older apps read worked
/// out from the lanes ([sound]); an edit without `v` is read with the old
/// meaning of `sound` ([fromSound]), and so is one whose `sound` an older
/// app changed since. Keys a newer app wrote that this one doesn't know
/// are kept in [extra], and written back.
class PageEdit {
  const PageEdit({
    required this.start,
    required this.end,
    this.ownVolume = 1,
    this.ownMuted = false,
    this.song,
    this.songMuted = false,
    this.trackId,
    this.trackStart = Duration.zero,
    this.trackEnd,
    this.offset = Duration.zero,
    this.trackVolume = 1,
    this.tab = true,
    this.title,
    this.watermark = true,
    this.fadeIn = defaultFade,
    this.fadeOut = defaultFade,
    this.extra = const {},
  });

  /// An edit as apps before the two lanes made it: [sound] says which
  /// lanes play. Original: the own sound; the track, if one is picked,
  /// stays as a manual song lane, muted, so it and its settings survive.
  /// None: both muted. Track: the own sound muted, the track audible.
  /// These play and download as they did.
  factory PageEdit.fromSound({
    required Duration start,
    required Duration end,
    EditSound sound = EditSound.original,
    String? trackId,
    Duration trackStart = Duration.zero,
    Duration? trackEnd,
    Duration offset = Duration.zero,
    double trackVolume = 1,
    Map<String, Object?> extra = const {},
  }) => PageEdit(
    start: start,
    end: end,
    trackId: trackId,
    trackStart: trackStart,
    trackEnd: trackEnd,
    offset: offset,
    trackVolume: trackVolume,
    extra: extra,
  ).followingSound(sound);

  /// The shortest part of a video that can be kept.
  static const minLength = Duration(milliseconds: 500);

  /// How long the fades in and out are by default, and at most.
  static const defaultFade = Duration(seconds: 3);
  static const maxFade = Duration(seconds: 10);

  /// [fade] as a fade over a kept part [length] long plays it: within 0
  /// and [maxFade], and never more than half of [length] (the fades in and
  /// out then meet in the middle).
  static Duration fadeWithin(Duration fade, Duration length) {
    var most = length ~/ 2;
    if (most > maxFade) most = maxFade;
    if (most < Duration.zero) most = Duration.zero;
    return fade < Duration.zero ? Duration.zero : (fade > most ? most : fade);
  }

  /// [fade] as kept: within 0 and [maxFade], to the millisecond.
  static Duration fadeLength(Duration fade) => fade < Duration.zero
      ? Duration.zero
      : fade > maxFade
      ? maxFade
      : Duration(milliseconds: fade.inMilliseconds);

  /// The version of the edit this app writes (`v`).
  static const version = 2;

  /// The keys [toJson] writes, and [fromJson] reads (and checks).
  static const Set<String> knownKeys = {
    'v',
    'startMs',
    'endMs',
    'sound',
    'trackId',
    'trackStartMs',
    'trackEndMs',
    'offsetMs',
    'trackVolume',
    'ownVolume',
    'ownMuted',
    'songMuted',
    'song',
    'tab',
    'title',
    'watermark',
    'fadeInMs',
    'fadeOutMs',
  };

  final Duration start;
  final Duration end;

  /// How loud the video's own sound plays, 0 to 1 (as it is, the
  /// default), and whether it's muted (its level kept).
  final double ownVolume;
  final bool ownMuted;

  /// How the song lane is placed; null: the default ([songMode]).
  final SongMode? song;

  /// Whether the song lane is muted (its level, [trackVolume], kept).
  final bool songMuted;

  /// The page of the capture the song lane plays (null: none picked).
  final String? trackId;
  final Duration trackStart;
  final Duration? trackEnd;
  final Duration offset;

  /// How loud the song lane plays, from 0 (silent) to 1 (as it is, the
  /// default): the players can't play it louder than it is.
  final double trackVolume;

  /// Whether the tab is drawn over a take that can have it (one whose
  /// log has its tab, not already in its picture: `tabOffered`): on by
  /// default, written (`tab: false`) only when turned off.
  final bool tab;

  /// The title drawn over the video: null (the default, not written) is
  /// the capture's name, on.
  final EditTitle? title;

  /// Whether the watermark is drawn: on by default, written (`watermark:
  /// false`) only when a Premium user turns it off; obeyed only when the
  /// one downloading has Premium (`RenderPlan.of`).
  final bool watermark;

  /// How long the video fades in from black at the kept part's start, and
  /// out to black at its end, both lanes' sound with it ([defaultFade]
  /// by default, written (`fadeInMs`, `fadeOutMs`) only when another; 0:
  /// no fade; at most [maxFade], and played at most half the kept part
  /// long, [fadeWithin]). An edit kept before the fades has none written,
  /// so it has the default ones.
  final Duration fadeIn;
  final Duration fadeOut;

  /// The keys of its JSON this version doesn't know (a newer app's, see
  /// `unknownKeys`), written back as they came, after the known ones,
  /// which win.
  final Map<String, Object?> extra;

  /// [volume] as a lane's: within 0–1, to the hundredth; 1 when it isn't
  /// a number.
  static double volume(Object? volume) => volume is num && volume.isFinite
      ? (volume.clamp(0, 1) * 100).round() / 100
      : 1;

  /// How the song lane is placed: as [song] says, or, by default, none
  /// without a song picked, and [SongMode.auto] with one. This version
  /// never writes a song without `song`; a later one leaves `song` out
  /// when it's the page's default (a take's log lining its song up by
  /// itself, or a song placed at the start for an older take), and this
  /// one then plays the one clip its track keys approximate it by (as
  /// [SongMode.auto] says), rather than dropping it.
  SongMode get songMode =>
      song ?? (trackId == null ? SongMode.off : SongMode.auto);

  /// Whether the video's own sound is heard.
  bool get ownAudible => !ownMuted && ownVolume > 0;

  /// Whether the song lane has a song in it (placed, and picked).
  bool get hasSong => songMode != SongMode.off && trackId != null;

  /// Whether the song lane is heard.
  bool get songAudible => hasSong && !songMuted && trackVolume > 0;

  /// The sound apps before the two lanes play (written as `sound`): the
  /// track alone when only the song is heard, none when neither is, and
  /// the video's own otherwise (with both heard, their safe fallback).
  EditSound get sound => ownAudible
      ? EditSound.original
      : songAudible
      ? EditSound.track
      : EditSound.none;

  /// This edit's lanes as [sound] means to an older app, which wins over
  /// them: the song lane, with a track picked, becomes [SongMode.manual]
  /// (its track keys), and the lanes are muted or not as [sound] says.
  /// The levels stay (the own sound's put back to 100% if it's to be heard
  /// at 0%, as an older app plays it as it is).
  PageEdit followingSound(EditSound sound) {
    final own = sound == EditSound.original;
    final picked = trackId != null;
    return copyWith(
      ownMuted: !own,
      ownVolume: own && ownVolume <= 0 ? 1 : ownVolume,
      song: picked ? SongMode.manual : song,
      songMuted: picked ? sound != EditSound.track : songMuted,
    );
  }

  Map<String, Object?> toJson() => {
    'v': version,
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
    'sound': sound.name,
    if (trackId != null) 'trackId': trackId,
    if (trackStart > Duration.zero) 'trackStartMs': trackStart.inMilliseconds,
    if (trackEnd != null) 'trackEndMs': trackEnd!.inMilliseconds,
    if (offset != Duration.zero) 'offsetMs': offset.inMilliseconds,
    if (trackVolume != 1) 'trackVolume': trackVolume,
    if (ownVolume != 1) 'ownVolume': ownVolume,
    if (ownMuted) 'ownMuted': true,
    if (songMuted) 'songMuted': true,
    if (song != null) 'song': song!.name,
    if (!tab) 'tab': false,
    if (title case final title?) 'title': title.toJson(),
    if (!watermark) 'watermark': false,
    if (fadeIn != defaultFade) 'fadeInMs': fadeIn.inMilliseconds,
    if (fadeOut != defaultFade) 'fadeOutMs': fadeOut.inMilliseconds,
    for (final MapEntry(:key, :value) in extraEntries(extra, knownKeys))
      key: value,
  };

  /// Null when [json] isn't an edit (one from a newer app, or broken).
  static PageEdit? fromJson(Object? json) {
    if (json is! Map) return null;
    Duration? ms(String key) => switch (json[key]) {
      final num n when n.isFinite => Duration(milliseconds: n.round()),
      _ => null,
    };
    final start = ms('startMs');
    final end = ms('endMs');
    if (start == null || end == null || end <= start) return null;
    final edit = PageEdit(
      start: start < Duration.zero ? Duration.zero : start,
      end: end,
      trackId: json['trackId'] is String ? json['trackId'] as String : null,
      trackStart: ms('trackStartMs') ?? Duration.zero,
      trackEnd: ms('trackEndMs'),
      offset: ms('offsetMs') ?? Duration.zero,
      trackVolume: volume(json['trackVolume']),
      tab: json['tab'] != false,
      title: EditTitle.fromJson(json['title']),
      watermark: json['watermark'] != false,
      fadeIn: fadeLength(ms('fadeInMs') ?? defaultFade),
      fadeOut: fadeLength(ms('fadeOutMs') ?? defaultFade),
      extra: unknownKeys(json, knownKeys),
    );
    final stored = json['sound'];
    final sound = EditSound.byName(stored);
    final v = json['v'];
    // Before the two lanes: `sound` says it all.
    if (v is! num || v < 2) return edit.followingSound(sound);
    final lanes = edit.copyWith(
      ownVolume: volume(json['ownVolume']),
      ownMuted: json['ownMuted'] == true,
      song: SongMode.byName(json['song']),
      songMuted: json['songMuted'] == true,
    );
    // An older app changed `sound` since (it knows only the old keys):
    // their old meaning wins for the lanes.
    if (stored is String && sound != lanes.sound) {
      return lanes.followingSound(sound);
    }
    return lanes;
  }

  /// This edit with the fields given changed (null for a nullable one
  /// clears it).
  PageEdit copyWith({
    Duration? start,
    Duration? end,
    double? ownVolume,
    bool? ownMuted,
    Object? song = _same,
    bool? songMuted,
    Object? trackId = _same,
    Duration? trackStart,
    Object? trackEnd = _same,
    Duration? offset,
    double? trackVolume,
    bool? tab,
    Object? title = _same,
    bool? watermark,
    Duration? fadeIn,
    Duration? fadeOut,
    Map<String, Object?>? extra,
  }) => PageEdit(
    start: start ?? this.start,
    end: end ?? this.end,
    ownVolume: ownVolume == null ? this.ownVolume : volume(ownVolume),
    ownMuted: ownMuted ?? this.ownMuted,
    song: identical(song, _same) ? this.song : song as SongMode?,
    songMuted: songMuted ?? this.songMuted,
    trackId: identical(trackId, _same) ? this.trackId : trackId as String?,
    trackStart: trackStart ?? this.trackStart,
    trackEnd: identical(trackEnd, _same)
        ? this.trackEnd
        : trackEnd as Duration?,
    offset: offset ?? this.offset,
    trackVolume: trackVolume == null ? this.trackVolume : volume(trackVolume),
    tab: tab ?? this.tab,
    title: identical(title, _same) ? this.title : title as EditTitle?,
    watermark: watermark ?? this.watermark,
    fadeIn: fadeIn == null ? this.fadeIn : fadeLength(fadeIn),
    fadeOut: fadeOut == null ? this.fadeOut : fadeLength(fadeOut),
    extra: extra ?? this.extra,
  );

  static const _same = Object();

  /// Every field but [extra], in one list: [==], [hashCode] and
  /// [toString] all go by it, so none can be forgotten in one of them.
  List<Object?> get _fields => [
    start,
    end,
    ownVolume,
    ownMuted,
    song,
    songMuted,
    trackId,
    trackStart,
    trackEnd,
    offset,
    trackVolume,
    tab,
    title,
    watermark,
    fadeIn,
    fadeOut,
  ];

  @override
  bool operator ==(Object other) {
    if (other is! PageEdit) return false;
    final mine = _fields;
    final theirs = other._fields;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) return false;
    }
    return jsonEquals(other.extra, extra);
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(_fields), jsonHash(extra));

  @override
  String toString() =>
      'PageEdit(${_fields.join(', ')}${extra.isEmpty ? '' : ', $extra'})';
}

/// The part of a track [trackLength] long that goes into a clip [clip]
/// long: of the track, the part from [trackStart] to [trackEnd] (null: its
/// end) is used, starting [offset] after the clip's start. The silence
/// before it ([gap]), and the part of the track itself, from [from] to
/// [to]. Null when none of the track falls within the clip.
({Duration gap, Duration from, Duration to})? trackSpan(
  Duration clip,
  Duration trackLength,
  Duration offset, {
  Duration trackStart = Duration.zero,
  Duration? trackEnd,
}) {
  if (clip <= Duration.zero || trackLength <= Duration.zero) return null;
  final usedEnd = trackEnd == null || trackEnd > trackLength
      ? trackLength
      : trackEnd;
  final gap = offset > Duration.zero ? offset : Duration.zero;
  final from = trackStart + (offset < Duration.zero ? -offset : Duration.zero);
  if (gap >= clip || from >= usedEnd) return null;
  final room = clip - gap;
  final to = from + room < usedEnd ? from + room : usedEnd;
  if (to <= from) return null;
  return (gap: gap, from: from, to: to);
}
