import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../auth/auth_service.dart';
import '../cloud/cloud_ocr.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import 'pdf_reader.dart';
import 'tab_reader.dart';

/// Where reading an event's tab stands, for its Text view.
enum ReadState {
  /// Reading now (on the device), or waiting for its turn.
  reading,

  /// Sent to TabCam Premium's cloud transcription: the text comes with
  /// sync.
  inCloud,

  /// Read, and no tab was found in the pages.
  noTab,

  /// Signed out: reading needs signing in (it reads once signed in).
  needsSignIn,

  /// Neither the device (the web) nor Premium can read it here.
  unsupported,

  /// Reading failed.
  failed,
}

/// How long a read may wait (on the cloud's transcription, mostly) before
/// it's given up as [ReadState.failed]: three times the OCR worker's
/// timeout, `Timeout: 900` (15 minutes) of `OcrFunction` in
/// `tabcam_infra/ocr.yaml`. A text that comes later still fills in.
const Duration cloudReadTimeout = Duration(minutes: 3 * 15);

/// Reads the tab of every event that has none yet, by itself: when the
/// user adds or changes the image or PDF pages of an event without a text
/// tab (a new capture, pages added, rotated or deleted), its pages are
/// read into its text tab, one event at a time. An event that has a text
/// tab (read, or written by the user) is only read again when asked
/// ([readSoon] with `again`, the Text tool's Read the tab again).
/// With TabCam Premium the cloud transcribes image pages ([CloudOcr]);
/// otherwise ML Kit on the device ([TabReader]). PDFs are read on the
/// device: their text where they have one (every platform, the web too),
/// else their pages as images, by ML Kit ([PdfTabReader]). A text the user edited or marked correct is
/// never replaced: a read only fills an empty text tab, or one an earlier
/// read left ([CaptureEvent.tabTextAuto], [CaptureEvent.tabTextCorrect]).
///
/// Reading needs signing in, in a build with sign-in: signed out, it waits
/// ([ReadState.needsSignIn]) and reads once the user signs in. Events
/// another device changed (cloud sync) are that device's to read.
class AutoReader extends ChangeNotifier {
  AutoReader({
    required this.library,
    this.auth,
    CloudOcr? Function()? ocr,
    Future<String?> Function(List<Uint8List> pages)? read,
    Future<String?> Function(
      Uint8List pdf,
      Future<String?> Function(List<Uint8List>)? ocr,
    )?
    readPdf,
    bool? supported,
    Duration cloudTimeout = cloudReadTimeout,
  }) : _timeout = cloudTimeout,
       _ocr = ocr ?? (() => null),
       _read = read ?? TabReader.read,
       _readPdf = readPdf ?? ((pdf, ocr) => PdfTabReader.read(pdf, ocr: ocr)),
       _supported = supported ?? TabReader.supported;

  final Library library;
  final AuthService? auth;
  final CloudOcr? Function() _ocr;
  final Future<String?> Function(List<Uint8List> pages) _read;
  final Future<String?> Function(
    Uint8List pdf,
    Future<String?> Function(List<Uint8List>)? ocr,
  )
  _readPdf;
  final bool _supported;

  /// How long a read may wait before it fails ([cloudReadTimeout]).
  final Duration _timeout;

  /// Gives up on reads the cloud hasn't answered ([ReadState.inCloud]).
  final Map<String, Timer> _timers = {};

  /// Each event's text tab when it was last asked to be read: a different
  /// one (the read's, by sync too, or the user's) ends what it said.
  final Map<String, String?> _textAt = {};

  /// Each event's latest read, so an earlier cloud read's answer doesn't
  /// speak for it.
  final Map<String, int> _reads = {};

  /// The cloud's answer when it came before the read was set in the cloud
  /// (true: a tab found).
  final Map<String, bool> _early = {};

  /// Events whose next read reads every page again (Read again).
  final Set<String> _again = {};

  final Map<String, ReadState> _states = {};

  /// Each event's image pages, as last seen: a read is due when they change.
  final Map<String, String> _seen = {};
  final List<String> _queue = [];
  bool _running = false;
  bool _started = false;
  bool _disposed = false;

  /// Where reading [eventId] stands; null when there's nothing to say (not
  /// read by this run, or read with a tab found: on the device, or by the
  /// cloud once its text arrives).
  ReadState? stateOf(String eventId) => _states[eventId];

