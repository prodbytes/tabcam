import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import '../library/library.dart';
import '../library/capture_event.dart';
import 'cognito.dart';
import 's3.dart';
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
/// - `<identity>/events/<event id>/event.json`: the event's details (no
///   `owner`), or its tombstone once deleted;
/// - `<identity>/events/<event id>/<page id>.<extension>`: each page's file,
///   written once (a rotated page is a new page).
///
/// A pass lists the folder (one request when nothing changed), then for
/// each event: one changed only here goes up, one changed only in the
/// folder (its `event.json`'s ETag differs from the last one seen) comes
/// down, and one changed in both keeps the later `updated`. Events that
/// synced with another account stay on the device, untouched.
///
/// Passes run at sign-in, a moment after each change, every
/// [CloudSync.period], and on [syncNow].
class CloudSync extends ChangeNotifier {
  CloudSync({
    required this.library,
    required this.auth,
    required this.bucket,
    required this.credentials,
    this.period = const Duration(minutes: 1),
    this.debounce = const Duration(seconds: 2),
  });

  final Library library;
  final AuthService auth;
  final ObjectStore bucket;
  final CredentialSource credentials;

  /// How often a signed-in device looks for other devices' changes.
  final Duration period;

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
    _onAuth();
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
    if (token == null) {
      credentials.clear();
      _periodic?.cancel();
      _soon?.cancel();
      _set(SyncState.signedOut, null);
      return;
    }
    // A new token of the same session (a refresh) needs no pass of its
    // own, unless the last one failed (it may have been the token).
    if (!wasSignedIn || _state == SyncState.failed) unawaited(syncNow());
    _periodic ??= Timer.periodic(period, (_) => unawaited(syncNow()));
  }

  void _onLocalChange() {
    if (_token == null) return;
    _soon?.cancel();
    _soon = Timer(debounce, () => unawaited(syncNow()));
  }

  /// Runs a pass now (or right after the running one).
  Future<void> syncNow() async {
    if (_token == null) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _pass();
      } while (_again && _token != null);
    } finally {
      _running = false;
    }
  }

  Future<void> _pass() async {
    final token = _token;
    if (token == null) return;
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
              : 'Sync failed (HTTP ${e.statusCode})',
          e,
        );
        return;
      } on CognitoException catch (e) {
        _fail(
          e.needsSignIn ? 'Sign in again to sync' : 'Sync failed: ${e.type}',
          e,
        );
        return;
      } catch (e) {
        _fail('Sync failed: $e', e);
        return;
      }
    }
  }

  static String? _summary(int up, int down) => up == 0 && down == 0
      ? null
      : [
          if (up > 0) '$up uploaded',
          if (down > 0) '$down downloaded',
        ].join(', ');

  void _fail(String message, Object e) {
    debugPrint('TabScan: cloud sync failed: $e');
    _set(SyncState.failed, message);
  }

  void _set(SyncState state, String? message) {
    _state = state;
    _message = message;
    notifyListeners();
  }

  /// One pass for [token]'s user: how many events went up and came down.
  Future<(int, int)> _run(String token) async {
    await library.ready;
    final session = await credentials.session(token);
    _check(token);
    final identity = session.identityId;
    final creds = session.credentials;
    final prefix = '$identity/events/';
    final listing = await bucket.listETags(prefix, credentials: creds);
    _check(token);

    // What the folder has: each event's event.json ETag, and its files.
    final remote = <String, String>{};
    final files = <String, Set<String>>{};
    for (final MapEntry(:key, :value) in listing.entries) {
      final parts = key.substring(prefix.length).split('/');
      if (parts.length != 2 || !_isId(parts[0])) continue;
      if (parts[1] == 'event.json') {
        remote[parts[0]] = value;
      } else {
        (files[parts[0]] ??= {}).add(parts[1]);
      }
    }

    final state = await _SyncState.load(library, identity);
    var up = 0;
    var down = 0;
    final seen = <String>{};

    for (final event in [...library.all]) {
      if (event.owner != null && event.owner != identity) continue;
      seen.add(event.id);
      final last = state.events[event.id];
      final etag = remote[event.id];
      final changedHere = last == null || last.updated != event.updated;
      final changedThere = etag != null && last?.etag != etag;
      if (changedThere) {
        final theirs = await _fetch(identity, event.id, creds);
        _check(token);
        if (theirs != null &&
            (!changedHere || !theirs.updated.isBefore(event.updated))) {
          if (await _take(identity, theirs, files, creds, token, seen: event)) {
            state.events[event.id] = _Synced(etag, theirs.updated);
            down++;
          }
          continue;
        }
      }
      if (changedHere || etag == null) {
        final sent = await _send(identity, event, files, creds, token);
        state.events[event.id] = _Synced(sent, event.updated);
        if (event.owner == null) await library.setOwner(event, identity);
        up++;
      }
    }

    // Events only in the folder: new from another device.
    for (final MapEntry(key: id, value: etag) in remote.entries) {
      if (seen.contains(id) || state.events[id]?.etag == etag) continue;
      final theirs = await _fetch(identity, id, creds);
      _check(token);
      if (theirs == null) continue;
      // Another device's tombstone of an event never here: nothing to take.
      if (theirs.isDeleted ||
          await _take(identity, theirs, files, creds, token)) {
        state.events[id] = _Synced(etag, theirs.updated);
        if (!theirs.isDeleted) down++;
      }
    }

    await state.save(library);
    return (up, down);
  }

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
      debugPrint('TabScan: skipping the cloud copy of $id: $e');
      return null;
    }
  }

  /// Brings [theirs] here: its pages first, then the event, so it never
  /// shows without them. False when it changed here meanwhile ([seen]).
  Future<bool> _take(
    String identity,
    CaptureEvent theirs,
    Map<String, Set<String>> files,
    AwsCredentials creds,
    String token, {
    CaptureEvent? seen,
  }) async {
    for (final page in theirs.pages) {
      if (!page.hasFile || await library.hasPage(theirs.id, page)) continue;
      final key = _key(identity, theirs.id, page.fileName);
      await library.putPageStream(
        theirs.id,
        page,
        await bucket.getStream(key, credentials: creds),
      );
      _check(token);
    }
    return library.applyRemote(theirs.copyWith(owner: identity), seen: seen);
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
    final json = utf8.encode(jsonEncode(event.toJson(local: false)));
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
  static String contentTypeOf(EventPage page) => switch (page.extension) {
    'img' || 'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'gif' => 'image/gif',
    'mp4' || 'm4v' => 'video/mp4',
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    _ => 'application/octet-stream',
  };

  @override
  void dispose() {
    if (_started) {
      auth.removeListener(_onAuth);
      library.localChanges.removeListener(_onLocalChange);
    }
    _periodic?.cancel();
    _soon?.cancel();
    super.dispose();
  }
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
  _SyncState(this.identity, this.events);

  final String identity;
  final Map<String, _Synced> events;

  static Future<_SyncState> load(Library library, String identity) async {
    try {
      final json = await library.readMeta(CloudSync.stateName);
      if (json != null) {
        final m = (jsonDecode(json) as Map).cast<String, Object?>();
        if (m['identity'] == identity) {
          return _SyncState(identity, {
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
      debugPrint('TabScan: starting cloud sync over: $e');
    }
    return _SyncState(identity, {});
  }

  Future<void> save(Library library) => library.writeMeta(
    CloudSync.stateName,
    jsonEncode({
      'identity': identity,
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
