import 'dart:math';

import 'package:flutter/foundation.dart';

import '../library/json_extra.dart';

/// What Cam noted while a take recorded, kept with the take's page
/// (`takeLog` in its details, `EventPage.takeLog`): written once, when the
/// take is saved, and never changed after (a clone only renames the pages
/// it names). A log read from JSON is written back as it came ([toJson]),
/// whatever in it this version doesn't know or can't read included (a
/// newer app's `lagFrom`, a field in a segment, a turn out of order), so
/// saving its page again (renamed, edited, published, cloned) loses
/// nothing. From it the editor can put the tab over the take as a layer
/// and line the song up with it, instead of the tab being in the picture
/// (see specs/cam.md, "What a take keeps").
///
/// Times are on the take's clock (Cam's, started once the recording had
/// started), in ms. Where a time falls in the file: the take's time plus
/// [lagMs] ([TakeTab.fileTime]).
@immutable
class TakeLog {
  const TakeLog({
    this.version = TakeLog.currentVersion,
    required this.burned,
    this.lagMs = 0,
    this.lagFrom = LagFrom.none,
    this.lagRaw = const {},
    this.tab,
    this.song = const [],
    this.songLink = false,
    this.extra = const {},
  }) : _json = null;

  const TakeLog._read(
    this._json, {
    required this.version,
    required this.burned,
    required this.lagMs,
    required this.lagFrom,
    required this.lagRaw,
    required this.tab,
    required this.song,
    required this.songLink,
    required this.extra,
  });

  /// The version this app writes.
  static const int currentVersion = 1;

  /// `v`: the version of the app's log that wrote it (kept as it came).
  final int version;

  /// Whether the tab is in the take's picture (burned in after it was
  /// recorded, or drawn in as the web recorded it): then it's never drawn
  /// over it again. False when it couldn't be put in, or there was none.
  final bool burned;

  /// How long the file had been recording when the take's clock started:
  /// a time on the clock is [lagMs] later in the file.
  final int lagMs;

  /// How [lagMs] was told.
  final LagFrom lagFrom;

  /// The clock's readings [lagMs] was told from (ms, the take's clock's
  /// 0 being its start), kept so it can be told again better later.
  final Map<String, int> lagRaw;

  /// The tab: the necklines shown, and when. Null with no tab.
  final TakeTab? tab;

  /// The song played along, as segments of the take; empty when none
  /// played (a later version notes them).
  final List<SongSegment> song;

  /// Whether a song played along was a link in a frame (no position).
  final bool songLink;

  /// Keys a newer app wrote, kept as they came.
  final Map<String, Object?> extra;

  /// The JSON this log was read from ([fromJson]), as it came (a copy):
  /// what [toJson] writes back. Null for a log Cam made.
  final Map<String, Object?>? _json;

  static const Set<String> knownKeys = {
    'v',
    'burned',
    'lagMs',
    'lagFrom',
    'lagRaw',
    'tab',
    'song',
    'songLink',
  };

  /// The neckline showing at [position] in the file (as it plays back);
  /// null with no tab.
  String? lineAt(Duration position) => tab?.lineAt(position, lagMs);

  /// A clone's copy: the songs it names are the copy's pages ([ids], old
  /// page ID to new; one not there stays as it is). Read from JSON, every
  /// segment there naming a page is renamed, those this version can't
  /// read too, and nothing else changes.
  TakeLog withPages(Map<String, String> ids) {
    final json = _json;
    if (json == null) {
      if (song.isEmpty) return this;
      return TakeLog(
        version: version,
        burned: burned,
        lagMs: lagMs,
        lagFrom: lagFrom,
        lagRaw: lagRaw,
        tab: tab,
        song: [for (final s in song) s.withPage(ids[s.page] ?? s.page)],
        songLink: songLink,
        extra: extra,
      );
    }
    final segments = json['song'];
    if (segments is! List ||
        !segments.any((s) => s is Map && ids.containsKey(s['page']))) {
      return this;
    }
    return TakeLog._read(
      Map.unmodifiable({
        ...json,
        'song': List<Object?>.unmodifiable([
          for (final s in segments)
            if (s case final Map m when ids.containsKey(m['page']))
              Map<String, Object?>.unmodifiable({
                ...m.cast<String, Object?>(),
                'page': ids[m['page']],
              })
            else
              s,
        ]),
      }),
      version: version,
      burned: burned,
      lagMs: lagMs,
      lagFrom: lagFrom,
      lagRaw: lagRaw,
      tab: tab,
      song: List.unmodifiable([
        for (final s in song) s.withPage(ids[s.page] ?? s.page),
      ]),
      songLink: songLink,
      extra: extra,
    );
  }

