import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../library/capture_event.dart';

/// A picked photo or video, to add to an event as a page.
class Media {
  const Media(this.file, this.kind, this.extension);

  final XFile file;
  final PageKind kind;
  final String extension;

  /// [file] as a page, by its extension (or MIME type); null when it's
  /// neither a known image nor a known video.
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
  };

  static const Map<String, String> _byMime = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/heic': 'heic',
    'image/webp': 'webp',
    'video/mp4': 'mp4',
    'video/quicktime': 'mov',
    'video/webm': 'webm',
  };
}

/// Pickers for photos and videos to add to an event. Files that are neither
/// images nor videos are left out, and counted in [MediaPick.skipped].
abstract final class MediaSource {
  /// Photos and videos from the device's photo library.
  static Future<MediaPick> library() async =>
      MediaPick.of(await ImagePicker().pickMultipleMedia());

  /// Image and video files, from the Files app (iOS), the system file
  /// picker (Android) or the browser.
  static Future<MediaPick> files() async {
    final files = await FilePicker.pickFiles(type: FileType.media);
    return MediaPick.of([for (final f in files) f.xFile]);
  }
}

/// What a picker returned: the media to add, and how many files weren't
/// images or videos.
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
        debugPrint('Not an image or video: ${f.name}');
      }
    }
    return MediaPick(media, files.length - media.length);
  }
}
