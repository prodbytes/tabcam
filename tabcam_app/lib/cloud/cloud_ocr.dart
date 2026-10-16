import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import '../l10n/language.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import 'cloud_sync.dart';
import 'cognito.dart';
import 'ocr_api.dart';
import 's3.dart';

/// TabCam Premium's cloud transcription, on the app's side.
///
/// For premium users the cloud OCR service (tabcam_locr) transcribes each
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
    // PDFs: each page read as if photographed.
    'pdf',
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

  /// Events read again (Read again): each page's result ETag when it was
  /// asked for (null until listed). The earlier results aren't the new
  /// reading: the event waits until every page's result is rewritten.
  final Map<String, Map<String, String>?> _again = {};

  /// Who waits for an event's transcription to be collected ([collected]).
  final Map<String, Completer<bool>> _waiting = {};

  /// Completes once [eventId]'s transcription is collected: true when a
  /// tab was found (the text tab filled, or kept as the user left it),
  /// false when no page had one. Ask before [transcribe], so a quick
  /// result isn't missed.
  Future<bool> collected(String eventId) =>
      (_waiting[eventId] ??= Completer<bool>()).future;

  void _collected(String eventId, bool found) =>
      _waiting.remove(eventId)?.complete(found);

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
      _again.clear();
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
      _error = status.checked ? null : appL10n.accountPremiumCheckFailedNow;
    } on OcrApiException catch (e) {
      _error = e.needsSignIn
          ? appL10n.accountSignInAgain
          : e.needsGoogle
          ? appL10n.accountPremiumNeedsGoogle
          : appL10n.accountPremiumCheckFailed;
      debugPrint('TabCam: premium check failed: $e');
    } on Object catch (e) {
      _error = appL10n.accountPremiumCheckFailed;
      debugPrint('TabCam: premium check failed: $e');
    } finally {
      _checking = false;
      notifyListeners();
    }
    if (premium && sync.state == SyncState.synced) await collect();
  }

  /// Transcribes [event] in the cloud now (reading by itself, for premium
  /// users):
  /// its synced pages that have no transcription yet. How many were queued.
  /// With [again] (Read again), every page, read before or not.
  Future<int> transcribe(CaptureEvent event, {bool again = false}) async {
    final token = _token;
    if (token == null || !premium) {
      debugPrint(
        'TabCam: cloud OCR: not transcribing ${event.id}: '
        '${token == null ? 'no ID token' : 'not premium'}',
      );
      return 0;
    }
    _requested.add(event.id);
    if (again) {
      _again[event.id] = null;
      try {
        final session = await credentials.session(token);
        _again[event.id] = await bucket.listETags(
          '${session.identityId}/ocr/${event.id}/',
          credentials: session.credentials,
        );
      } on Object catch (e) {
        // Then any result there counts as the new reading.
        debugPrint('TabCam: cloud OCR: listing ${event.id}\'s results: $e');
        _again[event.id] = const {};
      }
    }
    return api.transcribe(token, event.id, again: again);
  }

  /// Auto-correct: checks [text], [event]'s text tab, against [song]'s tab
  /// found online. Throws [OcrApiException] (402) for users without
  /// Premium, 401 signed out.
  Future<AutocorrectResult> autocorrect(
    CaptureEvent event, {
    required String song,
    required String text,
  }) async {
    final token = _token;
    if (token == null) throw OcrApiException(401, 'sign in');
    if (!premium) throw OcrApiException(402, 'premium only');
    return api.autocorrect(token, eventId: event.id, song: song, text: text);
  }

  /// A page the service reads: an image, or a PDF.
  static bool isImage(EventPage page) =>
      (page.isImage || page.isPdf) && imageExtensions.contains(page.extension);

  /// Applies the transcriptions that are complete, and asks for the missing
  /// ones that have waited too long.
  Future<void> collect() async {
    final token = _token;
    if (token == null || !premium || _collecting) return;
    _collecting = true;
    try {
      await _collect(token);
    } on Object catch (e) {
      debugPrint('TabCam: collecting transcriptions failed: $e');
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
    final etags = await bucket.listETags(prefix, credentials: creds);
    for (final key in etags.keys) {
      final parts = key.substring(prefix.length).split('/');
      if (parts.length != 2 || !parts[1].endsWith('.json')) continue;
      (done[parts[0]] ??= {}).add(parts[1].substring(0, parts[1].length - 5));
    }
    debugPrint(
      'TabCam: cloud OCR: results for ${done.length} events '
      '(${done.values.fold(0, (n, pages) => n + pages.length)} pages)',
    );
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
        debugPrint(
          'TabCam: cloud OCR: ${event.id} waits for ${missing.length} of '
          '${pages.length} pages${waited ? ', asking for them' : ''}',
        );
        if (waited && _requested.add(event.id)) {
          try {
            await api.transcribe(token, event.id);
          } on Object catch (e) {
            debugPrint('TabCam: asking to transcribe ${event.id}: $e');
          }
        }
        continue;
      }
      final signature = pages.map((p) => p.id).join(',');
      final last = state.events[event.id];
      // Read again: only once every page's result is a new one.
      final again = _again.containsKey(event.id);
      if (again) {
        final before = _again[event.id];
        if (before == null ||
            pages.any((p) {
              final key = '$prefix${event.id}/${p.id}.json';
              return before[key] != null && before[key] == etags[key];
            })) {
          debugPrint(
            'TabCam: cloud OCR: ${event.id} waits for its new reading',
          );
          continue;
        }
        _again.remove(event.id);
      } else if (last?.signature == signature) {
        _collected(event.id, last?.text != null);
        continue;
      }
      final texts = <String>[];
      for (final p in pages) {
        final bytes = await bucket.get(
          '$prefix${event.id}/${p.id}.json',
          credentials: creds,
        );
        final result = (jsonDecode(utf8.decode(bytes)) as Map)
            .cast<String, Object?>();
        debugPrint(
          'TabCam: cloud OCR: ${event.id}/${p.id}: ${result['status']}'
          '${result['error'] == null ? '' : ' (${result['error']})'}, '
          '${result['staves']} staves, ${result['lines']} lines, '
          'version ${result['version']}',
        );
        if (result['status'] == 'ok' && result['text'] is String) {
          final text = (result['text'] as String).trimRight();
          if (text.isNotEmpty) texts.add(text);
        }
      }
      final text = texts.isEmpty ? null : '${texts.join('\n\n')}\n';
      // Only while the text tab is still ours: never over the user's edits,
      // an on-device reading, or a text tab the user marked correct.
      final current = library.byId(event.id);
      if (current == null) continue;
      // Read again also replaces a text another read left (an on-device
      // one too).
      final ours =
          !current.tabTextCorrect &&
          (current.tabText == null ||
              current.tabText == last?.text ||
              (again && current.tabTextAuto));
      if (text != null && ours && current.tabText != text) {
        await library.update(
          current.copyWith(tabText: text, tabTextAuto: true),
        );
      }
      debugPrint(
        'TabCam: cloud OCR: ${event.id}: '
        '${text == null
            ? 'no tab on any page'
            : !ours
            ? 'text tab edited, kept'
            : 'text tab filled'}',
      );
      state.events[event.id] = _Filled(signature, ours ? text : last?.text);
      changed = true;
      _collected(event.id, text != null);
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
      debugPrint('TabCam: starting cloud OCR state over: $e');
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