  /// Starts watching the library, once it has loaded: the events there
  /// already were read before (or are read with Read again).
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await library.ready;
    if (_disposed) return;
    for (final e in library.all) {
      _seen[e.id] = _imagesOf(e);
    }
    library.localChanges.addListener(_onChange);
    library.addListener(_onLibrary);
    auth?.addListener(_onAuth);
  }

  String? _pagesNow(String id) => switch (library.byId(id)) {
    final e? => _imagesOf(e),
    null => null,
  };

  /// The pages a read reads: images and PDFs.
  static String _imagesOf(CaptureEvent e) => [
    for (final p in e.pages)
      if (p.isImage || p.isPdf) p.fileName,
  ].join(',');

  static bool _hasText(CaptureEvent e) => e.tabText?.trim().isNotEmpty ?? false;

  /// The user changed pages: events without a text tab yet are read.
  void _onChange() {
    for (final e in library.events) {
      final images = _imagesOf(e);
      if (_seen[e.id] == images) continue;
      _seen[e.id] = images;
      if (images.isEmpty || e.readOnly) continue;
      if (_hasText(e)) {
        _log('event ${e.id}: pages changed, already has a text tab');
        continue;
      }
      readSoon(e.id);
    }
  }

  /// Any change, cloud sync's too: an event gone, or one whose text tab
  /// came (the cloud's reading, say), has nothing more to say.
  void _onLibrary() {
    for (final MapEntry(:key, :value) in [..._states.entries]) {
      final e = library.byId(key);
      if (e == null ||
          (value != ReadState.reading &&
              _hasText(e) &&
              e.tabText != _textAt[key])) {
        _set(key, null);
      }
    }
  }

  /// A sign-in: the events that waited for it are read now.
  void _onAuth() {
    if (auth?.user == null) return;
    for (final MapEntry(:key, :value) in [..._states.entries]) {
      if (value == ReadState.needsSignIn) readSoon(key);
    }
  }

  /// Reads [eventId]'s tab after any reads before it (also for the Text
  /// view's Read again).
  ///
  /// With [again] (the Text view's Read again), the cloud reads every page
  /// again, not only those it hasn't read.
  void readSoon(String eventId, {bool again = false}) {
    if (again) _again.add(eventId);
    if (_disposed || _queue.contains(eventId)) return;
    _textAt[eventId] = library.byId(eventId)?.tabText;
    _reads[eventId] = (_reads[eventId] ?? 0) + 1;
    _early.remove(eventId);
    _queue.add(eventId);
    _set(eventId, ReadState.reading);
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final id = _queue.removeAt(0);
        final before = _pagesNow(id);
        try {
          _set(id, await _readOne(id).timeout(_timeout));
        } on Object catch (e) {
          _log('event $id: failed: $e');
          _set(id, ReadState.failed);
        }
        // Pages changed while it read: it reads them again.
        final after = _pagesNow(id);
        if (after != null && after != before && !_queue.contains(id)) {
          _log('event $id: pages changed while reading, reading again');
          _queue.add(id);
          _set(id, ReadState.reading);
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<ReadState?> _readOne(String id) async {
    final event = library.byId(id);
    if (event == null) return null;
    final auth = this.auth;
    if (auth != null && auth.available && auth.user == null) {
      _log('event $id: signed out, waiting for a sign-in');
      return ReadState.needsSignIn;
    }
    final images = event.pages.where((p) => p.isImage).length;
    final pdfs = event.pages.where((p) => p.isPdf).length;
    final ocr = _ocr();
    if (ocr != null && ocr.premium) {
      // PDFs only: their text, read here, is exact and at once; a scanned
      // one (no text) goes to the cloud, which reads its pages as photos.
      if (images == 0) {
        final parts = <String>[];
        for (final p in event.pages.where((p) => p.isPdf)) {
          if (await _readPdf(await library.original(event, p), null)
              case final t?) {
            parts.add(t);
          }
        }
        if (parts.isNotEmpty) {
          _log('event $id: read from its PDFs\' text');
          return _write(id, parts.join('\n\n'));
        }
      }
      // Its text comes with sync: then it's read (or no tab was found).
      final read = _reads[id];
      final collected = ocr.collected(id);
      final queued = await ocr.transcribe(event, again: _again.remove(id));
      _log('event $id: in the cloud, $queued pages queued');
      unawaited(
        collected.then((found) {
          if (_reads[id] != read) return;
          if (_states[id] == ReadState.reading) {
            _early[id] = found; // before it's set in the cloud
            return;
          }
          if (!const [
            ReadState.inCloud,
            ReadState.failed,
          ].contains(_states[id])) {
            return;
          }
          _log(
            'event $id: the cloud\'s reading came, ${found ? 'a tab' : 'no tab'}',
          );
          _set(id, found ? null : ReadState.noTab);
        }),
      );
      return ReadState.inCloud;
    }
    // Without OCR here (the web), only PDFs' text can be read.
    if (!_supported && pdfs == 0) {
      _log('event $id: this device can\'t read tabs');
      return ReadState.unsupported;
    }
    // In page order: each run of photos read together by OCR, each PDF by
    // its text (or OCR).
    final parts = <String>[];
    var read = 0;
    final photos = <Uint8List>[];
    Future<void> readPhotos() async {
      if (photos.isEmpty) return;
      if (await _read([...photos]) case final t?) parts.add(t);
      photos.clear();
    }

    for (final p in event.pages) {
      if (p.isImage && _supported) {
        read++;
        photos.add(await library.original(event, p));
      } else if (p.isPdf) {
        read++;
        await readPhotos();
        final bytes = await library.original(event, p);
        if (await _readPdf(bytes, _supported ? _read : null) case final t?) {
          parts.add(t);
        }
      }
    }
    await readPhotos();
    if (read == 0) return null;
    final text = parts.isEmpty ? null : parts.join('\n\n');
    _log(
      'event $id: $read pages, '
      '${text == null ? 'no tab found' : 'read ${text.length} characters'}',
    );
    // A scanned PDF needs OCR, which isn't here (the web): not "no tab".
    if (text == null && !_supported && pdfs > 0) {
      _log('event $id: a scanned PDF, and no OCR here');
      return ReadState.unsupported;
    }
    if (text == null) return ReadState.noTab;
    return _write(id, text);
  }

  /// Writes [text], read, as [id]'s text tab, unless the user edited it or
  /// marked it correct.
  Future<ReadState?> _write(String id, String text) async {
    // As it is now: the user may have edited the text meanwhile.
    final current = library.byId(id);
    if (current == null) return null;
    if (current.tabText != null &&
        (!current.tabTextAuto || current.tabTextCorrect)) {
      _log('event $id: kept the text (edited, or marked correct)');
      return null;
    }
    if (current.tabText != text) {
      // Only the text: pages added meanwhile stay.
      await library.patch(
        id,
        // The device's OCR says nothing of how sure it is: no doubts.
        (now) => now.copyWith(
          tabText: text,
          tabTextAuto: true,
          tabTextDoubts: const [],
        ),
      );
    }
    return null;
  }

  void _set(String id, ReadState? state) {
    if (_disposed) return;
    if (state == ReadState.inCloud) {
      if (_early.remove(id) case final found?) {
        state = found ? null : ReadState.noTab;
      }
    }
    _timers.remove(id)?.cancel();
    if (state == ReadState.inCloud) {
      _timers[id] = Timer(_timeout, () {
        _timers.remove(id);
        if (_states[id] != ReadState.inCloud) return;
        _log('event $id: no reading from the cloud in $_timeout, failed');
        _set(id, ReadState.failed);
      });
    }
    if (state == null) {
      _states.remove(id);
    } else {
      _states[id] = state;
    }
    notifyListeners();
  }

  /// The troubleshooting log (`devbox run android-log`, or the browser's
  /// console).
  static void _log(String message) => debugPrint('TabCam: read tab: $message');

  @override
  void dispose() {
    _disposed = true;
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    library.localChanges.removeListener(_onChange);
    library.removeListener(_onLibrary);
    auth?.removeListener(_onAuth);
    super.dispose();
  }
}

/// Gives the screens the app's [AutoReader].
class AutoReaderScope extends InheritedNotifier<AutoReader> {
  const AutoReaderScope({
    super.key,
    required AutoReader super.notifier,
    required super.child,
  });

  /// The app's reader, or null (in tests, say).
  static AutoReader? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AutoReaderScope>()?.notifier;
}
