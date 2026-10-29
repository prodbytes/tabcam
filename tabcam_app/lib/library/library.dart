import 'dart:async';

import 'package:flutter/foundation.dart';

import '../capture/media.dart';
import '../processing/page_crop.dart';
import '../processing/page_filter.dart';
import 'capture_event.dart';
import 'event_store.dart';
import 'search.dart';

/// The user's events, kept in a [EventStore]; screens listen to it, and so
/// does cloud sync ([localChanges]).
class Library extends ChangeNotifier {
  Library([
    EventStore? store,
    DateTime Function()? now,
    Future<Uint8List?> Function(Uint8List photo)? crop,
  ]) : _store = store ?? EventStore(),
       _now = now ?? DateTime.now,
       _crop = crop ?? cropToPage;

  final EventStore _store;
  final DateTime Function() _now;

  /// Crops a photo added by hand to the page in it ([cropToPage]); null
  /// leaves it as it is.
  final Future<Uint8List?> Function(Uint8List photo) _crop;

  /// Every event, newest first, tombstones included.
  List<CaptureEvent> _all = const [];
  List<CaptureEvent> _scans = const [];
  bool _loaded = false;

  /// Filtered pages already rendered, by page ID and filter.
  final Map<String, Uint8List> _filtered = {};

  /// Pages cloud sync brings after their event shows ([expectPage]), by
  /// `<event id>/<file name>`: what needs one ([original], [path]) waits.
  final Map<String, Completer<void>> _arriving = {};

  /// The events to show, newest first (not the deleted ones).
  List<CaptureEvent> get events => _scans;

  /// The studies the user's own events are in, sorted (case and accents
  /// aside); none until one is set.
  List<String> get studies {
    final names = {
      for (final e in _scans)
        if (!e.isShared && e.study.isNotEmpty) e.study,
    }.toList();
    return names..sort((a, b) => fold(a).compareTo(fold(b)));
  }

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

  /// A copy of [event], as a new event of the user's own: "<title>
  /// (copy)", the same artist, study, text tab and pages (each a new page, its
  /// file copied), created now. It's never synced or shared, so it can be
  /// shared with other people than the original.
  Future<CaptureEvent> clone(CaptureEvent event) async {
    final now = _now();
    final id = newId();
    final pages = <EventPage>[];
    for (final page in event.pages) {
      if (page.isLink) {
        pages.add(
          EventPage.link(id: newId(), url: page.url!, title: page.title),
        );
        continue;
      }
      final copy = EventPage(
        id: newId(),
        filter: page.filter,
        kind: page.kind,
        extension: page.extension,
      );
      await _arrival(event.id, page);
      final (bytes, _) = await _store.pageStream(event.id, page);
      await _store.putPageStream(id, copy, bytes);
      pages.add(copy);
    }
    final copy = CaptureEvent(
      id: id,
      title: '${event.title} (copy)',
      artist: event.artist,
      study: event.study,
      created: now,
      pages: pages,
      tabText: event.tabText,
      tabTextCorrect: event.tabTextCorrect,
      tabTextDoubts: event.tabTextDoubts,
      hideImages: event.hideImages,
    );
    await _store.save(copy);
    _set([copy, ..._all]);
    _changed();
    return copy;
  }

  Future<CaptureEvent> addPages(
    CaptureEvent event,
    List<Uint8List> pages,
  ) async {
    final added = await _addPages(event, pages);
    return event.contributes ? added : _update(added);
  }

  /// Adds picked photos and videos to the end of [event]. Photos get the
  /// Tab filter, as scanned pages do, and are cropped and straightened to
  /// the page in them when one stands out ([cropToPage]: a JPEG then);
  /// otherwise, and videos always, they're kept as picked. On a capture the
  /// user [CaptureEvent.contributes] to, they're added to their own
  /// contribution instead ([addedPages] says which they are).
  Future<CaptureEvent> addMedia(CaptureEvent event, List<Media> media) async {
    final added = <EventPage>[];
    for (final m in media) {
      final page = m.kind == PageKind.image
          ? await _addPhoto(event, m)
          : await _addFile(event, m);
      added.add(page);
    }
    return _append(event, added);
  }

  /// Adds a link to the end of [event] (see [parseLink]), or of the user's
  /// contribution to it.
  Future<CaptureEvent> addLink(CaptureEvent event, Uri url, {String? title}) =>
      _append(event, [EventPage.link(id: newId(), url: url, title: title)]);

