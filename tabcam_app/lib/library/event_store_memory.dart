import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'capture_event.dart';
import 'event_store.dart';

/// Events kept in memory, for the web: they last until the tab is closed.
class PlatformEventStore implements EventStore {
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

  @override
  Future<String?> readMeta(String name) async => _meta[name];

  @override
  Future<void> writeMeta(String name, String json) async => _meta[name] = json;
}
