import 'dart:async';

import 'package:flutter/foundation.dart';

import '../capture/media.dart';
import '../processing/page_filter.dart';
import 'capture_event.dart';
import 'event_store.dart';

/// The user's events, kept in a [EventStore]; screens listen to it, and so
/// does cloud sync ([localChanges]).
class Library extends ChangeNotifier {
  Library([EventStore? store, DateTime Function()? now])
    : _store = store ?? EventStore(),
      _now = now ?? DateTime.now;

  final EventStore _store;
  final DateTime Function() _now;

  /// Every event, newest first, tombstones included.
  List<CaptureEvent> _all = const [];
  List<CaptureEvent> _scans = const [];
  bool _loaded = false;

  /// Filtered pages already rendered, by page ID and filter.
  final Map<String, Uint8List> _filtered = {};

  /// The events to show, newest first (not the deleted ones).
  List<CaptureEvent> get events => _scans;

  /// Every event, deleted ones' tombstones included, for cloud sync.
  List<CaptureEvent> get all => _all;
  bool get loaded => _loaded;

  /// Changes when a page's image changes (a rotation), so images reload.
  int get revision => _revision;
  int _revision = 0;

  /// Changes each time the user changes an event (not when cloud sync
  /// brings one), so sync knows when there's something to upload.
  ValueListenable<int> get localChanges => _localChanges;
  final ValueNotifier<int> _localChanges = ValueNotifier(0);

