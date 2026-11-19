import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'capture_event.dart';
import 'library.dart';
import 'meta_names.dart';
import 'search.dart';

/// How Home orders its captures (**Sort by**).
enum LibrarySort {
  /// The ones not opened for longest first: never opened on this device
  /// before any opened (those newest first), then the opened ones from the
  /// longest ago. The default.
  leastOpened('leastopened'),

  /// The last opened first; one never opened counts as opened when it was
  /// made.
  recentlyOpened('recentlyopened'),

  /// The newest first (when made).
  newest('newest'),

  /// The oldest first.
  oldest('oldest'),

  /// By title, A to Z (case and accents aside).
  title('title'),

  /// By artist, A to Z, the ones without one last; the same artist's by
  /// title.
  artist('artist');

  const LibrarySort(this.key);

  /// Its name in the meta file.
  final String key;

  static LibrarySort? fromKey(Object? key) {
    for (final s in values) {
      if (s.key == key) return s;
    }
    return null;
  }
}

/// [events] (newest first, as [Library.events] has them) in [sort]'s
/// order, with [opened] the times they were last opened on this device.
/// Ties keep the newest first.
List<CaptureEvent> sortEvents(
  List<CaptureEvent> events,
  LibrarySort sort,
  Map<String, DateTime> opened,
) {
  final out = [...events];
  int newest(CaptureEvent a, CaptureEvent b) => b.created.compareTo(a.created);
  int Function(CaptureEvent, CaptureEvent) by;
  switch (sort) {
    case LibrarySort.leastOpened:
      by = (a, b) {
        final (x, y) = (opened[a.id], opened[b.id]);
        if (x == null || y == null) {
          if (x != y) return x == null ? -1 : 1;
          return newest(a, b);
        }
        final c = x.compareTo(y);
        return c != 0 ? c : newest(a, b);
      };
    case LibrarySort.recentlyOpened:
      by = (a, b) {
        final c = (opened[b.id] ?? b.created).compareTo(
          opened[a.id] ?? a.created,
        );
        return c != 0 ? c : newest(a, b);
      };
    case LibrarySort.newest:
      by = newest;
    case LibrarySort.oldest:
      by = (a, b) => a.created.compareTo(b.created);
    case LibrarySort.title:
      by = (a, b) {
        final c = fold(a.title).compareTo(fold(b.title));
        return c != 0 ? c : newest(a, b);
      };
    case LibrarySort.artist:
      by = (a, b) {
        final (x, y) = (fold(a.artist.trim()), fold(b.artist.trim()));
        if (x.isEmpty != y.isEmpty) return x.isEmpty ? 1 : -1;
        var c = x.compareTo(y);
        if (c == 0) c = fold(a.title).compareTo(fold(b.title));
        return c != 0 ? c : newest(a, b);
      };
  }
  mergeSort(out, compare: by);
  return out;
}

/// Home's order: the [sort] chosen, and when each capture was last opened
/// ([opened]), both kept on this device (the `libraryorder` meta file; the
/// browser's storage on the web). Opening a capture ([markOpened]) is
/// noted wherever it's opened from: a card, a link, a reload where the
/// user was.
class LibraryOrder extends ChangeNotifier {
  LibraryOrder._(this.library);

  static final Expando<LibraryOrder> _of = Expando();

  /// The order of [library]'s app.
  static LibraryOrder of(Library library) =>
      _of[library] ??= LibraryOrder._(library);

  /// The meta file it's kept in.
  static const String metaName = MetaNames.libraryOrder;

  /// The order before the user picks one.
  static const LibrarySort defaultSort = LibrarySort.leastOpened;

  final Library library;
  LibrarySort _sort = defaultSort;
  final Map<String, DateTime> _opened = {};
  Future<void>? _loading;

  /// The order chosen.
  LibrarySort get sort => _sort;

  /// When each capture was last opened on this device, by its ID.
  Map<String, DateTime> get opened => Map.unmodifiable(_opened);

  /// Reads the device's setting (once).
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final json = await library.readMeta(metaName);
      if (json == null) return;
      final map = jsonDecode(json);
      if (map is! Map) return;
      // What changed meanwhile (before it was read) wins.
      if (LibrarySort.fromKey(map['sort']) case final s? when !_sortSet) {
        _sort = s;
      }
      if (map['opened'] case final Map opened) {
        for (final MapEntry(:key, :value) in opened.entries) {
          if (key is String && value is int) {
            _opened.putIfAbsent(
              key,
              () => DateTime.fromMillisecondsSinceEpoch(value, isUtc: true),
            );
          }
        }
      }
      notifyListeners();
    } on Object catch (e) {
      debugPrint('TabCam: library order unreadable: $e');
    }
  }

  bool _sortSet = false;

  /// Orders Home by [sort] from now on.
  Future<void> setSort(LibrarySort sort) async {
    _sortSet = true;
    if (_sort == sort) return;
    _sort = sort;
    notifyListeners();
    await load();
    await _save();
  }

  /// Notes that the capture [eventId] was opened [at] (now).
  Future<void> markOpened(String eventId, {DateTime? at}) async {
    _opened[eventId] = (at ?? DateTime.now()).toUtc();
    notifyListeners();
    await load();
    await _save();
  }

  Future<void> _save() async {
    try {
      // Captures gone (deleted for good, unshared) are let go of; until the
      // library is read, none are.
      final known = library.loaded ? {for (final e in library.all) e.id} : null;
      await library.writeMeta(
        metaName,
        jsonEncode({
          'sort': _sort.key,
          'opened': {
            for (final MapEntry(:key, :value) in _opened.entries)
              if (known == null || known.contains(key))
                key: value.millisecondsSinceEpoch,
          },
        }),
      );
    } on Object catch (e) {
      debugPrint('TabCam: library order not saved: $e');
    }
  }
}
