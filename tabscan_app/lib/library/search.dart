import 'capture_event.dart';

/// Whether [event] matches what the user typed in Home's search: every
/// word of [query] is somewhere in its title, artist, text tab, file
/// names, links (title and address) or who shared it. Case and accents
/// don't matter ("canción" finds "Cancion"); an empty query matches all.
bool matchesSearch(CaptureEvent event, String query) {
  final words = fold(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final haystack = fold(
    [
      event.title,
      event.artist,
      event.tabText,
      event.sharedBy,
      for (final page in event.pages) ...[page.title, page.url?.toString()],
    ].whereType<String>().join('\n'),
  );
  return words.every(haystack.contains);
}

/// [text] in lower case, without accents, for comparing.
String fold(String text) {
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    out.write(_plain[char] ?? char);
  }
  return out.toString();
}

/// Latin letters with accents (Spanish, Portuguese, and their neighbors),
/// as their plain letter.
const Map<String, String> _plain = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', //
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', //
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', //
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', //
  'ñ': 'n', 'ç': 'c', 'ý': 'y', 'ÿ': 'y',
};
