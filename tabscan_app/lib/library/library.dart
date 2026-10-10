import 'dart:async';

import 'package:flutter/foundation.dart';

import '../capture/media.dart';
import '../processing/page_filter.dart';
import 'scan.dart';
import 'scan_store.dart';

/// The user's scans, kept in a [ScanStore]; screens listen to it, and so
/// does cloud sync ([localChanges]).
class Library extends ChangeNotifier {
  Library([ScanStore? store, DateTime Function()? now])
    : _store = store ?? ScanStore(),
      _now = now ?? DateTime.now;

  final ScanStore _store;
  final DateTime Function() _now;

  /// Every scan, newest first, tombstones included.
  List<Scan> _all = const [];
  List<Scan> _scans = const [];
  bool _loaded = false;

  /// Filtered pages already rendered, by page ID and filter.
  final Map<String, Uint8List> _filtered = {};

  /// The scans to show, newest first (not the deleted ones).
  List<Scan> get scans => _scans;

  /// Every scan, deleted ones' tombstones included, for cloud sync.
  List<Scan> get all => _all;
  bool get loaded => _loaded;

  /// Changes when a page's image changes (a rotation), so images reload.
  int get revision => _revision;
  int _revision = 0;

  /// Changes each time the user changes a scan (not when cloud sync
  /// brings one), so sync knows when there's something to upload.
  ValueListenable<int> get localChanges => _localChanges;
  final ValueNotifier<int> _localChanges = ValueNotifier(0);

