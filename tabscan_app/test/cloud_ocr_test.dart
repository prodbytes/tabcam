import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabscan_app/auth/auth_service.dart';
import 'package:tabscan_app/cloud/cloud_ocr.dart';
import 'package:tabscan_app/cloud/cloud_sync.dart';
import 'package:tabscan_app/cloud/ocr_api.dart';
import 'package:tabscan_app/library/capture_event.dart';
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/screens/account_panel.dart';
import 'package:tabscan_app/screens/event_screen.dart';
import 'package:tabscan_app/screens/premium_card.dart';

import 'fakes.dart';

// Made-up riffs: tests never use published songs' tabs.
const _riffA = 'e|---0---3---|\nB|-1---1-----|\n';
const _riffB = 'G|-2---2b4r2-|\nD|-----------|\n';

class FakeOcrApi implements OcrApi {
  FakeOcrApi({this.premium = false});

  bool premium;
  final List<String> transcribed = [];
  int accountCalls = 0;

  /// Thrown by [account] instead of answering.
  Object? error;

  @override
  Future<PremiumStatus> account(String idToken) async {
    accountCalls++;
    if (error case final e?) throw e;
    return PremiumStatus(
      premium: premium,
      expiresAt: premium ? DateTime(2027, 3, 1) : null,
      upgradeUrl: Uri.parse('https://example.com/subscribe'),
      voucherUrl: Uri.parse('https://example.com/voucher'),
    );
  }

  @override
  Future<int> transcribe(String idToken, String eventId) async {
    transcribed.add(eventId);
    return 1;
  }
}

class _Setup {
  _Setup({bool premium = false, this.now}) : api = FakeOcrApi(premium: premium);

  final library = Library(PlatformEventStore());
  final auth = FakeAuth();
  final bucket = FakeBucket();
  final credentials = FakeCredentials();
  final FakeOcrApi api;
  final DateTime? now;
  late final CloudSync sync;
  late final CloudOcr ocr;

  Future<void> start({bool syncing = true}) async {
    await library.load();
    sync = CloudSync(
      library: library,
      auth: auth,
      bucket: bucket,
      credentials: credentials,
      period: const Duration(days: 1),
    );
    if (syncing) sync.start();
    ocr = CloudOcr(
      library: library,
      auth: auth,
      sync: sync,
      bucket: bucket,
      credentials: credentials,
      api: api,
      now: now == null ? null : () => now!,
    )..start();
  }

  /// Signs in and waits for the first sync pass and premium check.
  Future<void> signIn() async {
    auth.signInAs('ana');
    await _until(() => sync.state == SyncState.synced && !ocr.checking);
  }

  void result(CaptureEvent event, EventPage page, String status, String text) {
    bucket.objects['us-east-1:me/ocr/${event.id}/${page.id}.json'] =
        Uint8List.fromList(
          utf8.encode(jsonEncode({'status': status, 'text': text})),
        );
  }

  void dispose() {
    ocr.dispose();
    sync.dispose();
  }
}

/// Waits (really) for [done], at most two seconds.
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue, reason: 'timed out');
}

Future<CaptureEvent> _twoPages(Library library) =>
    library.create([Uint8List(4), Uint8List(4)]);

