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

  /// The extensions the Files picker offers.
  static final List<String> extensions = _kinds.keys.toList();

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
  static Future<MediaPick> library() async =>
      MediaPick.of(await ImagePicker().pickMultipleMedia());

  /// PDF documents, from the Files app (iOS), the system file picker
  /// (Android) or the browser.
  static Future<MediaPick> documents() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    return MediaPick.of([for (final f in files) f.xFile]);
  }

  /// Image, video, audio and PDF files, from the Files app (iOS), the
  /// system file picker (Android) or the browser.
  static Future<MediaPick> files() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: Media.extensions,
    );
    return MediaPick.of([for (final f in files) f.xFile]);
  }
}

/// What a picker returned: the media to add, and how many files were of
/// other kinds.
class MediaPick {
  const MediaPick(this.media, this.skipped);

  final List<Media> media;
  final int skipped;

  factory MediaPick.of(List<XFile> files) {
    final media = <Media>[];
    for (final f in files) {
      final m = Media.of(f);
      if (m != null) {
        media.add(m);
      } else {
        debugPrint('Not a page: ${f.name}');
      }
    }
    return MediaPick(media, files.length - media.length);
  }
}
