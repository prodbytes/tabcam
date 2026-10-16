import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'capture_event.dart';
import 'event_store.dart';

/// Events kept as files, one folder per event in the app's documents folder:
/// `scans/<event id>/scan.json` (the folder and file names from before
/// scans were called events, so existing libraries still load) and a `<page id>.<extension>` per page (the
/// image as scanned, or the video as picked).
class PlatformEventStore implements EventStore {
  /// [_root] defaults to `scans/` in the app's documents folder.
  PlatformEventStore([this._root]);

  Directory? _root;

  Future<Directory> _scans() async {
    _root ??= Directory(
      '${(await getApplicationDocumentsDirectory()).path}/scans',
    );
    return _root!.create(recursive: true);
  }

  Future<Directory> _dir(String eventId) async =>
      Directory('${(await _scans()).path}/${checkId(eventId)}');

  @override
  Future<List<CaptureEvent>> list() async {
    final events = <CaptureEvent>[];
    await for (final entry in (await _scans()).list()) {
      final file = File('${entry.path}/scan.json');
      if (entry is! Directory || !await file.exists()) continue;
      try {
        events.add(
          CaptureEvent.fromJson(jsonDecode(await file.readAsString())),
        );
      } on Object catch (e) {
        // One broken event shouldn't hide the others.
        debugPrint('Skipping ${entry.path}: $e');
      }
    }
    return events..sort((a, b) => b.created.compareTo(a.created));
  }

  @override
  Future<void> save(CaptureEvent event) async {
    final dir = await (await _dir(event.id)).create();
    // Written beside, then renamed over, so a crash never leaves half a file.
    final temp = File('${dir.path}/scan.json.tmp');
    await temp.writeAsString(jsonEncode(event.toJson()), flush: true);
    await temp.rename('${dir.path}/scan.json');
  }

  @override
  Future<void> delete(String eventId) async {
    final dir = await _dir(eventId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<File> _page(String eventId, EventPage page) async => File(
    '${(await _dir(eventId)).path}/${checkId(page.id)}.'
    '${checkExtension(page.extension)}',
  );

  @override
  Future<void> putPage(String eventId, EventPage page, Uint8List bytes) async {
    await (await _dir(eventId)).create();
    await (await _page(eventId, page)).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> putPageFile(String eventId, EventPage page, XFile file) async {
    await (await _dir(eventId)).create();
    await file.saveTo((await _page(eventId, page)).path);
  }

  @override
  Future<Uint8List> page(String eventId, EventPage page) async =>
      (await _page(eventId, page)).readAsBytes();

  @override
  Future<String?> pagePath(String eventId, EventPage page) async =>
      (await _page(eventId, page)).path;

  @override
  Future<void> deletePage(String eventId, EventPage page) async {
    final file = await _page(eventId, page);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<bool> hasPage(String eventId, EventPage page) async =>
      (await _page(eventId, page)).exists();

  @override
  Future<(Stream<List<int>>, int)> pageStream(
    String eventId,
    EventPage page,
  ) async {
    final file = await _page(eventId, page);
    return (file.openRead(), await file.length());
  }

  @override
  Future<void> putPageStream(
    String eventId,
    EventPage page,
    Stream<List<int>> bytes,
  ) async {
    await (await _dir(eventId)).create();
    final file = await _page(eventId, page);
    // Written beside, then renamed over: a broken download leaves nothing.
    final temp = File('${file.path}.part');
    try {
      final sink = temp.openWrite();
      try {
        await sink.addStream(bytes);
        await sink.flush();
      } finally {
        await sink.close();
      }
      await temp.rename(file.path);
    } on Object {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  // Beside scans/, not in it: list() reads only event folders.
  Future<File> _meta(String name) async =>
      File('${(await _scans()).parent.path}/${checkId(name)}.json');

  @override
  Future<String?> readMeta(String name) async {
    final file = await _meta(name);
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> writeMeta(String name, String json) async {
    final file = await _meta(name);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(json, flush: true);
    await temp.rename(file.path);
  }
}