void main() {
  test(
    'a premium user\'s event gets its text tab once every page is read',
    () async {
      final s = _Setup(premium: true);
      await s.start();
      var event = await _twoPages(s.library);
      await s.signIn();
      expect(s.ocr.premium, isTrue);
      event = s.library.byId(event.id)!;

      s.result(event, event.pages[0], 'ok', _riffA);
      await s.ocr.collect();
      expect(s.library.byId(event.id)!.tabText, isNull); // one page still to go

      s.result(event, event.pages[1], 'ok', _riffB);
      await s.ocr.collect();
      expect(
        s.library.byId(event.id)!.tabText,
        '${_riffA.trim()}\n\n${_riffB.trim()}\n',
      );
      s.dispose();
    },
  );

  test('pages without tab are left out; none at all leaves no text', () async {
    final s = _Setup(premium: true);
    await s.start();
    var event = await _twoPages(s.library);
    await s.signIn();
    event = s.library.byId(event.id)!;
    s.result(event, event.pages[0], 'no-tab', '');
    s.result(event, event.pages[1], 'error', '');
    await s.ocr.collect();
    expect(s.library.byId(event.id)!.tabText, isNull);
    s.dispose();
  });

  test('the user\'s own edits are never replaced', () async {
    final s = _Setup(premium: true);
    await s.start();
    var event = await _twoPages(s.library);
    await s.signIn();
    event = s.library.byId(event.id)!;
    await s.library.update(event.copyWith(tabText: 'my own\n'));
    s.result(event, event.pages[0], 'ok', _riffA);
    s.result(event, event.pages[1], 'ok', _riffB);
    await s.ocr.collect();
    expect(s.library.byId(event.id)!.tabText, 'my own\n');
    s.dispose();
  });

  test('a text tab marked correct is never replaced', () async {
    final s = _Setup(premium: true);
    await s.start();
    var event = await _twoPages(s.library);
    await s.signIn();
    event = s.library.byId(event.id)!;
    s.result(event, event.pages[0], 'ok', _riffA);
    s.result(event, event.pages[1], 'ok', _riffB);
    await s.ocr.collect();
    event = s.library.byId(event.id)!;
    final read = event.tabText;
    await s.library.update(event.copyWith(tabTextCorrect: true));

    // A page added later would change the text tab, but it's checked.
    event = await s.library.addPages(s.library.byId(event.id)!, [Uint8List(4)]);
    s.result(event, event.pages[2], 'ok', _riffA);
    await s.ocr.collect();
    expect(s.library.byId(event.id)!.tabText, read);
    s.dispose();
  });

  test('a free user gets nothing from the cloud', () async {
    final s = _Setup();
    await s.start();
    var event = await _twoPages(s.library);
    await s.signIn();
    event = s.library.byId(event.id)!;
    s.result(event, event.pages[0], 'ok', _riffA);
    s.result(event, event.pages[1], 'ok', _riffB);
    await s.ocr.collect();
    expect(s.ocr.premium, isFalse);
    expect(s.library.byId(event.id)!.tabText, isNull);
    expect(s.bucket.requests.where((r) => r.contains('/ocr/')), isEmpty);
    s.dispose();
  });

  test('pages that waited too long are asked for, once', () async {
    final s = _Setup(
      premium: true,
      now: DateTime.now().add(const Duration(minutes: 5)),
    );
    await s.start();
    final event = await _twoPages(s.library);
    await s.signIn();
    await s.ocr.collect();
    await s.ocr.collect();
    expect(s.api.transcribed, [event.id]);
    s.dispose();
  });

  test('signing out forgets the status', () async {
    final s = _Setup(premium: true);
    await s.start();
    await s.signIn();
    expect(s.ocr.status, isNotNull);
    await s.auth.signOut();
    expect(s.ocr.status, isNull);
    s.dispose();
  });

  testWidgets('the Premium card offers the upgrade to free users', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(() async {
      await s.start(syncing: false);
      s.auth.signInAs('ana');
      await _until(() => s.ocr.status != null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PremiumCard(ocr: s.ocr, email: 'ana@example.com', store: false),
        ),
      ),
    );
    expect(find.text('TabScan Premium'), findsOneWidget);
    expect(find.text('Upgrade'), findsOneWidget);
    expect(find.text('Redeem a voucher'), findsOneWidget);
    expect(
      find.textContaining('Subscribe with ana@example.com'),
      findsOneWidget,
    );

    s.api.premium = true;
    await tester.runAsync(() async {
      await s.ocr.refresh();
      await _until(() => s.ocr.premium);
    });
    await tester.pump();
    expect(find.text('Upgrade'), findsNothing);
    expect(find.textContaining('transcribed in the cloud'), findsOneWidget);
    s.dispose();
  });

  testWidgets('an Apple user with a private relay address is labelled by '
      'Apple, and told how Premium goes by address', (tester) async {
    final s = _Setup();
    await tester.runAsync(() async {
      await s.start(syncing: false);
      s.auth.signInWith(
        const AuthUser(
          id: 'apple.user.1',
          email: 'x7k2@privaterelay.appleid.com',
          provider: AuthProvider.apple,
          privateEmail: true,
        ),
      );
      await _until(() => s.ocr.status != null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountPanel(
              auth: s.auth,
              sync: s.sync,
              ocr: s.ocr,
              store: true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Apple ID (private email)'), findsOneWidget);
    expect(
      find.text('x7k2@privaterelay.appleid.com\nSigned in with Apple'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('private-email')), findsOneWidget);
    s.dispose();
  });

  test(
    'a service that takes no Apple tokens says Premium needs Google',
    () async {
      final s = _Setup();
      s.api.error = OcrApiException(403, 'google sign-in needed');
      await s.start(syncing: false);
      s.auth.signInAs('ana');
      await _until(() => !s.ocr.checking && s.ocr.error != null);
      expect(s.ocr.error, 'Premium needs Google sign-in');
      expect(s.ocr.premium, isFalse);
      s.dispose();
    },
  );

  testWidgets('the profile shows the user\'s role', (tester) async {
    final s = _Setup();
    await tester.runAsync(() async {
      await s.start(syncing: false);
      s.auth.signInAs('ana');
      await _until(() => s.ocr.status != null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountPanel(
              auth: s.auth,
              sync: s.sync,
              ocr: s.ocr,
              store: false,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Role: Free'), findsOneWidget);
    expect(find.text('Upgrade'), findsOneWidget);

    s.api.premium = true;
    await tester.runAsync(() async {
      await s.ocr.refresh();
      await _until(() => s.ocr.premium);
    });
    await tester.pump();
    expect(find.text('Role: Premium'), findsOneWidget);
    s.dispose();
  });

  testWidgets('in a store app, the Premium card offers no purchase', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(() async {
      await s.start(syncing: false);
      s.auth.signInAs('ana');
      await _until(() => s.ocr.status != null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountPanel(
              auth: s.auth,
              sync: s.sync,
              ocr: s.ocr,
              store: true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Role: Free'), findsOneWidget);
    expect(find.text('TabScan Premium'), findsOneWidget);
    expect(
      find.text('TabScan Premium isn\'t active for ana@example.com.'),
      findsOneWidget,
    );
    expect(find.text('Upgrade'), findsNothing);
    expect(find.text('Redeem a voucher'), findsNothing);
    expect(find.textContaining('Subscribe'), findsNothing);
    expect(find.text('Check again'), findsOneWidget);

    // Premium bought on the web still works, and says until when.
    s.api.premium = true;
    await tester.runAsync(() async {
      await s.ocr.refresh();
      await _until(() => s.ocr.premium);
    });
    await tester.pump();
    expect(find.text('Role: Premium'), findsOneWidget);
    expect(find.textContaining('Premium until 2027-03-01.'), findsOneWidget);
    expect(find.textContaining('transcribed in the cloud'), findsOneWidget);
    s.dispose();
  });

  for (final store in [false, true]) {
    testWidgets(
      'the event\'s Premium hint ${store ? 'is hidden in a store app' : 'shows on the web'}',
      (tester) async {
        final s = _Setup();
        late String id;
        await tester.runAsync(() async {
          await s.start(syncing: false);
          id = (await _twoPages(s.library)).id;
          s.auth.signInAs('ana');
          await _until(() => s.ocr.status != null);
        });
        await tester.pumpWidget(
          MaterialApp(
            home: EventScreen(
              library: s.library,
              eventId: id,
              sync: s.sync,
              ocr: s.ocr,
              store: store,
            ),
          ),
        );
        await tester.pump();
        final hint = find.text(
          'TabScan Premium transcribes your scans automatically.',
        );
        expect(hint, store ? findsNothing : findsOneWidget);
        expect(find.text('Upgrade'), store ? findsNothing : findsOneWidget);
        s.dispose();
      },
    );
  }
}
