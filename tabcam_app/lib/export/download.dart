import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../library/capture_event.dart';
import '../library/library.dart';

/// [name] as a file name every platform takes: no path separators or
/// characters Windows, Android or iOS refuse, never empty.
String safeFileName(String name, String extension) {
  var base = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // A name of dots alone means something else to a file system.
  if (base.isEmpty || RegExp(r'^\.+$').hasMatch(base)) base = 'file';
  if (base.length > 120) base = base.substring(0, 120).trimRight();
  return extension.isEmpty ? base : '$base.$extension';
}

/// The extension [page] downloads with: scanned pages kept as `img` are
/// JPEGs.
String downloadExtension(EventPage page) =>
    page.extension == 'img' ? 'jpg' : page.extension;

/// The capture's files as one zip ([saveAll] downloads it): each file
/// under its name in the list ([label]), the text tab as `<title> tab.txt`
/// and its links, one address a line, as `links.txt`. Names that repeat
/// get " (2)", " (3)"…
Future<Uint8List> zipCapture(
  Library library,
  CaptureEvent event,
  String Function(EventPage page) label,
) async {
  final archive = Archive();
  final used = <String>{};
  String unique(String name) {
    if (used.add(name.toLowerCase())) return name;
    final dot = name.lastIndexOf('.');
    final (base, ext) = dot > 0
        ? (name.substring(0, dot), name.substring(dot))
        : (name, '');
    for (var n = 2; ; n++) {
      final next = '$base ($n)$ext';
      if (used.add(next.toLowerCase())) return next;
    }
  }

  final links = <String>[];
  for (final page in event.visiblePages) {
    if (!page.hasFile) {
      if (page.url case final url?) links.add('$url');
      continue;
    }
    final bytes = await library.original(event, page);
    archive.add(
      ArchiveFile.bytes(
        unique(safeFileName(label(page), downloadExtension(page))),
        bytes,
      ),
    );
  }
  final tab = event.tabText?.trim() ?? '';
  if (tab.isNotEmpty) {
    archive.add(
      ArchiveFile.bytes(
        unique(safeFileName('${event.title} tab', 'txt')),
        utf8.encode('$tab\n'),
      ),
    );
  }
  if (links.isNotEmpty) {
    archive.add(
      ArchiveFile.bytes(unique('links.txt'), utf8.encode(links.join('\n'))),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

/// Downloads: in the browser, a download; on Android and iOS, the
/// system's "save as" (`file_picker`). False when the user cancelled.
abstract final class Downloads {
  /// Tests pass their own.
  @visibleForTesting
  static Future<bool> Function(String name, Uint8List bytes, String type) save =
      _save;

  static Future<bool> _save(String name, Uint8List bytes, String type) async {
    final saved = await FilePicker.saveFile(
      fileName: name,
      bytes: bytes,
      mimeType: type,
    );
    // The web gives nothing back once the download starts.
    return kIsWeb || saved != null;
  }

  /// Saves [page]'s file, named as the list names it ([label]).
  static Future<bool> saveFile(
    Library library,
    CaptureEvent event,
    EventPage page,
    String label,
  ) async => save(
    safeFileName(label, downloadExtension(page)),
    await library.original(event, page),
    page.mimeType,
  );

  /// Saves the whole capture as `<title>.zip` ([zipCapture]).
  static Future<bool> saveAll(
    Library library,
    CaptureEvent event,
    String Function(EventPage page) label,
  ) async => save(
    safeFileName(event.title, 'zip'),
    await zipCapture(library, event, label),
    'application/zip',
  );
}
