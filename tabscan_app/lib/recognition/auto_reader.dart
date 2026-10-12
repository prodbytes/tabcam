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

  /// Sent to TabScan Premium's cloud transcription: the text comes with
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

/// Reads every event's tab by itself: whenever the user adds or changes an
/// event's image or PDF pages (a new capture, pages added, rotated or
/// deleted), its pages are read into its text tab, one event at a time.
/// With TabScan Premium the cloud transcribes image pages ([CloudOcr]);
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
  }) : _ocr = ocr ?? (() => null),
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
  /// read by this run, or read with a tab found).
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

  void _onChange() {
    for (final e in library.events) {
      final images = _imagesOf(e);
      if (_seen[e.id] == images) continue;
      _seen[e.id] = images;
      if (images.isEmpty || e.readOnly) continue;
      readSoon(e.id);
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
          _set(id, await _readOne(id));
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
      final queued = await ocr.transcribe(event, again: _again.remove(id));
      _log('event $id: in the cloud, $queued pages queued');
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
        (now) => now.copyWith(tabText: text, tabTextAuto: true),
      );
    }
    return null;
  }

  void _set(String id, ReadState? state) {
    if (_disposed) return;
    if (state == null) {
      _states.remove(id);
    } else {
      _states[id] = state;
    }
    notifyListeners();
  }

  /// The troubleshooting log (`devbox run android-log`, or the browser's
  /// console).
  static void _log(String message) => debugPrint('TabScan: read tab: $message');

  @override
  void dispose() {
    _disposed = true;
    library.localChanges.removeListener(_onChange);
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
