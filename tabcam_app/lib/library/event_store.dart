import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'capture_event.dart';
import 'event_store_memory.dart'
    if (dart.library.io) 'event_store_io.dart'
    as platform;
import 'meta_names.dart';

/// Where events are kept: files in the app's documents folder on Android,
/// iOS and the desktop (event_store_io.dart), memory on the web
/// (event_store_memory.dart, the device's settings in localStorage).
abstract class EventStore {
  factory EventStore() = platform.PlatformEventStore;

  /// Every event, newest first, tombstones included.
  Future<List<CaptureEvent>> list();

  /// Saves the event's details (not its pages' files).
  Future<void> save(CaptureEvent event);

  Future<void> delete(String eventId);

  /// Stores [bytes] as the page's file.
  Future<void> putPage(String eventId, EventPage page, Uint8List bytes);

  /// Stores a copy of [file] as the page's file, without reading it into
  /// memory where the platform has files (videos can be large).
  Future<void> putPageFile(String eventId, EventPage page, XFile file);

  /// The page's file, read.
  Future<Uint8List> page(String eventId, EventPage page);

  /// The page's file on disk, for players that stream from a path; null
  /// where there are no files (the web).
  Future<String?> pagePath(String eventId, EventPage page);

  Future<void> deletePage(String eventId, EventPage page);

  Future<bool> hasPage(String eventId, EventPage page);

  /// The page's file as a stream, and its length in bytes, for uploads
  /// that don't read videos into memory.
  Future<(Stream<List<int>>, int)> pageStream(String eventId, EventPage page);

  /// Stores [bytes], as they arrive, as the page's file (downloads). A
  /// failed download leaves no page behind.
  Future<void> putPageStream(
    String eventId,
    EventPage page,
    Stream<List<int>> bytes,
  );

  /// A small JSON document of the app's own, such as cloud sync's state
  /// or a device setting, by one of [MetaNames]; null if there's none. A
  /// name that fails `checkId` is refused (it names a file on the apps).
  Future<String?> readMeta(String name);

  Future<void> writeMeta(String name, String json);
}
