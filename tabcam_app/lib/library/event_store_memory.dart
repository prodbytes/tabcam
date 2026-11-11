import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'capture_event.dart';
import 'event_store.dart';
import 'meta_names.dart';
import 'meta_storage.dart';

/// Events kept in memory, for the web: they last until the tab is closed
/// (signed in, they come back with cloud sync). The device's settings
/// ([MetaNames.deviceSettings]) are also kept in [storage], the browser's
/// localStorage, so they last a reload; other metas, the events and their
/// files never are.
class PlatformEventStore implements EventStore {
  /// [storage] defaults to the browser's localStorage (none off the web).
  PlatformEventStore({MetaStorage? storage})
    : storage = storage ?? browserMetaStorage();

  /// Where the device's settings last a reload; null, only in memory.
  final MetaStorage? storage;

  /// The key a setting is kept under in [storage].
  static String storageKey(String name) => 'tabcam.meta.$name';

  final Map<String, CaptureEvent> _scans = {};
  final Map<String, Uint8List> _pages = {};
  final Map<String, String> _meta = {};

  String _key(String eventId, EventPage page) => '$eventId/${page.fileName}';

  @override
  Future<List<CaptureEvent>> list() async =>
      _scans.values.toList()..sort((a, b) => b.created.compareTo(a.created));

  @override
  Future<void> save(CaptureEvent event) async => _scans[event.id] = event;

  @override
  Future<void> delete(String eventId) async {
    _scans.remove(eventId);
    _pages.removeWhere((key, _) => key.startsWith('$eventId/'));
  }

  @override
  Future<void> putPage(String eventId, EventPage page, Uint8List bytes) async =>
      _pages[_key(eventId, page)] = bytes;

  @override
  Future<void> putPageFile(String eventId, EventPage page, XFile file) async =>
      _pages[_key(eventId, page)] = await file.readAsBytes();

  @override
  Future<Uint8List> page(String eventId, EventPage page) async =>
      _pages[_key(eventId, page)] ?? (throw StateError('No page ${page.id}'));

  @override
  Future<String?> pagePath(String eventId, EventPage page) async => null;

  @override
  Future<void> deletePage(String eventId, EventPage page) async =>
      _pages.remove(_key(eventId, page));

  @override
  Future<bool> hasPage(String eventId, EventPage page) async =>
      _pages.containsKey(_key(eventId, page));

  @override
  Future<(Stream<List<int>>, int)> pageStream(
    String eventId,
    EventPage page,
  ) async {
    final bytes = await this.page(eventId, page);
    return (Stream.value(bytes as List<int>), bytes.length);
  }

  @override
  Future<void> putPageStream(
    String eventId,
    EventPage page,
    Stream<List<int>> bytes,
  ) async {
    final builder = BytesBuilder(copy: false);
    await bytes.forEach(builder.add);
    _pages[_key(eventId, page)] = builder.takeBytes();
  }

  // Names are checked as on the apps, whose store names files by them.
  @override
  Future<String?> readMeta(String name) async {
    checkId(name);
    if (_meta[name] case final json?) return json;
    final storage = this.storage;
    if (storage == null || !MetaNames.deviceSettings.contains(name)) {
      return null;
    }
    try {
      return storage.getItem(storageKey(name));
    } on Object {
      return null; // storage disabled (a private window): memory only
    }
  }

  @override
  Future<void> writeMeta(String name, String json) async {
    _meta[checkId(name)] = json;
    if (storage case final storage?
        when MetaNames.deviceSettings.contains(name)) {
      try {
        storage.setItem(storageKey(name), json);
      } on Object {
        // Storage disabled or full: kept in memory, until the tab closes.
      }
    }
  }
}
