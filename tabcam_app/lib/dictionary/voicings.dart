/// Chord voicings on a guitar in standard tuning, found by itself: every
/// way to play the chord's notes within four frets, that a hand can hold
/// (four fingers, a barre counting as one), with the root (or the slash
/// chord's bass) as its lowest note, the best ones first.
library;

import 'music_theory.dart';

/// The open strings, low E to high E, as MIDI notes.
const List<int> standardTuning = [40, 45, 50, 55, 59, 64];

/// One way to play a chord: a fret per string, low to high, null for a
/// string not played.
class Voicing {
  Voicing(this.frets) : fingers = fingersOf(frets)!;

  final List<int?> frets;

  /// Fingers it takes, a barre counting as one.
  final int fingers;

  /// The lowest fret pressed (0 when every string is open).
  int get lowestFret => _lowestFret(frets);

  int get highestFret =>
      frets.whereType<int>().fold(0, (m, f) => f > m ? f : m);

  /// The fret the diagram starts at: 1 (with the nut) when the shape is
  /// low or uses open strings, else the lowest fret pressed.
  int get baseFret =>
      lowestFret <= 2 || frets.any((f) => f == 0) ? 1 : lowestFret;

  /// Whether a barre at [lowestFret] plays the shape.
  bool get barre => _withBarre(frets);

  /// The lowest string the barre covers, or null without one.
  int? get barreFrom => barre ? _barreStart(frets) : null;

  /// The strings played, low to high.
  int get strings => frets.whereType<int>().length;

  /// `x32010` (`x 10 12 10 12 10` past the ninth fret).
  String get label => frets
      .map((f) => f == null ? 'x' : '$f')
      .join(frets.any((f) => f != null && f > 9) ? ' ' : '');

  @override
  String toString() => label;
}

/// The lowest string a barre at the lowest fret would start from, when
/// at least two strings are at it and no open string lies above the
/// first, or null.
int? _barreStart(List<int?> frets) {
  final low = _lowestFret(frets);
  if (low == 0) return null;
  final at = [
    for (var s = 0; s < frets.length; s++)
      if (frets[s] == low) s,
  ];
  if (at.length < 2) return null;
  for (var s = at.first; s < frets.length; s++) {
    if (frets[s] == 0) return null;
  }
  return at.first;
}

int _lowestFret(List<int?> frets) {
  var low = 0;
  for (final f in frets) {
    if (f != null && f > 0 && (low == 0 || f < low)) low = f;
  }
  return low;
}

/// Whether [frets] is played with a barre: one is possible and either
/// the shape needs it (more than four strings pressed) or it covers
/// three or more strings at the barre's fret (as x02220 doesn't, and
/// xx7555 does).
bool _withBarre(List<int?> frets) {
  final from = _barreStart(frets);
  if (from == null) return false;
  final low = _lowestFret(frets);
  final pressed = frets.whereType<int>().where((f) => f > 0).length;
  final at = frets.where((f) => f == low).length;
  return pressed > 4 || at >= 3;
}

/// Fingers [frets] takes (a barre counting as one), or null when a hand
/// can't hold it (more than four).
int? fingersOf(List<int?> frets) {
  final pressed = frets.whereType<int>().where((f) => f > 0).length;
  if (pressed == 0) return 0;
  var count = pressed;
  if (_withBarre(frets)) {
    final low = _lowestFret(frets);
    count = 1;
    for (final f in frets) {
      if (f != null && f > low) count++;
    }
  }
  return count <= 4 ? count : null;
}

/// The voicings of [chord] worth showing, up the neck: the best [count]
/// by how easy and full they are, at most two starting at the same fret.
List<Voicing> voicingsOf(Chord chord, {int count = 8}) {
  final scored = [for (final v in allVoicings(chord)) (v, _score(v, chord))];
  scored.sort((a, b) => a.$2.compareTo(b.$2));
  final picked = <(Voicing, double)>[];
  final perBase = <int, int>{};
  for (final entry in scored) {
    final base = entry.$1.baseFret;
    if ((perBase[base] ?? 0) >= 2) continue;
    perBase[base] = (perBase[base] ?? 0) + 1;
    picked.add(entry);
    if (picked.length >= count) break;
  }
  picked.sort((a, b) {
    final c = a.$1.baseFret.compareTo(b.$1.baseFret);
    return c != 0 ? c : a.$2.compareTo(b.$2);
  });
  return [for (final (v, _) in picked) v];
}

