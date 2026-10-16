import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../auth/auth_service.dart';
import '../l10n/language.dart';
import '../library/library.dart';
import '../library/capture_event.dart';
import 'cognito.dart';
import 's3.dart';
import 'profile_service.dart';
import 'share_api.dart';
import 'sigv4.dart';

/// Where cloud sync stands, for the account sheet.
enum SyncState {
  /// Signed out: nothing syncs.
  signedOut,

  /// A pass is running.
  syncing,

  /// The last pass worked.
  synced,

  /// The last pass failed; [CloudSync.message] says why.
  failed,
}

/// Syncs a signed-in user's events with their folder in the user-data
/// bucket, both ways, so every device they sign in on has the same events.
///
/// The folder is the user's Cognito identity ID:
///
/// - `<identity>/events/<event id>/event.json`: the event's details (with
///   the folder's identity as `owner`, and its `shares`), or its tombstone
///   once deleted;
/// - `<identity>/events/<event id>/<page id>.<extension>`: each page's file,
///   written once (a rotated page is a new page);
/// - `<identity>/contrib/<event id>/<their identity>/`: what someone the
///   event is shared with to read added to it (`contrib.json` and its
///   files), which only they and the owner may read ([Contribution]).
///
/// A pass lists the folder (one request when nothing changed), then for
/// each event: one changed only here goes up, one changed only in the
/// folder (its `event.json`'s ETag differs from the last one seen) comes
/// down, and one changed in both keeps the later `updated`. Events that
/// synced with another account stay on the device, untouched.
///
/// Passes run at sign-in, a moment after each change, every
/// [CloudSync.period] while the app is in front (every
/// [CloudSync.backgroundPeriod] behind), as it comes back to the front,
/// and on [syncNow]: another device's change shows within seconds.
class CloudSync extends ChangeNotifier with WidgetsBindingObserver {
  CloudSync({
    required this.library,
    required this.auth,
    required this.bucket,
    required this.credentials,
    this.shares,
    this.period = const Duration(seconds: 10),
    this.backgroundPeriod = const Duration(minutes: 1),
    this.debounce = const Duration(seconds: 2),
  });

  final Library library;
  final AuthService auth;
  final ObjectStore bucket;
  final CredentialSource credentials;

  /// The share API, for captures shared with the user and their own
  /// grants; null in a build without sharing.
  final ShareApi? shares;

  /// The signed-in user's profile, in builds with the share API.
  ProfileService? profiles;

  /// How often a signed-in device looks for other devices' changes while
  /// the app is in front. A pass with nothing new is one listing.
  final Duration period;

  /// How often it looks while the app is behind (a hidden tab, a phone
  /// app in the background, while it still runs).
  final Duration backgroundPeriod;

  /// Whether the app is in front, as the platform last said.
  bool _foreground = true;

  /// When the last pass started.
  DateTime? _lastPass;

  /// How long after a change its pass starts, so a burst is one pass.
  final Duration debounce;

  /// The state file's name in the store (beside the events).
  static const String stateName = 'cloudsync';

  SyncState _state = SyncState.signedOut;
  SyncState get state => _state;

  /// Why the last pass failed, or what it did.
  String? get message => _message;
  String? _message;

  DateTime? get lastSynced => _lastSynced;

  /// Whether a pass has ended (synced or failed) since the user signed
  /// in; true signed out. Until then, an empty library may just not have
  /// come down yet (Home says it's loading).
  bool get firstPassDone => _token == null || _passed;
  bool _passed = false;
  DateTime? _lastSynced;

  String? _token;
  Timer? _periodic;
  Timer? _soon;
  bool _running = false;
  bool _again = false;
  bool _started = false;

