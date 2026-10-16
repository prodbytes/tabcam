final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// The ID of the YouTube video [url] is for (`youtube.com/watch?v=…`,
/// `youtu.be/…`, `/shorts/…`, `/live/…`, `/embed/…`), or null for any
/// other link. Such a link shows as a video; it opens, as any link does,
/// outside the app (a new tab, or the browser or YouTube app).
String? youTubeVideoId(Uri url) {
  if (url.scheme != 'https' && url.scheme != 'http') return null;
  final host = url.host.toLowerCase();
  final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
  final String? id;
  if (host == 'youtu.be') {
    id = segments.firstOrNull;
  } else if (host == 'youtube.com' ||
      host.endsWith('.youtube.com') ||
      host == 'youtube-nocookie.com' ||
      host.endsWith('.youtube-nocookie.com')) {
    id = switch (segments) {
      ['watch'] => url.queryParameters['v'],
      ['shorts' || 'live' || 'embed' || 'v', final id, ...] => id,
      _ => null,
    };
  } else {
    id = null;
  }
  if (id == null || !_videoId.hasMatch(id)) return null;
  return id;
}
