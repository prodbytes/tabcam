import '../processing/page_filter.dart';

/// What a page is: a picture of the tab, a video (someone playing it, a
/// lesson), or a link (a lesson online, a recording, the song's page).
enum PageKind { image, video, link }

/// One page of an event: an image's or video's file is kept by the store as
/// `<id>.<extension>`; a link has no file, only its [url].
class EventPage {
  const EventPage({
    required this.id,
    this.filter = PageFilter.tab,
    this.kind = PageKind.image,
    this.extension = 'img',
    this.url,
    this.title,
  });

  /// A link page to [url] (checked with [checkUrl]), with an optional
  /// [title].
  EventPage.link({required this.id, required Uri url, String? title})
    : filter = PageFilter.original,
      kind = PageKind.link,
      extension = 'url',
      url = checkUrl(url),
      title = (title?.trim().isEmpty ?? true) ? null : title!.trim();

  final String id;

  /// How an image page is shown; videos are always shown as they are.
  final PageFilter filter;
  final PageKind kind;

  /// The file's extension, lower case (`jpg`, `mp4`, ...). Scanned pages
  /// from before videos were added are `img`.
  final String extension;

  /// A link's address: http or https only.
  final Uri? url;

  /// A link's name, as the user gave it; null shows the address.
  final String? title;

  bool get isVideo => kind == PageKind.video;
  bool get isImage => kind == PageKind.image;
  bool get isLink => kind == PageKind.link;

  /// Whether the store keeps a file for it (images and videos, not links).
  bool get hasFile => !isLink;

  /// The page's file name in its event's folder.
  String get fileName => '$id.$extension';

  EventPage copyWith({PageFilter? filter}) => EventPage(
    id: id,
    filter: filter ?? this.filter,
    kind: kind,
    extension: extension,
    url: url,
    title: title,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'filter': filter.name,
    'kind': kind.name,
    'extension': extension,
    if (url != null) 'url': url.toString(),
    if (title != null) 'title': title,
  };

  factory EventPage.fromJson(Map<String, Object?> json) {
    final id = checkId(json['id'] as String);
    // Events also come from the cloud: a link is checked again here.
    if (json['kind'] == 'link') {
      return EventPage.link(
        id: id,
        url: Uri.parse(json['url'] as String),
        title: json['title'] as String?,
      );
    }
    return EventPage(
      id: id,
      filter: PageFilter.byName(json['filter'] as String?),
      kind: json['kind'] == 'video' ? PageKind.video : PageKind.image,
      extension: checkExtension(json['extension'] as String? ?? 'img'),
    );
  }
}

/// Someone a capture is shared with, as recorded on the event when its
/// owner shares it (the share API keeps the grants that count).
class EventShare {
  const EventShare(this.email, {this.readOnly = false});

  final String email;
  final bool readOnly;

  Map<String, Object?> toJson() => {
    'email': email,
    'role': readOnly ? 'read' : 'edit',
  };

  factory EventShare.fromJson(Map<String, Object?> json) =>
      EventShare(json['email'] as String, readOnly: json['role'] == 'read');

  @override
  bool operator ==(Object other) =>
      other is EventShare && other.email == email && other.readOnly == readOnly;

  @override
  int get hashCode => Object.hash(email, readOnly);
}

/// An event: what the user captured of a tab (scanned pages, photos,
/// videos, links), what it's called, and the text tab read from it (if it
/// was read).
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
    this.shares = const [],
    this.sharedBy,
    this.readOnly = false,
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
        sharedBy: event.sharedBy,
        readOnly: event.readOnly,
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
  /// before). Saved in the cloud too, but there the folder it's in says
  /// whose it is.
  final String? owner;

  /// Who the owner shared it with, as last recorded by the owner's app.
  final List<EventShare> shares;

  /// For an event someone shared with the user: their email (its [owner]
  /// is then their identity). Null for the user's own. Kept on the device
  /// only, like [readOnly].
  final String? sharedBy;
  bool get isShared => sharedBy != null;

  /// Shared read only: the user can see it, not change it.
  final bool readOnly;

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
    List<EventShare>? shares,
    String? sharedBy,
    bool? readOnly,
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
    shares: shares ?? this.shares,
    sharedBy: sharedBy ?? this.sharedBy,
    readOnly: readOnly ?? this.readOnly,
  );

  /// The event as saved: with its [owner] and [shares]; on the device
  /// also how it's shared with the user, which the cloud copy ([local]
  /// false) leaves out.
  Map<String, Object?> toJson({bool local = true}) => {
    'id': id,
    'title': title,
    'artist': artist,
    'created': created.toUtc().toIso8601String(),
    'updated': updated.toUtc().toIso8601String(),
    'pages': [for (final p in pages) p.toJson()],
    if (tabText != null) 'tabText': tabText,
    if (deleted != null) 'deleted': deleted!.toUtc().toIso8601String(),
    if (owner != null) 'owner': owner,
    if (shares.isNotEmpty) 'shares': [for (final s in shares) s.toJson()],
    if (local && sharedBy != null) 'sharedBy': sharedBy,
    if (local && readOnly) 'readOnly': true,
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
      shares: [
        for (final s in json['shares'] as List? ?? const [])
          EventShare.fromJson((s as Map).cast<String, Object?>()),
      ],
      sharedBy: json['sharedBy'] as String?,
      readOnly: json['readOnly'] == true,
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

/// [url] if it's an http or https address with a host; anything else
/// (`javascript:`, `file:`, `intent:`...) is refused, since links open in
/// the browser.
Uri checkUrl(Uri url) {
  if (!(url.isScheme('http') || url.isScheme('https')) || url.host.isEmpty) {
    throw FormatException('Not a web link', url.toString());
  }
  return url;
}

/// The link the user typed or pasted, or null if it isn't one: trimmed,
/// `https://` added when there's no scheme (`youtu.be/abc`).
Uri? parseLink(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) return null;
  final withScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(trimmed)
      ? trimmed
      : 'https://$trimmed';
  final url = Uri.tryParse(withScheme);
  if (url == null) return null;
  try {
    checkUrl(url);
  } on FormatException {
    return null;
  }
  // A host needs a dot (example.com), or it's a typo.
  return url.host.contains('.') || url.host == 'localhost' ? url : null;
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
