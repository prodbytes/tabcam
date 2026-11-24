import 'package:flutter/foundation.dart';

/// A chord's voicing or a scale the user pinned in the dictionary for a
/// capture ([CaptureEvent.pins]): what the dictionary looks up to show it
/// again ([query]: `Cmaj7`, `A minor pentatonic scale`) and, for a
/// chord, the voicing pinned ([frets]: a fret per string, low E to high
/// E, null for a string not played). Kept in the capture's event.json,
/// so it syncs and is shared with it; the user never sees it as a file.
@immutable
class DictionaryPin {
  const DictionaryPin(this.query, [this.frets]);

  /// The longest [query] kept; longer ones are dropped when read.
  static const maxQuery = 80;

  /// The most pins a capture keeps; more are dropped when read.
  static const max = 48;

  final String query;
  final List<int?>? frets;

  bool get isChord => frets != null;

  Map<String, Object?> toJson() => {'query': query, 'frets': ?frets};

  /// [json] as a pin, or null when it isn't one (from another app, or
  /// changed by hand): a query of 1 to [maxQuery] characters, and frets,
  /// if any, six of them, each null or 0 to 24.
  static DictionaryPin? fromJson(Object? json) {
    if (json is! Map) return null;
    final query = json['query'];
    if (query is! String) return null;
    final trimmed = query.trim();
    if (trimmed.isEmpty || trimmed.length > maxQuery) return null;
    final frets = json['frets'];
    if (frets == null) return DictionaryPin(trimmed);
    if (frets is! List || frets.length != 6) return null;
    final parsed = <int?>[];
    for (final f in frets) {
      if (f == null) {
        parsed.add(null);
      } else if (f is int && f >= 0 && f <= 24) {
        parsed.add(f);
      } else {
        return null;
      }
    }
    if (parsed.every((f) => f == null)) return null;
    return DictionaryPin(trimmed, List.unmodifiable(parsed));
  }

  /// [json] (event.json's `pins`) as pins: the valid ones, each once, at
  /// most [max].
  static List<DictionaryPin> listFromJson(Object? json) {
    if (json is! List) return const [];
    final pins = <DictionaryPin>[];
    for (final item in json) {
      final pin = fromJson(item);
      if (pin == null || pins.contains(pin)) continue;
      pins.add(pin);
      if (pins.length == max) break;
    }
    return List.unmodifiable(pins);
  }

  @override
  bool operator ==(Object other) =>
      other is DictionaryPin &&
      other.query == query &&
      listEquals(other.frets, frets);

  @override
  int get hashCode =>
      Object.hash(query, frets == null ? null : Object.hashAll(frets!));

  @override
  String toString() => frets == null ? query : '$query $frets';
}
