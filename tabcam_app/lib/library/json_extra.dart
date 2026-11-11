/// The keys of a JSON object (a page, an edit) that this version doesn't
/// know, written by a newer app: kept as they came, so saving the object
/// again (renamed, edited, copied) doesn't drop them.
library;

/// How deep a kept value may nest: anything deeper (no app writes it) is
/// left out, so reading and writing it can't run out of stack.
const int maxExtraDepth = 32;

/// The entries of [json] whose keys aren't [known]: plain JSON (null,
/// bools, finite numbers, strings, lists and string-keyed maps, at most
/// [maxExtraDepth] deep), unmodifiable copies. An entry that isn't is left
/// out whole. The known keys are never in it: they're read, and checked,
/// by their own code.
Map<String, Object?> unknownKeys(
  Map<Object?, Object?> json,
  Set<String> known,
) {
  final extra = <String, Object?>{};
  for (final MapEntry(:key, :value) in json.entries) {
    if (key is! String || known.contains(key)) continue;
    try {
      extra[key] = _copy(value, 1);
    } on _NotJson {
      // Not JSON: left out.
    }
  }
  return extra.isEmpty ? const {} : Map.unmodifiable(extra);
}

/// [extra]'s entries without [known]'s keys, to write after the known
/// ones: the known keys always win.
Iterable<MapEntry<String, Object?>> extraEntries(
  Map<String, Object?> extra,
  Set<String> known,
) => extra.entries.where((e) => !known.contains(e.key));

/// Whether [a] and [b] are the same JSON value (maps by their entries,
/// lists item by item).
bool jsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      if (!b.containsKey(key) || !jsonEquals(value, b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// A hash of [value] that agrees with [jsonEquals].
int jsonHash(Object? value) => switch (value) {
  final Map m => Object.hashAllUnordered([
    for (final MapEntry(:key, :value) in m.entries)
      Object.hash(key, jsonHash(value)),
  ]),
  final List l => Object.hashAll([for (final v in l) jsonHash(v)]),
  _ => value.hashCode,
};

class _NotJson implements Exception {
  const _NotJson();
}

Object? _copy(Object? value, int depth) {
  switch (value) {
    case null || bool() || String():
      return value;
    case final num n:
      if (!n.isFinite) throw const _NotJson();
      return n;
  }
  if (depth >= maxExtraDepth) throw const _NotJson();
  switch (value) {
    case final List l:
      return List<Object?>.unmodifiable([
        for (final v in l) _copy(v, depth + 1),
      ]);
    case final Map m:
      final copy = <String, Object?>{};
      for (final MapEntry(:key, :value) in m.entries) {
        if (key is! String) throw const _NotJson();
        copy[key] = _copy(value, depth + 1);
      }
      return Map<String, Object?>.unmodifiable(copy);
  }
  throw const _NotJson();
}
