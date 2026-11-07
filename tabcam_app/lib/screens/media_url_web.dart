import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// A blob URL for [bytes], for the browser's players; released with
/// [releaseMediaUrl].
String mediaUrl(Uint8List bytes, String mimeType) => web.URL.createObjectURL(
  web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType)),
);

void releaseMediaUrl(String url) => web.URL.revokeObjectURL(url);