  /// Starts following sign-ins and the library's changes.
  void start() {
    if (_started) return;
    _started = true;
    auth.addListener(_onAuth);
    library.localChanges.addListener(_onLocalChange);
    WidgetsBinding.instance.addObserver(this);
    _onAuth();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        final wasBehind = !_foreground;
        _foreground = true;
        // Back in front: what changed elsewhere meanwhile, at once.
        if (wasBehind) unawaited(syncNow());
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        _foreground = false;
      case AppLifecycleState.inactive:
        break; // still shown (a dialog over it, a window without focus)
    }
  }

  void _tick() {
    final last = _lastPass;
    if (!_foreground &&
        last != null &&
        DateTime.now().difference(last) < backgroundPeriod) {
      return;
    }
    unawaited(syncNow());
  }

  String? _userId;

  void _onAuth() {
    final token = auth.idToken;
    if (token == _token) return;
    // Another account: another identity, so other credentials.
    if (auth.user?.id != _userId) credentials.clear();
    _userId = auth.user?.id;
    final wasSignedIn = _token != null;
    _token = token;
    if (!wasSignedIn || token == null) _passed = false;
    if (token == null) {
      _paused = false;
      credentials.clear();
      // Cleared, so the next sign-in starts the timer again.
      _periodic?.cancel();
      _periodic = null;
      _soon?.cancel();
      _set(SyncState.signedOut, null);
      return;
    }
    // A new token of the same session (a refresh) needs no pass of its
    // own, unless the last one failed (it may have been the token).
    if (!wasSignedIn || _state == SyncState.failed) unawaited(syncNow());
    _periodic ??= Timer.periodic(period, (_) => _tick());
  }

  void _onLocalChange() {
    if (_token == null) return;
    _soon?.cancel();
    _soon = Timer(debounce, () => unawaited(syncNow()));
  }

  /// Runs a pass now (or right after the running one).
  Future<void> syncNow() async {
    if (_token == null || _paused) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    await (_passes = _runPasses());
  }

  Future<void> _runPasses() async {
    try {
      do {
        _again = false;
        await _pass();
      } while (_again && _token != null && !_paused);
    } finally {
      _running = false;
    }
  }

  /// The passes running, if any.
  Future<void>? _passes;
  bool _paused = false;

  /// Stops passes, for deleting the account (so none uploads what's being
  /// deleted), once the running one ends. Until [resume], or signing out.
  Future<void> pause() async {
    _paused = true;
    _soon?.cancel();
    if (_running) await _passes;
  }

  /// Lets passes run again after [pause].
  void resume() => _paused = false;

  Future<void> _pass() async {
    final token = _token;
    if (token == null) return;
    _lastPass = DateTime.now();
    _set(SyncState.syncing, null);
    // Rejected credentials and a skewed clock are worth one more try: new
    // credentials, and the clock S3 just corrected.
    for (var attempt = 0; ; attempt++) {
      try {
        final (up, down) = await _run(token);
        if (_token != token) return;
        _lastSynced = DateTime.now();
        _set(SyncState.synced, _summary(up, down));
        return;
      } on _SignedOut {
        return;
      } on S3Exception catch (e) {
        if (attempt == 0 && (e.credentialsRejected || e.clockSkewed)) {
          if (e.credentialsRejected) credentials.clear();
          continue;
        }
        _fail(
          e.clockOffset != null
              ? AwsClock.describe(e.clockOffset!)
              : appL10n.accountSyncFailedHttp('${e.statusCode}'),
          e,
        );
        return;
      } on CognitoException catch (e) {
        _fail(
          e.needsSignIn
              ? appL10n.accountSignInAgainToSync
              : appL10n.accountSyncFailedBecause(e.type),
          e,
        );
        return;
      } catch (e) {
        _fail(appL10n.accountSyncFailedBecause('$e'), e);
        return;
      }
    }
  }

  static String? _summary(int up, int down) => up == 0 && down == 0
      ? null
      : [
          if (up > 0) appL10n.accountSyncUploaded(up),
          if (down > 0) appL10n.accountSyncDownloaded(down),
        ].join(', ');

  void _fail(String message, Object e) {
    debugPrint('TabCam: cloud sync failed: $e');
    _set(SyncState.failed, message);
  }

  void _set(SyncState state, String? message) {
    // A pass that ends after dispose (the app closing) has no one to tell.
    if (_disposed) return;
    if (state == SyncState.synced || state == SyncState.failed) {
      _passed = true;
    }
    _state = state;
    _message = message;
    notifyListeners();
  }

  /// One pass for [token]'s user: their own folder, then each capture
  /// shared with them. How many events went up and came down.
  Future<(int, int)> _run(String token) async {
    await library.ready;
    final session = await credentials.session(token);
    _check(token);
    final identity = session.identityId;
    final user = auth.user?.id;
    final state = await _SyncState.load(library, identity, user);
    // The same user's folder moved (their sign-in joined a profile, or
    // left one): their own captures go with them, to sync into the new one.
    if (state.movedFrom case final previous?) {
      for (final e in library.all) {
        if (!e.isShared && e.owner == previous) {
          await library.setOwner(e, identity);
        }
      }
      debugPrint('TabCam: cloud sync: the folder moved from $previous');
    }
    // Captures the user left since: what synced of them is forgotten, so
    // shared again, they come down again.
    final forgotten = {..._forgotten};
    forgotten.forEach(state.events.remove);
    var (up, down) = await _folder(
      _Folder(owner: identity, credentials: session.credentials, own: true),
      state,
      token,
    );
    if (shares != null) {
      down += await _contributionsToMine(
        identity,
        session.credentials,
        state,
        token,
      );
      final (u, d) = await _shared(token, state);
      up += u;
      down += d;
      for (final MapEntry(key: id, value: key) in [..._unpublished.entries]) {
        await _publish(token, id, key);
      }
    }
    await state.save(library);
    _forgotten.removeAll(forgotten);
    return (up, down);
  }

  /// Keys (`<owner>/<capture id>`) of captures the user left, for the
  /// next pass to forget.
  final Set<String> _forgotten = {};

  /// Syncs the events of [folder]: all of the user's own, or the one
  /// capture shared with them.
  Future<(int, int)> _folder(
    _Folder folder,
    _SyncState state,
    String token,
  ) async {
    final owner = folder.owner;
    final creds = folder.credentials;
    final prefix = folder.only == null
        ? '$owner/events/'
        : '$owner/events/${folder.only}/';
    final listing = await bucket.listETags(prefix, credentials: creds);
    _check(token);

    // What the folder has: each event's event.json ETag, and its files.
    final base = '$owner/events/';
    final remote = <String, String>{};
    final files = <String, Set<String>>{};
    for (final MapEntry(:key, :value) in listing.entries) {
      final parts = key.substring(base.length).split('/');
      if (parts.length != 2 || !_isId(parts[0])) continue;
      if (folder.only != null && parts[0] != folder.only) continue;
      if (parts[1] == 'event.json') {
        remote[parts[0]] = value;
      } else {
        (files[parts[0]] ??= {}).add(parts[1]);
      }
    }

    var up = 0;
    var down = 0;
    final seen = <String>{};
    String key(String id) => '$owner/$id';

    // Every event.json that changed there, fetched several at a time
    // first: a new device lists its captures at once, their files after.
    final fetch = <String>{};
    for (final event in library.all) {
      if (!folder.holds(event)) continue;
      final etag = remote[event.id];
      if (etag != null && state.events[key(event.id)]?.etag != etag) {
        fetch.add(event.id);
      }
    }
    for (final MapEntry(key: id, value: etag) in remote.entries) {
      if (state.events[key(id)]?.etag == etag) continue;
      final local = library.byIdAll(id);
      if (local == null || folder.holds(local)) fetch.add(id);
    }
    final fetched = await _fetchAll(owner, fetch, creds, token);

    for (final event in [...library.all]) {
      if (!folder.holds(event)) continue;
      seen.add(event.id);
      final last = state.events[key(event.id)];
      final etag = remote[event.id];
      final changedHere = last == null || last.updated != event.updated;
      final changedThere = etag != null && last?.etag != etag;
      if (changedThere) {
        final theirs = fetched[event.id];
        if (theirs != null &&
            (!changedHere ||
                !folder.canWrite ||
                !theirs.updated.isBefore(event.updated))) {
          if (await _take(folder, theirs, files, token, seen: event)) {
            state.events[key(event.id)] = _Synced(etag, theirs.updated);
            down++;
          }
          continue;
        }
      }
      if (folder.canWrite && (changedHere || etag == null)) {
        final sent = await _send(owner, event, files, creds, token);
        state.events[key(event.id)] = _Synced(sent, event.updated);
        if (event.owner == null) await library.setOwner(event, owner);
        up++;
      }
    }

    // Events only in the folder: new from another device, or just shared.
    // Newest first, so the top of the list fills first.
    final only =
        [
          for (final MapEntry(key: id, value: etag) in remote.entries)
            if (!seen.contains(id) &&
                state.events[key(id)]?.etag != etag &&
                library.byIdAll(id) == null) // else someone else's ID
              (id, etag, fetched[id]),
        ]..sort(
          (a, b) => (b.$3?.updated ?? DateTime(0)).compareTo(
            a.$3?.updated ?? DateTime(0),
          ),
        );
    for (final (id, etag, theirs) in only) {
      if (theirs == null) continue;
      // Another device's tombstone of an event never here: nothing to take.
      if (theirs.isDeleted || await _take(folder, theirs, files, token)) {
        state.events[key(id)] = _Synced(etag, theirs.updated);
        if (!theirs.isDeleted) down++;
      }
    }

    // Files still to come (a download that failed, or the app closed
    // first): asked for again.
    for (final event in library.all) {
      if (!folder.holds(event) || event.isDeleted) continue;
      await _bringPages(folder, event, files, token);
    }
    return (up, down);
  }

  /// [ids]' event.json in [owner]'s folder, [fetchesAtOnce] at a time.
  Future<Map<String, CaptureEvent?>> _fetchAll(
    String owner,
    Set<String> ids,
    AwsCredentials creds,
    String token,
  ) async {
    final out = <String, CaptureEvent?>{};
    final left = [...ids];
    Future<void> worker() async {
      while (left.isNotEmpty) {
        final id = left.removeLast();
        out[id] = await _fetch(owner, id, creds);
        _check(token);
      }
    }

    await Future.wait([
      for (var i = 0; i < fetchesAtOnce && i < ids.length; i++) worker(),
    ]);
    return out;
  }

  /// How many event.json files a pass fetches at once.
  static const fetchesAtOnce = 8;

  /// How many page files download at once.
  static const downloadsAtOnce = 4;

  /// Page files to download ([_bringPages]), the next first.
  final List<_Download> _downloads = [];
  final Set<String> _queued = {};
  int _downloading = 0;

  /// Queues the files of [event]'s pages that aren't here yet but are in
  /// the folder ([files]): its previews show them loading until they are
  /// ([Library.expectPage]).
  Future<void> _bringPages(
    _Folder folder,
    CaptureEvent event,
    Map<String, Set<String>> files,
    String token,
  ) async {
    final there = files[event.id] ?? const <String>{};
    var added = false;
    for (final page in event.pages) {
      if (!page.hasFile || !there.contains(page.fileName)) continue;
      final key = '${event.id}/${page.fileName}';
      if (_queued.contains(key)) continue;
      if (await library.hasPage(event.id, page)) continue;
      library.expectPage(event.id, page);
      _queued.add(key);
      _downloads.add(
        _Download(
          key: key,
          objectKey: _key(folder.owner, event.id, page.fileName),
          eventId: event.id,
          page: page,
          credentials: folder.credentials,
          token: token,
          updated: event.updated,
        ),
      );
      added = true;
    }
    if (added) _queueChanged();
  }

  /// Queues the files of [contribution]'s pages (to [eventId]) that aren't
  /// here yet but are in its folder ([prefix], holding [there]).
  Future<void> _bringContribution(
    String eventId,
    Contribution contribution,
    String prefix,
    Set<String> there,
    AwsCredentials creds,
    String token,
  ) async {
    var added = false;
    for (final page in contribution.pages) {
      if (!page.hasFile || !there.contains(page.fileName)) continue;
      final key = '$eventId/${page.fileName}';
      if (_queued.contains(key)) continue;
      if (await library.hasPage(eventId, page)) continue;
      library.expectPage(eventId, page);
      _queued.add(key);
      _downloads.add(
        _Download(
          key: key,
          objectKey: '$prefix${page.fileName}',
          eventId: eventId,
          page: page,
          credentials: creds,
          token: token,
          updated: contribution.updated,
        ),
      );
      added = true;
    }
    if (added) _queueChanged();
  }

  void _queueChanged() {
    // Pictures and PDFs before videos and recordings; the newest first.
    _downloads.sort((a, b) {
      final slow = a.slow == b.slow ? 0 : (a.slow ? 1 : -1);
      return slow != 0 ? slow : b.updated.compareTo(a.updated);
    });
    _pump();
  }

  void _pump() {
    while (_downloading < downloadsAtOnce && _downloads.isNotEmpty) {
      final next = _downloads.removeAt(0);
      _downloading++;
      unawaited(
        _download(next).whenComplete(() {
          _downloading--;
          _queued.remove(next.key);
          if (!_disposed) _pump();
        }),
      );
    }
  }

  Future<void> _download(_Download d) async {
    // Signed out meanwhile: the next sign-in's pass asks again.
    if (_disposed || _token != d.token) return;
    final event = library.byIdAll(d.eventId);
    if (event == null || event.isDeleted) {
      library.pageGone(d.eventId, d.page);
      return;
    }
    try {
      await library.putPageStream(
        d.eventId,
        d.page,
        await bucket.getStream(d.objectKey, credentials: d.credentials),
      );
      library.pageArrived(d.eventId, d.page);
    } on Object catch (e) {
      // Still on its way: the next pass asks again.
      debugPrint('TabCam: cloud sync: ${d.key} not here yet: $e');
    }
  }

  /// Syncs each capture shared with the user, with credentials for its
  /// folder alone; drops the copies of captures no longer shared.
  Future<(int, int)> _shared(String token, _SyncState state) async {
    final api = shares!;
    final grants = await api.shared(token);
    _check(token);
    final keys = {for (final g in grants) '${g.owner}/${g.captureId}'};
    for (final event in [...library.all]) {
      final key = '${event.owner}/${event.id}';
      if (event.isShared && !keys.contains(key)) {
        await library.removeLocal(event);
        state.events.remove(key);
        _shareCredentials.remove(key);
      }
    }
    var up = 0;
    var down = 0;
    for (final g in grants) {
      final key = '${g.owner}/${g.captureId}';
      final local = library.byIdAll(g.captureId);
      if (local != null && !(local.isShared && local.owner == g.owner)) {
        continue; // the same ID as one of the user's own: left alone
      }
      try {
        var access = _shareCredentials[key];
        // New ones when they expire soon, or the role changed.
        if (access == null ||
            access.role != g.role ||
            access.credentials.expiresSoon(AwsClock.shared.now())) {
          access = await api.credentials(token, g.owner, g.captureId);
          _shareCredentials[key] = access;
        }
        _check(token);
        final readOnly = access.role == ShareRole.read;
        if (local != null) {
          await library.setSharing(local, g.ownerEmail, readOnly: readOnly);
        }
        final (u, d) = await _folder(
          _Folder(
            owner: g.owner,
            credentials: access.credentials,
            only: g.captureId,
            sharedBy: g.ownerEmail,
            readOnly: readOnly,
          ),
          state,
          token,
        );
        up += u;
        down += d;
        if (readOnly && access.contribPrefix != null) {
          final (cu, cd) = await _myContribution(
            g.captureId,
            access.contribPrefix!,
            access.credentials,
            state,
            token,
          );
          up += cu;
          down += cd;
        }
        // The owner deleted it: gone here, and no longer shared.
        if (library.byIdAll(g.captureId)?.isDeleted ?? false) {
          await _leave(token, library.byIdAll(g.captureId)!, state);
        }
      } on _SignedOut {
        rethrow;
      } on Object catch (e) {
        // One share failing doesn't stop the others; new credentials next.
        _shareCredentials.remove(key);
        debugPrint('TabCam: syncing ${g.captureId} of ${g.owner} failed: $e');
      }
    }
    return (up, down);
  }

  /// Credentials of shared captures, by `<owner>/<capture id>`.
  final Map<String, ShareCredentials> _shareCredentials = {};

  /// The name of a contribution's details in its folder.
  static const contributionName = 'contrib.json';

  /// The owner's side: what people added to the user's own captures
  /// (`<identity>/contrib/`, one listing), brought here as it changes; a
  /// contribution whose folder went is forgotten. The owner never writes
  /// them. How many came down.
  Future<int> _contributionsToMine(
    String identity,
    AwsCredentials creds,
    _SyncState state,
    String token,
  ) async {
    final base = '$identity/contrib/';
    final listing = await bucket.listETags(base, credentials: creds);
    _check(token);
    // Each contribution's contrib.json ETag, and its files, by
    // `<capture>/<their identity>`.
    final remote = <String, String>{};
    final files = <String, Set<String>>{};
    for (final MapEntry(:key, :value) in listing.entries) {
      final parts = key.substring(base.length).split('/');
      if (parts.length != 3 || !_isId(parts[0]) || parts[1].isEmpty) continue;
      final folder = '${parts[0]}/${parts[1]}';
      if (parts[2] == contributionName) {
        remote[folder] = value;
      } else {
        (files[folder] ??= {}).add(parts[2]);
      }
    }
    String stateKey(String folder) => 'contrib/$identity/$folder';
    var down = 0;
    final unnamed = <String>{};
    for (final event in [...library.all]) {
      if (event.isShared || event.owner != identity || event.isDeleted) {
        continue;
      }
      final here = {for (final c in event.contributions) ?c.by};
      final there = {
        for (final folder in remote.keys)
          if (folder.startsWith('${event.id}/'))
            folder.substring(event.id.length + 1),
      };
      for (final by in here.difference(there)) {
        await library.removeContribution(event.id, by);
        state.events.remove(stateKey('${event.id}/$by'));
      }
      for (final by in there) {
        final folder = '${event.id}/$by';
        final etag = remote[folder]!;
        if (state.events[stateKey(folder)]?.etag != etag) {
          final theirs = await _fetchContribution('$base$folder/', creds);
          _check(token);
          if (theirs == null) continue;
          await library.applyContribution(event.id, theirs.copyWith(by: by));
          state.events[stateKey(folder)] = _Synced(etag, theirs.updated);
          down++;
        }
        final c = library
            .byIdAll(event.id)
            ?.contributions
            .where((c) => c.by == by)
            .firstOrNull;
        if (c == null) continue;
        if (c.email == null) unnamed.add(event.id);
        await _bringContribution(
          event.id,
          c,
          '$base$folder/',
          files[folder] ?? const {},
          creds,
          token,
        );
      }
    }
    for (final id in unnamed) {
      await _nameContributors(token, id);
    }
    return down;
  }

  /// Captures whose contributors' addresses were asked for this session
  /// (once each, until a new contributor shows).
  final Map<String, Set<String>> _askedNames = {};

  /// Asks the share API who added to the user's capture [id] (its grants
  /// know each reader's identity), for their contributions' names.
  Future<void> _nameContributors(String token, String id) async {
    final event = library.byIdAll(id);
    if (event == null) return;
    final unknown = {
      for (final c in event.contributions)
        if (c.email == null) ?c.by,
    };
    final asked = _askedNames[id] ?? const {};
    if (unknown.difference(asked).isEmpty) return;
    _askedNames[id] = {...asked, ...unknown};
    try {
      final grants = await shares!.grants(token, id);
      _check(token);
      await library.nameContributions(
        id,
        emails: {for (final g in grants) ?g.identity: g.email},
      );
    } on _SignedOut {
      rethrow;
    } on Object catch (e) {
      debugPrint('TabCam: naming the contributors of $id failed: $e');
    }
  }

  /// The reader's side: their own contribution to [captureId], synced with
  /// its folder ([prefix]) both ways, as events are: changed only here it
  /// goes up, only there it comes down, in both the later wins. How many
  /// went up and came down.
  Future<(int, int)> _myContribution(
    String captureId,
    String prefix,
    AwsCredentials creds,
    _SyncState state,
    String token,
  ) async {
    final segments = prefix.split('/');
    final me = segments.length >= 2 ? segments[segments.length - 2] : '';
    if (me.isEmpty) return (0, 0);
    final listing = await bucket.listETags(prefix, credentials: creds);
    _check(token);
    final etag = listing['$prefix$contributionName'];
    final there = {
      for (final key in listing.keys)
        if (key != '$prefix$contributionName') key.substring(prefix.length),
    };
    await library.nameContributions(captureId, by: me);
    final stateKey = 'contrib/$prefix';
    final last = state.events[stateKey];
    var local = library.byIdAll(captureId)?.myContribution;
    final changedHere = local != null && last?.updated != local.updated;
    final changedThere = etag != null && last?.etag != etag;
    var (up, down) = (0, 0);
    if (changedThere) {
      final theirs = await _fetchContribution(prefix, creds);
      _check(token);
      if (theirs != null &&
          (!changedHere || !theirs.updated.isBefore(local.updated))) {
        await library.applyContribution(captureId, theirs.copyWith(by: me));
        state.events[stateKey] = _Synced(etag, theirs.updated);
        local = library.byIdAll(captureId)?.myContribution;
        down++;
      }
    }
    if (local != null && state.events[stateKey]?.updated != local.updated) {
      for (final page in local.pages) {
        if (!page.hasFile || there.contains(page.fileName)) continue;
        final (body, length) = await library.pageStream(captureId, page);
        await bucket.putStream(
          '$prefix${page.fileName}',
          body,
          length,
          contentType: contentTypeOf(page),
          credentials: creds,
        );
        _check(token);
      }
      final json = utf8.encode(jsonEncode(local.toJson(local: false)));
      await bucket.put(
        '$prefix$contributionName',
        json,
        contentType: 'application/json',
        credentials: creds,
      );
      final kept = {for (final p in local.pages) p.fileName};
      for (final name in there) {
        if (kept.contains(name)) continue;
        await bucket.delete('$prefix$name', credentials: creds);
      }
      state.events[stateKey] = _Synced(
        md5.convert(json).toString(),
        local.updated,
      );
      up++;
    }
    if (local != null) {
      await _bringContribution(captureId, local, prefix, there, creds, token);
    }
    return (up, down);
  }

  /// The contribution in the folder [prefix], or null when its
  /// contrib.json isn't one.
  Future<Contribution?> _fetchContribution(
    String prefix,
    AwsCredentials creds,
  ) async {
    final bytes = await bucket.get(
      '$prefix$contributionName',
      credentials: creds,
    );
    try {
      final json = (jsonDecode(utf8.decode(bytes)) as Map)
          .cast<String, Object?>();
      // Whose it is comes from its folder, never from what it says.
      return Contribution.fromJson(
        {...json}
          ..remove('by')
          ..remove('email'),
      );
    } on Object catch (e) {
      debugPrint('TabCam: skipping the contribution in $prefix: $e');
      return null;
    }
  }

  /// Joins the capture a link names (its [captureId] and [key]), signed
  /// in: shared with the user to read, so the next pass brings it. False
  /// when it's the user's own (nothing to join).
  Future<bool> joinLink(String captureId, String key) async {
    final joined = await shares!.joinLink(_signedIn(), captureId, key);
    if (joined.own) return false;
    await syncNow();
    return true;
  }

  Future<void> _leave(
    String token,
    CaptureEvent event,
    _SyncState state,
  ) async {
    await shares!.leave(token, event.owner!, event.id);
    await library.removeLocal(event);
    state.events.remove('${event.owner}/${event.id}');
  }

  /// Links (capture ID -> key) the share API hasn't recorded yet: tried
  /// again each pass.
  final Map<String, String> _unpublished = {};

  /// Lets anyone with [event]'s link (its [CaptureEvent.linkKey]) see it,
  /// read only: the share API records the key. Failing (offline), it's
  /// tried again at each pass.
  Future<void> publishLink(CaptureEvent event) async {
    final key = event.linkKey;
    final token = _token;
    if (key == null || shares == null || token == null || event.isShared) {
      return;
    }
    await _publish(token, event.id, key);
  }

  Future<void> _publish(String token, String id, String key) async {
    try {
      await shares!.publishLink(token, id, key);
      _unpublished.remove(id);
    } on Object catch (e) {
      _unpublished[id] = key;
      debugPrint('TabCam: publishing the link of $id failed: $e');
    }
  }

  /// Whether the user can share their events (signed in, with a share
  /// API).
  bool get canShare => shares != null && _token != null;

  /// Stops [event], shared with the user, being shared with them: it goes
  /// from this device, and stays its owner's.
  Future<void> leave(CaptureEvent event) async {
    if (!event.isShared) return;
    await shares!.leave(_signedIn(), event.owner!, event.id);
    await library.removeLocal(event);
    _forgotten.add('${event.owner}/${event.id}');
  }

  /// Who [event] is shared with.
  Future<List<Grant>> grants(CaptureEvent event) async =>
      _record(event, await shares!.grants(_signedIn(), event.id));

  /// Shares [event] with [email] as [role], and syncs it, so they find it.
  Future<List<Grant>> grant(
    CaptureEvent event,
    String email,
    ShareRole role,
  ) async {
    final grants = await shares!.grant(
      _signedIn(),
      event.id,
      email,
      role: role,
    );
    await _record(event, grants);
    unawaited(syncNow());
    return grants;
  }

  Future<List<Grant>> revoke(CaptureEvent event, String email) async =>
      _record(event, await shares!.revoke(_signedIn(), event.id, email));

  /// Keeps [grants] on the event (its `shares`), so they sync with it.
  Future<List<Grant>> _record(CaptureEvent event, List<Grant> grants) async {
    final current = library.byId(event.id);
    final recorded = [
      for (final g in grants)
        EventShare(g.email, readOnly: g.role == ShareRole.read),
    ];
    if (current != null &&
        !current.isShared &&
        !listEquals(current.shares, recorded)) {
      await library.update(current.copyWith(shares: recorded));
    }
    return grants;
  }

  String _signedIn() =>
      _token ?? (throw ShareApiException(401, appL10n.accountSignInToShare));

  /// The event in the folder, or null when its event.json isn't one.
  Future<CaptureEvent?> _fetch(
    String identity,
    String id,
    AwsCredentials creds,
  ) async {
    final bytes = await bucket.get(_key(identity, id), credentials: creds);
    try {
      final event = CaptureEvent.fromJson(
        (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>(),
      );
      return event.id == id ? event : null;
    } on Object catch (e) {
      debugPrint('TabCam: skipping the cloud copy of $id: $e');
      return null;
    }
  }

  /// Brings [theirs] here: the event at once, its pages' files after
  /// ([_bringPages]), shown loading until they come. False when it changed
  /// here meanwhile ([seen]).
  Future<bool> _take(
    _Folder folder,
    CaptureEvent theirs,
    Map<String, Set<String>> files,
    String token, {
    CaptureEvent? seen,
  }) async {
    final taken = await library.applyRemote(
      theirs.copyWith(
        owner: folder.owner,
        sharedBy: folder.sharedBy,
        readOnly: folder.readOnly,
      ),
      seen: seen,
    );
    if (taken) await _bringPages(folder, theirs, files, token);
    return taken;
  }

  /// Sends [event] to the folder: the pages it lacks, then event.json, then
  /// removes the files the event no longer has. Returns event.json's ETag.
  Future<String> _send(
    String identity,
    CaptureEvent event,
    Map<String, Set<String>> files,
    AwsCredentials creds,
    String token,
  ) async {
    final there = files[event.id] ?? const <String>{};
    for (final page in event.pages) {
      if (!page.hasFile || there.contains(page.fileName)) continue;
      final (body, length) = await library.pageStream(event.id, page);
      await bucket.putStream(
        _key(identity, event.id, page.fileName),
        body,
        length,
        contentType: contentTypeOf(page),
        credentials: creds,
      );
      _check(token);
    }
    final json = utf8.encode(
      jsonEncode(event.copyWith(owner: identity).toJson(local: false)),
    );
    await bucket.put(
      _key(identity, event.id),
      json,
      contentType: 'application/json',
      credentials: creds,
    );
    final kept = {for (final p in event.pages) p.fileName};
    for (final name in there) {
      if (kept.contains(name)) continue;
      await bucket.delete(_key(identity, event.id, name), credentials: creds);
    }
    // A single PUT's ETag (SSE-S3) is the MD5 of its bytes.
    return md5.convert(json).toString();
  }

  void _check(String token) {
    if (_token != token) throw const _SignedOut();
  }

  static String _key(
    String identity,
    String id, [
    String file = 'event.json',
  ]) => '$identity/events/$id/$file';

  static final RegExp _idPattern = RegExp(r'^[a-z0-9]{1,32}$');
  static bool _isId(String s) => _idPattern.hasMatch(s);

  /// The MIME type a page's file is uploaded with.
  @visibleForTesting
  static String contentTypeOf(EventPage page) => page.mimeType;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    if (_started) {
      auth.removeListener(_onAuth);
      library.localChanges.removeListener(_onLocalChange);
      WidgetsBinding.instance.removeObserver(this);
    }
    _periodic?.cancel();
    _soon?.cancel();
    super.dispose();
  }
}

