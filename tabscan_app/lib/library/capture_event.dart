import '../processing/page_filter.dart';

/// What a page is: a picture of the tab, or a video (someone playing it,
/// a lesson).
enum PageKind { image, video }

/// One page of an event: its file is kept by the store as `<id>.<extension>`.
class EventPage {
  const EventPage({
    required this.id,
    this.filter = PageFilter.tab,
    this.kind = PageKind.image,
    this.extension = 'img',
  });

  final String id;

  /// How an image page is shown; videos are always shown as they are.
  final PageFilter filter;
  final PageKind kind;

  /// The file's extension, lower case (`jpg`, `mp4`, ...). Scanned pages
  /// from before videos were added are `img`.
  final String extension;

  bool get isVideo => kind == PageKind.video;

  /// The page's file name in its event's folder.
  String get fileName => '$id.$extension';

  EventPage copyWith({PageFilter? filter}) => EventPage(
    id: id,
    filter: filter ?? this.filter,
    kind: kind,
    extension: extension,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'filter': filter.name,
    'kind': kind.name,
    'extension': extension,
  };

  factory EventPage.fromJson(Map<String, Object?> json) => EventPage(
    id: checkId(json['id'] as String),
    filter: PageFilter.byName(json['filter'] as String?),
    kind: json['kind'] == 'video' ? PageKind.video : PageKind.image,
    extension: checkExtension(json['extension'] as String? ?? 'img'),
  );
}

/// A scanned tab: its pages, what it's called, and the text tab read from
/// it (if it was read).
class CaptureEvent {
  CaptureEvent({
    required this.id,
    required this.title,
    required this.created,
    DateTime? updated,
    this.artist = '',
    this.pages = const [],
    this.tabText,
    this.deleted,
    this.owner,
  }) : updated = updated ?? created;

  /// What's left of [event] once deleted: a tombstone, so the deletion
  /// reaches the user's other devices through cloud sync.
  CaptureEvent.tombstone(CaptureEvent event, DateTime when)
    : this(
        id: event.id,
        title: '',
        created: event.created,
        updated: when,
        deleted: when,
        owner: event.owner,
      );

  final String id;
  final String title;
  final String artist;
  final DateTime created;

  /// When it last changed on any device (cloud sync keeps the latest).
  final DateTime updated;
  final List<EventPage> pages;

  /// The tab as plain text, from Read tab, as the user last edited it.
  final String? tabText;

  /// When it was deleted, for a tombstone: not shown, no pages.
  final DateTime? deleted;
  bool get isDeleted => deleted != null;

  /// The Cognito identity ID it syncs with, once it has synced (null
  /// before). Kept on the device only: other users' events never sync.
  final String? owner;

  /// A file name for exports: the title, safe for any file system.
  String get fileName {
    final name = [
      title,
      if (artist.isNotEmpty) artist,
    ].join(' - ').replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '').trim();
    return name.isEmpty ? 'tab' : name;
  }

  CaptureEvent copyWith({
    String? title,
    String? artist,
    List<EventPage>? pages,
    String? tabText,
    DateTime? updated,
    String? owner,
  }) => CaptureEvent(
    id: id,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    created: created,
    updated: updated ?? this.updated,
    pages: pages ?? this.pages,
    tabText: tabText ?? this.tabText,
    deleted: deleted,
    owner: owner ?? this.owner,
  );

  /// The event as saved: on the device with its [owner], in the cloud
  /// ([local] false) without.
  Map<String, Object?> toJson({bool local = true}) => {
    'id': id,
    'title': title,
    'artist': artist,
    'created': created.toUtc().toIso8601String(),
    'updated': updated.toUtc().toIso8601String(),
    'pages': [for (final p in pages) p.toJson()],
    if (tabText != null) 'tabText': tabText,
    if (deleted != null) 'deleted': deleted!.toUtc().toIso8601String(),
    if (local && owner != null) 'owner': owner,
  };

  factory CaptureEvent.fromJson(Map<String, Object?> json) {
    DateTime? time(String key) => switch (json[key]) {
      final String t => DateTime.parse(t).toLocal(),
      _ => null,
    };
    return CaptureEvent(
      id: checkId(json['id'] as String),
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      created: time('created')!,
      updated: time('updated'),
      pages: [
        for (final p in json['pages'] as List? ?? const [])
          EventPage.fromJson((p as Map).cast<String, Object?>()),
      ],
      tabText: json['tabText'] as String?,
      deleted: time('deleted'),
      owner: json['owner'] as String?,
    );
  }
}

final RegExp _id = RegExp(r'^[a-z0-9]{1,32}$');

/// [id] if it's a valid event or page ID; IDs name files, so anything else
/// (a path, say) is refused.
String checkId(String id) {
  if (!_id.hasMatch(id)) throw FormatException('Bad ID', id);
  return id;
}

final RegExp _extension = RegExp(r'^[a-z0-9]{1,5}$');

/// [extension] if it's a plain file extension; it names files, so anything
/// else is refused.
String checkExtension(String extension) {
  if (!_extension.hasMatch(extension)) {
    throw FormatException('Bad extension', extension);
  }
  return extension;
}

var _lastId = 0;

/// A new ID: the time in microseconds, base 36, unique within this run.
String newId() {
  var now = DateTime.now().microsecondsSinceEpoch;
  if (now <= _lastId) now = _lastId + 1;
  _lastId = now;
  return now.toRadixString(36);
}
