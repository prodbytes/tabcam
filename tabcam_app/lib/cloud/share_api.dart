import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_service.dart';
import '../auth/session_auth_service.dart';
import '../export/capture_link.dart';
import '../l10n/language.dart';
import '../library/capture_event.dart';
import 'cdn.dart';
import 'sigv4.dart';

/// What a person may do with a capture shared with them.
enum ShareRole {
  /// Change it, as its owner can (the default).
  edit,

  /// See the owner's files, and add their own (a contribution only they
  /// and the owner see).
  read;

  static ShareRole byName(String? name) => name == 'read' ? read : edit;

  String get label => this == edit
      ? appL10n.accountPeopleCanEdit
      : appL10n.accountPeopleReadOnly;
}

/// One person a capture is shared with.
class Grant {
  const Grant(this.email, this.role, {this.identity, this.viaLink = false});

  final String email;
  final ShareRole role;

  /// Their identity (their contribution's folder), once they've synced it.
  final String? identity;

  /// They joined by opening the capture's link, signed in.
  final bool viaLink;
}

/// What joining a capture by its link gave ([ShareApi.joinLink]).
class JoinedCapture {
  const JoinedCapture({
    required this.owner,
    required this.captureId,
    this.own = false,
  });

  final String owner;
  final String captureId;

  /// It's the user's own capture: nothing to join.
  final bool own;
}

/// A capture someone shared with the signed-in user.
class SharedCapture {
  const SharedCapture({
    required this.owner,
    required this.captureId,
    required this.ownerEmail,
    required this.role,
  });

  /// The owner's Cognito identity: the folder the capture is in.
  final String owner;
  final String captureId;
  final String ownerEmail;
  final ShareRole role;
}

/// Credentials for one shared capture's folder, and what they allow.
class ShareCredentials {
  const ShareCredentials(this.credentials, this.role, {this.contribPrefix});

  final AwsCredentials credentials;
  final ShareRole role;

  /// A reader's own contribution's folder
  /// (`<owner>/contrib/<capture id>/<identity>/`), which they may write too.
  final String? contribPrefix;
}

/// Read-only credentials for a capture anyone with its link may open, and
/// whose folder it's in.
class LinkedCapture {
  const LinkedCapture(this.owner, this.credentials);

  /// The owner's Cognito identity: the folder the capture is in.
  final String owner;
  final AwsCredentials credentials;
}

/// A public capture tabs.cam's search found ([ShareApi.searchPublic]):
/// enough to show it and open it by its link.
class PublicCapture {
  const PublicCapture({
    required this.captureId,
    required this.key,
    required this.title,
    this.artist = '',
  });

  final String captureId;

  /// Its link key: public, anyone may open it.
  final String key;
  final String title;
  final String artist;

  /// Its full link, `…/app/?c=<id>&k=<key>`, on [app] (the site's by
  /// default).
  Uri link([Uri? app]) => (app ?? CaptureLink.app).replace(
    queryParameters: {'c': captureId, 'k': key},
  );

  /// The answer's captures, those well formed.
  static List<PublicCapture> listOf(Object? json) => [
    for (final c in switch (json) {
      {'captures': final List list} => list,
      _ => const [],
    })
      if (c is Map &&
          c['captureId'] is String &&
          RegExp(r'^[a-z0-9]{1,32}$').hasMatch(c['captureId'] as String) &&
          c['key'] is String &&
          isLinkKey(c['key'] as String))
        PublicCapture(
          captureId: c['captureId'] as String,
          key: c['key'] as String,
          title: '${c['title'] ?? ''}'.trim(),
          artist: '${c['artist'] ?? ''}'.trim(),
        ),
  ];
}

/// One sign-in linked to the user's profile.
class ProfileAccount {
  const ProfileAccount({
    required this.id,
    required this.email,
    required this.provider,
    required this.owner,
    required this.you,
  });

  /// What the API calls it (a hash of the sign-in): to unlink it.
  final String id;
  final String email;

  /// `google` or `apple`.
  final String provider;

  /// The profile's owner: it can't be unlinked.
  final bool owner;

  /// The sign-in this app is using.
  final bool you;
}

/// The signed-in user's profile: its ID (`huge_wavy_darter`), the sign-ins
/// linked to it, and its roles, every linked address's together.
class Profile {
  const Profile({
    required this.id,
    required this.accounts,
    required this.roles,
    this.globalRoles = const [],
  });

  final String id;
  final List<ProfileAccount> accounts;
  final List<String> roles;
  final List<String> globalRoles;

  bool get premium => roles.contains('premium');

  /// Whether this sign-in owns the profile (only the owner deletes it).
  bool get youOwn => accounts.any((a) => a.you && a.owner);

  static Profile fromJson(Map<String, Object?> json) => Profile(
    id: json['profileId'] as String? ?? '',
    accounts: [
      for (final a in json['accounts'] as List? ?? const [])
        if (a is Map)
          ProfileAccount(
            id: a['id'] as String? ?? '',
            email: a['email'] as String? ?? '',
            provider: a['provider'] as String? ?? '',
            owner: a['owner'] == true,
            you: a['you'] == true,
          ),
    ],
    roles: [for (final r in json['roles'] as List? ?? const []) '$r'],
    globalRoles: [
      for (final r in json['globalRoles'] as List? ?? const []) '$r',
    ],
  );
}

