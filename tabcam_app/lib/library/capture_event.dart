import 'dart:convert';
import 'dart:math';

import '../processing/page_filter.dart';
import '../recognition/tab_doubts.dart';

/// What a page is: a picture of the tab, a video (someone playing it, a
/// lesson), a recording, a PDF (the tab as a document), or a link (a lesson
/// online, a recording, the song's page).
enum PageKind { image, video, audio, pdf, link }

/// One page of an event: an image's, video's, recording's or PDF's file is
/// kept by the store as `<id>.<extension>`; a link has no file, only its
/// [url].
class EventPage {
  const EventPage({
    required this.id,
    this.filter = PageFilter.tab,
    this.kind = PageKind.image,
    this.extension = 'img',
    this.url,
    this.title,
    this.from,
  });

  /// A link page to [url] (checked with [checkUrl]), with an optional
  /// [title].
  EventPage.link({required this.id, required Uri url, String? title, this.from})
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

  /// The page's name, as the user gave it (any kind: a link, a file, a
  /// photo); null shows its kind and number, or a link's address.
  final String? title;

  /// For a page the owner published from someone's [Contribution]: the ID
  /// of the page it's a copy of there.
  final String? from;

  bool get isVideo => kind == PageKind.video;
  bool get isImage => kind == PageKind.image;
  bool get isAudio => kind == PageKind.audio;
  bool get isPdf => kind == PageKind.pdf;
  bool get isLink => kind == PageKind.link;

  /// Whether the store keeps a file for it (all but links).
  bool get hasFile => !isLink;

  /// The MIME type of its file, by its extension.
  String get mimeType => switch (extension) {
    'img' || 'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' || 'heif' => 'image/heic',
    'gif' => 'image/gif',
    'mp4' || 'm4v' => 'video/mp4',
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    '3gp' => 'video/3gpp',
    'mp3' => 'audio/mpeg',
    'm4a' => 'audio/mp4',
    'aac' => 'audio/aac',
    'wav' => 'audio/wav',
    'ogg' || 'oga' => 'audio/ogg',
    'opus' => 'audio/opus',
    'flac' => 'audio/flac',
    'pdf' => 'application/pdf',
    _ => 'application/octet-stream',
  };

  /// The page's file name in its event's folder.
  String get fileName => '$id.$extension';

  EventPage copyWith({PageFilter? filter, String? Function()? title}) =>
      EventPage(
        id: id,
        filter: filter ?? this.filter,
        kind: kind,
        extension: extension,
        url: url,
        title: title == null ? this.title : title(),
        from: from,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'filter': filter.name,
    'kind': kind.name,
    'extension': extension,
    if (url != null) 'url': url.toString(),
    if (title != null) 'title': title,
    if (from != null) 'from': from,
  };

