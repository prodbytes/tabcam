import 'dart:convert';

import 'tab_sites.dart';

/// A tab site's page, as imported: its title and the tab's text, as the
/// site shows it (tab staves, chords over lyrics, section names).
class TabPage {
  const TabPage({
    required this.url,
    required this.site,
    required this.title,
    required this.text,
  });

  final Uri url;
  final TabSite site;

  /// The page's title ("Song Chords by Artist"); empty when it has none.
  final String title;
  final String text;
}

/// The longest text kept from a page.
const int maxTabPageText = 200000;

/// [body], the page at [url] on [site], as a [TabPage]; null when there's
/// no tab's text in it (a page drawn by scripts, such as Songsterr's, or a
/// bot check instead of the page).
///
/// Ultimate Guitar's tab is in the page's data (`js-store`); the other
/// sites print it in `<pre>` blocks; a plain-text page (Classtab's) is the
/// tab itself.
TabPage? parseTabPage(
  String body,
  Uri url,
  TabSite site, {
  String? contentType,
}) {
  final plain =
      (contentType ?? '').toLowerCase().startsWith('text/plain') ||
      !body.contains('<');
  String? title;
  String? text;
  if (plain) {
    text = body;
  } else {
    final store = _ultimateGuitar(body);
    if (store != null) (title, text) = store;
    text ??= _preBlocks(body);
    title ??= _title(body);
  }
  text = _tidy(text ?? '');
  if (text.isEmpty) return null;
  if (text.length > maxTabPageText) text = text.substring(0, maxTabPageText);
  return TabPage(
    url: url,
    site: site,
    title: _oneLine(title ?? ''),
    text: text,
  );
}

/// Ultimate Guitar's song name and tab, from the page's data.
(String?, String?)? _ultimateGuitar(String html) {
  final tag = RegExp(r'''<div[^>]*class=["'][^"']*js-store[^"']*["'][^>]*>''')
      .firstMatch(html)
      ?.group(0);
  final data = tag == null
      ? null
      : RegExp(r'data-content="([^"]*)"').firstMatch(tag)?.group(1);
  if (data == null) return null;
  Object? json;
  try {
    json = jsonDecode(decodeHtmlEntities(data));
  } on FormatException {
    return null;
  }
  Object? at(Object? node, List<String> path) {
    for (final key in path) {
      if (node is! Map) return null;
      node = node[key];
    }
    return node;
  }

  final page = at(json, ['store', 'page', 'data']);
  final content = at(page, ['tab_view', 'wiki_tab', 'content']);
  if (content is! String || content.trim().isEmpty) return null;
  final (song, artist) = (
    at(page, ['tab', 'song_name']),
    at(page, ['tab', 'artist_name']),
  );
  final title = switch ((song, artist)) {
    (final String s, final String a) when a.isNotEmpty => '$s by $a',
    (final String s, _) => s,
    _ => null,
  };
  // [tab] marks a chord line with its lyrics; [ch]Am[/ch] a chord.
  final text = content.replaceAll(RegExp(r'\[/?(tab|ch)\]'), '');
  return (title, text);
}

/// Every `<pre>` block's text with more than one line, in page order.
String? _preBlocks(String html) {
  final blocks = [
    for (final m in RegExp(
      r'<pre\b[^>]*>(.*?)</pre>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html))
      _textOf(m.group(1)!),
  ].where((b) => b.trim().split('\n').length > 1);
  return blocks.isEmpty ? null : blocks.join('\n\n');
}

String? _title(String html) {
  final og = RegExp(
    r'''<meta[^>]*property=["']og:title["'][^>]*content=["']([^"']*)["']''',
    caseSensitive: false,
  ).firstMatch(html)?.group(1);
  final title =
      og ??
      RegExp(
        r'<title[^>]*>(.*?)</title>',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(html)?.group(1);
  return title == null ? null : decodeHtmlEntities(title);
}

/// An HTML fragment's text: line breaks kept, tags dropped.
String _textOf(String html) => decodeHtmlEntities(
  html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), ''),
);

/// Lines as the page has them (spaces line chords up), without trailing
/// spaces, at most one blank line in a row, none at either end.
String _tidy(String text) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\t', '    ')
      .split('\n')
      .map((l) => l.trimRight());
  final out = <String>[];
  for (final line in lines) {
    if (line.isEmpty && (out.isEmpty || out.last.isEmpty)) continue;
    out.add(line);
  }
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out.join('\n');
}

String _oneLine(String text) {
  final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return line.length > 200 ? line.substring(0, 200) : line;
}

const Map<String, String> _entities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'ndash': '–',
  'mdash': '—',
  'hellip': '…',
  'lsquo': '‘',
  'rsquo': '’',
  'ldquo': '“',
  'rdquo': '”',
  'aacute': 'á',
  'eacute': 'é',
  'iacute': 'í',
  'oacute': 'ó',
  'uacute': 'ú',
  'Aacute': 'Á',
  'Eacute': 'É',
  'Iacute': 'Í',
  'Oacute': 'Ó',
  'Uacute': 'Ú',
  'agrave': 'à',
  'acirc': 'â',
  'ecirc': 'ê',
  'ocirc': 'ô',
  'atilde': 'ã',
  'otilde': 'õ',
  'ntilde': 'ñ',
  'Ntilde': 'Ñ',
  'ccedil': 'ç',
  'Ccedil': 'Ç',
  'uuml': 'ü',
};

/// [text] with its HTML character references decoded (`&amp;`, `&#39;`,
/// `&#x2F;`, and the common named ones); unknown ones kept as written.
String decodeHtmlEntities(String text) => text.replaceAllMapped(
  RegExp(r'&(#[0-9]+|#[xX][0-9a-fA-F]+|[A-Za-z]+);'),
  (m) {
    final name = m.group(1)!;
    if (name.startsWith('#')) {
      final code = name[1] == 'x' || name[1] == 'X'
          ? int.tryParse(name.substring(2), radix: 16)
          : int.tryParse(name.substring(1));
      if (code == null || code <= 0 || code > 0x10FFFF) return m.group(0)!;
      return String.fromCharCode(code);
    }
    return _entities[name] ?? m.group(0)!;
  },
);