/// Every voicing of [chord] a hand can hold, in no particular order.
List<Voicing> allVoicings(Chord chord) {
  final allowed = chord.pitchClasses;
  final required = chord.requiredPitchClasses;
  final bass = chord.bassPitchClass;
  final minStrings = required.length < 3 ? required.length : 3;
  // A power chord is its root, fifth and octave, not a six-string shape.
  final maxStrings = chord.quality.symbol == '5' ? 3 : 6;
  final seen = <String>{};
  final found = <Voicing>[];
  final frets = List<int?>.filled(6, null);

  void visit(int string, int position, bool started, bool ended) {
    if (string == 6) {
      final played = frets.whereType<int>().length;
      if (played < minStrings || played > maxStrings) return;
      final pcs = <int>{};
      int? lowest;
      for (var s = 0; s < 6; s++) {
        final f = frets[s];
        if (f == null) continue;
        final pc = (standardTuning[s] + f) % 12;
        lowest ??= pc;
        pcs.add(pc);
      }
      if (lowest != bass || !pcs.containsAll(required)) return;
      if (fingersOf(frets) == null) return;
      final key = frets.join(',');
      if (seen.add(key)) found.add(Voicing(List.of(frets)));
      return;
    }
    // Not played: before the first string played, or after the last (a
    // string skipped in the middle can't ring).
    frets[string] = null;
    visit(string + 1, position, started, started);
    if (ended) return;
    // No use going on when the strings left can't hold the notes missing.
    final have = <int>{
      for (var s = 0; s < string; s++)
        if (frets[s] case final f?) (standardTuning[s] + f) % 12,
    };
    if (required.difference(have).length > 6 - string) return;
    final open = standardTuning[string];
    for (var f = position; f <= position + 3; f++) {
      if (!allowed.contains((open + f) % 12)) continue;
      frets[string] = f;
      visit(string + 1, position, true, false);
    }
    if (position > 0 && position <= 2 && allowed.contains(open % 12)) {
      frets[string] = 0;
      visit(string + 1, position, true, false);
    }
    frets[string] = null;
  }

  for (var position = 0; position <= 12; position++) {
    visit(0, position, false, false);
  }
  return found;
}

/// Lower is better: low on the neck, few fingers, many strings, the top
/// strings played, no barre that isn't needed, no stretch, no open
/// string among the pressed ones (the higher the frets around it, the
/// more awkward), the fifth in.
double _score(Voicing v, Chord chord) {
  final frets = v.frets;
  var score = v.lowestFret * 1.5 + v.fingers * 3.0 + (6 - v.strings) * 4.0;
  // Top strings not played (a power chord is meant to leave them out).
  if (chord.quality.symbol != '5') {
    var s = 5;
    while (s >= 0 && frets[s] == null) {
      score += 6;
      s--;
    }
  }
  final pressed = frets.whereType<int>().where((f) => f > 0).length;
  if (v.barre && pressed <= 4) score += 2;
  if (v.lowestFret > 0) score += (v.highestFret - v.lowestFret) * 0.5;
  for (var i = 0; i < 6; i++) {
    if (frets[i] != 0) continue;
    score -= 0.5;
    final below = frets.take(i).whereType<int>().where((f) => f > 0);
    final above = frets.skip(i + 1).whereType<int>().where((f) => f > 0);
    if (below.isEmpty || above.isEmpty) continue;
    // Between pressed strings: the nearest on each side set how awkward.
    final near = [below.last, above.first].reduce((a, b) => a > b ? a : b);
    score += near * 0.75;
  }
  final pcs = {
    for (var i = 0; i < 6; i++)
      if (frets[i] case final f?) (standardTuning[i] + f) % 12,
  };
  for (final d in chord.quality.optional) {
    if (!pcs.contains(d.on(chord.root).pitchClass)) score += 2;
  }
  return score;
}