  factory EventPage.fromJson(Map<String, Object?> json) {
    final id = checkId(json['id'] as String);
    final from = switch (json['from']) {
      final String f => checkId(f),
      _ => null,
    };
    // Events also come from the cloud: a link is checked again here.
    if (json['kind'] == 'link') {
      return EventPage.link(
        id: id,
        url: Uri.parse(json['url'] as String),
        title: json['title'] as String?,
        from: from,
      );
    }
    return EventPage(
      id: id,
      filter: PageFilter.byName(json['filter'] as String?),
      // Unknown kinds (from a newer app) show as images, as before kinds.
      kind: switch (json['kind']) {
        'video' => PageKind.video,
        'audio' => PageKind.audio,
        'pdf' => PageKind.pdf,
        _ => PageKind.image,
      },
      extension: checkExtension(json['extension'] as String? ?? 'img'),
      // The name the user gave the file: kept, on the device and coming
      // down from the cloud, as a link's is.
      title: json['title'] as String?,
      from: from,
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

/// What one person a capture is shared with to read added to it: their
/// own files and links, which only they and the capture's owner see, kept
/// in a folder of their own beside the capture's
/// (`<owner>/contrib/<capture id>/<their identity>/`). The owner publishes
/// one by copying it into the capture's pages: then everyone sees it.
class Contribution {
  const Contribution({
    this.by,
    required this.updated,
    this.pages = const [],
    this.email,
  });

  /// Whose it is: their Cognito identity (their folder's name). Null for
  /// the user's own until it first syncs.
  final String? by;

  /// When it last changed, on any of its person's devices.
  final DateTime updated;
  final List<EventPage> pages;

  /// Who they are, as the share API knows them (on the owner's devices,
  /// once known); never in the cloud copy.
  final String? email;

  Contribution copyWith({
    String? by,
    DateTime? updated,
    List<EventPage>? pages,
    String? email,
  }) => Contribution(
    by: by ?? this.by,
    updated: updated ?? this.updated,
    pages: pages ?? this.pages,
    email: email ?? this.email,
  );

  /// As saved: on the device with [by] and [email]; the cloud copy
  /// ([local] false, `contrib.json`) leaves them out (its folder says
  /// whose it is).
  Map<String, Object?> toJson({bool local = true}) => {
    'updated': updated.toUtc().toIso8601String(),
    'pages': [for (final p in pages) p.toJson()],
    if (local && by != null) 'by': by,
    if (local && email != null) 'email': email,
  };

  factory Contribution.fromJson(Map<String, Object?> json) => Contribution(
    by: json['by'] as String?,
    updated: DateTime.parse(json['updated'] as String).toLocal(),
    pages: [
      for (final p in json['pages'] as List? ?? const [])
        EventPage.fromJson((p as Map).cast<String, Object?>()),
    ],
    email: json['email'] as String?,
  );
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
    this.study = '',
    this.pages = const [],
    this.tabText,
    this.tabTextAuto = false,
    this.tabTextCorrect = false,
    this.tabTextDoubts = const [],
    this.hideImages = false,
    this.deleted,
    this.owner,
    this.shares = const [],
    this.sharedBy,
    this.readOnly = false,
    this.linkKey,
    this.contributions = const [],
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

  /// The study it's in, a group of related captures the user named
  /// ("Jazz chords"); empty for none. Home filters by it.
  final String study;
  final DateTime created;

  /// When it last changed on any device (cloud sync keeps the latest).
  final DateTime updated;
  final List<EventPage> pages;

  /// The tab as plain text, read from the pages, as the user last edited
  /// it.
  final String? tabText;

  /// Whether [tabText] is as an automatic read left it (on the device, or
  /// in the cloud), not edited since: a new read may replace it then, and
  /// never text the user edited.
  final bool tabTextAuto;

  /// The user marked [tabText] as a correct reading: the event then opens
  /// on its Text view, and no read replaces it.
  final bool tabTextCorrect;

  /// The notes of [tabText] the read wasn't sure of (likely wrong), shown
  /// in red; those the user changed since drop out (standingDoubts).
  final List<TabDoubt> tabTextDoubts;

  /// Whether its owner hid the photos and scans: it then shows only the
  /// text tab and the other pages (videos and links), to everyone it's
  /// shared with too, and exports leave the images out. The images are
  /// kept (they're still read) and come back when shown again.
  final bool hideImages;

  /// The pages it shows and exports: all of them, or, with [hideImages],
  /// the videos and links.
  List<EventPage> get visiblePages => hideImages
      ? [
          for (final p in pages)
            if (!p.isImage) p,
        ]
      : pages;

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

  /// Shared to read: the user sees the owner's files, can't change them,
  /// and adds their own instead ([contributes]).
  final bool readOnly;

  /// Shared with the user to read: what they add (files, links, Cam's
  /// takes) is their [Contribution], not the owner's capture.
  bool get contributes => isShared && readOnly;

  /// What people added ([Contribution]): on the owner's devices, everyone's
  /// who did; on a reader's, their own (one at most). Kept on the device
  /// (each syncs with its own folder), never in the capture's event.json.
  final List<Contribution> contributions;

  /// The user's own contribution, on a capture they [contributes] to.
  Contribution? get myContribution =>
      contributes ? contributions.firstOrNull : null;

  /// Whether [page] (a contribution's) is published: copied into the
  /// capture's own pages.
  bool isPublished(EventPage page) => publishedCopy(page) != null;

  /// The capture's copy of [page], a contribution's, once published.
  EventPage? publishedCopy(EventPage page) =>
      pages.where((p) => p.from == page.id).firstOrNull;

  /// Every page whose file is kept with the event: its own and the
  /// contributions'.
  Iterable<EventPage> get allPages sync* {
    yield* pages;
    for (final c in contributions) {
      yield* c.pages;
    }
  }

  /// The key in the capture's link (`…/app/?c=<id>&k=<key>`), made the first
  /// time its owner copies the link: with it, anyone holding the link may
  /// see the capture, read only, signed in or not ([CaptureLink]). Synced,
  /// so every device of the owner's copies the same link.
  final String? linkKey;

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
    String? study,
    List<EventPage>? pages,
    String? tabText,
    bool? tabTextAuto,
    bool? tabTextCorrect,
    List<TabDoubt>? tabTextDoubts,
    bool? hideImages,
    DateTime? updated,
    String? owner,
    List<EventShare>? shares,
    String? sharedBy,
    bool? readOnly,
    String? linkKey,
    List<Contribution>? contributions,
  }) => CaptureEvent(
    id: id,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    study: study ?? this.study,
    created: created,
    updated: updated ?? this.updated,
    pages: pages ?? this.pages,
    tabText: tabText ?? this.tabText,
    tabTextAuto: tabTextAuto ?? this.tabTextAuto,
    tabTextCorrect: tabTextCorrect ?? this.tabTextCorrect,
    tabTextDoubts: tabTextDoubts ?? this.tabTextDoubts,
    hideImages: hideImages ?? this.hideImages,
    deleted: deleted,
    owner: owner ?? this.owner,
    shares: shares ?? this.shares,
    sharedBy: sharedBy ?? this.sharedBy,
    readOnly: readOnly ?? this.readOnly,
    linkKey: linkKey ?? this.linkKey,
    contributions: contributions ?? this.contributions,
  );

  /// The event as saved: with its [owner] and [shares]; on the device
  /// also how it's shared with the user, which the cloud copy ([local]
  /// false) leaves out.
  Map<String, Object?> toJson({bool local = true}) => {
    'id': id,
    'title': title,
    'artist': artist,
    if (study.isNotEmpty) 'study': study,
    'created': created.toUtc().toIso8601String(),
    'updated': updated.toUtc().toIso8601String(),
    'pages': [for (final p in pages) p.toJson()],
    if (tabText != null) 'tabText': tabText,
    if (tabTextAuto) 'tabTextAuto': true,
    if (tabTextCorrect) 'tabTextCorrect': true,
    if (tabTextDoubts.isNotEmpty)
      'tabTextDoubts': [for (final d in tabTextDoubts) d.toJson()],
    if (hideImages) 'hideImages': true,
    if (deleted != null) 'deleted': deleted!.toUtc().toIso8601String(),
    if (owner != null) 'owner': owner,
    if (shares.isNotEmpty) 'shares': [for (final s in shares) s.toJson()],
    if (linkKey != null) 'linkKey': linkKey,
    if (local && sharedBy != null) 'sharedBy': sharedBy,
    if (local && readOnly) 'readOnly': true,
    if (local && contributions.isNotEmpty)
      'contributions': [for (final c in contributions) c.toJson()],
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
      study: (json['study'] as String? ?? '').trim(),
      created: time('created')!,
      updated: time('updated'),
      pages: [
        for (final p in json['pages'] as List? ?? const [])
          EventPage.fromJson((p as Map).cast<String, Object?>()),
      ],
      tabText: json['tabText'] as String?,
      tabTextAuto: json['tabTextAuto'] == true,
      tabTextCorrect: json['tabTextCorrect'] == true,
      tabTextDoubts: [
        for (final d in json['tabTextDoubts'] as List? ?? const [])
          ?TabDoubt.fromJson(d),
      ],
      hideImages: json['hideImages'] == true,
      deleted: time('deleted'),
      owner: json['owner'] as String?,
      shares: [
        for (final s in json['shares'] as List? ?? const [])
          EventShare.fromJson((s as Map).cast<String, Object?>()),
      ],
      sharedBy: json['sharedBy'] as String?,
      readOnly: json['readOnly'] == true,
      linkKey: switch (json['linkKey']) {
        final String k when isLinkKey(k) => k,
        _ => null,
      },
      contributions: [
        for (final c in json['contributions'] as List? ?? const [])
          Contribution.fromJson((c as Map).cast<String, Object?>()),
      ],
    );
  }
}

final RegExp _linkKey = RegExp(r'^[A-Za-z0-9_-]{32,64}$');

/// Whether [key] is a link key ([CaptureEvent.linkKey]): what the share
/// API takes.
bool isLinkKey(String key) => _linkKey.hasMatch(key);

/// A new link key: 192 random bits, base64url (32 characters).
String newLinkKey() {
  final random = Random.secure();
  return base64Url
      .encode([for (var i = 0; i < 24; i++) random.nextInt(256)])
      .replaceAll('=', '');
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
