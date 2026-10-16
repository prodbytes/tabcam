import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tabcam_app/cloud/cognito.dart';

void main() {
  final now = DateTime.utc(2026, 10, 10, 12);
  final expires = now.add(const Duration(hours: 1)).millisecondsSinceEpoch;

  test('a Google token becomes credentials (GetId, then '
      'GetCredentialsForIdentity), reused while valid', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final cognito = CognitoCredentials(
      region: 'us-east-1',
      identityPoolId: 'us-east-1:pool',
      now: () => now,
      client: MockClient((request) async {
        final action = request.headers['x-amz-target']!.split('.').last;
        calls.add((action, (jsonDecode(request.body) as Map).cast()));
        // Unsigned: the Google token is the proof.
        expect(request.headers.containsKey('authorization'), isFalse);
        return http.Response(
          jsonEncode(switch (action) {
            'GetId' => {'IdentityId': 'us-east-1:me'},
            _ => {
              'IdentityId': 'us-east-1:me',
              'Credentials': {
                'AccessKeyId': 'ASIA',
                'SecretKey': 'secret',
                'SessionToken': 'session',
                'Expiration': expires / 1000,
              },
            },
          }),
          200,
        );
      }),
    );

    final session = await cognito.session('google-token');
    expect(session.identityId, 'us-east-1:me');
    expect(session.credentials.sessionToken, 'session');
    expect(calls.map((c) => c.$1), ['GetId', 'GetCredentialsForIdentity']);
    expect(calls.first.$2['Logins'], {'accounts.google.com': 'google-token'});

    await cognito.session('google-token');
    expect(calls, hasLength(2));

    // A refreshed token keeps the identity: only new credentials.
    await cognito.session('google-token-2');
    expect(calls.map((c) => c.$1).last, 'GetCredentialsForIdentity');
    expect(calls, hasLength(3));
  });

  test('a rejected token needs a new sign-in', () async {
    final cognito = CognitoCredentials(
      region: 'us-east-1',
      identityPoolId: 'us-east-1:pool',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            '__type': 'NotAuthorizedException',
            'message': 'Invalid login token. Token expired',
          }),
          400,
        ),
      ),
    );
    await expectLater(
      cognito.session('old'),
      throwsA(
        isA<CognitoException>().having(
          (e) => e.needsSignIn,
          'needsSignIn',
          true,
        ),
      ),
    );
  });
}
