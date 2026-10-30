import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../library/capture_event.dart';

/// A picked photo, video, recording or PDF, to add to an event as a page.
class Media {
  const Media(this.file, this.kind, this.extension);

  final XFile file;
  final PageKind kind;
  final String extension;

  /// [file] as a page, by its extension (or MIME type); null when it's not
  /// a known image, video, recording or PDF.
  static Media? of(XFile file) {
    final name = file.name.toLowerCase();
    final dot = name.lastIndexOf('.');
    var extension = dot < 0 ? '' : name.substring(dot + 1);
    final mime = file.mimeType ?? '';
    if (extension.isEmpty || !_kinds.containsKey(extension)) {
      extension = _byMime[mime] ?? extension;
    }
    final kind = _kinds[extension];
    if (kind == null) return null;
    return Media(file, kind, extension);
  }

  static const Map<String, PageKind> _kinds = {
    'jpg': PageKind.image,
    'jpeg': PageKind.image,
    'png': PageKind.image,
    'heic': PageKind.image,
    'heif': PageKind.image,
    'webp': PageKind.image,
    'gif': PageKind.image,
    'mp4': PageKind.video,
    'mov': PageKind.video,
    'm4v': PageKind.video,
    'webm': PageKind.video,
    '3gp': PageKind.video,
    'mp3': PageKind.audio,
    'm4a': PageKind.audio,
    'aac': PageKind.audio,
    'wav': PageKind.audio,
    'ogg': PageKind.audio,
    'oga': PageKind.audio,
    'opus': PageKind.audio,
    'flac': PageKind.audio,
    'pdf': PageKind.pdf,
  };

  /// The extensions the Files picker offers: the pages', and zips (whose
  /// files are added, [MediaPick.from]).
  static final List<String> extensions = [..._kinds.keys, 'zip'];

  static const Map<String, String> _byMime = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/heic': 'heic',
    'image/webp': 'webp',
    'video/mp4': 'mp4',
    'video/quicktime': 'mov',
    'video/webm': 'webm',
    'audio/mpeg': 'mp3',
    'audio/mp4': 'm4a',
    'audio/x-m4a': 'm4a',
    'audio/aac': 'aac',
    'audio/wav': 'wav',
    'audio/x-wav': 'wav',
    'audio/ogg': 'ogg',
    'audio/flac': 'flac',
    'application/pdf': 'pdf',
  };
}

/// Pickers for photos, videos, recordings and PDFs to add to an event.
/// Files of other kinds are left out, and counted in [MediaPick.skipped].
abstract final class MediaSource {
  /// Photos and videos from the device's photo library.
  /// Their names are made up by the picker (`image_picker_…`), so they
  /// don't name anything ([MediaPick.fileName] is null).
  static Future<MediaPick> library() async {
    final pick = await MediaPick.from(await ImagePicker().pickMultipleMedia());
    return MediaPick(pick.media, pick.skipped);
  }

  /// PDF documents, from the Files app (iOS), the system file picker
  /// (Android) or the browser.
  static Future<MediaPick> documents() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    return MediaPick.from([for (final f in files) f.xFile]);
  }

  /// Image, video, audio and PDF files, and zips of them, from the Files app (iOS), the
  /// system file picker (Android) or the browser.
  static Future<MediaPick> files() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: Media.extensions,
    );
    return MediaPick.from([for (final f in files) f.xFile]);
  }
}

/// What a picker returned: the media to add, how many files were of
/// other kinds, and the name of the first file picked.
class MediaPick {
  const MediaPick(this.media, this.skipped, {this.fileName});

  final List<Media> media;
  final int skipped;

  /// The first file picked's name (a zip's own, not its files'), to name
  /// a capture made of them; null when the picker makes names up.
  final String? fileName;

  /// [files] as media. A zip's files take its place, in its order, its
  /// folders flattened (a zip in it too, one level down); macOS's
  /// `__MACOSX` folder and hidden files are left out. Files of other
  /// kinds, in a zip or not, are counted in [skipped], as is a zip that
  /// can't be read or is too big ([maxZipEntries], [maxZipBytes]).
  static Future<MediaPick> from(List<XFile> files) async {
    final media = <Media>[];
    var skipped = 0;
    Future<void> add(XFile file, int depth) async {
      if (depth < 2 && isZip(file)) {
        final inside = await unzip(file);
        if (inside == null) {
          skipped++;
          return;
        }
        for (final f in inside) {
          await add(f, depth + 1);
        }
        return;
      }
      if (Media.of(file) case final m?) {
        media.add(m);
      } else {
        debugPrint('Not a page: ${file.name}');
        skipped++;
      }
    }

    for (final f in files) {
      await add(f, 0);
    }
    return MediaPick(media, skipped, fileName: files.firstOrNull?.name);
  }

  /// At most this many files in a zip, and this many bytes unzipped: a
  /// bigger one (a zip bomb, say) isn't opened.
  static const maxZipEntries = 1000;
  static const maxZipBytes = 1024 * 1024 * 1024;

  /// Whether [file] is a zip, by its extension or MIME type.
  static bool isZip(XFile file) =>
      file.name.toLowerCase().endsWith('.zip') ||
      const {
        'application/zip',
        'application/x-zip-compressed',
      }.contains(file.mimeType);

  /// [zip]'s files, or null when it can't be read (or has nothing in it)
  /// or is too big.
  static Future<List<XFile>?> unzip(XFile zip) async {
    try {
      final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
      // Bytes that aren't a zip decode to nothing, rather than failing.
      if (archive.isEmpty) return null;
      final entries = [
        for (final e in archive.files)
          if (e.isFile && _kept(e.name)) e,
      ];
      final bytes = entries.fold<int>(0, (sum, e) => sum + e.size);
      if (entries.length > maxZipEntries || bytes > maxZipBytes) {
        debugPrint('TabCam: ${zip.name}: too big to unzip');
        return null;
      }
      return [
        for (final e in entries)
          if (e.name.split('/').last case final name)
            // The name is the path's on Android and iOS, the name on the web.
            XFile.fromData(e.content, name: name, path: name),
      ];
    } on Object catch (e) {
      debugPrint('TabCam: ${zip.name} can\'t be unzipped: $e');
      return null;
    }
  }

  /// Whether a zip's [path] is a file to add: not in macOS's `__MACOSX`
  /// folder, nor hidden (`.DS_Store`, `._x`).
  static bool _kept(String path) {
    final parts = path.split('/');
    return !parts.contains('__MACOSX') && !parts.last.startsWith('.');
  }
}
