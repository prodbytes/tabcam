/// What happens to a video's sound when it's edited.
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

/// A video page's edit, kept with the page (and synced with it): the part
/// kept, from [start] to [end], and its sound: kept, removed, or replaced
/// by the capture's recording [trackId], of which the part from
/// [trackStart] to [trackEnd] (null: its end) is used, starting [offset]
/// after the kept part's start (before it, when negative). The video's
/// file stays as it is: players play it as edited, and a download makes a
/// file of it.
class PageEdit {
  const PageEdit({
    required this.start,
    required this.end,
    this.sound = EditSound.original,
    this.trackId,
    this.trackStart = Duration.zero,
    this.trackEnd,
    this.offset = Duration.zero,
  });

  final Duration start;
  final Duration end;
  final EditSound sound;

  /// The page of the capture whose sound replaces the video's, for
  /// [EditSound.track] (null: none picked yet).
  final String? trackId;
  final Duration trackStart;
  final Duration? trackEnd;
  final Duration offset;

  Map<String, Object?> toJson() => {
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
    'sound': sound.name,
    if (trackId != null) 'trackId': trackId,
    if (trackStart > Duration.zero) 'trackStartMs': trackStart.inMilliseconds,
    if (trackEnd != null) 'trackEndMs': trackEnd!.inMilliseconds,
    if (offset != Duration.zero) 'offsetMs': offset.inMilliseconds,
  };

  /// Null when [json] isn't an edit (one from a newer app, or broken).
  static PageEdit? fromJson(Object? json) {
    if (json is! Map) return null;
    Duration? ms(String key) => switch (json[key]) {
      final num n => Duration(milliseconds: n.round()),
      _ => null,
    };
    final start = ms('startMs');
    final end = ms('endMs');
    if (start == null || end == null || end <= start) return null;
    return PageEdit(
      start: start < Duration.zero ? Duration.zero : start,
      end: end,
      sound: EditSound.byName(json['sound']),
      trackId: json['trackId'] is String ? json['trackId'] as String : null,
      trackStart: ms('trackStartMs') ?? Duration.zero,
      trackEnd: ms('trackEndMs'),
      offset: ms('offsetMs') ?? Duration.zero,
    );
  }

  /// This edit with its track [trackId] now [id] (a cloned capture's).
  PageEdit withTrackId(String? id) => PageEdit(
    start: start,
    end: end,
    sound: sound,
    trackId: id,
    trackStart: trackStart,
    trackEnd: trackEnd,
    offset: offset,
  );

  @override
  bool operator ==(Object other) =>
      other is PageEdit &&
      other.start == start &&
      other.end == end &&
      other.sound == sound &&
      other.trackId == trackId &&
      other.trackStart == trackStart &&
      other.trackEnd == trackEnd &&
      other.offset == offset;

  @override
  int get hashCode =>
      Object.hash(start, end, sound, trackId, trackStart, trackEnd, offset);

  @override
  String toString() =>
      'PageEdit($start–$end, $sound, $trackId $trackStart–$trackEnd, '
      '$offset)';
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