  /// The log as JSON: as it came, when it was read from JSON ([fromJson]).
  Map<String, Object?> toJson() => _json ?? _made();

  Map<String, Object?> _made() => {
    'v': version,
    'burned': burned,
    'lagMs': lagMs,
    'lagFrom': lagFrom.name,
    if (lagRaw.isNotEmpty) 'lagRaw': lagRaw,
    if (tab != null) 'tab': tab!.toJson(),
    'song': [for (final s in song) s.toJson()],
    if (songLink) 'songLink': true,
    for (final MapEntry(:key, :value) in extraEntries(extra, knownKeys))
      key: value,
  };

  /// The log in [json], read leniently (it also comes from the cloud):
  /// what isn't as expected is left out of its fields, but kept in what
  /// [toJson] writes back. Null when it's no log at all.
  static TakeLog? fromJson(Object? json) {
    if (json is! Map) return null;
    final raw = json['lagRaw'];
    return TakeLog._read(
      // All of it, as it came (a JSON copy: plain JSON only).
      unknownKeys(json, const {}),
      version: _int(json['v']) ?? 1,
      // Unsaid, taken as burned: the tab is then never drawn twice.
      burned: json['burned'] != false,
      lagMs: _int(json['lagMs']) ?? 0,
      lagFrom: LagFrom.values.asNameMap()[json['lagFrom']] ?? LagFrom.none,
      lagRaw: raw is Map
          ? Map.unmodifiable({
              for (final MapEntry(:key, :value) in raw.entries)
                if (key is String && _int(value) != null) key: _int(value)!,
            })
          : const {},
      tab: TakeTab.fromJson(json['tab']),
      song: switch (json['song']) {
        final List list => List.unmodifiable([
          for (final s in list) ?SongSegment.fromJson(s),
        ]),
        _ => const [],
      },
      songLink: json['songLink'] == true,
      extra: unknownKeys(json, knownKeys),
    );
  }

  /// Equal when they'd be written the same ([toJson]).
  @override
  bool operator ==(Object other) =>
      identical(other, this) ||
      other is TakeLog && jsonEquals(other.toJson(), toJson());

  @override
  int get hashCode => jsonHash(toJson());

  @override
  String toString() => 'TakeLog(${toJson()})';
}

/// How a take's [TakeLog.lagMs] was told.
enum LagFrom {
  /// The browser's recorder said when it started ([lagFromRecorder]).
  recorder,

  /// From when the camera was told to start and stop, and the file's
  /// length ([lagFromBounds]).
  bounds,

  /// Not told: taken as 0.
  none,
}

/// The tab in a take: the necklines it showed ([lines], each text once)
/// and when ([marks]: ms on the take's clock, and which of [lines]).
/// Cam's turns are all kept as they came: those made with Auto-pass off,
/// with the tab hidden, or back to the line showing.
@immutable
class TakeTab {
  const TakeTab({required this.lines, required this.marks});

  /// From the capture's necklines ([all]) and Cam's [marks] (into [all]):
  /// the necklines used, in the order first shown, each text once, and
  /// every mark, its line one of those. At most [maxMarks] marks (the
  /// first ones).
  factory TakeTab.of(List<String> all, List<(Duration, int)> marks) {
    final lines = <String>[];
    final index = <String, int>{};
    final kept = <(int, int)>[];
    for (final (at, line) in _kept(all, marks)) {
      final text = all[line];
      final i = index[text] ??= (lines..add(text)).length - 1;
      kept.add((max(0, at.inMilliseconds), i));
    }
    return TakeTab(
      lines: List.unmodifiable(lines),
      marks: List.unmodifiable(kept),
    );
  }

  /// The [marks] (into [all]) that [TakeTab.of] keeps, in order.
  static Iterable<(Duration, int)> _kept(
    List<String> all,
    List<(Duration, int)> marks,
  ) => marks.take(maxMarks).where((m) => m.$2 >= 0 && m.$2 < all.length);

  /// For each mark [TakeTab.of] keeps from [marks], the line of [all] it
  /// came from: what [placesIn] gives exactly, while Cam still has them.
  static List<int> placesOf(List<String> all, List<(Duration, int)> marks) => [
    for (final (_, line) in _kept(all, marks)) line,
  ];

