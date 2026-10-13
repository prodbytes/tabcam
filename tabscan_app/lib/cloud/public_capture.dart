import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../export/capture_link.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import 's3.dart';
import 'share_api.dart';
import 'sigv4.dart';

/// Why a capture's link didn't open: a wrong key, a capture its owner
/// deleted, or one not in the cloud yet.
class LinkUnavailable implements Exception {
  const LinkUnavailable(this.reason);

  final Object reason;

  @override
  String toString() => 'The link didn\'t open: $reason';
}

/// Opens captures by their link alone: anyone holding a capture's link
/// with its key (`…/app/?c=<id>&k=<key>`, [CaptureLink]) sees it, read
/// only, signed in or not, and without being one of the people it's shared
/// with. The share API swaps the key for read-only credentials to that
/// capture's folder.
class PublicCaptures {
  PublicCaptures({required this.api, required this.bucket});

  final ShareApi api;
  final ObjectStore bucket;

  /// Whether [link] can be opened this way: it names a capture and has its
  /// key.
  static bool opens(Uri link) =>
      CaptureLink.idIn(link) != null && CaptureLink.keyIn(link) != null;

  /// Brings the capture [link] names into [library] (one of its own, kept
  /// apart from the user's), read only: its pages, then the event. Throws
  /// [LinkUnavailable] when it can't.
  Future<CaptureEvent> open(Uri link, Library library) async =>
      (await _load(link, library, onlyIfChanged: false))!;

  /// Brings in what changed since [open] (or the last refresh): a rename,
  /// a file added, removed or moved, the text tab. Null when nothing did.
  /// Throws [LinkUnavailable] once the capture is gone (deleted, or the key
  /// changed).
  Future<CaptureEvent?> refresh(Uri link, Library library) =>
      _load(link, library, onlyIfChanged: true);

  /// Each link's credentials (by capture ID), until they expire soon.
  final Map<String, LinkedCapture> _access = {};

  /// Each capture's `event.json` as last brought in (by capture ID).
  final Map<String, List<int>> _seen = {};

  Future<CaptureEvent?> _load(
    Uri link,
    Library library, {
    required bool onlyIfChanged,
  }) async {
    final id = CaptureLink.idIn(link);
    final key = CaptureLink.keyIn(link);
    if (id == null || key == null) throw const LinkUnavailable('no key');
    await library.ready;
    try {
      var access = _access[id];
      if (access == null ||
          access.credentials.expiresSoon(AwsClock.shared.now())) {
        access = _access[id] = await api.openLink(id, key);
      }
      final creds = access.credentials;
      final folder = '${access.owner}/events/$id';
      final bytes = await bucket.get('$folder/event.json', credentials: creds);
      if (onlyIfChanged && listEquals(_seen[id], bytes)) return null;
      final event = CaptureEvent.fromJson(
        (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>(),
      );
      if (event.id != id || event.isDeleted) {
        throw const LinkUnavailable('deleted');
      }
      for (final page in event.pages) {
        if (!page.hasFile || await library.hasPage(id, page)) continue;
        await library.putPageStream(
          id,
          page,
          await bucket.getStream(
            '$folder/${page.fileName}',
            credentials: creds,
          ),
        );
      }
      final shown = event.copyWith(owner: access.owner, readOnly: true);
      await library.applyRemote(shown);
      _seen[id] = bytes;
      return shown;
    } on LinkUnavailable {
      rethrow;
    } on Object catch (e) {
      // New credentials next time: these may be what failed.
      _access.remove(id);
      throw LinkUnavailable(e);
    }
  }
}
