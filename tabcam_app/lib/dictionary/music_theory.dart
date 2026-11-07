/// Music theory for the dictionary: notes and their spelling, chord
/// qualities and scale types, by degree ("1 b3 5 b7"), and how a query is
/// read as a chord, a scale, or neither.
///
/// Everything here runs on the device: there's no chord or scale data to
/// fetch, the notes are computed from the root and the degrees.
library;

/// A note: its letter (0 = C … 6 = B) and accidental (−2 … 2, flats
/// negative), which spell it (`E#` is not `F` in a C# chord).
class Note {
  const Note(this.letter, this.accidental);

  final int letter;
  final int accidental;

  static const _letters = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
  static const _naturals = [0, 2, 4, 5, 7, 9, 11];

  /// The pitch class, 0 (C) to 11 (B).
  int get pitchClass => (_naturals[letter] + accidental) % 12;

  /// `C#`, `Bb`, `E`, `F##`.
  String get name =>
      _letters[letter] +
      (accidental < 0 ? 'b' * -accidental : '#' * accidental);

  /// The note [semitones] up from this one, spelled [steps] letters up
  /// (a third above C# is E#, not F).
  Note up(int steps, int semitones) {
    final letter = (this.letter + steps) % 7;
    var accidental = (pitchClass + semitones - _naturals[letter]) % 12;
    if (accidental > 6) accidental -= 12;
    return Note(letter, accidental);
  }

  /// A spelling of [pitchClass], with sharps or, [flat], with flats.
  static Note of(int pitchClass, {bool flat = false}) {
    pitchClass %= 12;
    final natural = _naturals.indexOf(pitchClass);
    if (natural >= 0) return Note(natural, 0);
    return flat
        ? Note(_naturals.indexOf(pitchClass + 1), -1)
        : Note(_naturals.indexOf(pitchClass - 1), 1);
  }

  @override
  bool operator ==(Object other) =>
      other is Note && other.letter == letter && other.accidental == accidental;

  @override
  int get hashCode => Object.hash(letter, accidental);

  @override
  String toString() => name;
}

/// A degree of a chord or scale: `1`, `b3`, `#11`, `13`.
class Degree {
  const Degree._(this.number, this.accidental);

  /// The degree number (1 … 13).
  final int number;

  /// Flats negative.
  final int accidental;

  static final _pattern = RegExp(r'^([#b]*)(\d+)$');

  /// `b7`, `#11`, `9`.
  factory Degree.parse(String text) {
    final match = _pattern.firstMatch(text)!;
    final marks = match.group(1)!;
    return Degree._(
      int.parse(match.group(2)!),
      marks.split('').fold(0, (n, c) => n + (c == '#' ? 1 : -1)),
    );
  }

  static const _semitones = [0, 2, 4, 5, 7, 9, 11];

  /// Letters above the root.
  int get steps => (number - 1) % 7;

  /// Semitones above the root, within an octave.
  int get semitones => (_semitones[steps] + accidental) % 12;

  /// The degree's note, from [root].
  Note on(Note root) => root.up(steps, semitones);

  /// `b7`, `#11`.
  String get label =>
      '${accidental < 0 ? 'b' * -accidental : '#' * accidental}$number';

  @override
  String toString() => label;
}

/// A chord quality: its symbol after the root (`m7`), its degrees, and
/// which of them a voicing can leave out (the fifth of a seventh chord,
/// the ninth of an eleventh…).
class ChordQuality {
  const ChordQuality(this.symbol, this._degrees, {this._optional = ''});

  final String symbol;
  final String _degrees;
  final String _optional;

  List<Degree> get degrees =>
      _degrees.split(' ').map(Degree.parse).toList(growable: false);

  /// The degrees a voicing may leave out.
  List<Degree> get optional => _optional.isEmpty
      ? const []
      : _optional.split(' ').map(Degree.parse).toList(growable: false);

  /// The degrees every voicing must have.
  List<Degree> get required {
    final optional = this.optional.map((d) => d.label).toSet();
    return degrees.where((d) => !optional.contains(d.label)).toList();
  }
}

