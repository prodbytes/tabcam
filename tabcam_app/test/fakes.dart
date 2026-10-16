import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tabcam_app/auth/auth_service.dart';
import 'package:tabcam_app/cloud/cognito.dart';
import 'package:tabcam_app/cloud/s3.dart';
import 'package:tabcam_app/cloud/share_api.dart';
import 'package:tabcam_app/cloud/sigv4.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records the URLs the app opens, and how, opening none; [opens] says
/// whether they open.
class FakeLauncher extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  FakeLauncher({this.opens = true});

  final bool opens;
  final launched = <(String, LaunchOptions)>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add((url, options));
    return opens;
  }
}

/// The bucket, in memory: ETags are MD5s, as S3's are for single PUTs.
class FakeBucket implements ObjectStore {
  final Map<String, Uint8List> objects = {};
  final List<String> requests = [];
  int failNext = 0;
  int failStatus = 403;
  String failBody = '<Error><Code>ExpiredToken</Code></Error>';

  void _request(String what) {
    requests.add(what);
    if (failNext > 0) {
      failNext--;
      throw S3Exception(failStatus, failBody);
    }
  }

  @override
  Future<Map<String, String>> listETags(
    String prefix, {
    required AwsCredentials credentials,
  }) async {
    _request('LIST $prefix');
    await holdList?.future;
    return {
      for (final MapEntry(:key, :value) in objects.entries)
        if (key.startsWith(prefix)) key: md5.convert(value).toString(),
    };
  }

  @override
  Future<Uint8List> get(
    String key, {
    required AwsCredentials credentials,
  }) async {
    _request('GET $key');
    return objects[key] ?? (throw S3Exception(404, 'NoSuchKey'));
  }

  @override
  Future<Stream<List<int>>> getStream(
    String key, {
    required AwsCredentials credentials,
  }) async {
    // Page files (not event.json) wait while [holdFiles] is set, and
    // the next [failFiles] fail.
    if (!key.endsWith('/event.json')) {
      await holdFiles?.future;
      if (failFiles > 0) {
        failFiles--;
        _request('GET $key');
        throw S3Exception(500, 'InternalError');
      }
    }
    return Stream.value(await get(key, credentials: credentials));
  }

  /// While set, listings don't come until it completes.
  Completer<void>? holdList;

  /// While set, page files don't come until it completes.
  Completer<void>? holdFiles;

  /// How many of the next page files fail to come.
  int failFiles = 0;

  @override
  Future<void> put(
    String key,
    Uint8List bytes, {
    required String contentType,
    required AwsCredentials credentials,
  }) async {
    _request('PUT $key');
    objects[key] = bytes;
  }

  @override
  Future<void> putStream(
    String key,
    Stream<List<int>> body,
    int length, {
    required String contentType,
    required AwsCredentials credentials,
  }) async {
    _request('PUT $key');
    final builder = BytesBuilder();
    await body.forEach(builder.add);
    expect(builder.length, length);
    objects[key] = builder.takeBytes();
  }

  @override
  Future<void> delete(String key, {required AwsCredentials credentials}) async {
    _request('DELETE $key');
    objects.remove(key);
  }

  /// Keys a batch delete leaves, reported as not deleted (AccessDenied).
  final Set<String> undeletable = {};

  @override
  Future<List<String>> deleteBatch(
    List<String> keys, {
    required AwsCredentials credentials,
  }) async {
    _request('DELETE ${keys.length}');
    expect(keys.length, lessThanOrEqualTo(S3Bucket.maxBatch));
    final failed = [
      for (final key in keys)
        if (undeletable.contains(key)) key,
    ];
    for (final key in keys) {
      if (!undeletable.contains(key)) objects.remove(key);
    }
    return failed;
  }

  Map<String, Object?> json(String key) =>
      (jsonDecode(utf8.decode(objects[key]!)) as Map).cast();
}

class FakeCredentials implements CredentialSource {
  FakeCredentials([this.identityId = 'us-east-1:me']);

  /// The folder: changes when the user's sign-in joins another profile.
  String identityId;
  int sessions = 0;
  int clears = 0;
  Object? error;

  @override
  Future<CognitoSession> session(String idToken) async {
    sessions++;
    if (error case final e?) throw e;
    return CognitoSession(
      identityId: identityId,
      credentials: const AwsCredentials(
        accessKeyId: 'AKID',
        secretAccessKey: 'secret',
      ),
    );
  }

  @override
  void clear() => clears++;
}

class FakeAuth extends AuthService {
  FakeAuth({this.offered = const [AuthProvider.google]});

  /// The providers whose buttons show.
  final List<AuthProvider> offered;

  /// Each [signIn], by provider.
  final List<AuthProvider> signIns = [];

  AuthUser? _user;
  String? _token;

  void signInAs(String id, [String token = 'token']) =>
      signInWith(AuthUser(id: id, email: '$id@example.com'), token);

  void signInWith(AuthUser user, [String token = 'token']) {
    _user = user;
    _token = token;
    notifyListeners();
  }

  @override
  AuthUser? get user => _user;
  @override
  String? get idToken => _token;
  @override
  List<AuthProvider> get providers => offered;
  @override
  bool get checking => false;
  @override
  bool get available => true;
  @override
  String? get unavailableReason => null;
  @override
  String? get error => null;
  @override
  Future<void> init() async {}
  @override
  Future<void> signIn([AuthProvider provider = AuthProvider.google]) async =>
      signIns.add(provider);
  @override
  Future<void> signOut() async {
    _user = null;
    _token = null;
    notifyListeners();
  }

