import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import 'cloud_sync.dart';
import 'cognito.dart';
import 'ocr_api.dart';
import 's3.dart';

/// TabScan Premium's cloud transcription, on the app's side.
///
/// For premium users the cloud OCR service (tabscan_locr) transcribes each
/// page image as cloud sync uploads it, into
/// `<identity>/ocr/<event id>/<page id>.json`. After each sync pass this
/// lists those results; once every image page of an event has one, their
/// texts become the event's text tab, unless the user has edited it since
/// (a text tab only changes while it's still the one transcribed here).
/// Pages that synced before the user upgraded get transcribed on request
/// (`/transcribe`), once each session.
///
/// It also keeps whether the user is premium ([status]), for the account
/// sheet's upgrade offer.
class CloudOcr extends ChangeNotifier {
  CloudOcr({
    required this.library,
    required this.auth,
    required this.sync,
    required this.bucket,
    required this.credentials,
    required this.api,
    this.backfillAfter = const Duration(minutes: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Library library;
  final AuthService auth;
  final CloudSync sync;
  final ObjectStore bucket;
  final CredentialSource credentials;
  final OcrApi api;

  /// How long a synced page may wait for its transcription before it's
  /// asked for (it was uploaded before the user upgraded).
  final Duration backfillAfter;
  final DateTime Function() _now;

  /// The state file's name in the store (beside the events).
  static const String stateName = 'cloudocr';

  /// Image pages the service reads, as cloud sync uploads them.
  static const Set<String> imageExtensions = {
    'img',
    'jpg',
    'jpeg',
    'png',
    'webp',
  };

  PremiumStatus? _status;

  /// Null while signed out, or until the service has answered.
  PremiumStatus? get status => _status;
  bool get premium => _status?.premium ?? false;

  bool _checking = false;
  bool get checking => _checking;

  /// Why the last check failed, if it did.
  String? get error => _error;
  String? _error;

  String? _token;
  String? _userId;
  bool _started = false;
  bool _collecting = false;
  SyncState? _lastSyncState;
  final Set<String> _requested = {};

  void start() {
    if (_started) return;
    _started = true;
    auth.addListener(_onAuth);
    sync.addListener(_onSync);
    _onAuth();
  }

  void _onAuth() {
    final token = auth.idToken;
    if (token == _token) return;
    final user = auth.user?.id;
    _token = token;
    if (token == null || user != _userId) {
      _status = null;
      _error = null;
      _requested.clear();
      notifyListeners();
    }
    _userId = user;
    // A refreshed token of the same user needs no new check.
    if (token != null && _status == null) unawaited(refresh());
  }

  void _onSync() {
    final state = sync.state;
    if (state == _lastSyncState) return;
    _lastSyncState = state;
    if (state == SyncState.synced && premium) unawaited(collect());
  }

  /// Asks the service again whether the user is premium (after upgrading,
  /// say), then collects transcriptions if they are.
  Future<void> refresh() async {
    final token = _token;
    if (token == null || _checking) return;
    _checking = true;
    notifyListeners();
    try {
      final status = await api.account(token);
      if (_token != token) return;
      _status = status;
      _error = status.checked ? null : 'Couldn\'t check Premium right now';
    } on OcrApiException catch (e) {
      _error = e.needsSignIn ? 'Sign in again' : 'Couldn\'t check Premium';
      debugPrint('TabScan: premium check failed: $e');
    } on Object catch (e) {
      _error = 'Couldn\'t check Premium';
      debugPrint('TabScan: premium check failed: $e');
    } finally {
      _checking = false;
      notifyListeners();
    }
    if (premium && sync.state == SyncState.synced) await collect();
  }

  /// Transcribes [event] in the cloud now (Read tab, for premium users):
  /// its synced pages that have no transcription yet. How many were queued.
  Future<int> transcribe(CaptureEvent event) async {
    final token = _token;
    if (token == null || !premium) return 0;
    _requested.add(event.id);
    return api.transcribe(token, event.id);
  }

  static bool isImage(EventPage page) =>
      page.isImage && imageExtensions.contains(page.extension);

  /// Applies the transcriptions that are complete, and asks for the missing
  /// ones that have waited too long.
  Future<void> collect() async {
    final token = _token;
    if (token == null || !premium || _collecting) return;
    _collecting = true;
    try {
      await _collect(token);
    } on Object catch (e) {
      debugPrint('TabScan: collecting transcriptions failed: $e');
    } finally {
      _collecting = false;
    }
  }

  Future<void> _collect(String token) async {
    final session = await credentials.session(token);
    final identity = session.identityId;
    final creds = session.credentials;
    final prefix = '$identity/ocr/';
    final done = <String, Set<String>>{};
    for (final key in (await bucket.listETags(
      prefix,
      credentials: creds,
    )).keys) {
      final parts = key.substring(prefix.length).split('/');
      if (parts.length != 2 || !parts[1].endsWith('.json')) continue;
      (done[parts[0]] ??= {}).add(parts[1].substring(0, parts[1].length - 5));
    }
    final state = await _OcrState.load(library, identity);
    var changed = false;
    for (final event in [...library.events]) {
      if (_token != token) return;
      if (event.owner != identity) continue; // not synced (yet), or another's
      final pages = [
        for (final p in event.pages)
          if (isImage(p)) p,
      ];
      if (pages.isEmpty) continue;
      final have = done[event.id] ?? const <String>{};
      final missing = [
        for (final p in pages)
          if (!have.contains(p.id)) p,
      ];
      if (missing.isNotEmpty) {
        final waited = _now().difference(event.updated) > backfillAfter;
        if (waited && _requested.add(event.id)) {
          try {
            await api.transcribe(token, event.id);
          } on Object catch (e) {
            debugPrint('TabScan: asking to transcribe ${event.id}: $e');
          }
        }
        continue;
      }
      final signature = pages.map((p) => p.id).join(',');
      final last = state.events[event.id];
      if (last?.signature == signature) continue;
      final texts = <String>[];
      for (final p in pages) {
        final bytes = await bucket.get(
          '$prefix${event.id}/${p.id}.json',
          credentials: creds,
        );
        final result = (jsonDecode(utf8.decode(bytes)) as Map)
            .cast<String, Object?>();
        if (result['status'] == 'ok' && result['text'] is String) {
          final text = (result['text'] as String).trimRight();
          if (text.isNotEmpty) texts.add(text);
        }
      }
      final text = texts.isEmpty ? null : '${texts.join('\n\n')}\n';
      // Only while the text tab is still ours: never over the user's edits
      // or an on-device reading.
      final current = library.byId(event.id);
      if (current == null) continue;
      final ours = current.tabText == null || current.tabText == last?.text;
      if (text != null && ours && current.tabText != text) {
        await library.update(current.copyWith(tabText: text));
      }
      state.events[event.id] = _Filled(signature, ours ? text : last?.text);
      changed = true;
    }
    if (changed) await state.save(library);
  }

  @override
  void dispose() {
    if (_started) {
      auth.removeListener(_onAuth);
      sync.removeListener(_onSync);
    }
    super.dispose();
  }
}

/// What was filled for an event: from which pages, and the text written.
class _Filled {
  const _Filled(this.signature, this.text);

  final String signature;
  final String? text;
}

class _OcrState {
  _OcrState(this.identity, this.events);

  final String identity;
  final Map<String, _Filled> events;

  static Future<_OcrState> load(Library library, String identity) async {
    try {
      final json = await library.readMeta(CloudOcr.stateName);
      if (json != null) {
        final m = (jsonDecode(json) as Map).cast<String, Object?>();
        if (m['identity'] == identity) {
          return _OcrState(identity, {
            for (final MapEntry(:key, :value)
                in (m['events'] as Map).cast<String, Object?>().entries)
              key: _Filled(
                (value as Map)['signature'] as String,
                value['text'] as String?,
              ),
          });
        }
      }
    } on Object catch (e) {
      debugPrint('TabScan: starting cloud OCR state over: $e');
    }
    return _OcrState(identity, {});
  }

  Future<void> save(Library library) => library.writeMeta(
    CloudOcr.stateName,
    jsonEncode({
      'identity': identity,
      'events': {
        for (final MapEntry(:key, :value) in events.entries)
          key: {'signature': value.signature, 'text': value.text},
      },
    }),
  );
}
