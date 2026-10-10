import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabscan_app/auth/auth_service.dart';
import 'package:tabscan_app/cloud/cognito.dart';
import 'package:tabscan_app/cloud/s3.dart';
import 'package:tabscan_app/cloud/sigv4.dart';

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
  }) async => Stream.value(await get(key, credentials: credentials));

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

  Map<String, Object?> json(String key) =>
      (jsonDecode(utf8.decode(objects[key]!)) as Map).cast();
}

class FakeCredentials implements CredentialSource {
  FakeCredentials([this.identityId = 'us-east-1:me']);

  final String identityId;
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
  AuthUser? _user;
  String? _token;

  void signInAs(String id, [String token = 'token']) {
    _user = AuthUser(id: id, email: '$id@example.com');
    _token = token;
    notifyListeners();
  }

  @override
  AuthUser? get user => _user;
  @override
  String? get idToken => _token;
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
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async {
    _user = null;
    _token = null;
    notifyListeners();
  }

  @override
  Widget? buildSignInButton() => null;
}