/// The chord qualities, by the symbols they're written with (lower case,
/// no spaces; `maj` for a capital M and the words in the app's
/// languages, see [_chordAliases]).
const Map<String, ChordQuality> chordQualities = {
  '': ChordQuality('', '1 3 5'),
  'm': ChordQuality('m', '1 b3 5'),
  '5': ChordQuality('5', '1 5'),
  'dim': ChordQuality('dim', '1 b3 b5'),
  'aug': ChordQuality('aug', '1 3 #5'),
  'sus2': ChordQuality('sus2', '1 2 5'),
  'sus4': ChordQuality('sus4', '1 4 5'),
  '6': ChordQuality('6', '1 3 5 6', optional: '5'),
  'm6': ChordQuality('m6', '1 b3 5 6', optional: '5'),
  '7': ChordQuality('7', '1 3 5 b7', optional: '5'),
  'maj7': ChordQuality('maj7', '1 3 5 7', optional: '5'),
  'm7': ChordQuality('m7', '1 b3 5 b7', optional: '5'),
  'mmaj7': ChordQuality('m(maj7)', '1 b3 5 7', optional: '5'),
  'dim7': ChordQuality('dim7', '1 b3 b5 bb7'),
  'm7b5': ChordQuality('m7b5', '1 b3 b5 b7'),
  '7sus4': ChordQuality('7sus4', '1 4 5 b7', optional: '5'),
  '7sus2': ChordQuality('7sus2', '1 2 5 b7', optional: '5'),
  'aug7': ChordQuality('aug7', '1 3 #5 b7'),
  '7b5': ChordQuality('7b5', '1 3 b5 b7'),
  'add9': ChordQuality('add9', '1 3 5 9', optional: '5'),
  'madd9': ChordQuality('madd9', '1 b3 5 9', optional: '5'),
  'add11': ChordQuality('add11', '1 3 5 11', optional: '5'),
  '69': ChordQuality('6/9', '1 3 5 6 9', optional: '5'),
  '9': ChordQuality('9', '1 3 5 b7 9', optional: '5'),
  'maj9': ChordQuality('maj9', '1 3 5 7 9', optional: '5'),
  'm9': ChordQuality('m9', '1 b3 5 b7 9', optional: '5'),
  '7b9': ChordQuality('7b9', '1 3 5 b7 b9', optional: '5'),
  '7#9': ChordQuality('7#9', '1 3 5 b7 #9', optional: '5'),
  '11': ChordQuality('11', '1 3 5 b7 9 11', optional: '3 5 9'),
  'm11': ChordQuality('m11', '1 b3 5 b7 9 11', optional: '5 9'),
  '13': ChordQuality('13', '1 3 5 b7 9 13', optional: '5 9'),
  'maj13': ChordQuality('maj13', '1 3 5 7 9 13', optional: '5 9'),
  'm13': ChordQuality('m13', '1 b3 5 b7 9 13', optional: '5 9'),
};

/// Other ways the qualities are written, normalised as [chordQualities]'s
/// keys are.
const Map<String, String> _chordAliases = {
  'maj': '',
  'major': '',
  'mayor': '',
  'maior': '',
  'min': 'm',
  'minor': 'm',
  'menor': 'm',
  '-': 'm',
  'o': 'dim',
  '°': 'dim',
  'º': 'dim',
  '+': 'aug',
  'sus': 'sus4',
  '7sus': '7sus4',
  'maj6': '6',
  'min6': 'm6',
  'minor6': 'm6',
  'dom7': '7',
  'maj7': 'maj7',
  'ma7': 'maj7',
  'Δ': 'maj7',
  'Δ7': 'maj7',
  'min7': 'm7',
  'minor7': 'm7',
  '-7': 'm7',
  'm(maj7)': 'mmaj7',
  'mmaj7': 'mmaj7',
  'minmaj7': 'mmaj7',
  '-maj7': 'mmaj7',
  'o7': 'dim7',
  '°7': 'dim7',
  'º7': 'dim7',
  'ø': 'm7b5',
  'ø7': 'm7b5',
  'm7-5': 'm7b5',
  'min7b5': 'm7b5',
  '7+': 'aug7',
  '+7': 'aug7',
  '7#5': 'aug7',
  '7-5': '7b5',
  'add2': 'add9',
  'madd2': 'madd9',
  'min9': 'm9',
  'maj9': 'maj9',
  '6/9': '69',
  '6add9': '69',
  'min11': 'm11',
  'min13': 'm13',
  '7-9': '7b9',
  '7+9': '7#9',
};