/// A folder a pass syncs: the user's own ([own]: every event of theirs),
/// or one capture shared with them ([only]), read only or not.
class _Folder {
  const _Folder({
    required this.owner,
    required this.credentials,
    this.own = false,
    this.only,
    this.sharedBy,
    this.readOnly = false,
  });

  /// The identity whose folder it is.
  final String owner;
  final AwsCredentials credentials;
  final bool own;
  final String? only;
  final String? sharedBy;
  final bool readOnly;

  bool get canWrite => !readOnly;

  /// Whether [event], on the device, is this folder's.
  bool holds(CaptureEvent event) => own
      ? !event.isShared && (event.owner == null || event.owner == owner)
      : event.id == only && event.isShared && event.owner == owner;
}

/// Signed out (or another account signed in) during a pass: it stops.
class _SignedOut implements Exception {
  const _SignedOut();
}

/// What an event was when it last synced: its event.json's ETag, and its
/// `updated`.
class _Synced {
  const _Synced(this.etag, this.updated);

  final String etag;
  final DateTime updated;
}

/// What has synced, per event, for one identity: kept beside the events
/// ([CloudSync.stateName]). Another identity's state starts over.
class _SyncState {
  _SyncState(this.identity, this.events, {this.user, this.movedFrom});

  final String identity;
  final Map<String, _Synced> events;

