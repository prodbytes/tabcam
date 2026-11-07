import 'dart:typed_data';

/// Off the web, files play from their paths; a file in memory (tests)
/// plays from a data URL.
String mediaUrl(Uint8List bytes, String mimeType) =>
    Uri.dataFromBytes(bytes, mimeType: mimeType).toString();

void releaseMediaUrl(String url) {}
