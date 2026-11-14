import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../library/capture_event.dart';
import '../library/library.dart';
import '../library/meta_names.dart';
import 'place_address_stub.dart'
    if (dart.library.js_interop) 'place_address_web.dart'
    as platform;

/// Where the user is in the app: the tab, and the event open over it (its
/// Text view or its files, and the file or Cam open over them). Kept on this
/// device (the library's `place` meta file) in the apps, and in the
/// address on the web ([inAddress]), so a reload or a restart opens where
/// the user was.
@immutable
class Place {
  const Place({
    this.tab,
    this.eventId,
    this.text = false,
    this.fileId,
    this.cam = false,
  });

  /// The tab's name ([HomeTab.name]).
  final String? tab;

  /// The event open, if one is.
  final String? eventId;

  /// Its Text view, not its files.
  final bool text;

  /// The file open over its list, if one is (its page's ID).
  final String? fileId;

  /// Cam open over the event ([PlayAlongScreen]).
  final bool cam;

  /// A copy with these changed; another event (or none) closes Cam,
  /// unless [cam] says otherwise.
  Place copyWith({
    String? tab,
    String? Function()? eventId,
    bool? text,
    String? Function()? fileId,
    bool? cam,
  }) => Place(
    tab: tab ?? this.tab,
    eventId: eventId == null ? this.eventId : eventId(),
    text: text ?? this.text,
    fileId: fileId == null ? this.fileId : fileId(),
    cam: cam ?? (eventId == null && this.cam),
  );

  Map<String, Object?> toJson() => {
    'tab': ?tab,
    'event': ?eventId,
    if (text) 'text': true,
    'file': ?fileId,
    if (cam && eventId != null) 'cam': true,
  };

  static Place fromJson(Map<String, Object?> json) => Place(
    tab: json['tab'] as String?,
    eventId: json['event'] as String?,
    text: json['text'] == true,
    fileId: json['file'] as String?,
    cam: json['event'] != null && json['cam'] == true,
  );

  /// The address's parameters a place is written in:
  /// `?tab=<tab>&open=<event>&view=<text|files>&file=<file>&cam=1`. Home
  /// and no event open leave them out.
  static const Set<String> addressKeys = {'tab', 'open', 'view', 'file', 'cam'};

  /// A capture's link's parameters (`CaptureLink`): gone from the address
  /// once an event is open (the link's, or another the user moved to), so
  /// its key isn't left there, and kept only while the link the page
  /// opened at is still the address's ([PlaceMemory]).
  static const Set<String> linkKeys = {'c', 'k', 'f'};

  /// The place [address] holds (no event, Home, if it holds none). Bad
  /// IDs are left out.
  static Place fromAddress(Uri address) {
    final query = address.queryParameters;
    String? id(String name) {
      final id = query[name];
      if (id == null) return null;
      try {
        return checkId(id);
      } on FormatException {
        return null;
      }
    }

    final eventId = id('open');
    final tab = query['tab'];
    return Place(
      tab: tab != null && RegExp(r'^[a-z]{1,20}$').hasMatch(tab) ? tab : null,
      eventId: eventId,
      text: eventId != null && query['view'] == 'text',
      fileId: eventId == null ? null : id('file'),
      cam: eventId != null && query['cam'] == '1',
    );
  }

  /// [address] (the page's: its path, the app's base `/app/`, and its
  /// fragment kept) with this place in it. Other parameters stay, except
  /// a sign-in email's code, used at launch, and a capture's link, unless
  /// [keepLink] and no event is open.
  Uri inAddress(Uri address, {bool keepLink = false}) {
    final query = {...address.queryParameters}
      ..removeWhere(
        (key, _) =>
            addressKeys.contains(key) ||
            key == 'signin-code' ||
            ((eventId != null || !keepLink) && linkKeys.contains(key)),
      );
    if (tab case final tab? when tab != 'home') query['tab'] = tab;
    if (eventId case final id?) {
      query['open'] = id;
      query['view'] = text ? 'text' : 'files';
      if (fileId case final file?) query['file'] = file;
      if (cam) query['cam'] = '1';
    }
    return Uri(
      scheme: address.scheme,
      userInfo: address.userInfo,
      host: address.host,
      port: address.hasPort ? address.port : null,
      path: address.path,
      queryParameters: query.isEmpty ? null : query,
      fragment: address.hasFragment ? address.fragment : null,
    );
  }
}