  /// Puts [added] (their files stored) at the end of [event]'s pages, or of
  /// the user's contribution when they contribute to it: as the event is
  /// now, not as it was (a read may have written its text meanwhile).
  Future<CaptureEvent> _append(
    CaptureEvent event,
    List<EventPage> added,
  ) async {
    if (event.contributes) {
      return await patchContribution(
            event.id,
            (pages) => [...pages, ...added],
          ) ??
          event;
    }
    return await patch(
          event.id,
          (now) => now.copyWith(pages: [...now.pages, ...added]),
        ) ??
        _save(event.copyWith(pages: [...event.pages, ...added]));
  }

  /// The pages a user adds to [event] go to: its own, or their
  /// contribution's when they contribute to it.
  static List<EventPage> addedPages(CaptureEvent event) =>
      event.contributes ? event.myContribution?.pages ?? const [] : event.pages;

  /// Changes the pages of the user's own contribution to [id] (made the
  /// first time), as it is now. It's a change of theirs (sync sends it), but
  /// not of the capture: its `updated` stays. Null when it's gone.
  Future<CaptureEvent?> patchContribution(
    String id,
    List<EventPage> Function(List<EventPage> pages) change,
  ) async {
    final now = _byIdAll(id);
    if (now == null || !now.contributes) return null;
    final mine = now.myContribution ?? Contribution(updated: _now());
    final pages = change(mine.pages);
    final updated = _update(
      now.copyWith(
        contributions: [mine.copyWith(pages: pages, updated: _now())],
      ),
    );
    await _store.save(updated);
    await _dropFiles(updated, mine.pages);
    return updated;
  }

  /// Deletes [page] from the user's own contribution to [event].
  Future<CaptureEvent?> deleteContributionPage(
    CaptureEvent event,
    EventPage page,
  ) => patchContribution(
    event.id,
    (pages) => [
      for (final p in pages)
        if (p.id != page.id) p,
    ],
  );

  /// The owner publishes [page], someone's contribution to [event]: it's
  /// copied into the capture's own pages, a new page with a file of its
  /// own (its [EventPage.from] says what it's a copy of), so everyone it's
  /// shared with, and its link's holders, see it.
  Future<CaptureEvent?> publish(CaptureEvent event, EventPage page) async {
    if (event.isShared || event.isPublished(page)) return event;
    final EventPage copy;
    if (page.isLink) {
      copy = EventPage.link(
        id: newId(),
        url: page.url!,
        title: page.title,
        from: page.id,
      );
    } else {
      copy = EventPage(
        id: newId(),
        filter: page.filter,
        kind: page.kind,
        extension: page.extension,
        title: page.title,
        from: page.id,
      );
      await _arrival(event.id, page);
      final (bytes, _) = await _store.pageStream(event.id, page);
      await _store.putPageStream(event.id, copy, bytes);
    }
    return patch(
      event.id,
      (now) => now.isPublished(page)
          ? now
          : now.copyWith(pages: [...now.pages, copy]),
    );
  }

  /// Takes [page] back out of the capture's pages, after [publish]: its
  /// copy goes; the contribution keeps the original.
  Future<CaptureEvent?> unpublish(CaptureEvent event, EventPage page) async {
    final now = _byIdAll(event.id);
    final copy = now?.publishedCopy(page);
    if (now == null || copy == null) return now;
    return deletePage(now, copy);
  }

  Future<EventPage> _addFile(CaptureEvent event, Media m) async {
    final page = EventPage(
      id: newId(),
      kind: m.kind,
      extension: m.extension,
      // A file is named after its file (photos' names are the picker's).
      title: m.kind == PageKind.image ? null : nameOfFile(m.file.name),
    );
    await _store.putPageFile(event.id, page, m.file);
    return page;
  }