  @override
  Widget? buildSignInButton([AuthProvider provider = AuthProvider.google]) =>
      null;
}

/// The share API, in memory: grants by `<owner>/<capture>`, then email.
/// Each device has its own, for its user ([email], [identity]).
class FakeShareApi extends ShareApi {
  FakeShareApi(this.grantsBy, {required this.email, this.identity = ''})
    : super(baseUrl: Uri.parse('https://share.example'));

  /// Shared by every device: `<owner>/<capture>` → email → role.
  final Map<String, Map<String, ShareRole>> grantsBy;

  /// Whose requests: their email, and their identity (as an owner).
  final String email;
  final String identity;

  /// Owners' emails, by identity.
  static final Map<String, String> emails = {};

  int credentialRequests = 0;

  List<Grant> _of(String key) => [
    for (final MapEntry(:key, :value) in (grantsBy[key] ?? {}).entries)
      Grant(key, value),
  ];

  @override
  Future<List<Grant>> grants(String token, String captureId) async =>
      _of('$identity/$captureId');

  @override
  Future<List<Grant>> grant(
    String token,
    String captureId,
    String email, {
    ShareRole role = ShareRole.edit,
  }) async {
    emails[identity] = this.email;
    (grantsBy['$identity/$captureId'] ??= {})[email] = role;
    return _of('$identity/$captureId');
  }

  @override
  Future<List<Grant>> revoke(
    String token,
    String captureId,
    String email,
  ) async {
    grantsBy['$identity/$captureId']?.remove(email);
    return _of('$identity/$captureId');
  }

  @override
  Future<List<SharedCapture>> shared(String token) async => [
    for (final MapEntry(:key, :value) in grantsBy.entries)
      if (value[email] case final role?)
        SharedCapture(
          owner: key.split('/').first,
          captureId: key.split('/').last,
          ownerEmail: emails[key.split('/').first] ?? '?',
          role: role,
        ),
  ];

  @override
  Future<void> leave(String token, String owner, String captureId) async =>
      grantsBy['$owner/$captureId']?.remove(email);

  /// Published links, shared by every device: key -> `<owner>/<capture>`.
  static final Map<String, String> links = {};

  /// Thrown by the next [publishLink], once.
  Object? failPublish;

  @override
  Future<void> publishLink(String token, String captureId, String key) async {
    if (failPublish case final e?) {
      failPublish = null;
      throw e;
    }
    calls.add('publish $captureId');
    links[key] = '$identity/$captureId';
  }

  @override
  Future<LinkedCapture> openLink(String captureId, String key) async {
    final found = links[key];
    if (found == null || found.split('/').last != captureId) {
      throw ShareApiException(404, 'No such link');
    }
    return LinkedCapture(
      found.split('/').first,
      const AwsCredentials(accessKeyId: 'ASIA', secretAccessKey: 'public'),
    );
  }

  /// The user's profile, as the API answers it; [linkTo] the profile a
  /// good code links to, and [linkError] what a link throws instead.
  Profile profileNow = const Profile(
    id: 'brave_calm_otter',
    accounts: [
      ProfileAccount(
        id: 'a1',
        email: 'ana@example.com',
        provider: 'google',
        owner: true,
        you: true,
      ),
    ],
    roles: ['free'],
  );
  Profile? linkTo;
  Object? linkError;
  final List<String> calls = [];

  @override
  Future<Profile> profile(String token) async {
    calls.add('profile');
    return profileNow;
  }

  @override
  Future<LinkCode> linkCode(String token) async {
    calls.add('link-code');
    return LinkCode('ABCD-EFGH', DateTime(2030));
  }

  @override
  Future<Profile> link(String token, String code) async {
    calls.add('link $code');
    if (linkError case final e?) throw e;
    return profileNow = linkTo!;
  }

  @override
  Future<Profile?> unlink(String token, String id) async {
    calls.add('unlink $id');
    final left = profileNow.accounts.firstWhere((a) => a.id == id);
    profileNow = Profile(
      id: profileNow.id,
      accounts: [
        for (final a in profileNow.accounts)
          if (a.id != id) a,
      ],
      roles: profileNow.roles,
    );
    return left.you ? null : profileNow;
  }

  @override
  Future<ProfileToken> profileToken(String token) async {
    calls.add('credentials');
    return ProfileToken(
      profileId: profileNow.id,
      identityId: identity,
      token: 'openid-${profileNow.id}',
    );
  }

  /// Identities whose accounts were deleted.
  final List<String> deletedAccounts = [];

  /// Thrown by the next [deleteAccount], once.
  Object? failDeleteAccount;

  @override
  Future<void> deleteAccount(String token) async {
    if (failDeleteAccount case final e?) {
      failDeleteAccount = null;
      throw e;
    }
    grantsBy.removeWhere((key, _) => key.startsWith('$identity/'));
    for (final grants in grantsBy.values) {
      grants.remove(email);
    }
    deletedAccounts.add(identity);
  }

  @override
  Future<ShareCredentials> credentials(
    String token,
    String owner,
    String captureId,
  ) async {
    credentialRequests++;
    final role = grantsBy['$owner/$captureId']?[email];
    if (role == null) throw ShareApiException(404, 'Not shared with you');
    return ShareCredentials(
      AwsCredentials(
        accessKeyId: 'ASIA',
        secretAccessKey: 'secret',
        expiration: DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
      role,
    );
  }
}