  CaptureEvent? byId(String id) {
    for (final s in _scans) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> load() async {
    _set(await _store.list());
    _loaded = true;
    notifyListeners();
    if (!_ready.isCompleted) _ready.complete();
  }

  /// Done once the events have loaded: cloud sync waits for it.
  Future<void> get ready => _ready.future;
  final Completer<void> _ready = Completer();

  void _set(List<CaptureEvent> all) {
    _all = all..sort((a, b) => b.created.compareTo(a.created));
    _scans = [
      for (final s in _all)
        if (!s.isDeleted) s,
    ];
  }

  /// A new event of [pages], titled with its date and time.
  Future<CaptureEvent> create(List<Uint8List> pages) async {
    final now = _now();
    var event = CaptureEvent(
      id: newId(),
      title: defaultTitle(now),
      created: now,
    );
    event = await _addPages(event, pages);
    _set([event, ..._all]);
    _changed();
    return event;
  }

  Future<CaptureEvent> addPages(
    CaptureEvent event,
    List<Uint8List> pages,
  ) async => _update(await _addPages(event, pages));

  /// Adds picked photos and videos to the end of [event]. Photos get the
  /// Tab filter, as scanned pages do.
  Future<CaptureEvent> addMedia(CaptureEvent event, List<Media> media) async {
    final added = <EventPage>[];
    for (final m in media) {
      final page = EventPage(id: newId(), kind: m.kind, extension: m.extension);
      await _store.putPageFile(event.id, page, m.file);
      added.add(page);
    }
    return _save(event.copyWith(pages: [...event.pages, ...added]));
  }

  /// Adds a link to the end of [event] (see [parseLink]).
  Future<CaptureEvent> addLink(CaptureEvent event, Uri url, {String? title}) =>
      _save(
        event.copyWith(
          pages: [
            ...event.pages,
            EventPage.link(id: newId(), url: url, title: title),
          ],
        ),
      );

  Future<CaptureEvent> _addPages(
    CaptureEvent event,
    List<Uint8List> pages,
  ) async {
    final added = <EventPage>[];
    for (final bytes in pages) {
      final page = EventPage(id: newId());
      await _store.putPage(event.id, page, bytes);
      added.add(page);
    }
    final updated = event.copyWith(
      pages: [...event.pages, ...added],
      updated: _now(),
    );
    await _store.save(updated);
    return updated;
  }

  Future<CaptureEvent> update(CaptureEvent event) => _save(event);

  /// Saves the user's change to [event], as changed now.
  Future<CaptureEvent> _save(CaptureEvent event) async {
    final updated = event.copyWith(updated: _now());
    await _store.save(updated);
    return _update(updated);
  }

  CaptureEvent _update(CaptureEvent event) {
    _set([for (final s in _all) s.id == event.id ? event : s]);
    _changed();
    return event;
  }

  void _changed() {
    notifyListeners();
    _localChanges.value++;
  }

  /// Turns the page a quarter turn. The turned image is a new page (a new
  /// ID): page files never change once written, so cloud sync only has to
  /// look at which pages an event has.
  Future<CaptureEvent> rotatePage(CaptureEvent event, EventPage page) async {
    final rotated = await rotatedPage(await _store.page(event.id, page));
    final turned = EventPage(
      id: newId(),
      filter: page.filter,
      kind: page.kind,
      extension: page.extension,
    );
    await _store.putPage(event.id, turned, rotated);
    final updated = await _save(
      event.copyWith(
        pages: [for (final p in event.pages) p.id == page.id ? turned : p],
      ),
    );
    await _store.deletePage(event.id, page);
    _forget(page);
    _revision++;
    notifyListeners();
    return updated;
  }

  Future<CaptureEvent> deletePage(CaptureEvent event, EventPage page) async {
    final updated = await _save(
      event.copyWith(
        pages: [
          for (final p in event.pages)
            if (p.id != page.id) p,
        ],
      ),
    );
    await _store.deletePage(event.id, page);
    _forget(page);
    return updated;
  }

  /// Deletes [event] and its pages. One that has synced leaves a tombstone,
  /// so the deletion reaches the user's other devices.
  Future<void> delete(CaptureEvent event) async {
    await _removePages(event);
    if (event.owner == null) {
      await _store.delete(event.id);
      _set([
        for (final s in _all)
          if (s.id != event.id) s,
      ]);
      _changed();
    } else {
      final tombstone = CaptureEvent.tombstone(event, _now());
      await _store.save(tombstone);
      _update(tombstone);
    }
  }

  Future<void> _removePages(CaptureEvent event) async {
    for (final p in event.pages) {
      await _store.deletePage(event.id, p);
      _forget(p);
    }
  }

  void _forget(EventPage page) =>
      _filtered.removeWhere((key, _) => key.startsWith('${page.id}/'));

  // Cloud sync's side: what it brings isn't a local change.

  /// Takes [event] as cloud sync brought it (its pages already stored with
  /// [putPageStream]): saved and shown, and the local pages it no longer
  /// has deleted. Skipped, returning false, when the event changed here
  /// since it was [seen] (that change wins, and goes up next).
  Future<bool> applyRemote(CaptureEvent event, {CaptureEvent? seen}) async {
    final local = _byIdAll(event.id);
    if (local != null && seen != null && local.updated != seen.updated) {
      return false;
    }
    await _store.save(event);
    final kept = {for (final p in event.pages) p.fileName};
    for (final p in local?.pages ?? const <EventPage>[]) {
      if (!kept.contains(p.fileName)) {
        await _store.deletePage(event.id, p);
        _forget(p);
      }
    }
    _set([
      for (final s in _all)
        if (s.id != event.id) s,
      event,
    ]);
    if (local != null) _revision++;
    notifyListeners();
    return true;
  }

  /// Records that [event] syncs with [owner], without counting as a change.
  Future<void> setOwner(CaptureEvent event, String owner) async {
    final local = _byIdAll(event.id);
    if (local == null || local.owner == owner) return;
    final owned = local.copyWith(owner: owner);
    await _store.save(owned);
    _set([for (final s in _all) s.id == event.id ? owned : s]);
  }

  CaptureEvent? _byIdAll(String id) {
    for (final s in _all) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<bool> hasPage(String eventId, EventPage page) =>
      _store.hasPage(eventId, page);

  Future<(Stream<List<int>>, int)> pageStream(String eventId, EventPage page) =>
      _store.pageStream(eventId, page);

  Future<void> putPageStream(
    String eventId,
    EventPage page,
    Stream<List<int>> bytes,
  ) => _store.putPageStream(eventId, page, bytes);

  Future<String?> readMeta(String name) => _store.readMeta(name);

  Future<void> writeMeta(String name, String json) =>
      _store.writeMeta(name, json);

  /// The page's file as scanned or picked.
  Future<Uint8List> original(CaptureEvent event, EventPage page) =>
      _store.page(event.id, page);

  /// The page's file on disk (videos play from it); null on the web.
  Future<String?> path(CaptureEvent event, EventPage page) =>
      _store.pagePath(event.id, page);

  /// An image page with its filter applied (cached); a video as it is.
  Future<Uint8List> filtered(CaptureEvent event, EventPage page) async {
    if (!page.isImage) return original(event, page);
    final key = '${page.id}/${page.filter.name}';
    return _filtered[key] ??= await applyFilter(
      await original(event, page),
      page.filter,
    );
  }

  @override
  void dispose() {
    _localChanges.dispose();
    super.dispose();
  }
}

/// A new event's title: "Tab" and when it was scanned, e.g. "Tab 2026-10-10 14:05".
String defaultTitle(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Tab ${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