  /// The most marks kept: an hour of turning every second, a few tens of
  /// KB.
  static const int maxMarks = 4000;

  final List<String> lines;
  final List<(int, int)> marks;

  /// Where [take] (on the take's clock) is in the file, [lagMs] after it
  /// ([TakeLog.lagMs]). The start stays the start: the neckline showing
  /// then showed from the file's first frame.
  static Duration fileTime(Duration take, int lagMs) => take <= Duration.zero
      ? Duration.zero
      : take + Duration(milliseconds: lagMs);

  /// The turns at their times in the file ([fileTime]): when, and which
  /// of [lines].
  List<(Duration, int)> fileMarks(int lagMs) => [
    for (final (ms, line) in marks)
      (fileTime(Duration(milliseconds: ms), lagMs), line),
  ];

  /// The neckline showing at [position] in the file, [lagMs] after the
  /// take's clock; null with no marks.
  String? lineAt(Duration position, int lagMs) {
    final mark = markAt(position, lagMs);
    return mark == null ? null : lines[marks[mark].$2];
  }

  /// Which of [marks] is the one at [position] in the file, [lagMs] after
  /// the take's clock: the last at or before it (before the first, the
  /// first); null with no marks.
  int? markAt(Duration position, int lagMs) {
    if (marks.isEmpty) return null;
    // The last turn at or before it (they're in time order); before the
    // first, the first.
    var lo = 0;
    var hi = marks.length - 1;
    var found = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (fileTime(Duration(milliseconds: marks[mid].$1), lagMs) <= position) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  /// For each of [marks], the line of [all] (a capture's necklines now)
  /// with its text; -1 where none has it (the tab changed since). A text
  /// in [all] more than once: the copy nearest the line before, and of
  /// two as near, the one the way the take was going (forward at first,
  /// as a take mostly moves on); for the first mark, the first copy. The
  /// exact lines are only known while Cam has them ([placesOf]); this is
  /// the guess for a take recorded before.
  List<int> placesIn(List<String> all) {
    final copies = <String, List<int>>{};
    for (final (i, text) in all.indexed) {
      (copies[text] ??= []).add(i);
    }
    final places = <int>[];
    int? before;
    var back = false;
    for (final (_, line) in marks) {
      final found = copies[lines[line]];
      if (found == null) {
        places.add(-1);
        continue;
      }
      var place = found.first;
      if (before != null) {
        for (final i in found) {
          final (d, best) = ((i - before).abs(), (place - before).abs());
          if (d < best || (d == best && !back)) place = i;
        }
        if (place != before) back = place < before;
      }
      places.add(place);
      before = place;
    }
    return places;
  }

  Map<String, Object?> toJson() => {
    'lines': lines,
    'marks': [
      for (final (ms, line) in marks) [ms, line],
    ],
  };

  static TakeTab? fromJson(Object? json) {
    if (json is! Map) return null;
    final lines = [
      for (final l in json['lines'] is List ? json['lines'] as List : const [])
        if (l is String) l,
    ];
    if (lines.isEmpty) return null;
    final marks = <(int, int)>[];
    for (final m in json['marks'] is List ? json['marks'] as List : const []) {
      if (m is! List || m.length < 2) continue;
      final (ms, line) = (_int(m[0]), _int(m[1]));
      if (ms == null || line == null || line < 0 || line >= lines.length) {
        continue;
      }
      // In time order, as Cam notes them: one out of it is left out.
      if (marks.isNotEmpty && ms < marks.last.$1) continue;
      marks.add((max(0, ms), line));
      if (marks.length >= maxMarks) break;
    }
    return TakeTab(
      lines: List.unmodifiable(lines),
      marks: List.unmodifiable(marks),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TakeTab &&
      listEquals(other.lines, lines) &&
      listEquals(other.marks, marks);

  @override
  int get hashCode => Object.hash(Object.hashAll(lines), Object.hashAll(marks));
}

/// A neckline in a take: which one ([line]), from [start] to [end] (null:
/// to the end of the take).
@immutable
class TabBand {
  const TabBand(this.line, this.start, [this.end]);

  final int line;
  final Duration start;
  final Duration? end;

  @override
  bool operator ==(Object other) =>
      other is TabBand &&
      other.line == line &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(line, start, end);

  @override
  String toString() => 'TabBand($line, $start, $end)';
}

/// When each neckline showed in a take, from the times the tab moved
/// ([marks]: when, and to which neckline, the first at the start): one
/// band per neckline shown, each until the next.
List<TabBand> bandsOf(List<(Duration, int)> marks) {
  final bands = <TabBand>[];
  for (final (i, (start, line)) in marks.indexed) {
    // Moved twice at once: only the last counts.
    final end = i + 1 < marks.length ? marks[i + 1].$1 : null;
    if (end != null && end <= start) continue;
    // Back to the neckline showing: the same band goes on.
    if (bands.lastOrNull case final last? when last.line == line) {
      bands[bands.length - 1] = TabBand(line, last.start, end);
      continue;
    }
    bands.add(TabBand(line, start, end));
  }
  return bands;
}

/// A stretch of a take with a song playing along: from [at] to [to] on
/// the take's clock, page [page] played from [from] (ms in the song) at
/// [speed]. Where the song was at take time t: `from + (t - at) * speed`.
@immutable
class SongSegment {
  const SongSegment({
    required this.at,
    required this.to,
    required this.page,
    required this.from,
    this.speed = 1,
  });

  final int at;
  final int to;
  final String page;
  final int from;
  final double speed;

  SongSegment withPage(String page) =>
      SongSegment(at: at, to: to, page: page, from: from, speed: speed);

  Map<String, Object?> toJson() => {
    'at': at,
    'to': to,
    'page': page,
    'from': from,
    'speed': speed,
  };

  static SongSegment? fromJson(Object? json) {
    if (json is! Map) return null;
    final (at, to, from) = (
      _int(json['at']),
      _int(json['to']),
      _int(json['from']),
    );
    final page = json['page'];
    final speed = json['speed'] ?? 1;
    if (at == null || to == null || from == null || page is! String) {
      return null;
    }
    if (speed is! num || !speed.isFinite || speed <= 0 || to < at) return null;
    return SongSegment(
      at: at,
      to: to,
      page: page,
      from: from,
      speed: speed.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SongSegment &&
      other.at == at &&
      other.to == to &&
      other.page == page &&
      other.from == from &&
      other.speed == speed;

  @override
  int get hashCode => Object.hash(at, to, page, from, speed);
}

/// The browser's take: its recorder started [sinceStartMs] before the
/// take's clock did (read as the clock started), so that's the lag.
({int lagMs, LagFrom from, Map<String, int> raw}) lagFromRecorder(
  double sinceStartMs, {
  required int startCallMs,
  required int startReturnMs,
}) {
  final lag = max(0, sinceStartMs.round());
  return (
    lagMs: lag,
    from: LagFrom.recorder,
    raw: {
      'startCallMs': startCallMs,
      'startReturnMs': startReturnMs,
      'recorderStartMs': -lag,
    },
  );
}

/// The phones' takes: the lag told from when the camera was told to
/// start and stop (ms, the take's clock's 0 being its start, which is
/// after the start returned) and the file's length ([fileMs]; null when
/// it couldn't be read).
///
/// The file's first frame came between the start's call and its return,
/// so the lag is between `-startReturnMs` and `-startCallMs`; its last
/// between the stop's call and its return, so the lag is between
/// `fileMs - stopReturnMs` and `fileMs - stopCallMs`. The lag is the
/// middle of where both agree; where they don't, the middle of the first.
({int lagMs, LagFrom from, Map<String, int> raw}) lagFromBounds({
  required int startCallMs,
  required int startReturnMs,
  required int stopCallMs,
  required int stopReturnMs,
  int? fileMs,
}) {
  final raw = {
    'startCallMs': startCallMs,
    'startReturnMs': startReturnMs,
    'stopCallMs': stopCallMs,
    'stopReturnMs': stopReturnMs,
    'fileMs': ?fileMs,
  };
  final (startLo, startHi) = (-startReturnMs, -startCallMs);
  var (lo, hi) = (startLo, startHi);
  if (fileMs != null) {
    final (endLo, endHi) = (fileMs - stopReturnMs, fileMs - stopCallMs);
    if (max(lo, endLo) <= min(hi, endHi)) {
      (lo, hi) = (max(lo, endLo), min(hi, endHi));
    }
  }
  return (
    lagMs: max(0, ((lo + hi) / 2).round()),
    from: LagFrom.bounds,
    raw: raw,
  );
}

int? _int(Object? value) => switch (value) {
  final int i => i,
  final double d when d.isFinite => d.round(),
  _ => null,
};