  /// Whose folder it is (the sign-in's user ID).
  final String? user;

  /// The folder the same user synced before, when it was another one.
  final String? movedFrom;

  static Future<_SyncState> load(
    Library library,
    String identity, [
    String? user,
  ]) async {
    try {
      final json = await library.readMeta(CloudSync.stateName);
      if (json != null) {
        final m = (jsonDecode(json) as Map).cast<String, Object?>();
        final before = m['identity'];
        if (before is String &&
            before != identity &&
            user != null &&
            (m['user'] == user || m['user'] == null)) {
          return _SyncState(identity, {}, user: user, movedFrom: before);
        }
        if (before == identity) {
          return _SyncState(identity, user: user, {
            for (final MapEntry(:key, :value)
                in (m['events'] as Map).cast<String, Object?>().entries)
              key: _Synced(
                (value as Map)['etag'] as String,
                DateTime.parse(value['updated'] as String).toLocal(),
              ),
          });
        }
      }
    } on Object catch (e) {
      debugPrint('TabCam: starting cloud sync over: $e');
    }
    return _SyncState(identity, {}, user: user);
  }

  Future<void> save(Library library) => library.writeMeta(
    CloudSync.stateName,
    jsonEncode({
      'identity': identity,
      'user': ?user,
      'events': {
        for (final MapEntry(:key, :value) in events.entries)
          key: {
            'etag': value.etag,
            'updated': value.updated.toUtc().toIso8601String(),
          },
      },
    }),
  );
}

/// A page's file to download ([CloudSync._bringPages]).
class _Download {
  _Download({
    required this.key,
    required this.objectKey,
    required this.eventId,
    required this.page,
    required this.credentials,
    required this.token,
    required this.updated,
  });

  final String key;

  /// Where it is in the bucket.
  final String objectKey;
  final String eventId;
  final EventPage page;
  final AwsCredentials credentials;
  final String token;
  final DateTime updated;

  /// Videos and recordings: big, after the rest.
  bool get slow => page.kind == PageKind.video || page.kind == PageKind.audio;
}
