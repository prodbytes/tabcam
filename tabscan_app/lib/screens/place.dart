import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../library/library.dart';

/// Where the user is in the app: the tab, and the event open over it (its
/// Text view or its files, and the file open over them). Kept on this device (the
/// library's `place` meta file), so a reload or a restart opens where the
/// user was.
@immutable
class Place {
  const Place({this.tab, this.eventId, this.text = false, this.fileId});

  /// The tab's name ([HomeTab.name]).
  final String? tab;

  /// The event open, if one is.
  final String? eventId;

  /// Its Text view, not its files.
  final bool text;

  /// The file open over its list, if one is (its page's ID).
  final String? fileId;

  Place copyWith({
    String? tab,
    String? Function()? eventId,
    bool? text,
    String? Function()? fileId,
  }) => Place(
    tab: tab ?? this.tab,
    eventId: eventId == null ? this.eventId : eventId(),
    text: text ?? this.text,
    fileId: fileId == null ? this.fileId : fileId(),
  );

  Map<String, Object?> toJson() => {
    'tab': ?tab,
    'event': ?eventId,
    if (text) 'text': true,
    'file': ?fileId,
  };

  static Place fromJson(Map<String, Object?> json) => Place(
    tab: json['tab'] as String?,
    eventId: json['event'] as String?,
    text: json['text'] == true,
    fileId: json['file'] as String?,
  );
}

/// The [Place] of a library's app: read once at launch, written (soon
/// after) at every move.
class PlaceMemory {
  PlaceMemory._(this.library);

  static final Expando<PlaceMemory> _of = Expando();

  /// The memory of [library]'s app.
  static PlaceMemory of(Library library) =>
      _of[library] ??= PlaceMemory._(library);

  /// The meta file it's kept in.
  static const String metaName = 'place';

  final Library library;
  Place _place = const Place();
  Timer? _save;

  Place get place => _place;

  /// Where the user was last time.
  Future<Place> load() async {
    try {
      final json = await library.readMeta(metaName);
      if (json != null) {
        _place = Place.fromJson((jsonDecode(json) as Map).cast());
      }
    } on Object catch (e) {
      debugPrint('TabScan: place unreadable: $e');
    }
    return _place;
  }

  /// The user moved: [change] applied, saved half a second later.
  void update(Place Function(Place place) change) {
    _place = change(_place);
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 500), flush);
  }

  Future<void> flush() async {
    _save?.cancel();
    _save = null;
    try {
      await library.writeMeta(metaName, jsonEncode(_place.toJson()));
    } on Object catch (e) {
      debugPrint('TabScan: place not saved: $e');
    }
  }
}
