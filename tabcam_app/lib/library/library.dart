import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

import '../capture/media.dart';
import '../capture/take_log.dart';
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
        if (!s.isDeleted && !s.isTrashed) s,
    ];
  }

  /// The user's own events in the trash ([CaptureEvent.trashed]), the
  /// latest deleted first: hidden, kept until restored ([restore]) or
  /// purged ([purge]).
  List<CaptureEvent> get trashed => [
    for (final s in _all)
      if (s.isTrashed && !s.isDeleted && !s.isShared) s,
  ]..sort((a, b) => b.trashed!.compareTo(a.trashed!));

  /// The user's own events shown, with files in their trash
  /// ([CaptureEvent.deletedPages]).
  List<CaptureEvent> get withDeletedPages => [
    for (final s in _scans)
      if (!s.isShared && s.deletedPages.isNotEmpty) s,
  ];

  /// Whether there's anything in the trash to restore or purge.
  bool get hasTrash => trashed.isNotEmpty || withDeletedPages.isNotEmpty;

  /// A new event of [pages], titled [title], or with its date and time.
  Future<CaptureEvent> create(List<Uint8List> pages, {String? title}) async {
    final now = _now();
    final name = title?.trim() ?? '';
    var event = CaptureEvent(
      id: newId(),
      title: name.isEmpty ? defaultTitle(now) : name,
      created: now,
    );
    event = await _addPages(event, pages);
    _set([event, ..._all]);
    _changed();
    return event;
  }

  /// A copy of [event], as a new event of the user's own: "<title>
  /// (copy)", the same artist, study, text tab and pages, created now. It's
  /// never synced or shared, so it can be shared with other people than
  /// the original. Each page is a new page, but its file isn't copied: it
  /// shows the original's ([EventPage.source], copy on write) until it has
  /// to be its own ([_keepCopies], [ownFiles]). On a capture shared with
  /// the user, the phrase passes are theirs where they have some. It
  /// keeps which page of the original each of its pages is
  /// ([CaptureEvent.clonedPages]), so the user's copy of a shared capture
  /// can catch up with it ([copyToAdd]).
  Future<CaptureEvent> clone(CaptureEvent event) async {
    final now = _now();
    final id = newId();
    // A video's edit names its track by ID, a take's log its songs, and
    // phrase times their song: the copy's.
    final ids = {for (final page in event.pages) page.id: newId()};
    final pages = [
      for (final page in event.pages)
        _clonePage(page, ids[page.id]!, ids, event.id),
    ];
    final phrases = {...event.phrases, ...?event.myContribution?.phrases};
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
      pins: event.pins,
      phrases: {
        for (final MapEntry(:key, :value) in phrases.entries) ?ids[key]: value,
      },
      clonedFrom: event.id,
      clonedPages: ids,
    );
    await _store.save(copy);
    _set([copy, ..._all]);
    _changed();
    return copy;
  }

  /// Where what the user adds to [event] goes: [event] itself, or, on a
  /// capture shared with them (only its owner changes it), their own copy
  /// of it: the newest one they have ([CaptureEvent.clonedFrom]), caught
  /// up with what the owner added since ([_caughtUp]), or a new [clone],
  /// made now.
  Future<CaptureEvent> copyToAdd(CaptureEvent event) async {
    if (!event.isShared) return event;
    final copy = copyOf(event.id);
    if (copy == null) return clone(event);
    final caught = _caughtUp(copy, _byIdAll(event.id) ?? event);
    return caught == null ? copy : _save(caught);
  }

  /// [page] of capture [origin] as a clone's page [id]: all of it, as its
  /// JSON has it (so whatever a page keeps comes too, a newer app's keys
  /// as well), but its file is the original's ([EventPage.source], copy
  /// on write; a clone of a clone's, the first original's), without the
  /// original's kept render (a file of the original's folder), and the
  /// pages its edit and take log name are the clone's ([ids], the
  /// original's page IDs to the clone's).
  static EventPage _clonePage(
    EventPage page,
    String id,
    Map<String, String> ids,
    String origin,
  ) {
    final copy = EventPage.fromJson(
      {...page.toJson(), 'id': id}
        ..remove('source')
        ..remove('render'),
    );
    if (!copy.hasFile) return copy;
    return copy.copyWith(
      edit: () => page.edit?.copyWith(trackId: ids[page.edit?.trackId]),
      takeLog: page.takeLog?.withPages(ids),
      source: () => page.source ?? FileOrigin(origin, page.id),
    );
  }

  /// [copy], the user's copy of [original] (a capture shared with them),
  /// caught up with what the owner added since it was made: each of the
  /// original's pages it has never taken ([CaptureEvent.clonedPages]),
  /// added at its end as [clone] adds them (the original's file, its take
  /// log); the phrase passes of each song it took, where the copy has
  /// none of its own for it; and the song found in a take's sound (its
  /// log's sync), where the copy's log has none. A page the user deleted
  /// from their copy, or changed, stays as they left it. Null when there's
  /// nothing to catch up.
  ///
  /// A copy made before [CaptureEvent.clonedPages] was kept knows the
  /// pages still showing the original's files; any other page of the
  /// original made before the copy is taken as there when it was made.
  CaptureEvent? _caughtUp(CaptureEvent copy, CaptureEvent original) {
    final taken = {...copy.clonedPages};
    if (taken.isEmpty) {
      for (final p in [...copy.pages, ...copy.deletedPages]) {
        if (p.source case final from? when from.eventId == original.id) {
          taken[from.pageId] = p.id;
        }
      }
      for (final p in original.pages) {
        final made = timeOfId(p.id);
        if (made != null && !made.isAfter(copy.created)) {
          taken.putIfAbsent(p.id, () => '');
        }
      }
    }
    final fresh = [
      for (final p in original.pages)
        if (!taken.containsKey(p.id)) p,
    ];
    for (final p in fresh) {
      taken[p.id] = newId();
    }
    // The original's page IDs to the copy's, where the copy's is known.
    final ids = {
      for (final MapEntry(:key, :value) in taken.entries)
        if (value.isNotEmpty) key: value,
    };
    final theirs = {for (final p in original.pages) p.id: p};
    final mine = {for (final MapEntry(:key, :value) in ids.entries) value: key};
    var changed = fresh.isNotEmpty || !mapEquals(taken, copy.clonedPages);

    // A take's song found in its sound since: the owner's, where the
    // copy's log has none.
    final pages = <EventPage>[];
    for (final p in copy.pages) {
      final log = p.takeLog;
      final sync = theirs[mine[p.id]]?.takeLog?.withPages(ids).sync;
      if (log != null && log.sync == null && sync != null) {
        pages.add(p.copyWith(takeLog: log.withSync(sync)));
        changed = true;
      } else {
        pages.add(p);
      }
    }
    for (final p in fresh) {
      pages.add(_clonePage(p, ids[p.id]!, ids, original.id));
    }

    // The passes of the songs it took, where it has none of its own (an
    // empty list is its own too: passes the user cleared there).
    final passes = {...original.phrases, ...?original.myContribution?.phrases};
    final phrases = {...copy.phrases};
    for (final MapEntry(key: theirId, value: id) in ids.entries) {
      final times = passes[theirId];
      if (times == null || times.isEmpty) continue;
      if (!pages.any((p) => p.id == id)) continue;
      if (phrases.containsKey(id)) continue;
      phrases[id] = times;
      changed = true;
    }
    if (!changed) return null;
    return copy.copyWith(pages: pages, phrases: phrases, clonedPages: taken);
  }

  /// The user's newest copy of capture [id] ([CaptureEvent.clonedFrom]),
  /// if they have one.
  CaptureEvent? copyOf(String id) {
    for (final e in _scans) {
      if (e.clonedFrom == id && !e.isShared) return e;
    }
    return null;
  }

  /// Adds scanned [pages] to the end of [event], or of the user's copy of
  /// it when it's shared with them ([copyToAdd]): the event they went to.
  Future<CaptureEvent> addPages(
    CaptureEvent event,
    List<Uint8List> pages,
  ) async => _update(await _addPages(await copyToAdd(event), pages));

  /// Adds picked photos and videos to the end of [event]. Photos get the
  /// Tab filter, as scanned pages do, and are cropped and straightened to
  /// the page in them when one stands out ([cropToPage]: a JPEG then);
  /// otherwise, and videos always, they're kept as picked. On a capture
  /// shared with the user, they're added to their own copy of it instead
  /// ([copyToAdd]); the event they went to is returned. [take]: Cam's
  /// takes, marked so ([EventPage.take]), each with [takeLog] if given
  /// ([EventPage.takeLog]: Cam adds one take at a time).
  Future<CaptureEvent> addMedia(
    CaptureEvent event,
    List<Media> media, {
    bool take = false,
    TakeLog? takeLog,
  }) async {
    event = await copyToAdd(event);
    final added = <EventPage>[];
    for (final m in media) {
      final page = m.kind == PageKind.image
          ? await _addPhoto(event, m)
          : await _addFile(
              event,
              m,
              take: take,
              takeLog: take ? takeLog : null,
            );
      added.add(page);
    }
    return _append(event, added);
  }

  /// Adds a link to the end of [event] (see [parseLink]), or of the user's
  /// copy of it when it's shared with them ([copyToAdd]).
  Future<CaptureEvent> addLink(
    CaptureEvent event,
    Uri url, {
    String? title,
  }) async => _append(await copyToAdd(event), [
    EventPage.link(id: newId(), url: url, title: title),
  ]);

  /// Puts [added] (their files stored) at the end of [event]'s pages: as
  /// the event is now, not as it was (a read may have written its text
  /// meanwhile).
  Future<CaptureEvent> _append(
    CaptureEvent event,
    List<EventPage> added,
  ) async {
    return await patch(
          event.id,
          (now) => now.copyWith(pages: [...now.pages, ...added]),
        ) ??
        _save(event.copyWith(pages: [...event.pages, ...added]));
  }

  /// Changes the pages of the user's own contribution to [id] (made the
  /// first time), as it is now. It's a change of theirs (sync sends it), but
  /// not of the capture: its `updated` stays. Null when it's gone.
  Future<CaptureEvent?> patchContribution(
    String id,
    List<EventPage> Function(List<EventPage> pages) change,
  ) async {
    final now = _byIdAll(id);
    if (now == null || !now.isShared) return null;
    final mine = now.myContribution ?? Contribution(updated: _now());
    final pages = change(mine.pages);
    final kept = {for (final p in pages) p.id};
    final gone = [
      for (final p in mine.pages)
        if (!kept.contains(p.id)) p,
    ];
    final updated = _update(
      now.copyWith(
        contributions: [
          mine.copyWith(
            pages: pages,
            phrases: _phrasesWithout(
              _songPhrasesKept(now, mine.phrases, gone),
              gone,
            ),
            updated: _now(),
          ),
        ],
      ),
    );
    await _store.save(updated);
    await _dropFiles(updated, mine.pages);
    return updated;
  }

  /// [times] without those of the files [gone]: a file's phrase passes go
  /// with it. (Only theirs: others may be of files still on their way.)
  static Map<String, PhraseTimes> _phrasesWithout(
    Map<String, PhraseTimes> times,
    Iterable<EventPage> gone,
  ) {
    final ids = {for (final p in gone) p.id};
    return {
      for (final MapEntry(:key, :value) in times.entries)
        if (!ids.contains(key)) key: value,
    };
  }

  /// [phrases] (the capture's, or the user's own contribution's) with, for
  /// each song a take of [gone] played along with that has no passes kept
  /// (none recorded for it, as by apps before songs kept them; not one
  /// cleared on purpose, which keeps an empty list), the passes the
  /// capture's takes made while it played ([songPhrasesOf]: each take's
  /// own, on its clock, put at the song's times its log noted), oldest
  /// take first, merged as passes recorded live are. So a take deleted or
  /// purged leaves the song its timings, and auto-pass turns the tab along
  /// it as before.
  static Map<String, PhraseTimes> _songPhrasesKept(
    CaptureEvent event,
    Map<String, PhraseTimes> phrases,
    Iterable<EventPage> gone,
  ) {
    final mine = event.myContribution;
    final goneIds = {for (final p in gone) p.id};
    final stored = {
      for (final p in [...event.storedPages, ...?mine?.pages]) p.id: p,
    };
    final songs = {
      for (final take in gone)
        for (final s in take.takeLog?.song ?? const <SongSegment>[])
          if (!goneIds.contains(s.page) &&
              stored.containsKey(s.page) &&
              !phrases.containsKey(s.page) &&
              mine?.phrases[s.page] == null &&
              event.phrases[s.page] == null)
            s.page,
    };
    if (songs.isEmpty) return phrases;
    final out = {...phrases};
    for (final song in songs) {
      var times = PhraseTimes.none;
      for (final take in stored.values) {
        final log = take.takeLog;
        if (log == null || take.id == song) continue;
        final own = mine?.phrases[take.id] ?? event.phrases[take.id];
        if (own == null || own.isEmpty) continue;
        times = songPhrasesOf(own, log.song, song, into: times);
      }
      if (times.isNotEmpty) out[song] = times;
    }
    return out;
  }

  /// The [PhraseTimes] of song [pageId] of event [eventId], its file's own
  /// (each file keeps its own, by its page ID): the user's, on a capture
  /// they contribute to (else the owner's), or the capture's.
  PhraseTimes phrasesOf(String eventId, String pageId) {
    final event = byId(eventId);
    if (event == null) return PhraseTimes.none;
    return event.myContribution?.phrases[pageId] ??
        event.phrases[pageId] ??
        PhraseTimes.none;
  }

  /// Keeps [times] for song [pageId] of event [eventId] (empty or null:
  /// none): with the capture, or, on one shared with the user (only its
  /// owner changes it), with their own contribution to it, which keeps
  /// them. Songs since deleted are let go of meanwhile.
  Future<void> setPhrases(String eventId, String pageId, PhraseTimes? times) =>
      _putPhrases(eventId, pageId, times);

  /// Clears song [pageId]'s passes on purpose (Clear on the player's bar):
  /// none, kept as an empty list, so a take of it deleted later doesn't
  /// give it the take's again ([_songPhrasesKept]).
  Future<void> clearPhrases(String eventId, String pageId) =>
      _putPhrases(eventId, pageId, PhraseTimes.none, cleared: true);

  Future<void> _putPhrases(
    String eventId,
    String pageId,
    PhraseTimes? times, {
    bool cleared = false,
  }) async {
    Map<String, PhraseTimes> changed(
      Map<String, PhraseTimes> now,
      Set<String> songs,
    ) => {
      for (final MapEntry(:key, :value) in now.entries)
        if (key != pageId && songs.contains(key)) key: value,
      if (times != null &&
          (times.isNotEmpty || cleared) &&
          songs.contains(pageId))
        pageId: times,
    };
    final now = _byIdAll(eventId);
    if (now == null || now.deleted != null) return;
    // A deleted file's passes stay with it, in the trash.
    final songs = {for (final p in now.storedPages) p.id};
    if (now.isShared) {
      final mine = now.myContribution ?? Contribution(updated: _now());
      final updated = _update(
        now.copyWith(
          contributions: [
            mine.copyWith(
              phrases: changed(mine.phrases, songs),
              updated: _now(),
            ),
          ],
        ),
      );
      await _store.save(updated);
      return;
    }
    await patch(
      eventId,
      (now) => now.copyWith(phrases: changed(now.phrases, songs)),
    );
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
        extra: page.extra,
      );
    } else {
      copy = EventPage(
        id: newId(),
        filter: page.filter,
        kind: page.kind,
        extension: page.extension,
        title: page.title,
        from: page.id,
        take: page.take,
        takeLog: page.takeLog,
        extra: page.extra,
      );
      await _arrival(event.id, page);
      final (bytes, _) = await _store.pageStream(event.id, page);
      await _store.putPageStream(event.id, copy, bytes);
    }
    return patch(event.id, (now) {
      if (now.isPublished(page)) return now;
      // Its phrase passes come with it (the owner's, else its reader's):
      // the copy plays along as the file did.
      final times =
          now.phrases[page.id] ??
          now.contributions
              .where((c) => c.pages.any((p) => p.id == page.id))
              .firstOrNull
              ?.phrases[page.id];
      return now.copyWith(
        pages: [...now.pages, copy],
        phrases: times == null ? null : {...now.phrases, copy.id: times},
      );
    });
  }

  /// Takes [page] back out of the capture's pages, after [publish]: its
  /// copy goes, with its file and passes (not to the trash: it's a copy;
  /// the contribution keeps the original, which is what's lost nothing).
  Future<CaptureEvent?> unpublish(CaptureEvent event, EventPage page) async {
    final now = _byIdAll(event.id);
    final copy = now?.publishedCopy(page);
    if (now == null || copy == null) return now;
    final updated = await _save(
      now.copyWith(
        pages: [
          for (final p in now.pages)
            if (p.id != copy.id) p,
        ],
        phrases: _phrasesWithout(now.phrases, [copy]),
      ),
    );
    await _dropFiles(updated, [copy]);
    return updated;
  }

  Future<EventPage> _addFile(
    CaptureEvent event,
    Media m, {
    bool take = false,
    TakeLog? takeLog,
  }) async {
    final page = EventPage(
      id: newId(),
      kind: m.kind,
      extension: m.extension,
      // A file is named after its file (photos' names are the picker's).
      title: m.kind == PageKind.image ? null : nameOfFile(m.file.name),
      take: take,
      takeLog: takeLog,
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

  /// Keeps where the song really is in take [pageId] of event [eventId]
  /// with its log ([TakeLog.withSync]): measured from the take's sound
  /// after it was saved, the one thing added to a log later. A take that
  /// has one already (another device's came first) keeps it.
  Future<CaptureEvent?> setTakeSync(
    String eventId,
    String pageId,
    TakeSync sync,
  ) {
    EventPage synced(EventPage p) {
      final log = p.takeLog;
      if (p.id != pageId || log == null || log.sync != null) return p;
      return p.copyWith(takeLog: log.withSync(sync));
    }

    final now = _byIdAll(eventId);
    // One of the user's own contribution (Cam's take on a shared capture).
    if (now != null && !now.pages.any((p) => p.id == pageId)) {
      return patchContribution(
        eventId,
        (pages) => [for (final p in pages) synced(p)],
      );
    }
    return patch(
      eventId,
      (now) => now.copyWith(pages: [for (final p in now.pages) synced(p)]),
    );
  }

  /// Keeps [edit] with video [pageId] of event [eventId] (null: none, the
  /// video plays as it is). A kept render made from another edit
  /// ([EventPage.render]) no longer plays in its place: it goes, with its
  /// file.
  Future<CaptureEvent?> setPageEdit(
    String eventId,
    String pageId,
    PageEdit? edit,
  ) async {
    // Read as patch will see it: nothing runs in between.
    final stale = switch (_pageOf(eventId, pageId)?.render) {
      final render? when render.edit != edit => render,
      _ => null,
    };
    final updated = await patch(
      eventId,
      (now) => now.copyWith(
        pages: [
          for (final p in now.pages)
            p.id == pageId
                ? p.copyWith(
                    edit: () => edit,
                    render: stale == null ? null : () => null,
                  )
                : p,
        ],
      ),
    );
    if (updated != null && stale != null) {
      await _dropFiles(updated, [stale.file]);
    }
    return updated;
  }

  /// Page [pageId] of event [eventId], as it is now; null when either is
  /// gone.
  EventPage? _pageOf(String eventId, String pageId) =>
      _byIdAll(eventId)?.pages.where((p) => p.id == pageId).firstOrNull;

  /// Keeps [file], the video the editor's Download just made of video
  /// [pageId] of event [eventId] from its [edit] (its title showing
  /// [title]), as the page's render ([EventPage.render]): it plays in the
  /// page's place while the edit is still that one (`currentRender`), on
  /// this device and, synced, the others, and for those the capture is
  /// shared with. The render it replaces goes, with its file. Null when
  /// the page is gone (then nothing is kept).
  Future<CaptureEvent?> keepRender(
    String eventId,
    String pageId,
    XFile file, {
    required String extension,
    PageEdit? edit,
    String title = '',
  }) async {
    bool takes(CaptureEvent? event) =>
        event != null &&
        !event.isShared &&
        event.pages.any((p) => p.id == pageId && p.isVideo);
    if (!takes(_byIdAll(eventId))) return null;
    final render = PageRender(
      id: newId(),
      extension: checkExtension(extension),
      edit: edit,
      title: title,
    );
    await _store.putPageFile(eventId, render.file, file);
    // Gone while it was stored: so is its copy.
    if (!takes(_byIdAll(eventId))) {
      await _store.deletePage(eventId, render.file);
      return null;
    }
    // Read as patch will see it: nothing runs in between.
    final old = _pageOf(eventId, pageId)?.render;
    final updated = await patch(
      eventId,
      (now) => now.copyWith(
        pages: [
          for (final p in now.pages)
            p.id == pageId ? p.copyWith(render: () => render) : p,
        ],
      ),
    );
    if (updated != null && old != null) await _dropFiles(updated, [old.file]);
    return updated;
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
    final rotated = await rotatedPage(await original(event, page));
    final turned = EventPage(
      id: newId(),
      filter: page.filter,
      kind: page.kind,
      extension: page.extension,
      extra: page.extra,
    );
    await _store.putPage(event.id, turned, rotated);
    // The image as it was goes to the trash: files are deleted only when
    // the trash is purged.
    final updated = await _save(
      event.copyWith(
        pages: [for (final p in event.pages) p.id == page.id ? turned : p],
        deletedPages: [...event.deletedPages, page],
      ),
    );
    _forget(page);
    _revision++;
    notifyListeners();
    return updated;
  }

  /// Puts [media] (an edited video, say) in [page]'s place: a new page
  /// (a new ID, as [rotatePage] makes: page files never change once
  /// written) of [media]'s kind and extension, with [page]'s name,
  /// filter, take mark and the keys a newer app wrote
  /// ([EventPage.extra]); [page] goes to the trash
  /// ([CaptureEvent.deletedPages]), file and all. Not its take log
  /// ([EventPage.takeLog]): that tells of the file recorded, not of
  /// [media].
  Future<CaptureEvent> replacePage(
    CaptureEvent event,
    EventPage page,
    Media media,
  ) async {
    final replaced = EventPage(
      id: newId(),
      filter: page.filter,
      kind: media.kind,
      extension: media.extension,
      title: page.title,
      take: page.take,
      extra: page.extra,
    );
    await _store.putPageFile(event.id, replaced, media.file);
    final updated = await _save(
      event.copyWith(
        pages: [for (final p in event.pages) p.id == page.id ? replaced : p],
        deletedPages: [...event.deletedPages, page],
      ),
    );
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

  /// Deletes [page] from [event]: it goes to the event's trash
  /// ([CaptureEvent.deletedPages]) with its file and phrase passes, which
  /// stay (on the device and in the cloud) until it's restored
  /// ([restorePage]) or the trash is purged ([purge]). A take's songs
  /// with no passes kept get those it and the other takes made along them
  /// ([_songPhrasesKept]), so they outlive it.
  Future<CaptureEvent> deletePage(CaptureEvent event, EventPage page) => _save(
    event.copyWith(
      pages: [
        for (final p in event.pages)
          if (p.id != page.id) p,
      ],
      deletedPages: [...event.deletedPages, page],
      phrases: _songPhrasesKept(event, event.phrases, [page]),
    ),
  );

  /// Puts [page], deleted from event [eventId] ([deletePage]), back at the
  /// end of its pages. Null when the event is gone.
  Future<CaptureEvent?> restorePage(String eventId, EventPage page) =>
      patch(eventId, (now) {
        if (!now.deletedPages.any((p) => p.id == page.id)) return now;
        return now.copyWith(
          pages: [...now.pages, page],
          deletedPages: [
            for (final p in now.deletedPages)
              if (p.id != page.id) p,
          ],
        );
      });

  /// Deletes the files of [gone] (pages [event] had, and their kept
  /// renders, [EventPage.files]) that it no longer keeps: a published page
  /// and its contribution share one file.
  Future<void> _dropFiles(CaptureEvent event, Iterable<EventPage> gone) async {
    final kept = {for (final p in event.storedFiles) p.fileName};
    for (final p in gone.expand((p) => p.files)) {
      if (!kept.add(p.fileName)) continue;
      await _deleteFile(event.id, p);
    }
  }

  /// Deletes [page]'s file, of event [eventId], when it has its own
  /// ([EventPage.hasOwnFile]), once the clones still showing it have a
  /// copy of their own ([_keepCopies]).
  Future<void> _deleteFile(String eventId, EventPage page) async {
    if (!page.hasOwnFile) return _forget(page);
    await _keepCopies(eventId, page);
    pageGone(eventId, page);
    await _store.deletePage(eventId, page);
    _forget(page);
  }

  /// Copy on write's copy: before [page]'s file (of event [eventId]) goes,
  /// each clone page still showing it ([EventPage.source]) gets a copy of
  /// its own, a change of the user's that cloud sync sends. One whose file
  /// isn't on this device (never came) is left as it is: nothing waits
  /// for it, since it won't come now.
  Future<void> _keepCopies(String eventId, EventPage page) async {
    final source = FileOrigin(eventId, page.id);
    // Those in the trash too: they may be restored.
    for (final e in [..._all]) {
      if (e.isDeleted || e.isShared) continue;
      if (!e.storedPages.any((p) => p.source == source)) continue;
      await _ownFiles(e.id, (p) => p.source == source);
    }
  }

  /// [event] with a file of its own for each page that still shows
  /// another capture's ([EventPage.source]): before it gets a link, whose
  /// holders read only its own folder. A file still on its way is waited
  /// for (at most [ownFilesWait]); pages whose file isn't on this device
  /// stay as they are.
  Future<CaptureEvent> ownFiles(CaptureEvent event) async =>
      await _ownFiles(event.id, (p) => p.source != null, wait: ownFilesWait) ??
      event;

  /// How long [ownFiles] waits for a file still on its way.
  static const ownFilesWait = Duration(seconds: 30);

  /// Copies into event [id] the files of its pages [which] picks that
  /// still show another capture's, and saves them as its own; null when
  /// the event is gone. A file still arriving is waited for up to [wait]
  /// (none: not at all).
  Future<CaptureEvent?> _ownFiles(
    String id,
    bool Function(EventPage page) which, {
    Duration? wait,
  }) async {
    final event = _byIdAll(id);
    if (event == null) return null;
    final owned = <String, EventPage>{};
    for (final page in event.pages) {
      if (page.source == null || !which(page)) continue;
      final (fromId, from) = _fileOf(id, page);
      try {
        if (wait != null) await _arrival(fromId, from).timeout(wait);
        if (!await _store.hasPage(fromId, from)) continue;
        final own = page.copyWith(source: () => null);
        final (bytes, _) = await _store.pageStream(fromId, from);
        await _store.putPageStream(id, own, bytes);
        owned[page.id] = own;
      } on Object catch (e) {
        debugPrint('TabCam: ${page.fileName} not copied into $id: $e');
      }
    }
    if (owned.isEmpty) return event;
    return patch(
      id,
      (now) => now.copyWith(
        pages: [
          for (final p in now.pages) p.source != null ? owned[p.id] ?? p : p,
        ],
      ),
    );
  }

  /// Where [page]'s file is kept: with event [eventId], or, for a clone's
  /// page still showing the original's ([EventPage.source]), with the
  /// original.
  (String, EventPage) _fileOf(String eventId, EventPage page) {
    final source = page.source;
    if (source == null) return (eventId, page);
    return (
      source.eventId,
      EventPage(id: source.pageId, kind: page.kind, extension: page.extension),
    );
  }

  /// Deletes [event]: it goes to the trash ([CaptureEvent.trashed]),
  /// hidden, its pages and their files kept (on the device and in the
  /// cloud) until it's restored ([restore]) or the trash is purged
  /// ([purge]). Synced, so it goes from the user's other devices too.
  Future<void> delete(CaptureEvent event) async {
    if (event.isShared) return;
    await patch(event.id, (now) => now.copyWith(trashed: () => _now()));
  }

  /// Takes [event] out of the trash ([delete]): shown again, as it was.
  Future<CaptureEvent?> restore(CaptureEvent event) =>
      patch(event.id, (now) => now.copyWith(trashed: () => null));

  /// Empties the trash, for good: each of the user's events in it is
  /// deleted with its files ([_purgeEvent]), and each file deleted from an
  /// event ([CaptureEvent.deletedPages]) goes with its phrase passes. The
  /// only way files are deleted (but those of captures shared with the
  /// user, which are their owners'). Synced: the cloud copies go too, and
  /// the other devices' at their next pass. Copies of them a clone still
  /// shows get files of their own first ([_keepCopies]).
  Future<void> purge() async {
    // Newest first: a trashed clone goes before its original, so its
    // original's files aren't copied into it for nothing.
    for (final e in trashed..sort((a, b) => b.created.compareTo(a.created))) {
      await _purgeEvent(_byIdAll(e.id) ?? e);
    }
    for (final e in withDeletedPages) {
      final gone = e.deletedPages;
      final updated = await patch(
        e.id,
        (now) => now.copyWith(
          deletedPages: const [],
          phrases: _phrasesWithout(
            _songPhrasesKept(now, now.phrases, gone),
            gone,
          ),
        ),
      );
      if (updated != null) await _dropFiles(updated, gone);
    }
  }

  /// Deletes [event] for good, and its files. One that has synced leaves a
  /// tombstone, so the deletion reaches the user's other devices.
  Future<void> _purgeEvent(CaptureEvent event) async {
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
    for (final p in {for (final p in event.storedFiles) p.fileName: p}.values) {
      await _deleteFile(event.id, p);
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
    // The pages it no longer has, nor has in its trash (purged on another
    // device), go.
    await _dropFiles(event, [...?local?.pages, ...?local?.deletedPages]);
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
        if (c.by == contribution.by || (local.isShared && c.by == null)) c,
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
  bool isArriving(String eventId, EventPage page) {
    final (id, file) = _fileOf(eventId, page);
    return _arriving.containsKey(_arrivalKey(id, file));
  }

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
    final (id, file) = _fileOf(event.id, page);
    await _arrival(id, file);
    return _store.page(id, file);
  }

  /// The page's file on disk (videos play from it); null on the web.
  Future<String?> path(CaptureEvent event, EventPage page) async {
    final (id, file) = _fileOf(event.id, page);
    await _arrival(id, file);
    return _store.pagePath(id, file);
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