  Future<EventPage> _addPhoto(CaptureEvent event, Media m) async {
    Uint8List? cropped;
    try {
      cropped = await _crop(await m.file.readAsBytes());
    } on Object catch (e) {
      debugPrint('TabCam: photo not cropped: $e');
    }
    if (cropped == null) return _addFile(event, m);
    final page = EventPage(id: newId(), extension: 'jpg');
    await _store.putPage(event.id, page, cropped);
    return page;
  }

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
    if (event.contributes) return _append(event, added);
    final updated = event.copyWith(
      pages: [...event.pages, ...added],
      updated: _now(),
    );
    await _store.save(updated);
    return updated;
  }

  Future<CaptureEvent> update(CaptureEvent event) => _save(event);

  /// Names page [pageId] of event [eventId] [name] (trimmed); an empty
  /// name goes back to the page's default (its kind and number, or a
  /// link's address).
  Future<CaptureEvent?> renamePage(String eventId, String pageId, String name) {
    final title = name.trim();
    EventPage renamed(EventPage p) => p.id == pageId
        ? p.copyWith(title: () => title.isEmpty ? null : title)
        : p;
    final now = _byIdAll(eventId);
    // One of the user's own contribution (a reader's file, or Cam's take).
    if (now != null && !now.pages.any((p) => p.id == pageId)) {
      return patchContribution(
        eventId,
        (pages) => [for (final p in pages) renamed(p)],
      );
    }
    return patch(
      eventId,
      (now) => now.copyWith(
        pages: [
          for (final p in now.pages)
            p.id == pageId
                ? p.copyWith(title: () => title.isEmpty ? null : title)
                : p,
        ],
      ),
    );
  }

  /// Applies [change] to the event [id] as it is now, so changes made
  /// meanwhile (pages added while a read ran) aren't overwritten by an
  /// older copy: memory first, then the store. Null when it's gone.
  Future<CaptureEvent?> patch(
    String id,
    CaptureEvent Function(CaptureEvent now) change,
  ) async {
    final now = _byIdAll(id);
    if (now == null) return null;
    final updated = _update(change(now).copyWith(updated: _now()));
    await _store.save(updated);
    return updated;
  }

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
    await _arrival(event.id, page);
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

  /// Puts the pages [order] names (page IDs, some or all of the event's) in
  /// that order. They take the places those pages had, so pages left out
  /// (images hidden from the list) stay where they are. The event as it is
  /// now is changed; IDs it no longer has are skipped.
  Future<CaptureEvent?> reorderPages(String eventId, List<String> order) =>
      patch(eventId, (now) {
        final byId = {for (final p in now.pages) p.id: p};
        final moved = [for (final id in order) ?byId[id]];
        final ids = {for (final p in moved) p.id};
        var next = 0;
        return now.copyWith(
          pages: [
            for (final p in now.pages) ids.contains(p.id) ? moved[next++] : p,
          ],
        );
      });

  Future<CaptureEvent> deletePage(CaptureEvent event, EventPage page) async {
    final updated = await _save(
      event.copyWith(
        pages: [
          for (final p in event.pages)
            if (p.id != page.id) p,
        ],
      ),
    );
    await _dropFiles(updated, [page]);
    return updated;
  }

  /// Deletes the files of [gone] (pages [event] had) that it no longer
  /// keeps: a published page and its contribution share one file.
  Future<void> _dropFiles(CaptureEvent event, Iterable<EventPage> gone) async {
    final kept = {for (final p in event.allPages) p.fileName};
    for (final p in gone) {
      if (!p.hasFile || kept.contains(p.fileName)) continue;
      pageGone(event.id, p);
      await _store.deletePage(event.id, p);
      _forget(p);
    }
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
    for (final p in {for (final p in event.allPages) p.fileName: p}.values) {
      pageGone(event.id, p);
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
    // Contributions sync on their own: the device's stay as they are.
    event = event.copyWith(contributions: local?.contributions ?? const []);
    await _store.save(event);
    await _dropFiles(event, local?.pages ?? const []);
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

  /// Records who shared [event] with the user and whether it's read only,
  /// without counting as a change (the grant changed, not the event).
  Future<void> setSharing(
    CaptureEvent event,
    String sharedBy, {
    required bool readOnly,
  }) async {
    final local = _byIdAll(event.id);
    if (local == null ||
        (local.sharedBy == sharedBy && local.readOnly == readOnly)) {
      return;
    }
    final updated = local.copyWith(sharedBy: sharedBy, readOnly: readOnly);
    await _store.save(updated);
    _set([for (final s in _all) s.id == event.id ? updated : s]);
    notifyListeners();
  }

  /// Takes [contribution] (someone's, by its [Contribution.by]) to
  /// [eventId] as cloud sync brought it: in place of theirs, or added. The
  /// files its pages no longer have go. Not a local change.
  Future<void> applyContribution(
    String eventId,
    Contribution contribution,
  ) async {
    final local = _byIdAll(eventId);
    if (local == null) return;
    final before = [
      for (final c in local.contributions)
        if (c.by == contribution.by || (local.contributes && c.by == null)) c,
    ];
    final others = [
      for (final c in local.contributions)
        if (!before.contains(c)) c,
    ];
    // A page whose ID is the capture's, or another's contribution's, isn't
    // taken: its file would be theirs.
    final taken = {
      for (final p in local.pages) p.id,
      for (final c in others) ...c.pages.map((p) => p.id),
    };
    final updated = local.copyWith(
      contributions: [
        ...others,
        contribution.copyWith(
          email: before.firstOrNull?.email,
          pages: [
            for (final p in contribution.pages)
              if (!taken.contains(p.id)) p,
          ],
        ),
      ],
    );
    await _store.save(updated);
    _set([for (final s in _all) s.id == eventId ? updated : s]);
    await _dropFiles(updated, [for (final c in before) ...c.pages]);
    notifyListeners();
  }

  /// Forgets the contribution of [by] to [eventId] (its folder is gone),
  /// and its files the capture doesn't keep. Not a local change.
  Future<void> removeContribution(String eventId, String by) async {
    final local = _byIdAll(eventId);
    if (local == null) return;
    final gone = [
      for (final c in local.contributions)
        if (c.by == by) c,
    ];
    if (gone.isEmpty) return;
    final updated = local.copyWith(
      contributions: [
        for (final c in local.contributions)
          if (c.by != by) c,
      ],
    );
    await _store.save(updated);
    _set([for (final s in _all) s.id == eventId ? updated : s]);
    await _dropFiles(updated, [for (final c in gone) ...c.pages]);
    notifyListeners();
  }

  /// Records whose contributions to [eventId] are: [by] for the user's
  /// own (once known), and the people's addresses ([emails], by identity)
  /// on the owner's devices. Not a local change.
  Future<void> nameContributions(
    String eventId, {
    String? by,
    Map<String, String> emails = const {},
  }) async {
    final local = _byIdAll(eventId);
    if (local == null) return;
    var changed = false;
    final named = <Contribution>[];
    for (final c in local.contributions) {
      final email = emails[c.by];
      if (by != null && c.by == null) {
        named.add(c.copyWith(by: by));
      } else if (email != null && email != c.email) {
        named.add(c.copyWith(email: email));
      } else {
        named.add(c);
        continue;
      }
      changed = true;
    }
    if (!changed) return;
    final updated = local.copyWith(contributions: named);
    await _store.save(updated);
    _set([for (final s in _all) s.id == eventId ? updated : s]);
    notifyListeners();
  }

  /// Removes [event] from this device only: no tombstone, nothing to sync
  /// (a capture no longer shared with the user).
  Future<void> removeLocal(CaptureEvent event) async {
    final local = _byIdAll(event.id);
    if (local == null) return;
    await _removePages(local);
    await _store.delete(local.id);
    _set([
      for (final s in _all)
        if (s.id != local.id) s,
    ]);
    notifyListeners();
  }

  /// Any event on the device by [id], tombstones included.
  CaptureEvent? byIdAll(String id) => _byIdAll(id);

  CaptureEvent? _byIdAll(String id) {
    for (final s in _all) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<bool> hasPage(String eventId, EventPage page) =>
      _store.hasPage(eventId, page);

  /// [page]'s file, for cloud sync to send. It doesn't wait for one still
  /// arriving ([expectPage]): sync sends only what the folder lacks, and
  /// what arrives comes from there.
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

  static String _arrivalKey(String eventId, EventPage page) =>
      '$eventId/${page.fileName}';

  /// Whether [page]'s file is still on its way (cloud sync brings it
  /// after its event): its preview shows that it's loading.
  bool isArriving(String eventId, EventPage page) =>
      _arriving.containsKey(_arrivalKey(eventId, page));

  /// Cloud sync shows an event before its pages' files, and brings them
  /// after: until [pageArrived], what needs [page] waits for it.
  void expectPage(String eventId, EventPage page) => _arriving.putIfAbsent(
    _arrivalKey(eventId, page),
    // Nothing may be waiting when it fails ([pageGone]).
    () => Completer<void>()..future.ignore(),
  );

  /// [page]'s file is stored ([putPageStream]): what waited for it goes
  /// on, and its previews show it.
  void pageArrived(String eventId, EventPage page) {
    final arrival = _arriving.remove(_arrivalKey(eventId, page));
    if (arrival == null) return;
    arrival.complete();
    notifyListeners();
  }

  /// [page] won't come (it, or its event, went): what waited for it fails.
  void pageGone(String eventId, EventPage page) {
    final arrival = _arriving.remove(_arrivalKey(eventId, page));
    if (arrival == null) return;
    arrival.completeError(StateError('${page.fileName} is gone'));
    notifyListeners();
  }

  Future<void> _arrival(String eventId, EventPage page) =>
      _arriving[_arrivalKey(eventId, page)]?.future ?? Future.value();

  /// The page's file as scanned or picked (once it's here: see
  /// [expectPage]).
  Future<Uint8List> original(CaptureEvent event, EventPage page) async {
    await _arrival(event.id, page);
    return _store.page(event.id, page);
  }

  /// The page's file on disk (videos play from it); null on the web.
  Future<String?> path(CaptureEvent event, EventPage page) async {
    await _arrival(event.id, page);
    return _store.pagePath(event.id, page);
  }

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

/// A file's name without its extension and path, for a page's name; null
/// when there's none to keep.
String? nameOfFile(String fileName) {
  final base = fileName.split(RegExp(r'[/\\]')).last;
  final dot = base.lastIndexOf('.');
  final name = (dot > 0 ? base.substring(0, dot) : base).trim();
  return name.isEmpty ? null : name;
}
