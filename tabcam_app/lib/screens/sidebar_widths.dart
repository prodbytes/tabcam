import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../library/library.dart';
import '../library/meta_names.dart';

/// How wide the user has dragged each sidebar (the play-along player,
/// the dictionary, the metronome), app-wide: set on one screen, every screen's sidebar
/// is that wide. Kept on the device (the library's `sidebars` meta
/// file) once [load]ed, so it lasts between sessions; a sidebar not
/// dragged yet (or put back by a double tap on its edge) has its
/// default width. It also keeps which sidebars the user turned into a
/// panel under the screen ([isBelow]: the dictionary's Rotate button), and
/// how tall they dragged it ([dictionaryHeight]).
class SidebarWidths extends ChangeNotifier {
  SidebarWidths._();

  /// The app's.
  static final SidebarWidths instance = SidebarWidths._();

  /// The play-along player's sidebar.
  static const playAlong = 'playAlong';

  /// The dictionary's.
  static const dictionary = 'dictionary';

  /// The metronome's.
  static const metronome = 'metronome';

  /// How tall the dictionary is as a panel under the screen.
  static const dictionaryHeight = 'dictionaryHeight';

  /// The meta file's entry that lists the sidebars shown under the screen.
  static const belowName = 'below';

  /// The narrowest a sidebar is dragged.
  static const min = 160.0;

  /// The meta file they're kept in.
  static const metaName = MetaNames.sidebars;

  final Map<String, double> _widths = {};
  final Set<String> _below = {};
  Library? _library;

  /// The width [sidebar] was dragged to, or null for its default.
  double? of(String sidebar) => _widths[sidebar];

  /// [sidebar]'s width: dragged, else [fallback]; at least [least], at
  /// most [max] (the room the screen leaves it).
  double widthOf(
    String sidebar, {
    required double fallback,
    required double max,
    double least = min,
  }) {
    final width = _widths[sidebar] ?? fallback;
    return max <= least
        ? max.clamp(0.0, double.infinity)
        : width.clamp(least, max);
  }

  /// Whether [sidebar] shows as a panel under the screen, across it,
  /// instead of at its side.
  bool isBelow(String sidebar) => _below.contains(sidebar);

  /// Shows [sidebar] under the screen ([below]) or at its side, and keeps
  /// that on the device.
  void setBelow(String sidebar, bool below) {
    if (!(below ? _below.add(sidebar) : _below.remove(sidebar))) return;
    notifyListeners();
    save();
  }

  /// Sets [sidebar]'s width (saved when the drag ends, [save]).
  void set(String sidebar, double width) {
    if (_widths[sidebar] == width) return;
    _widths[sidebar] = width;
    notifyListeners();
  }

  /// Puts [sidebar] back to its default width.
  void reset(String sidebar) {
    if (_widths.remove(sidebar) == null) return;
    notifyListeners();
    save();
  }

  /// Reads the widths kept in [library], and keeps them there from now on.
  Future<void> load(Library library) async {
    _library = library;
    try {
      final json = await library.readMeta(metaName);
      if (json == null) return;
      final map = jsonDecode(json);
      if (map is! Map) return;
      for (final MapEntry(:key, :value) in map.entries) {
        if (key is String && value is num && value.isFinite && value > 0) {
          _widths[key] = value.toDouble();
        }
      }
      if (map[belowName] case final List<Object?> below) {
        _below.addAll(below.whereType<String>());
      }
      notifyListeners();
    } on Object catch (e) {
      debugPrint('TabCam: sidebar widths unreadable: $e');
    }
  }

  /// Keeps the widths on the device (after a drag).
  void save() {
    final library = _library;
    if (library == null) return;
    unawaited(
      library
          .writeMeta(
            metaName,
            jsonEncode({
              ..._widths,
              if (_below.isNotEmpty) belowName: _below.toList(),
            }),
          )
          .catchError((Object e) {
            debugPrint('TabCam: sidebar widths not saved: $e');
          }),
    );
  }

  /// Back to the defaults, kept nowhere (tests).
  @visibleForTesting
  void clear() {
    _widths.clear();
    _below.clear();
    _library = null;
    notifyListeners();
  }
}
