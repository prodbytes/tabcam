import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../library/library.dart';
import '../library/meta_names.dart';

/// The song's delays kept on this device per audio output
/// (`TakeOutput.key`: its route and fingerprint), in ms: how much later
/// the song is heard through it than its player says, as the editor's
/// delay control set it and **Remember** kept it. A take through that
/// output (headphones) whose song wasn't found in its sound opens with
/// it. The library's meta `outdelays`, a device setting (kept in the
/// browser's storage on the web):
///
/// ```json
/// {"v": 1, "ms": {"bluetooth|3f9a1c07": 170}}
/// ```
abstract final class OutDelays {
  static const String metaName = MetaNames.outDelays;

  /// The furthest a kept delay goes either way, ms: earlier for a device
  /// that overstates its delay, later as far as AirPlay's.
  static const int least = -500;
  static const int most = 2500;

  /// The delays kept: none when there are none, or they can't be read.
  /// Read leniently: whole numbers only, kept within [least] and [most],
  /// zeros left out.
  static Future<Map<String, int>> read(Library library) async {
    try {
      final json = await library.readMeta(metaName);
      if (json == null) return const {};
      final kept = jsonDecode(json);
      final ms = kept is Map ? kept['ms'] : null;
      if (ms is! Map) return const {};
      return Map.unmodifiable({
        for (final MapEntry(:key, :value) in ms.entries)
          if (key is String)
            if (_ms(value) case final v? when v != 0) key: v,
      });
    } on Object catch (e) {
      debugPrint('TabCam: output delays unreadable: $e');
      return const {};
    }
  }

  /// Keeps [delays] (zeros left out, each within [least] and [most]).
  static Future<void> write(Library library, Map<String, int> delays) async {
    try {
      await library.writeMeta(
        metaName,
        jsonEncode({
          'v': 1,
          'ms': {
            for (final MapEntry(:key, :value) in delays.entries)
              if (value != 0) key: value.clamp(least, most),
          },
        }),
      );
    } on Object catch (e) {
      debugPrint('TabCam: output delays not kept: $e');
    }
  }

  static int? _ms(Object? value) => switch (value) {
    final int i => i.clamp(least, most),
    final double d when d.isFinite => d.round().clamp(least, most),
    _ => null,
  };
}
