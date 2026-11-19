import 'dart:math';

import 'package:flutter/foundation.dart';

import '../library/json_extra.dart';

/// What Cam noted while a take recorded, kept with the take's page
/// (`takeLog` in its details, `EventPage.takeLog`): written once, when the
/// take is saved, and never changed after, but for its [sync], added once,
/// when the song is found in the take's sound ([withSync]; a clone only
/// renames the pages it names). A log read from JSON is written back as it came ([toJson]),
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
    this.sync,
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
    required this.sync,
    required this.extra,
  });

  /// The version this app writes.
  static const int currentVersion = 1;

  /// `v`: the version of the app's log that wrote it (kept as it came).
  final int version;

  /// Whether the tab is in the take's picture: true only on takes saved by
  /// the versions that put it there (burned in after recording, or drawn
  /// in as the web recorded); it's then never drawn over again. Cam now
  /// saves every take with false: the editor draws the tab from the log.
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

  /// The song played along, as segments of the take ([SongNotes]); empty
  /// when none played (and on takes saved before Cam noted them).
  final List<SongSegment> song;

  /// Whether a song played along was a link in a frame (no position).
  final bool songLink;

  /// Where the song really is in the take, measured from the take's own
  /// sound after it was saved ([TakeSync]); null: not measured (yet).
  final TakeSync? sync;

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
    'sync',
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
    final renamed = sync?.withPage(ids[sync!.page] ?? sync!.page);
    if (json == null) {
      if (song.isEmpty && sync == null) return this;
      return TakeLog(
        version: version,
        burned: burned,
        lagMs: lagMs,
        lagFrom: lagFrom,
        lagRaw: lagRaw,
        tab: tab,
        song: [for (final s in song) s.withPage(ids[s.page] ?? s.page)],
        songLink: songLink,
        sync: renamed,
        extra: extra,
      );
    }
    bool named(Object? s) => s is Map && ids.containsKey(s['page']);
    final segments = json['song'];
    final measured = json['sync'];
    final inSong = segments is List && segments.any(named);
    if (!inSong && !named(measured)) return this;
    Map<String, Object?> renamedMap(Map m) => Map<String, Object?>.unmodifiable(
      {...m.cast<String, Object?>(), 'page': ids[m['page']]},
    );
    return TakeLog._read(
      Map.unmodifiable({
        ...json,
        if (inSong)
          'song': List<Object?>.unmodifiable([
            for (final s in segments)
              if (named(s)) renamedMap(s as Map) else s,
          ]),
        if (named(measured)) 'sync': renamedMap(measured as Map),
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
      sync: renamed,
      extra: extra,
    );
  }

  /// This log with where the song really is in the take ([sync]), measured
  /// after it was saved: the one thing added to a log later. Everything
  /// else stays as it is (read from JSON: as it came).
  TakeLog withSync(TakeSync sync) {
    final json = _json;
    if (json == null) {
      return TakeLog(
        version: version,
        burned: burned,
        lagMs: lagMs,
        lagFrom: lagFrom,
        lagRaw: lagRaw,
        tab: tab,
        song: song,
        songLink: songLink,
        sync: sync,
        extra: extra,
      );
    }
    return TakeLog._read(
      Map.unmodifiable({...json, 'sync': sync.toJson()}),
      version: version,
      burned: burned,
      lagMs: lagMs,
      lagFrom: lagFrom,
      lagRaw: lagRaw,
      tab: tab,
      song: song,
      songLink: songLink,
      sync: sync,
      extra: extra,
    );
  }

  /// The song the log lines up by itself: the segments of the one that
  /// played along longest, at its own speed (one played at another speed
  /// is noted, but no renderer plays a song at another speed yet), as
  /// noted; empty when none played.
  List<SongSegment> get linedSong {
    final byPage = <String, List<SongSegment>>{};
    for (final s in song) {
      if (s.speed == 1 && s.to > s.at) (byPage[s.page] ??= []).add(s);
    }
    List<SongSegment> best = const [];
    var most = 0;
    for (final segments in byPage.values) {
      final played = segments.fold(0, (sum, s) => sum + s.to - s.at);
      if (played > most) (best, most) = (segments, played);
    }
    return best;
  }

  /// Where [segment] of the song starts in the file: its time on the
  /// take's clock, the lag after it, moved by what its sound in the take
  /// told ([sync], when it measured that song; [synced] false: as the log
  /// alone has it). May be before the file's start.
  int songFileMs(SongSegment segment, {bool synced = true}) =>
      segment.at +
      lagMs +
      (synced && sync?.page == segment.page ? sync!.shiftAt(segment.at) : 0);

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
    if (sync != null) 'sync': sync!.toJson(),
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
      sync: TakeSync.fromJson(json['sync']),
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

/// Where the song played along really is in a take ([TakeLog.sync]),
/// measured after the take was saved by finding the song's sound in the
/// take's own (the microphone hears the speaker): what the log's line-up
/// (the player's word, and the lag) is off by. A segment of the song then
/// starts [shiftAt] later in the file than the log alone says.
///
/// ```json
/// "sync": {"v": 1, "page": "p3", "from": "sound", "ms": 38,
///          "clips": [{"at": 2000, "ms": 38, "score": 21.4}]}
/// ```
@immutable
class TakeSync {
  const TakeSync({
    required this.page,
    required this.from,
    this.ms = 0,
    this.clips = const [],
  });

  /// The song measured (its page).
  final String page;

  /// How it was told.
  final SyncFrom from;

  /// How much later than the log says the song is in the file (ms;
  /// earlier when negative): the middle one of [clips]' shifts. 0 when it
  /// wasn't found.
  final int ms;

  /// The segments measured: each by its start on the take's clock
  /// ([SongSegment.at]), its own shift and how clearly it was found.
  final List<SyncClip> clips;

  /// Whether the song was found in the take's sound, so the line-up is
  /// measured rather than noted.
  bool get found => from == SyncFrom.sound;

  /// The shift of the segment that starts at [at] on the take's clock:
  /// its own, when it was measured, else the song's ([ms]).
  int shiftAt(int at) {
    for (final c in clips) {
      if (c.at == at) return c.ms;
    }
    return ms;
  }

  TakeSync withPage(String page) =>
      TakeSync(page: page, from: from, ms: ms, clips: clips);

  Map<String, Object?> toJson() => {
    'v': 1,
    'page': page,
    'from': from.name,
    'ms': ms,
    if (clips.isNotEmpty) 'clips': [for (final c in clips) c.toJson()],
  };

  /// Read leniently; null when it's none, or by a way this version
  /// doesn't know (a newer app's: the log's line-up is used, and the log
  /// writes it back as it came).
  static TakeSync? fromJson(Object? json) {
    if (json is! Map) return null;
    final page = json['page'];
    final from = SyncFrom.values.asNameMap()[json['from']];
    if (page is! String || from == null) return null;
    return TakeSync(
      page: page,
      from: from,
      ms: from == SyncFrom.sound ? _int(json['ms']) ?? 0 : 0,
      clips: from == SyncFrom.sound && json['clips'] is List
          ? List.unmodifiable([
              for (final c in json['clips'] as List) ?SyncClip.fromJson(c),
            ])
          : const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TakeSync &&
      other.page == page &&
      other.from == from &&
      other.ms == ms &&
      listEquals(other.clips, clips);

  @override
  int get hashCode => Object.hash(page, from, ms, Object.hashAll(clips));

  @override
  String toString() => 'TakeSync(${toJson()})';
}

/// How a take's [TakeSync] was told.
enum SyncFrom {
  /// The song was found in the take's own sound.
  sound,

  /// Looked for and not found (headphones, or the song too quiet in the
  /// take): the log's line-up stands, and it isn't looked for again.
  none,
}

/// One segment of the song as measured ([TakeSync.clips]): the one that
/// starts at [at] on the take's clock is [ms] later in the file than the
/// log says; [score] says how clearly it was found (how far its match
/// stands above the rest, in their spread).
@immutable
class SyncClip {
  const SyncClip({required this.at, required this.ms, this.score = 0});

  final int at;
  final int ms;
  final double score;

  Map<String, Object?> toJson() => {'at': at, 'ms': ms, 'score': score};

  static SyncClip? fromJson(Object? json) {
    if (json is! Map) return null;
    final (at, ms) = (_int(json['at']), _int(json['ms']));
    final score = json['score'];
    if (at == null || ms == null) return null;
    return SyncClip(
      at: at,
      ms: ms,
      score: score is num && score.isFinite ? score.toDouble() : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SyncClip &&
      other.at == at &&
      other.ms == ms &&
      other.score == score;

  @override
  int get hashCode => Object.hash(at, ms, score);
}

/// Notes the song playing along while a take records, as the segments
/// its log keeps ([TakeLog.song]): each stretch of one song playing on,
/// from where it was, at one speed, on the take's clock. Told what the
/// song's player says each time it changes ([note]): a pause, its end,
/// another song, another speed or a jump (a seek, a skip, its section or
/// Repeat starting it over) ends a segment, and playing again starts the
/// next. A segment's start is then told again from a fresh reading of
/// where the song is ([anchor]): the player's own position is only
/// updated every so often, so the one it has as it starts may be late.
class SongNotes {
  /// How far from where it would be, playing on, the song can be before
  /// it's taken as a jump: the player's position is updated about every
  /// half second, and read late by as much.
  static const jumpMs = 300;

  /// The most segments kept (the first): a section of 5 s played over
  /// and over for an hour is 720.
  static const maxSegments = 2000;

  final _segments = <SongSegment>[];
  ({int at, String page, int from, double speed})? _open;
  bool _link = false;
  int _segment = 0;

  /// Which segment is the one playing (or the last one started): each one
  /// [note] starts counts one more, so a reading for one ([anchor]) isn't
  /// taken for the next.
  int get segment => _segment;

  /// Whether a link in a frame played (it has no position to note).
  bool get link => _link;

  /// The song's player at [t] (ms on the take's clock): playing or not,
  /// which song ([page]; null: none, or a link), where in it
  /// ([position], ms) and at what [speed]. Whether a segment started
  /// (then worth an [anchor]).
  bool note(
    int t, {
    required String? page,
    required bool playing,
    required int position,
    double speed = 1,
  }) {
    final open = _open;
    if (open != null) {
      final expected = open.from + ((t - open.at) * open.speed).round();
      if (playing &&
          page == open.page &&
          speed == open.speed &&
          (position - expected).abs() <= jumpMs) {
        return false;
      }
      _close(t);
    }
    if (!playing || page == null || _segments.length >= maxSegments) {
      return false;
    }
    _open = (at: t, page: page, from: max(0, position), speed: speed);
    _segment++;
    return true;
  }

  /// A link in a frame played along: noted as such ([TakeLog.songLink]).
  void noteLink() => _link = true;

  /// A fresh reading at [t]: [page] was at [position]. The segment
  /// playing it ([segment], when given: that one only), if it's still
  /// open, is told from it: where it was at its start. One that would
  /// have started before its song's start (its player said it played
  /// before its sound started, its position held meanwhile) starts later
  /// instead, when the song's start sounded. A later reading tells it
  /// again, better.
  void anchor(
    int t, {
    required String page,
    required int position,
    int? segment,
  }) {
    final open = _open;
    if (open == null || open.page != page || t < open.at) return;
    if (segment != null && segment != _segment) return;
    final from = position - ((t - open.at) * open.speed).round();
    final at = from >= 0 ? open.at : t - (position / open.speed).round();
    _open = (at: at, page: page, from: max(0, from), speed: open.speed);
  }

  /// The segments noted, the one playing ended at [t].
  List<SongSegment> finish(int t) {
    _close(t);
    return List.unmodifiable(_segments);
  }

  void _close(int t) {
    final open = _open;
    _open = null;
    if (open == null || t <= open.at) return;
    _segments.add(
      SongSegment(
        at: open.at,
        to: t,
        page: open.page,
        from: open.from,
        speed: open.speed,
      ),
    );
  }
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
