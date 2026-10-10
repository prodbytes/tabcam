import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tabscan_app/cloud/share_api.dart';

void main() {
  late List<http.Request> sent;
  ShareApi api(int status, Object body) => ShareApi(
    baseUrl: Uri.parse('https://api.example'),
    client: MockClient((request) async {
      sent.add(request);
      return http.Response(jsonEncode(body), status);
    }),
  );
  setUp(() => sent = []);

  test('a grant is a PUT with the token, the email and the role', () async {
    final grants = await api(200, {
      'grants': [
        {'email': 'ana@example.com', 'role': 'read', 'grantedAt': 1},
      ],
    }).grant('token', 'abc', 'ana@example.com', role: ShareRole.read);
    expect(sent.single.method, 'PUT');
    expect(sent.single.url.toString(), 'https://api.example/shares/abc');
    expect(sent.single.headers['authorization'], 'Bearer token');
    expect(jsonDecode(sent.single.body), {
      'email': 'ana@example.com',
      'role': 'read',
    });
    expect(grants.single.role, ShareRole.read);
  });

  test('revoking names the email in the query', () async {
    await api(200, {'grants': []}).revoke('token', 'abc', 'ana@example.com');
    expect(sent.single.method, 'DELETE');
    expect(sent.single.url.queryParameters['email'], 'ana@example.com');
  });

  test('credentials for a shared capture', () async {
    final access = await api(200, {
      'accessKeyId': 'ASIA',
      'secretAccessKey': 'secret',
      'sessionToken': 'session',
      'expiration': 1791633600,
      'prefix': 'us-east-1:o/events/abc/',
      'role': 'edit',
    }).credentials('token', 'us-east-1:o', 'abc');
    expect(sent.single.url.path, '/shared/us-east-1:o/abc/credentials');
    expect(access.role, ShareRole.edit);
    expect(access.credentials.sessionToken, 'session');
  });

  test("the API's refusal says why", () async {
    await expectLater(
      api(404, {'message': 'Not shared with you'}).credentials('t', 'o', 'a'),
      throwsA(
        isA<ShareApiException>()
            .having((e) => e.notShared, 'notShared', true)
            .having((e) => e.message, 'message', 'Not shared with you'),
      ),
    );
  });
}
