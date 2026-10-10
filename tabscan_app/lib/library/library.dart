import 'package:flutter/foundation.dart';

import '../capture/media.dart';
import '../processing/page_filter.dart';
import 'scan.dart';
import 'scan_store.dart';

/// The user's scans, kept in a [ScanStore]; screens listen to it.
class Library extends ChangeNotifier {
  Library([ScanStore? store]) : _store = store ?? ScanStore();

  final ScanStore _store;
  List<Scan> _scans = const [];
  bool _loaded = false;

  /// Filtered pages already rendered, by page ID and filter.
  final Map<String, Uint8List> _filtered = {};

  List<Scan> get scans => _scans;
  bool get loaded => _loaded;

  /// Changes when a page's image changes (a rotation), so images reload.
  int get revision => _revision;
  int _revision = 0;

  Scan? byId(String id) {
    for (final s in _scans) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> load() async {
    _scans = await _store.list();
    _loaded = true;
    notifyListeners();
  }

  /// A new scan of [pages], titled with its date and time.
  Future<Scan> create(List<Uint8List> pages) async {
    final now = DateTime.now();
    var scan = Scan(id: newId(), title: defaultTitle(now), created: now);
    scan = await _addPages(scan, pages);
    _scans = [scan, ..._scans];
    notifyListeners();
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
    final updated = scan.copyWith(pages: [...scan.pages, ...added]);
    await _store.save(updated);
    return _update(updated);
  }

  Future<Scan> _addPages(Scan scan, List<Uint8List> pages) async {
    final added = <ScanPage>[];
    for (final bytes in pages) {
      final page = ScanPage(id: newId());
      await _store.putPage(scan.id, page, bytes);
      added.add(page);
    }
    final updated = scan.copyWith(pages: [...scan.pages, ...added]);
    await _store.save(updated);
    return updated;
  }

  Future<Scan> update(Scan scan) async {
    await _store.save(scan);
    return _update(scan);
  }

  Scan _update(Scan scan) {
    _scans = [for (final s in _scans) s.id == scan.id ? scan : s];
    notifyListeners();
    return scan;
  }

  Future<Scan> rotatePage(Scan scan, ScanPage page) async {
    final rotated = await rotatedPage(await _store.page(scan.id, page));
    await _store.putPage(scan.id, page, rotated);
    _filtered.removeWhere((key, _) => key.startsWith('${page.id}/'));
    _revision++;
    return _update(scan);
  }

  Future<Scan> deletePage(Scan scan, ScanPage page) async {
    final updated = scan.copyWith(
      pages: [
        for (final p in scan.pages)
          if (p.id != page.id) p,
      ],
    );
    await _store.save(updated);
    await _store.deletePage(scan.id, page);
    _filtered.removeWhere((key, _) => key.startsWith('${page.id}/'));
    return _update(updated);
  }

  Future<void> delete(Scan scan) async {
    await _store.delete(scan.id);
    for (final p in scan.pages) {
      _filtered.removeWhere((key, _) => key.startsWith('${p.id}/'));
    }
    _scans = [
      for (final s in _scans)
        if (s.id != scan.id) s,
    ];
    notifyListeners();
  }

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
}

/// A new scan's title: "Tab" and when it was scanned, e.g. "Tab 2026-10-10 14:05".
String defaultTitle(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Tab ${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