/// A scale type: its key (the English name, lower case, the l10n looks it
/// up) and its degrees.
class ScaleType {
  const ScaleType(this.key, String degrees) : _degrees = degrees;

  final String key;
  final String _degrees;

  List<Degree> get degrees =>
      _degrees.split(' ').map(Degree.parse).toList(growable: false);
}

/// The scale types, by key.
const Map<String, ScaleType> scaleTypes = {
  'major': ScaleType('major', '1 2 3 4 5 6 7'),
  'minor': ScaleType('minor', '1 2 b3 4 5 b6 b7'),
  'harmonic minor': ScaleType('harmonic minor', '1 2 b3 4 5 b6 7'),
  'melodic minor': ScaleType('melodic minor', '1 2 b3 4 5 6 7'),
  'major pentatonic': ScaleType('major pentatonic', '1 2 3 5 6'),
  'minor pentatonic': ScaleType('minor pentatonic', '1 b3 4 5 b7'),
  'blues': ScaleType('blues', '1 b3 4 b5 5 b7'),
  'major blues': ScaleType('major blues', '1 2 b3 3 5 6'),
  'dorian': ScaleType('dorian', '1 2 b3 4 5 6 b7'),
  'phrygian': ScaleType('phrygian', '1 b2 b3 4 5 b6 b7'),
  'lydian': ScaleType('lydian', '1 2 3 #4 5 6 7'),
  'mixolydian': ScaleType('mixolydian', '1 2 3 4 5 6 b7'),
  'locrian': ScaleType('locrian', '1 b2 b3 4 b5 b6 b7'),
  'phrygian dominant': ScaleType('phrygian dominant', '1 b2 3 4 5 b6 b7'),
  'lydian dominant': ScaleType('lydian dominant', '1 2 3 #4 5 6 b7'),
  'harmonic major': ScaleType('harmonic major', '1 2 3 4 5 b6 7'),
  'double harmonic': ScaleType('double harmonic', '1 b2 3 4 5 b6 7'),
  'whole tone': ScaleType('whole tone', '1 2 3 #4 #5 b7'),
  'diminished': ScaleType('diminished', '1 2 b3 4 b5 b6 6 7'),
  'dominant diminished': ScaleType(
    'dominant diminished',
    '1 b2 b3 3 #4 5 6 b7',
  ),
  'chromatic': ScaleType('chromatic', '1 b2 2 b3 3 4 #4 5 b6 6 b7 7'),
};

/// Other ways the scale types are named (English, Spanish and Portuguese,
/// lower case, accents off, one space between words).
const Map<String, String> _scaleAliases = {
  'ionian': 'major',
  'ionico': 'major',
  'jonico': 'major',
  'mayor': 'major',
  'maior': 'major',
  'natural minor': 'minor',
  'aeolian': 'minor',
  'eolico': 'minor',
  'eolio': 'minor',
  'menor': 'minor',
  'menor natural': 'minor',
  'm': 'minor',
  'min': 'minor',
  'harmonic': 'harmonic minor',
  'minor harmonic': 'harmonic minor',
  'menor armonica': 'harmonic minor',
  'menor harmonica': 'harmonic minor',
  'armonica menor': 'harmonic minor',
  'harmonica menor': 'harmonic minor',
  'melodic': 'melodic minor',
  'minor melodic': 'melodic minor',
  'jazz minor': 'melodic minor',
  'menor melodica': 'melodic minor',
  'melodica menor': 'melodic minor',
  'pentatonic': 'major pentatonic',
  'pentatonic major': 'major pentatonic',
  'pentatonica': 'major pentatonic',
  'pentatonica mayor': 'major pentatonic',
  'pentatonica maior': 'major pentatonic',
  'mayor pentatonica': 'major pentatonic',
  'maior pentatonica': 'major pentatonic',
  'pentatonic minor': 'minor pentatonic',
  'm pentatonic': 'minor pentatonic',
  'min pentatonic': 'minor pentatonic',
  'pentatonica menor': 'minor pentatonic',
  'menor pentatonica': 'minor pentatonic',
  'minor blues': 'blues',
  'blues menor': 'blues',
  'blues mayor': 'major blues',
  'blues maior': 'major blues',
  'dorico': 'dorian',
  'phrygian mode': 'phrygian',
  'frigio': 'phrygian',
  'lidio': 'lydian',
  'mixolidio': 'mixolydian',
  'locrio': 'locrian',
  'locrian mode': 'locrian',
  'frigio dominante': 'phrygian dominant',
  'lidio dominante': 'lydian dominant',
  'mayor armonica': 'harmonic major',
  'maior harmonica': 'harmonic major',
  'armonica mayor': 'harmonic major',
  'harmonica maior': 'harmonic major',
  'byzantine': 'double harmonic',
  'doble armonica': 'double harmonic',
  'dupla harmonica': 'double harmonic',
  'wholetone': 'whole tone',
  'tonos enteros': 'whole tone',
  'tons inteiros': 'whole tone',
  'whole half diminished': 'diminished',
  'whole half': 'diminished',
  'disminuida': 'diminished',
  'diminuta': 'diminished',
  'half whole diminished': 'dominant diminished',
  'half whole': 'dominant diminished',
  'disminuida dominante': 'dominant diminished',
  'diminuta dominante': 'dominant diminished',
  'cromatica': 'chromatic',
};

