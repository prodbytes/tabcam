/// Which way a phrase pass turns the tab: to the next neckline, or back to
/// the one before.
enum PassDirection {
  next,
  previous;

  static PassDirection? byName(Object? name) =>
      values.where((d) => d.name == name).firstOrNull;
}

/// One phrase pass, in a song's time: [at] its position, the tab turned
/// [direction] to neckline [line] (0 the first). [count] passes, recorded
/// on different times through the song, were averaged into it.
class PhrasePass {
  const PhrasePass(this.at, this.direction, this.line, {this.count = 1});

  final Duration at;
  final PassDirection direction;
  final int line;
  final int count;

  /// The neckline showing before it.
  int get from => direction == PassDirection.next ? line - 1 : line + 1;

  Map<String, Object?> toJson() => {
    'ms': at.inMilliseconds,
    'dir': direction.name,
    'line': line,
    if (count > 1) 'n': count,
  };

  /// Null when [json] isn't a pass (one from a newer app, or broken).
  static PhrasePass? fromJson(Object? json) {
    if (json is! Map) return null;
    final (ms, dir, line, n) = (
      json['ms'],
      PassDirection.byName(json['dir']),
      json['line'],
      json['n'] ?? 1,
    );
    if (ms is! int || ms < 0 || dir == null) return null;
    if (line is! int || line < 0 || n is! int || n < 1) return null;
    return PhrasePass(Duration(milliseconds: ms), dir, line, count: n);
  }

  @override
  bool operator ==(Object other) =>
      other is PhrasePass &&
      other.at == at &&
      other.direction == direction &&
      other.line == line &&
      other.count == count;

  @override
  int get hashCode => Object.hash(at, direction, line, count);

  @override
  String toString() => 'PhrasePass($at, ${direction.name}, $line, ×$count)';
}

/// When the tab turned while a song (one of the capture's recordings or
/// videos) played in Cam: its phrase passes, in order. Kept with the
/// capture (its `phrases`, by the song's page), apart from any file, so
/// Cam turns the tab by itself the next time the song plays ([auto-pass]).
class PhraseTimes {
  const PhraseTimes([this.passes = const []]);

  static const none = PhraseTimes();

  /// Passes this close, the same way, are one: they're merged at their
  /// average time.
  static const mergeWithin = Duration(seconds: 2);

  /// In order of [PhrasePass.at].
  final List<PhrasePass> passes;

  bool get isEmpty => passes.isEmpty;
  bool get isNotEmpty => passes.isNotEmpty;

  /// With a pass at [at] (the tab turned [direction] to [line]): merged
  /// into one the same way within [mergeWithin] of it (the nearest), at
  /// their average time (each pass of a merged one counting), the newer's
  /// [line] kept; else added.
  PhraseTimes add(Duration at, PassDirection direction, int line) {
    final list = [...passes];
    final near = _nearest(list, at, direction, -1);
    if (near < 0) {
      list.add(PhrasePass(at, direction, line));
    } else {
      list[near] = _merge(list[near], PhrasePass(at, direction, line));
      // Moved, it may now be within reach of another: one with it too.
      for (var i = near; ;) {
        final other = _nearest(list, list[i].at, direction, i);
        if (other < 0) break;
        list
          ..[other] = _merge(list[other], list[i])
          ..removeAt(i);
        i = other > i ? other - 1 : other;
      }
    }
    list.sort((a, b) => a.at.compareTo(b.at));
    return PhraseTimes(List.unmodifiable(list));
  }

  /// The pass in [list] the same way and nearest [at] within [mergeWithin]
  /// (not [skip]); -1 for none.
  static int _nearest(
    List<PhrasePass> list,
    Duration at,
    PassDirection direction,
    int skip,
  ) {
    var best = -1;
    Duration? gap;
    for (var i = 0; i < list.length; i++) {
      final p = list[i];
      if (i == skip || p.direction != direction) continue;
      final d = (p.at - at).abs();
      if (d <= mergeWithin && (gap == null || d < gap)) {
        best = i;
        gap = d;
      }
    }
    return best;
  }

  /// [older] and [newer] as one: their average time, the newer's line.
  static PhrasePass _merge(PhrasePass older, PhrasePass newer) {
    final count = older.count + newer.count;
    final ms =
        (older.at.inMilliseconds * older.count +
            newer.at.inMilliseconds * newer.count) /
        count;
    return PhrasePass(
      Duration(milliseconds: ms.round()),
      older.direction,
      newer.line,
      count: count,
    );
  }

  /// The neckline the passes show at [at]: the last one's before it, or
  /// before the first, where that one turns from (null without passes).
  int? lineAt(Duration at) {
    if (passes.isEmpty) return null;
    PhrasePass? last;
    for (final p in passes) {
      if (p.at > at) break;
      last = p;
    }
    return last?.line ?? passes.first.from;
  }

  List<Object?> toJson() => [for (final p in passes) p.toJson()];

  /// The passes in [json], in order; those it can't read are left out.
  factory PhraseTimes.fromJson(Object? json) {
    if (json is! List) return none;
    final list = [for (final p in json) ?PhrasePass.fromJson(p)]
      ..sort((a, b) => a.at.compareTo(b.at));
    return PhraseTimes(List.unmodifiable(list));
  }

  /// Every song's phrase times in [json] (by page ID), the empty left out.
  static Map<String, PhraseTimes> mapFromJson(
    Object? json,
    String Function(String) checkId,
  ) {
    if (json is! Map) return const {};
    final out = <String, PhraseTimes>{};
    for (final MapEntry(:key, :value) in json.entries) {
      if (key is! String) continue;
      try {
        final times = PhraseTimes.fromJson(value);
        if (times.isNotEmpty) out[checkId(key)] = times;
      } on FormatException {
        continue;
      }
    }
    return Map.unmodifiable(out);
  }

  static Map<String, Object?> mapToJson(Map<String, PhraseTimes> map) => {
    for (final MapEntry(:key, :value) in map.entries)
      if (value.isNotEmpty) key: value.toJson(),
  };

  @override
  String toString() => 'PhraseTimes($passes)';
}
