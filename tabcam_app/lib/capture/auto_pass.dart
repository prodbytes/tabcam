import '../library/phrase_times.dart';

/// Auto-pass: turns Cam's tab by itself where it turned before while the
/// same song played ([PhraseTimes]), following the song's position as it
/// plays. Fed the position about every tenth of a second ([tick]), it
/// says the neckline to show: a pass's, as the song passes it; after a
/// jump (the song starting over at its end or its section's, «, », a
/// scrub, the first tick) the one the passes show there.
class AutoPass {
  /// A position this far past the last (or before it) is a jump, not
  /// playing on: more than a tick at the fastest speed, with room for a
  /// slow frame.
  static const jump = Duration(seconds: 2);

  Duration? _last;
  PhrasePass? _fired;

  /// Starts over: the next [tick] is taken as a jump (another song, or the
  /// song paused).
  void reset() {
    _last = null;
    _fired = null;
  }

  /// The song is at [at]: the neckline to show now, or null to leave it.
  int? tick(PhraseTimes times, Duration at) {
    final last = _last;
    _last = at;
    if (last == null || at < last || at - last > jump) {
      _fired = null;
      return times.lineAt(at);
    }
    int? line;
    for (final p in times.passes) {
      if (p.at > at) break;
      if (p.at <= last) continue;
      line = p.line;
      _fired = p;
    }
    return line;
  }

  /// The user passes [direction] at [at] while auto-pass is on: whether
  /// that's the pass auto-pass just made (the same way, within
  /// [PhraseTimes.mergeWithin] after it), which then doesn't turn the tab
  /// again. Once is all: a second pass turns it.
  bool absorbs(Duration at, PassDirection direction) {
    final fired = _fired;
    if (fired == null || fired.direction != direction) return false;
    final after = at - fired.at;
    if (after < Duration.zero || after > PhraseTimes.mergeWithin) return false;
    _fired = null;
    return true;
  }
}

/// A take's own phrase passes, from when its necklines showed ([marks]:
/// the first the one it started on): played along later, auto-pass turns
/// the tab as it turned in the take. The marks at the indexes in [skip]
/// (made with auto-pass off) are turns of the tab, but no passes: they
/// leave a gap, through which auto-pass stays where the pass before left
/// the tab (before the first pass, where that one turned from:
/// [PhraseTimes.lineAt]) and catches up at the next.
PhraseTimes takePhrases(
  List<(Duration, int)> marks, {
  Set<int> skip = const {},
}) {
  var times = PhraseTimes.none;
  for (var i = 1; i < marks.length; i++) {
    if (skip.contains(i)) continue;
    final (at, line) = marks[i];
    final before = marks[i - 1].$2;
    if (line == before) continue;
    times = times.add(
      at,
      line > before ? PassDirection.next : PassDirection.previous,
      line,
    );
  }
  return times;
}
