import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../auth/auth_service.dart';
import '../cloud/cloud_ocr.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
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
/// event's image pages (a new capture, pages added, rotated or deleted),
/// its pages are read into its text tab, one event at a time. With TabScan
/// Premium the cloud transcribes them ([CloudOcr]); otherwise ML Kit on
/// the device ([TabReader]). A text the user edited or marked correct is
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
    bool? supported,
  }) : _ocr = ocr ?? (() => null),
       _read = read ?? TabReader.read,
       _supported = supported ?? TabReader.supported;

  final Library library;
  final AuthService? auth;
  final CloudOcr? Function() _ocr;
  final Future<String?> Function(List<Uint8List> pages) _read;
  final bool _supported;

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

  static String _imagesOf(CaptureEvent e) => [
    for (final p in e.pages)
      if (p.isImage) p.fileName,
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
  void readSoon(String eventId) {
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
        try {
          _set(id, await _readOne(id));
        } on Object catch (e) {
          _log('event $id: failed: $e');
          _set(id, ReadState.failed);
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
    final ocr = _ocr();
    if (ocr != null && ocr.premium) {
      final queued = await ocr.transcribe(event);
      _log('event $id: in the cloud, $queued pages queued');
      return ReadState.inCloud;
    }
    if (!_supported) {
      _log('event $id: this device can\'t read tabs');
      return ReadState.unsupported;
    }
    final pages = [
      for (final p in event.pages)
        if (p.isImage) await library.original(event, p),
    ];
    if (pages.isEmpty) return null;
    final text = await _read(pages);
    _log(
      'event $id: ${pages.length} pages, '
      '${text == null ? 'no tab found' : 'read ${text.length} characters'}',
    );
    if (text == null) return ReadState.noTab;
    // As it is now: the user may have edited the text meanwhile.
    final current = library.byId(id);
    if (current == null) return null;
    if (current.tabText != null &&
        (!current.tabTextAuto || current.tabTextCorrect)) {
      _log('event $id: kept the text (edited, or marked correct)');
      return null;
    }
    if (current.tabText != text) {
      await library.update(current.copyWith(tabText: text, tabTextAuto: true));
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
