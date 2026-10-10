import '../processing/page_filter.dart';

/// One page of a scan: its image is kept by the store under [id].
class ScanPage {
  const ScanPage({required this.id, this.filter = PageFilter.tab});

  final String id;
  final PageFilter filter;

  ScanPage copyWith({PageFilter? filter}) =>
      ScanPage(id: id, filter: filter ?? this.filter);

  Map<String, Object?> toJson() => {'id': id, 'filter': filter.name};

  factory ScanPage.fromJson(Map<String, Object?> json) => ScanPage(
    id: checkId(json['id'] as String),
    filter: PageFilter.byName(json['filter'] as String?),
  );
}

/// A scanned tab: its pages, what it's called, and the text tab read from
/// it (if it was read).
class Scan {
  const Scan({
    required this.id,
    required this.title,
    required this.created,
    this.artist = '',
    this.pages = const [],
    this.tabText,
  });

  final String id;
  final String title;
  final String artist;
  final DateTime created;
  final List<ScanPage> pages;

  /// The tab as plain text, from Read tab, as the user last edited it.
  final String? tabText;

  /// A file name for exports: the title, safe for any file system.
  String get fileName {
    final name = [
      title,
      if (artist.isNotEmpty) artist,
    ].join(' - ').replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '').trim();
    return name.isEmpty ? 'tab' : name;
  }

  Scan copyWith({
    String? title,
    String? artist,
    List<ScanPage>? pages,
    String? tabText,
  }) => Scan(
    id: id,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    created: created,
    pages: pages ?? this.pages,
    tabText: tabText ?? this.tabText,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'created': created.toUtc().toIso8601String(),
    'pages': [for (final p in pages) p.toJson()],
    if (tabText != null) 'tabText': tabText,
  };

  factory Scan.fromJson(Map<String, Object?> json) => Scan(
    id: checkId(json['id'] as String),
    title: json['title'] as String? ?? '',
    artist: json['artist'] as String? ?? '',
    created: DateTime.parse(json['created'] as String).toLocal(),
    pages: [
      for (final p in json['pages'] as List? ?? const [])
        ScanPage.fromJson((p as Map).cast<String, Object?>()),
    ],
    tabText: json['tabText'] as String?,
  );
}

final RegExp _id = RegExp(r'^[a-z0-9]{1,32}$');

/// [id] if it's a valid scan or page ID; IDs name files, so anything else
/// (a path, say) is refused.
String checkId(String id) {
  if (!_id.hasMatch(id)) throw FormatException('Bad ID', id);
  return id;
}

var _lastId = 0;

/// A new ID: the time in microseconds, base 36, unique within this run.
String newId() {
  var now = DateTime.now().microsecondsSinceEpoch;
  if (now <= _lastId) now = _lastId + 1;
  _lastId = now;
  return now.toRadixString(36);
}