/// A chord: a root, a quality and perhaps another bass note (`G/B`).
class Chord {
  const Chord(this.root, this.quality, {this.bass});

  final Note root;
  final ChordQuality quality;
  final Note? bass;

  /// `C#m7`, `G/B`.
  String get name =>
      root.name + quality.symbol + (bass == null ? '' : '/${bass!.name}');

  /// The chord's notes, root first, as the degrees spell them.
  List<Note> get notes =>
      quality.degrees.map((d) => d.on(root)).toList(growable: false);

  /// The pitch classes a voicing must have (the root, the bass, and the
  /// degrees that aren't optional).
  Set<int> get requiredPitchClasses => {
    root.pitchClass,
    if (bass case final bass?) bass.pitchClass,
    for (final d in quality.required) d.on(root).pitchClass,
  };

  /// Every pitch class a voicing may have.
  Set<int> get pitchClasses => {
    if (bass case final bass?) bass.pitchClass,
    for (final n in notes) n.pitchClass,
  };

  /// The lowest note a voicing must have.
  int get bassPitchClass => (bass ?? root).pitchClass;

  /// The note of [pitchClass] in the chord, as the chord spells it.
  Note? spell(int pitchClass) {
    if (bass case final bass? when bass.pitchClass == pitchClass) return bass;
    return notes.where((n) => n.pitchClass == pitchClass).firstOrNull;
  }
}

/// A scale: a root and a type.
class Scale {
  const Scale(this.root, this.type);

  final Note root;
  final ScaleType type;

  /// The scale's notes, root first, as the degrees spell them.
  List<Note> get notes =>
      type.degrees.map((d) => d.on(root)).toList(growable: false);

  Set<int> get pitchClasses => {for (final n in notes) n.pitchClass};

  /// The note of [pitchClass] in the scale, as the scale spells it.
  Note? spell(int pitchClass) =>
      notes.where((n) => n.pitchClass == pitchClass).firstOrNull;
}

/// What a dictionary query is: a chord, a scale, or something else (a
/// song, to look up elsewhere).
sealed class Lookup {
  const Lookup();

  /// Reads [query]: a chord first (`C`, `Am7`, `F#m7b5`, `G/B`, `Do
  /// menor`), then a scale (`A minor pentatonic`, `D dorian`, `C major
  /// scale`); anything else is [Other]. `C major` is the chord; `C major
  /// scale` the scale.
  static Lookup of(String query) {
    final text = _normalise(query);
    if (text.isEmpty) return const Other();
    return parseChord(text) ?? parseScale(text) ?? const Other();
  }
}

class ChordLookup extends Lookup {
  const ChordLookup(this.chord);
  final Chord chord;
}

class ScaleLookup extends Lookup {
  const ScaleLookup(this.scale);
  final Scale scale;
}

class Other extends Lookup {
  const Other();
}

