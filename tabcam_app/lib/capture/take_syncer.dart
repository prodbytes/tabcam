import 'dart:async';

import 'package:flutter/foundation.dart';

import '../library/capture_event.dart';
import '../library/library.dart';
import '../screens/video_page.dart' show pageFile;
import 'song_sync.dart';
import 'sound_reader.dart';
import 'take_log.dart';
import 'take_priority.dart';

/// Has a take's song found in its sound ([SongSync]) and kept with its
/// log ([Library.setTakeSync]), once: after Cam saves the take, and when
/// the editor opens one that hasn't been measured (a take from before,
/// or from a device that couldn't). One take at a time, and never while
/// a take records ([TakePriority.recording]): it waits for it to end.
abstract final class TakeSyncer {
  /// The takes being measured, by event and page.
  static final _measuring = <(String, String), Future<TakeLog?>>{};

  /// The last one asked for: the next waits for it.
  static Future<void> _last = Future.value();

  /// Forgets the takes being measured (a test's, left unfinished when its
  /// clock stopped, would hold the next back for ever).
  @visibleForTesting
  static void reset() {
    _measuring.clear();
    _last = Future.value();
  }

  /// Measures take [pageId] of event [eventId], unless it's been
  /// measured, and keeps what's found with its log. Its log as it is
  /// then; null when it's not a take with a log (or gone). Never throws.
  static Future<TakeLog?> sync(Library library, String eventId, String pageId) {
    final key = (eventId, pageId);
    return _measuring[key] ??= () async {
      final before = _last;
      final done = Completer<void>();
      _last = done.future;
      try {
        await before;
        return await _sync(library, eventId, pageId);
      } on Object catch (e) {
        debugPrint('TabCam: sync: not measured: $e');
        return _page(library, eventId, pageId)?.takeLog;
      } finally {
        done.complete();
        unawaited(_measuring.remove(key));
      }
    }();
  }

  static EventPage? _page(Library library, String eventId, String pageId) =>
      library.byId(eventId)?.allPages.where((p) => p.id == pageId).firstOrNull;

  static Future<TakeLog?> _sync(
    Library library,
    String eventId,
    String pageId,
  ) async {
    await _notRecording();
    final event = library.byId(eventId);
    final page = _page(library, eventId, pageId);
    final log = page?.takeLog;
    if (event == null || page == null || log == null) return null;
    if (log.sync != null) return log;
    final lined = log.linedSong;
    if (lined.isEmpty) return log;
    // The song, while it's still one of the capture's files.
    final song = event.allPages
        .where((p) => p.id == lined.first.page && (p.isAudio || p.isVideo))
        .firstOrNull;
    final reader = song == null ? null : SoundReader.open();
    if (song == null || reader == null) return log;
    final TakeSync? sync;
    try {
      sync = await SongSync.measure(
        log: log,
        take: await pageFile(library, event, page),
        song: await pageFile(library, event, song),
        reader: reader,
        wait: _notRecording,
      );
    } finally {
      reader.close();
    }
    if (sync == null) return log;
    debugPrint('TabCam: sync: $sync');
    await library.setTakeSync(eventId, pageId, sync);
    return _page(library, eventId, pageId)?.takeLog;
  }

  /// Waits while a take records.
  static Future<void> _notRecording() async {
    final recording = TakePriority.recording;
    while (recording.value) {
      final ended = Completer<void>();
      void changed() {
        if (!recording.value && !ended.isCompleted) ended.complete();
      }

      recording.addListener(changed);
      try {
        await ended.future;
      } finally {
        recording.removeListener(changed);
      }
    }
  }
}
