import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tabcam_app/maintenance/maintenance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final url = Uri.parse('https://tabcam.example/status.json');

  /// A check whose site answers with [respond] (changeable between checks).
  MaintenanceCheck checkWith(Future<http.Response> Function() respond) {
    return MaintenanceCheck(
      url: url,
      client: MockClient((_) => respond()),
      period: const Duration(days: 1),
    );
  }

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  group('MaintenanceCheck', () {
    test('reads maintenance mode and the message', () async {
      final check = checkWith(
        () async => json({'maintenance': true, 'message': ' Back at 6 '}),
      );
      addTearDown(check.dispose);
      await check.check();
      expect(check.checked, isTrue);
      expect(check.on, isTrue);
      expect(check.message, 'Back at 6');
    });

    test('maintenance false, or no message', () async {
      final check = checkWith(() async => json({'maintenance': false}));
      addTearDown(check.dispose);
      await check.check();
      expect(check.on, isFalse);
      expect(check.message, isNull);
    });

    test('asks for a fresh copy', () async {
      late Uri asked;
      final check = MaintenanceCheck(
        url: url,
        client: MockClient((request) async {
          asked = request.url;
          return json({'maintenance': false});
        }),
      );
      addTearDown(check.dispose);
      await check.check();
      expect(asked.path, '/status.json');
      expect(asked.queryParameters, contains('t'));
    });

    test('no status file: not in maintenance', () async {
      for (final status in [403, 404]) {
        final check = checkWith(() async => http.Response('nope', status));
        addTearDown(check.dispose);
        await check.check();
        expect(check.checked, isTrue);
        expect(check.on, isFalse);
      }
    });

    test('fails open at first: offline, or not JSON', () async {
      for (final respond in <Future<http.Response> Function()>[
        () async => throw http.ClientException('offline'),
        () async => http.Response('<!doctype html>', 200),
        () async => http.Response('oops', 500),
      ]) {
        final check = checkWith(respond);
        addTearDown(check.dispose);
        await check.check();
        expect(check.checked, isTrue);
        expect(check.on, isFalse);
      }
    });

    test('a failed check keeps maintenance mode on', () async {
      var down = false;
      final check = checkWith(() async {
        if (down) throw http.ClientException('offline');
        return json({'maintenance': true});
      });
      addTearDown(check.dispose);
      await check.check();
      down = true;
      await check.check();
      expect(check.on, isTrue);
    });
  });

  group('MaintenanceGate', () {
    testWidgets('shows nothing until checked, then the app', (tester) async {
      final check = checkWith(() async => json({'maintenance': false}));
      addTearDown(check.dispose);
      await tester.pumpWidget(
        MaintenanceGate(
          check: check,
          app: (_) => const MaterialApp(home: Text('the app')),
        ),
      );
      expect(find.text('the app'), findsNothing);
      expect(find.byType(MaintenanceScreen), findsNothing);

      await tester.runAsync(check.check);
      await tester.pump();
      expect(find.text('the app'), findsOneWidget);
    });

    testWidgets('in maintenance mode, only the sorry message', (tester) async {
      var on = true;
      var entered = 0;
      var built = 0;
      final check = checkWith(
        () async => json({'maintenance': on, 'message': 'Back soon'}),
      );
      addTearDown(check.dispose);
      await tester.pumpWidget(
        MaintenanceGate(
          check: check,
          app: (_) {
            built++;
            return const MaterialApp(home: Text('the app'));
          },
          onEnter: () => entered++,
        ),
      );
      await tester.runAsync(check.check);
      await tester.pump();
      expect(find.text('Back soon'), findsOneWidget);
      expect(find.text('the app'), findsNothing);
      expect(built, 0, reason: 'the app never starts in maintenance mode');
      expect(entered, 0);

      // Maintenance ends: the app starts.
      on = false;
      await tester.runAsync(check.check);
      await tester.pump();
      expect(find.text('the app'), findsOneWidget);
      expect(find.text('Back soon'), findsNothing);

      // It starts again: the running app is hidden and told to stop.
      on = true;
      await tester.runAsync(check.check);
      await tester.pump();
      expect(find.text('Back soon'), findsOneWidget);
      expect(find.text('the app'), findsNothing);
      expect(entered, 1);
    });

    testWidgets('without a message, the default one', (tester) async {
      final check = checkWith(() async => json({'maintenance': true}));
      addTearDown(check.dispose);
      await tester.pumpWidget(
        MaintenanceGate(
          check: check,
          app: (_) => const MaterialApp(home: Text('the app')),
        ),
      );
      await tester.runAsync(check.check);
      await tester.pump();
      expect(find.text(MaintenanceScreen.defaultMessage), findsOneWidget);
    });
  });
}