  Scan? byId(String id) {
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

  /// Done once the scans have loaded: cloud sync waits for it.
  Future<void> get ready => _ready.future;
  final Completer<void> _ready = Completer();

  void _set(List<Scan> all) {
    _all = all..sort((a, b) => b.created.compareTo(a.created));
    _scans = [
      for (final s in _all)
        if (!s.isDeleted) s,
    ];
  }

  /// A new scan of [pages], titled with its date and time.
  Future<Scan> create(List<Uint8List> pages) async {
    final now = _now();
    var scan = Scan(id: newId(), title: defaultTitle(now), created: now);
    scan = await _addPages(scan, pages);
    _set([scan, ..._all]);
    _changed();
    return scan;
  }

  Future<Scan> addPages(Scan scan, List<Uint8List> pages) async =>
      _update(await _addPages(scan, pages));

  /// Adds picked photos and videos to the end of [scan]. Photos get the
  /// Tab filter, as scanned pages do.
  Future<Scan> addMedia(Scan scan, List<Media> media) async {
    final added = <ScanPage>[];
    for (final m in media) {
      final page = ScanPage(id: newId(), kind: m.kind, extension: m.extension);
      await _store.putPageFile(scan.id, page, m.file);
      added.add(page);
    }
    return _save(scan.copyWith(pages: [...scan.pages, ...added]));
  }

  Future<Scan> _addPages(Scan scan, List<Uint8List> pages) async {
    final added = <ScanPage>[];
    for (final bytes in pages) {
      final page = ScanPage(id: newId());
      await _store.putPage(scan.id, page, bytes);
      added.add(page);
    }
    final updated = scan.copyWith(
      pages: [...scan.pages, ...added],
      updated: _now(),
    );
    await _store.save(updated);
    return updated;
  }

  Future<Scan> update(Scan scan) => _save(scan);

  /// Saves the user's change to [scan], as changed now.
  Future<Scan> _save(Scan scan) async {
    final updated = scan.copyWith(updated: _now());
    await _store.save(updated);
    return _update(updated);
  }

  Scan _update(Scan scan) {
    _set([for (final s in _all) s.id == scan.id ? scan : s]);
    _changed();
    return scan;
  }

  void _changed() {
    notifyListeners();
    _localChanges.value++;
  }

  /// Turns the page a quarter turn. The turned image is a new page (a new
  /// ID): page files never change once written, so cloud sync only has to
  /// look at which pages a scan has.
  Future<Scan> rotatePage(Scan scan, ScanPage page) async {
    final rotated = await rotatedPage(await _store.page(scan.id, page));
    final turned = ScanPage(
      id: newId(),
      filter: page.filter,
      kind: page.kind,
      extension: page.extension,
    );
    await _store.putPage(scan.id, turned, rotated);
    final updated = await _save(
      scan.copyWith(
        pages: [for (final p in scan.pages) p.id == page.id ? turned : p],
      ),
    );
    await _store.deletePage(scan.id, page);
    _forget(page);
    _revision++;
    notifyListeners();
    return updated;
  }

  Future<Scan> deletePage(Scan scan, ScanPage page) async {
    final updated = await _save(
      scan.copyWith(
        pages: [
          for (final p in scan.pages)
            if (p.id != page.id) p,
        ],
      ),
    );
    await _store.deletePage(scan.id, page);
    _forget(page);
    return updated;
  }

  /// Deletes [scan] and its pages. One that has synced leaves a tombstone,
  /// so the deletion reaches the user's other devices.
  Future<void> delete(Scan scan) async {
    await _removePages(scan);
    if (scan.owner == null) {
      await _store.delete(scan.id);
      _set([
        for (final s in _all)
          if (s.id != scan.id) s,
      ]);
      _changed();
    } else {
      final tombstone = Scan.tombstone(scan, _now());
      await _store.save(tombstone);
      _update(tombstone);
    }
  }

  Future<void> _removePages(Scan scan) async {
    for (final p in scan.pages) {
      await _store.deletePage(scan.id, p);
      _forget(p);
    }
  }

  void _forget(ScanPage page) =>
      _filtered.removeWhere((key, _) => key.startsWith('${page.id}/'));

  // Cloud sync's side: what it brings isn't a local change.

  /// Takes [scan] as cloud sync brought it (its pages already stored with
  /// [putPageStream]): saved and shown, and the local pages it no longer
  /// has deleted. Skipped, returning false, when the scan changed here
  /// since it was [seen] (that change wins, and goes up next).
  Future<bool> applyRemote(Scan scan, {Scan? seen}) async {
    final local = _byIdAll(scan.id);
    if (local != null && seen != null && local.updated != seen.updated) {
      return false;
    }
    await _store.save(scan);
    final kept = {for (final p in scan.pages) p.fileName};
    for (final p in local?.pages ?? const <ScanPage>[]) {
      if (!kept.contains(p.fileName)) {
        await _store.deletePage(scan.id, p);
        _forget(p);
      }
    }
    _set([
      for (final s in _all)
        if (s.id != scan.id) s,
      scan,
    ]);
    if (local != null) _revision++;
    notifyListeners();
    return true;
  }

  /// Records that [scan] syncs with [owner], without counting as a change.
  Future<void> setOwner(Scan scan, String owner) async {
    final local = _byIdAll(scan.id);
    if (local == null || local.owner == owner) return;
    final owned = local.copyWith(owner: owner);
    await _store.save(owned);
    _set([for (final s in _all) s.id == scan.id ? owned : s]);
  }

  Scan? _byIdAll(String id) {
    for (final s in _all) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<bool> hasPage(String scanId, ScanPage page) =>
      _store.hasPage(scanId, page);

  Future<(Stream<List<int>>, int)> pageStream(String scanId, ScanPage page) =>
      _store.pageStream(scanId, page);

  Future<void> putPageStream(
    String scanId,
    ScanPage page,
    Stream<List<int>> bytes,
  ) => _store.putPageStream(scanId, page, bytes);

  Future<String?> readMeta(String name) => _store.readMeta(name);

  Future<void> writeMeta(String name, String json) =>
      _store.writeMeta(name, json);

  /// The page's file as scanned or picked.
  Future<Uint8List> original(Scan scan, ScanPage page) =>
      _store.page(scan.id, page);

  /// The page's file on disk (videos play from it); null on the web.
  Future<String?> path(Scan scan, ScanPage page) =>
      _store.pagePath(scan.id, page);

  /// An image page with its filter applied (cached); a video as it is.
  Future<Uint8List> filtered(Scan scan, ScanPage page) async {
    if (page.isVideo) return original(scan, page);
    final key = '${page.id}/${page.filter.name}';
    return _filtered[key] ??= await applyFilter(
      await original(scan, page),
      page.filter,
    );
  }

  @override
  void dispose() {
    _localChanges.dispose();
    super.dispose();
  }
}

/// A new scan's title: "Tab" and when it was scanned, e.g. "Tab 2026-10-10 14:05".
String defaultTitle(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Tab ${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