/// Lower case, accents off the letters that carry them in the names
/// (ré, fá, lá, pentatónica…), unicode accidentals as ASCII, one space
/// between words.
String _normalise(String query) {
  var text = query.trim();
  // A capital M is major before the lower-casing takes it.
  text = text.replaceAllMapped(
    RegExp(r'([A-Ga-g#b♯♭])M(?=\d|$|\s|/)'),
    (m) => '${m.group(1)}maj',
  );
  text = text.toLowerCase();
  const accents = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'é': 'e',
    'ê': 'e',
    'í': 'i',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ú': 'u',
    'ç': 'c',
    '♯': '#',
    '♭': 'b',
    '♮': '',
    '’': "'",
  };
  for (final e in accents.entries) {
    text = text.replaceAll(e.key, e.value);
  }
  return text.replaceAll(RegExp(r'\s+'), ' ');
}

/// The root at the start of [text] (`c#`, `bb`, `do#`, `reb`, `sol`),
/// and what follows it.
(Note, String)? _root(String text) {
  const solfege = {
    'do': 0,
    're': 1,
    'mi': 2,
    'fa': 3,
    'sol': 4,
    'la': 5,
    'si': 6,
    'ti': 6,
  };
  const letters = 'cdefgab';
  int? letter;
  var rest = text;
  for (final e in solfege.entries) {
    if (text.startsWith(e.key)) {
      letter = e.value;
      rest = text.substring(e.key.length);
      break;
    }
  }
  if (letter == null) {
    if (text.isEmpty || !letters.contains(text[0])) return null;
    letter = letters.indexOf(text[0]);
    rest = text.substring(1);
  }
  var accidental = 0;
  if (rest.startsWith('#')) {
    accidental = 1;
    rest = rest.substring(1);
  } else if (rest.startsWith('b') && _isFlat(rest)) {
    accidental = -1;
    rest = rest.substring(1);
  }
  return (Note(letter, accidental), rest);
}

/// What a chord's symbol may start with, after a flat (`bbm`, `ebmaj7`).
const _qualityStarts = [
  'm',
  'maj',
  'min',
  'dim',
  'aug',
  'sus',
  'add',
  'ø',
  'Δ',
  'º',
  '°',
  '+',
  '-',
];

/// Whether a `b` after the root letter is a flat (`bb`, `ab7`, `eb
/// minor`) rather than the start of a word (`blues`, `byzantine`).
bool _isFlat(String rest) {
  if (rest.length == 1) return true;
  final next = rest[1];
  if (next == ' ' || next == '/') return true;
  if (RegExp(r'[0-9#]').hasMatch(next)) return true;
  // `bm`, `bmaj7`, `bdim`: a quality starting after the flat.
  final after = rest.substring(1);
  for (final word in _qualityStarts) {
    if (after.startsWith(word)) return true;
  }
  return false;
}

/// [text] as a chord, or null.
ChordLookup? parseChord(String text) {
  final parsed = _root(text);
  if (parsed == null) return null;
  final (root, rest) = parsed;
  var symbol = rest;
  Note? bass;
  final slash = rest.indexOf('/');
  if (slash >= 0) {
    // `6/9` has no bass note.
    final bassText = rest.substring(slash + 1).trim();
    final bassParsed = _root(bassText);
    if (bassParsed != null && bassParsed.$2.isEmpty) {
      bass = bassParsed.$1;
      symbol = rest.substring(0, slash);
    } else if (!(rest.replaceAll(' ', '') == '6/9')) {
      return null;
    }
  }
  symbol = symbol.replaceAll(' ', '');
  // `C chord`, `Am acorde`.
  for (final word in ['chord', 'acorde']) {
    if (symbol.endsWith(word)) {
      symbol = symbol.substring(0, symbol.length - word.length);
    }
  }
  final key = _chordAliases[symbol] ?? symbol;
  final quality = chordQualities[key];
  if (quality == null) return null;
  return ChordLookup(Chord(root, quality, bass: bass));
}

/// [text] as a scale, or null.
ScaleLookup? parseScale(String text) {
  final parsed = _root(text);
  if (parsed == null) return null;
  final (root, rest) = parsed;
  final words = rest
      .trim()
      .split(' ')
      .where((w) => w.isNotEmpty)
      .where((w) => !const {'scale', 'mode', 'escala', 'modo'}.contains(w))
      .toList();
  final name = words.join(' ');
  final key = _scaleAliases[name] ?? name;
  final type = scaleTypes[key];
  if (type == null) return null;
  return ScaleLookup(Scale(root, type));
}