/// A code another sign-in enters to join the profile.
class LinkCode {
  const LinkCode(this.code, this.expiresAt);

  final String code;
  final DateTime expiresAt;
}

/// The profile's Cognito identity and a token for it.
class ProfileToken {
  const ProfileToken({
    required this.profileId,
    required this.identityId,
    required this.token,
    this.cdn,
  });

  final String profileId;
  final String identityId;
  final String token;

  /// Reading the profile's folder through CloudFront (none without one).
  final CdnGrant? cdn;
}

/// Why the share API refused.
class ShareApiException implements Exception {
  ShareApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  /// Not shared with the user (any more), or a link code that's wrong.
  bool get notShared => statusCode == 404;

  /// The request can't be done as things are (linking, unlinking).
  bool get conflict => statusCode == 409;

  /// Too many tries (link codes).
  bool get throttled => statusCode == 429;

  /// The capture is private: only its owner opens it (its link, joining
  /// it).
  bool get private => statusCode == 403;

  @override
  String toString() => message;
}

/// The share API (tabcam_api/shares): grants of the user's own captures,
/// what's shared with them, and credentials for it; and TabCam's sign-in
/// sessions ([SessionApi]). Every request carries the user's ID token:
/// Google's at the API's root, Apple's under `/apple`, email's under
/// `/email`, a TabCam session's under `/tabcam` (each path has its own
/// authorizer, for its issuer).
class ShareApi implements SessionApi {
  ShareApi({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _client;

  Future<List<Grant>> grants(String token, String captureId) async =>
      _grants(await _call(token, 'GET', ['shares', captureId]));

  /// Shares [captureId] with [email] as [role] (a new grant, or a changed
  /// one); the capture's grants after.
  Future<List<Grant>> grant(
    String token,
    String captureId,
    String email, {
    ShareRole role = ShareRole.edit,
  }) async => _grants(
    await _call(
      token,
      'PUT',
      ['shares', captureId],
      body: {'email': email, 'role': role.name},
    ),
  );

  Future<List<Grant>> revoke(
    String token,
    String captureId,
    String email,
  ) async => _grants(
    await _call(
      token,
      'DELETE',
      ['shares', captureId],
      query: {'email': email},
    ),
  );

  Future<List<SharedCapture>> shared(String token) async {
    final body = await _call(token, 'GET', ['shared']);
    return [
      for (final s in body['shared'] as List)
        SharedCapture(
          owner: (s as Map)['owner'] as String,
          captureId: s['captureId'] as String,
          ownerEmail: s['ownerEmail'] as String,
          role: ShareRole.byName(s['role'] as String?),
        ),
    ];
  }

  /// The user's profile, made at their first sign-in.
  Future<Profile> profile(String token) async =>
      Profile.fromJson(await _call(token, 'GET', ['profile']));

  /// A code for another sign-in to join the profile (10 minutes, once).
  Future<LinkCode> linkCode(String token) async {
    final body = await _call(token, 'POST', ['profile', 'link-code']);
    return LinkCode(
      body['code'] as String,
      DateTime.fromMillisecondsSinceEpoch(
        ((body['expiresAt'] as num?) ?? 0).toInt() * 1000,
      ),
    );
  }

  /// Joins the profile [code] is for; that profile.
  Future<Profile> link(String token, String code) async => Profile.fromJson(
    await _call(token, 'POST', ['profile', 'link'], body: {'code': code}),
  );

  /// Unlinks the account [id] from the profile; the profile after (null
  /// when the user unlinked this sign-in).
  Future<Profile?> unlink(String token, String id) async {
    final body = await _call(
      token,
      'POST',
      ['profile', 'unlink'],
      body: {'id': id},
    );
    return body['unlinked'] == true ? null : Profile.fromJson(body);
  }

  /// A Cognito token for the profile's identity (its folder).
  @override
  Future<SessionTokens> startSession(String providerToken) async =>
      SessionTokens.fromJson(await _call(providerToken, 'POST', ['session']));

  @override
  Future<SessionTokens> refreshSession(String refreshToken) async =>
      SessionTokens.fromJson(
        await _call(
          null,
          'POST',
          ['session', 'refresh'],
          body: {'refreshToken': refreshToken},
        ),
      );

  @override
  Future<void> endSession(String refreshToken) => _call(
    null,
    'POST',
    ['session', 'end'],
    body: {'refreshToken': refreshToken},
  );

  Future<ProfileToken> profileToken(String token) async {
    final body = await _call(token, 'POST', ['profile', 'credentials']);
    return ProfileToken(
      profileId: body['profileId'] as String,
      identityId: body['identityId'] as String,
      token: body['token'] as String,
      cdn: CdnGrant.fromJson(body['cdn']),
    );
  }

  /// Stops [captureId] of [owner] being shared with the user.
  Future<void> leave(String token, String owner, String captureId) =>
      _call(token, 'DELETE', ['shared', owner, captureId]);

  /// Deletes what the API keeps about the user, when they delete their
  /// account: the grants of their captures, the grants to their address,
  /// and their Cognito identity (last: their folder must be emptied
  /// first, with its credentials). Signed in with Apple,
  /// [appleAuthorizationCode] lets it revoke their Apple tokens first.
  Future<void> deleteAccount(String token, {String? appleAuthorizationCode}) =>
      _call(
        token,
        'DELETE',
        ['account'],
        body: appleAuthorizationCode == null
            ? null
            : {'appleAuthorizationCode': appleAuthorizationCode},
      );

  Future<ShareCredentials> credentials(
    String token,
    String owner,
    String captureId,
  ) async {
    final c = await _call(token, 'POST', [
      'shared',
      owner,
      captureId,
      'credentials',
    ]);
    return ShareCredentials(
      _credentials(c),
      ShareRole.byName(c['role'] as String?),
      contribPrefix: c['contribPrefix'] as String?,
    );
  }

  /// Joins the capture a link names ([captureId] and its [key]), signed in:
  /// shared with the user to read from then on, unless it's theirs or
  /// shared with them already.
  Future<JoinedCapture> joinLink(
    String token,
    String captureId,
    String key,
  ) async {
    final body = await _call(
      token,
      'POST',
      ['links', captureId, 'join'],
      body: {'key': key},
    );
    return JoinedCapture(
      owner: body['owner'] as String,
      captureId: body['captureId'] as String? ?? captureId,
      own: body['own'] == true,
    );
  }

  /// Records the capture's link [key] and who may open it by it
  /// ([visibility]): anyone holding it (unlisted), anyone, also found by
  /// tabs.cam's search under its [title] and [artist] (public, the only
  /// time they're sent), or only the owner (private). The same again does
  /// nothing new.
  Future<void> publishLink(
    String token,
    String captureId,
    String key, {
    CaptureVisibility visibility = CaptureVisibility.unlisted,
    String? title,
    String? artist,
  }) => _call(
    token,
    'PUT',
    ['links', captureId],
    body: {
      'key': key,
      'visibility': visibility.name,
      if (visibility == CaptureVisibility.public) ...{
        'title': ?title,
        'artist': ?artist,
      },
    },
  );

  /// The public captures whose title or artist has every word of [query]
  /// (newest first, 20 at most), without signing in.
  Future<List<PublicCapture>> searchPublic(String query) async =>
      PublicCapture.listOf(
        await _call(null, 'GET', ['public'], query: {'q': query.trim()}),
      );

  /// Read-only credentials for the capture a link names, without signing
  /// in: its [captureId] and [key].
  Future<LinkedCapture> openLink(String captureId, String key) async {
    final c = await _call(
      null,
      'POST',
      ['public', captureId, 'credentials'],
      body: {'key': key},
    );
    return LinkedCapture(c['owner'] as String, _credentials(c));
  }

  static AwsCredentials _credentials(Map<String, Object?> c) => AwsCredentials(
    accessKeyId: c['accessKeyId'] as String,
    secretAccessKey: c['secretAccessKey'] as String,
    sessionToken: c['sessionToken'] as String,
    expiration: DateTime.fromMillisecondsSinceEpoch(
      (c['expiration'] as num).toInt() * 1000,
      isUtc: true,
    ),
    cdn: CdnGrant.fromJson(c['cdn']),
  );

  static List<Grant> _grants(Map<String, Object?> body) => [
    for (final g in body['grants'] as List)
      Grant(
        (g as Map)['email'] as String,
        ShareRole.byName(g['role'] as String?),
        identity: g['identity'] as String?,
        viaLink: g['via'] == 'link',
      ),
  ];

  /// Calls the API: with the user's ID [token], or, null, without one (the
  /// public route).
  Future<Map<String, Object?>> _call(
    String? token,
    String method,
    List<String> path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    final uri = baseUrl.replace(
      pathSegments: [
        ...baseUrl.pathSegments.where((s) => s.isNotEmpty),
        // Apple's, email's and TabCam's tokens go to the routes under their
        // own name.
        if (token != null && isSessionToken(token))
          'tabcam'
        else if (token != null)
          ...switch (AuthProvider.ofToken(token)) {
            AuthProvider.apple => ['apple'],
            AuthProvider.email => ['email'],
            AuthProvider.google => const <String>[],
          },
        ...path,
      ],
      queryParameters: query,
    );
    final request = http.Request(method, uri);
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    Map<String, Object?> decoded;
    try {
      decoded = (jsonDecode(response.body) as Map).cast<String, Object?>();
    } on Object {
      decoded = {};
    }
    if (response.statusCode != 200) {
      throw ShareApiException(
        response.statusCode,
        decoded['message'] as String? ??
            (response.statusCode == 401
                ? appL10n.accountSignInAgainToShare
                : appL10n.accountShareFailedHttp('${response.statusCode}')),
      );
    }
    return decoded;
  }
}