/// The address the web app's page is at, which keeps its [Place].
abstract class PlaceAddress {
  Uri get current;

  /// Shows [address] in place of [current], adding no history entry.
  void replace(Uri address);

  /// Called each time the browser's Back (or Forward) moves to another
  /// history entry. Flutter's history handling then shows that entry's
  /// address, which may be an older place's, or the link the page was
  /// opened at, before it closes what's open (a route the place doesn't
  /// follow, Cam say, changes nothing in it).
  set onMoved(VoidCallback? moved);
}

/// The [Place] of a library's app: read once at launch, written (soon
/// after) at every move. On the web it's kept in the page's address
/// ([address]), at once: the library there is only in memory, and the
/// address lasts a reload (and is the place, copied to another tab).
class PlaceMemory {
  PlaceMemory._(this.library);

  static final Expando<PlaceMemory> _of = Expando();

  /// The memory of [library]'s app.
  static PlaceMemory of(Library library) =>
      _of[library] ??= PlaceMemory._(library);

  /// The meta file it's kept in.
  static const String metaName = MetaNames.place;

  /// The web page's address, which keeps the place there (null in the
  /// apps: the meta file does). Tests set their own.
  static PlaceAddress? get address => _address;
  static set address(PlaceAddress? address) {
    _address = address;
    _keepLink = null;
  }

  static PlaceAddress? _address = platform.browserAddress();

  /// Whether a capture's link stays in the address: only the one the page
  /// was opened at (by the link: the parameters in it at first sight),
  /// until an event opens. A link the browser's Back brings back later
  /// (Flutter's history handling restores the first entry's address)
  /// goes, so its key isn't shown again and a reload doesn't follow it.
  static bool? _keepLink;
  static bool _linkKept(PlaceAddress address) => _keepLink ??= address
      .current
      .queryParameters
      .keys
      .any(Place.linkKeys.contains);

  final Library library;
  Place _place = const Place();
  Timer? _save;

  Place get place => _place;

  /// Where the user was last time (on the web, the address's place).
  Future<Place> load() async {
    if (address case final address?) {
      _linkKept(address);
      address.onMoved = _write;
      return _place = Place.fromAddress(address.current);
    }
    try {
      final json = await library.readMeta(metaName);
      if (json != null) {
        _place = Place.fromJson((jsonDecode(json) as Map).cast());
      }
    } on Object catch (e) {
      debugPrint('TabCam: place unreadable: $e');
    }
    return _place;
  }

  /// The user moved: [change] applied, saved half a second later.
  void update(Place Function(Place place) change) {
    _place = change(_place);
    if (address != null) {
      _write();
      return;
    }
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 500), flush);
  }

  /// Writes the place in the web page's address.
  void _write() {
    final address = PlaceMemory.address;
    if (address == null) return;
    if (_place.eventId != null) _keepLink = false;
    // Moves that change nothing (the event screen remembers its view at
    // every rebuild) leave the address alone: browsers limit how often it
    // may change.
    final current = address.current;
    final next = _place.inAddress(current, keepLink: _linkKept(address));
    if (next != current) address.replace(next);
  }

  Future<void> flush() async {
    _save?.cancel();
    _save = null;
    if (address != null) return;
    try {
      await library.writeMeta(metaName, jsonEncode(_place.toJson()));
    } on Object catch (e) {
      debugPrint('TabCam: place not saved: $e');
    }
  }
}
