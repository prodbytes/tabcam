import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../library/library.dart';

/// Where the user is in the app: the tab, and the event open over it (its
/// Text view or its pages, and which page). Kept on this device (the
/// library's `place` meta file), so a reload or a restart opens where the
/// user was.
@immutable
class Place {
  const Place({this.tab, this.eventId, this.text = false, this.page = 0});

  /// The tab's name ([HomeTab.name]).
  final String? tab;

  /// The event open, if one is.
  final String? eventId;

  /// Its Text view, not its pages.
  final bool text;

  /// The page shown.
  final int page;

  Place copyWith({
    String? tab,
    String? Function()? eventId,
    bool? text,
    int? page,
  }) => Place(
    tab: tab ?? this.tab,
    eventId: eventId == null ? this.eventId : eventId(),
    text: text ?? this.text,
    page: page ?? this.page,
  );

  Map<String, Object?> toJson() => {
    'tab': ?tab,
    'event': ?eventId,
    if (text) 'text': true,
    if (page > 0) 'page': page,
  };

  static Place fromJson(Map<String, Object?> json) => Place(
    tab: json['tab'] as String?,
    eventId: json['event'] as String?,
    text: json['text'] == true,
    page: (json['page'] as num?)?.toInt() ?? 0,
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
