import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tabcam_app/recognition/auto_reader.dart';
import 'package:tabcam_app/capture/media.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/auth/auth_service.dart';
import 'package:tabcam_app/capture/play_along_screen.dart';
import 'package:tabcam_app/cloud/cloud_ocr.dart';
import 'package:tabcam_app/cloud/cloud_sync.dart';
import 'package:tabcam_app/cloud/ocr_api.dart';
import 'package:tabcam_app/import/tab_page_import.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/main.dart';
import 'package:tabcam_app/recognition/tab_doubts.dart';
import 'package:tabcam_app/screens/account_panel.dart';
import 'package:tabcam_app/screens/event_screen.dart';
import 'package:tabcam_app/screens/premium_card.dart';
import 'package:tabcam_app/screens/tab_text_view.dart';

import 'fakes.dart';

// Made-up riffs: tests never use published songs' tabs.
const _riffA = 'e|---0---3---|\nB|-1---1-----|\n';
const _riffB = 'G|-2---2b4r2-|\nD|-----------|\n';

class FakeOcrApi implements OcrApi {
  FakeOcrApi({this.premium = false});

  bool premium;
  final List<String> transcribed = [];
  final List<String> transcribedAgain = [];
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

  int warmed = 0;

  @override
  Future<bool> warm(String idToken) async {
    warmed++;
    return true;
  }

  @override
  Future<int> transcribe(
    String idToken,
    String eventId, {
    bool again = false,
  }) async {
    transcribed.add(eventId);
    if (again) transcribedAgain.add(eventId);
    return 1;
  }

  /// What [page] answers, and the pages asked for.
  String pageHtml = '';
  final List<Uri> pages = [];

  @override
  Future<FetchedPage> page(String idToken, Uri url) async {
    pages.add(url);
    return FetchedPage(body: pageHtml, contentType: 'text/html');
  }

  AutocorrectResult corrections = const AutocorrectResult(found: false);
  final List<({String song, String text})> checked = [];

  @override
  Future<AutocorrectResult> autocorrect(
    String idToken, {
    required String eventId,
    required String song,
    required String text,
  }) async {
    checked.add((song: song, text: text));
    return corrections;
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

  void result(
    CaptureEvent event,
    EventPage page,
    String status,
    String text, {
    List<List<Object>> doubts = const [],
  }) {
    bucket.objects['us-east-1:me/ocr/${event.id}/${page.id}.json'] =
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({'status': status, 'text': text, 'doubts': doubts}),
          ),
        );
  }

  void dispose() {
    ocr.dispose();
    sync.dispose();
  }
}

/// Lets animations run a while; not pumpAndSettle (spinners never settle).
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
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
  _fixTests();
  group('a tab site\'s page on the web', () {
    setUp(() => importsTabSites = true);
    tearDown(() => importsTabSites = false);

    final url = Uri.parse('https://www.azchords.com/n/nobody-tabs/riff.html');
    const html =
        '<html><title>Riff</title><pre>e|-0-----3-|\nB|-1-----0-|</pre></html>';

    test('the service fetches it for Premium users', () async {
      final s = _Setup(premium: true);
      await s.start();
      await s.signIn();
      s.api.pageHtml = html;
      final event = await s.library.create(const []);
      final done = await TabPageImporter(
        ocr: s.ocr,
        onDevice: false,
      ).addTo(s.library, event, url);
      expect(done!.outcome, TabImportOutcome.imported);
      expect(s.api.pages, [url]);
      expect(s.library.byId(event.id)!.pages.single.title, 'Riff');
      s.dispose();
    });

    test('without Premium, the service isn\'t asked', () async {
      final s = _Setup();
      await s.start();
      await s.signIn();
      final event = await s.library.create(const []);
      final done = await TabPageImporter(
        ocr: s.ocr,
        onDevice: false,
      ).addTo(s.library, event, url);
      expect(done!.outcome, TabImportOutcome.needsPremium);
      expect(s.api.pages, isEmpty);
      s.dispose();
    });
  });

  test(
    'the camera opening warms a reader up, for premium users only',
    () async {
      final free = _Setup();
      await free.start();
      await free.signIn();
      free.ocr.warm();
      await pumpEventQueue();
      expect(free.api.warmed, 0);
      free.dispose();

      final s = _Setup(premium: true);
      await s.start();
      s.ocr.warm(); // not signed in yet
      await pumpEventQueue();
      expect(s.api.warmed, 0);
      await s.signIn();
      s.ocr.warm();
      await pumpEventQueue();
      expect(s.api.warmed, 1);
      s.dispose();
    },
  );

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

  test(
    'the cloud\'s doubtful notes come with the text, at their lines',
    () async {
      final s = _Setup(premium: true);
      await s.start();
      var event = await _twoPages(s.library);
      await s.signIn();
      event = s.library.byId(event.id)!;
      s.result(
        event,
        event.pages[0],
        'ok',
        _riffA,
        doubts: [
          [0, 5, '0'],
        ],
      );
      s.result(
        event,
        event.pages[1],
        'ok',
        _riffB,
        doubts: [
          [0, 7, '2b4r2'],
          [5, 0, 'gone'], // no such line: dropped
        ],
      );
      await s.ocr.collect();
      final filled = s.library.byId(event.id)!;
      // The second page's lines come after the first's two and a blank line.
      expect(filled.tabTextDoubts, const [
        TabDoubt(0, 5, '0'),
        TabDoubt(3, 7, '2b4r2'),
      ]);
      expect(filled.tabText!.split('\n')[3].substring(7, 12), '2b4r2');
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

    // Nor does a Rescan's new reading.
    event = s.library.byId(event.id)!;
    await s.ocr.transcribe(event, again: true, replace: true);
    s.result(event, event.pages[0], 'ok', _riffB);
    s.result(event, event.pages[1], 'ok', _riffB);
    s.result(event, event.pages[2], 'ok', _riffB);
    await s.ocr.collect();
    expect(s.library.byId(event.id)!.tabText, read);
    expect(s.library.byId(event.id)!.tabTextCorrect, isTrue);
    s.dispose();
  });

  test(
    'Premium: a PDF\'s text is read here; a scanned PDF goes to the cloud',
    () async {
      final s = _Setup(premium: true);
      await s.start();
      await s.signIn();
      String? pdfText = 'e|--0--3--|';
      final reader = AutoReader(
        library: s.library,
        auth: s.auth,
        ocr: () => s.ocr,
        supported: false, // the web: no OCR here
        read: (_) async => fail('no OCR here'),
        readPdf: (pdf, ocr) async => pdfText,
      )..start();
      Future<CaptureEvent> addPdf() async =>
          s.library.addMedia(await s.library.create(const []), [
            Media(
              XFile.fromData(Uint8List.fromList([1]), name: 'tab.pdf'),
              PageKind.pdf,
              'pdf',
            ),
          ]);
      final withText = await addPdf();
      await _until(() => s.library.byId(withText.id)!.tabText != null);
      expect(s.library.byId(withText.id)!.tabText, 'e|--0--3--|');
      expect(s.api.transcribed, isEmpty);

      pdfText = null; // scanned: no text
      final scanned = await addPdf();
      // Its upload starts the cloud's reading: nothing is asked for.
      await _until(() => reader.stateOf(scanned.id) == ReadState.inCloud);
      expect(s.api.transcribed, isEmpty);
      expect(s.api.transcribedAgain, isEmpty);

      // Read again: the cloud reads every page again.
      reader.readSoon(scanned.id, again: true);
      await _until(() => s.api.transcribedAgain.contains(scanned.id));

      // The cloud's reading of the PDF fills the text tab.
      await s.sync.syncNow();
      final page = s.library.byId(scanned.id)!.pages.single;
      s.result(s.library.byId(scanned.id)!, page, 'ok', _riffA);
      await s.ocr.collect();
      await _until(() => s.library.byId(scanned.id)!.tabText != null);
      expect(s.library.byId(scanned.id)!.tabText, contains('e|---0---3---|'));
      reader.dispose();
      s.dispose();
    },
  );

  test('Premium: once the cloud\'s text arrives, it isn\'t reading', () async {
    final s = _Setup(premium: true);
    await s.start();
    await s.signIn();
    final reader = AutoReader(
      library: s.library,
      auth: s.auth,
      ocr: () => s.ocr,
      supported: true,
      read: (_) async => fail('read in the cloud'),
    )..start();
    final created = await _twoPages(s.library);
    await _until(() => reader.stateOf(created.id) == ReadState.inCloud);

    await s.sync.syncNow();
    final event = s.library.byId(created.id)!;
    s.result(event, event.pages[0], 'ok', _riffA);
    s.result(event, event.pages[1], 'ok', _riffB);
    await s.ocr.collect();
    await _until(() => s.library.byId(event.id)!.tabText != null);
    await _until(() => reader.stateOf(event.id) == null);

    // Read: pages put in another order aren't read again.
    final read = s.library.byId(event.id)!;
    await s.library.reorderPages(read.id, [read.pages[1].id, read.pages[0].id]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(reader.stateOf(event.id), isNull);
    // The uploads started the readings: the app never asked for them.
    expect(s.api.transcribed, isEmpty);
    reader.dispose();
    s.dispose();
  });

  test('Premium: Read again replaces the text an earlier read left', () async {
    final s = _Setup(premium: true);
    await s.start();
    await s.signIn();
    final reader = AutoReader(
      library: s.library,
      auth: s.auth,
      ocr: () => s.ocr,
      supported: true,
      read: (_) async => fail('read in the cloud'),
    )..start();
    final created = await _twoPages(s.library);
    await _until(() => reader.stateOf(created.id) == ReadState.inCloud);
    await s.sync.syncNow();
    var event = s.library.byId(created.id)!;
    s.result(event, event.pages[0], 'ok', _riffA);
    s.result(event, event.pages[1], 'ok', _riffA);
    await s.ocr.collect();
    await _until(() => reader.stateOf(event.id) == null);
    final first = s.library.byId(event.id)!.tabText;
    expect(first, isNotNull);

    reader.readSoon(event.id, again: true);
    await _until(() => reader.stateOf(event.id) == ReadState.inCloud);
    expect(s.api.transcribedAgain, [event.id]);
    // The earlier results are still there: they aren't the new reading.
    await s.ocr.collect();
    expect(s.library.byId(event.id)!.tabText, first);
    expect(reader.stateOf(event.id), ReadState.inCloud);

    // The new reading, page by page.
    event = s.library.byId(event.id)!;
    s.result(event, event.pages[0], 'ok', _riffB);
    await s.ocr.collect();
    expect(s.library.byId(event.id)!.tabText, first);
    s.result(event, event.pages[1], 'ok', _riffB);
    await s.ocr.collect();
    await _until(() => reader.stateOf(event.id) == null);
    expect(
      s.library.byId(event.id)!.tabText,
      '${_riffB.trim()}\n\n${_riffB.trim()}\n',
    );
    reader.dispose();
    s.dispose();
  });

  test('Premium: the same text read again isn\'t reading forever', () async {
    final s = _Setup(premium: true);
    await s.start();
    await s.signIn();
    final reader = AutoReader(
      library: s.library,
      auth: s.auth,
      ocr: () => s.ocr,
      supported: true,
      read: (_) async => fail('read in the cloud'),
    )..start();
    final created = await _twoPages(s.library);
    await _until(() => reader.stateOf(created.id) == ReadState.inCloud);
    await s.sync.syncNow();
    final event = s.library.byId(created.id)!;
    s.result(event, event.pages[0], 'ok', _riffA);
    s.result(event, event.pages[1], 'ok', _riffB);
    await s.ocr.collect();
    await _until(() => reader.stateOf(event.id) == null);

    reader.readSoon(event.id, again: true);
    await _until(() => reader.stateOf(event.id) == ReadState.inCloud);
    // Rewritten (each result has the time it was made), the same text.
    s.bucket.objects.updateAll(
      (key, value) =>
          key.contains('/ocr/') ? Uint8List.fromList([...value, 0x20]) : value,
    );
    await s.ocr.collect();
    await _until(() => reader.stateOf(event.id) == null);
    reader.dispose();
    s.dispose();
  });

  test('Premium: a read the cloud never answers gives up, and the text '
      'still fills in when it comes later', () async {
    final s = _Setup(premium: true);
    await s.start();
    await s.signIn();
    final reader = AutoReader(
      library: s.library,
      auth: s.auth,
      ocr: () => s.ocr,
      supported: true,
      read: (_) async => fail('read in the cloud'),
      cloudTimeout: const Duration(milliseconds: 100),
    )..start();
    final created = await _twoPages(s.library);
    await _until(() => reader.stateOf(created.id) == ReadState.inCloud);
    await _until(() => reader.stateOf(created.id) == ReadState.failed);

    await s.sync.syncNow();
    final event = s.library.byId(created.id)!;
    s.result(event, event.pages[0], 'ok', _riffA);
    s.result(event, event.pages[1], 'ok', _riffB);
    await s.ocr.collect();
    await _until(() => s.library.byId(event.id)!.tabText != null);
    await _until(() => reader.stateOf(event.id) == null);
    reader.dispose();
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
      now: DateTime.now().add(const Duration(minutes: 25)),
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
          body: PremiumCard(ocr: s.ocr, email: 'ana@example.com'),
        ),
      ),
    );
    expect(find.text('TabCam Premium'), findsOneWidget);
    expect(find.text('Upgrade'), findsOneWidget);
    expect(find.text('Redeem a voucher'), findsOneWidget);
    expect(
      find.textContaining(
        '\$10 a month or \$100 a year: subscribe with ana@example.com',
      ),
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
            child: AccountPanel(auth: s.auth, sync: s.sync, ocr: s.ocr),
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
            child: AccountPanel(auth: s.auth, sync: s.sync, ocr: s.ocr),
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

  testWidgets('without Premium, Text and Cam are locked: Text opens a '
      'preview of the view under the Premium card', (tester) async {
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
        ),
      ),
    );
    await tester.pump();
    // No hint any more: the tools say it, with a lock each.
    expect(find.byKey(const Key('tool-locked')), findsNWidgets(2));
    expect(find.byKey(const Key('premium-gate')), findsNothing);
    expect(find.byTooltip('Text: TabCam Premium'), findsOneWidget);
    expect(find.byTooltip('Cam: TabCam Premium'), findsOneWidget);

    await tester.tap(find.byKey(const Key('text')));
    await tester.pump();
    expect(find.byKey(const Key('premium-gate')), findsOneWidget);
    expect(
      find.textContaining('Text is part of TabCam Premium'),
      findsOneWidget,
    );
    expect(
      find.textContaining('subscribe with ana@example.com'),
      findsOneWidget,
    );
    expect(find.text('Upgrade'), findsOneWidget);
    expect(find.text('Redeem a voucher'), findsOneWidget);
    // No text tab yet: the preview shows a sample, said to be one.
    expect(find.text('A preview with a sample tab'), findsOneWidget);
    expect(find.textContaining('e|--0---0---1---1---|'), findsOneWidget);
    // Nothing in the preview works.
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .ancestor(
                  of: find.byType(TabTextView),
                  matching: find.byType(IgnorePointer),
                )
                .first,
          )
          .ignoring,
      isTrue,
    );

    // Not now (the card scrolls on a small screen): back to the files.
    await tester.ensureVisible(find.byKey(const Key('premium-not-now')));
    await tester.tap(find.byKey(const Key('premium-not-now')));
    await tester.pump();
    expect(find.byKey(const Key('premium-gate')), findsNothing);
    expect(find.text('Page 1'), findsOneWidget);

    // Premium: the locks go, and Text is the view itself.
    s.api.premium = true;
    await tester.runAsync(() async {
      await s.ocr.refresh();
      await _until(() => s.ocr.premium);
    });
    await tester.pump();
    expect(find.byKey(const Key('tool-locked')), findsNothing);
    await tester.tap(find.byKey(const Key('text')));
    await tester.pump();
    expect(find.byKey(const Key('premium-gate')), findsNothing);
    expect(find.text('A preview with a sample tab'), findsNothing);
    await tester.pump(const Duration(seconds: 1)); // the place is remembered
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });

  testWidgets('without Premium, Cam opens as a preview: no camera, the tab '
      'along the bottom, and the Premium card', (tester) async {
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
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('cam')));
    await _frames(tester);
    expect(find.byType(PlayAlongScreen), findsOneWidget);
    expect(find.byKey(const Key('premium-gate')), findsOneWidget);
    expect(
      find.textContaining('Cam is part of TabCam Premium'),
      findsOneWidget,
    );
    expect(find.text('Upgrade'), findsOneWidget);
    // No camera was asked for: a placeholder in its place.
    expect(find.byKey(const Key('cam-preview')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // The sample tab's first neckline.
    expect(find.byKey(const Key('neckline')), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('premium-not-now')));
    await tester.tap(find.byKey(const Key('premium-not-now')));
    await _frames(tester);
    expect(find.byType(PlayAlongScreen), findsNothing);
    expect(find.byKey(const Key('cam')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });

  testWidgets('a capture opened by its link, signed out, says to sign in '
      'to subscribe', (tester) async {
    final s = _Setup();
    late String id;
    await tester.runAsync(() async {
      await s.start(syncing: false);
      id = (await _twoPages(s.library)).id;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EventScreen(
          library: s.library,
          eventId: id,
          sync: s.sync,
          ocr: s.ocr,
          byLink: true,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('text')));
    await tester.pump();
    expect(find.byKey(const Key('premium-gate')), findsOneWidget);
    expect(find.byKey(const Key('premium-sign-in')), findsOneWidget);
    expect(find.text('Upgrade'), findsNothing);
    await tester.pump(const Duration(seconds: 1)); // the place is remembered
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });

  test('without Premium, nothing is read until it comes', () async {
    final s = _Setup();
    await s.start();
    await s.signIn();
    var reads = 0;
    final reader = AutoReader(
      library: s.library,
      auth: s.auth,
      ocr: () => s.ocr,
      supported: true,
      read: (_) async {
        reads++;
        return _riffA;
      },
    )..start();
    final created = await _twoPages(s.library);
    await _until(() => reader.stateOf(created.id) == ReadState.needsPremium);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(reads, 0);
    expect(s.api.transcribed, isEmpty);
    expect(s.library.byId(created.id)!.tabText, isNull);

    // Premium: the event that waited goes to the cloud.
    s.api.premium = true;
    await s.ocr.refresh();
    await _until(() => reader.stateOf(created.id) == ReadState.inCloud);
    expect(reads, 0);
    reader.dispose();
    s.dispose();
  });

  testWidgets('Home tells a signed-in user without Premium that text tabs '
      'and Cam are Premium\'s, until they close it', (tester) async {
    final s = _Setup();
    await tester.runAsync(() async {
      await s.start(syncing: false);
      s.auth.signInAs('ana');
      await _until(() => s.ocr.status != null);
    });
    await tester.pumpWidget(
      TabCamApp(library: s.library, auth: s.auth, sync: s.sync, ocr: s.ocr),
    );
    await _frames(tester);
    final banner = find.byKey(const Key('premium-banner'));
    expect(banner, findsOneWidget);
    expect(
      find.text('Text tabs and Cam are TabCam Premium features.'),
      findsOneWidget,
    );
    // Upgrade opens the account sheet, with the offer.
    await tester.tap(find.text('Upgrade'));
    await _frames(tester);
    expect(
      find.textContaining('subscribe with ana@example.com'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(5, 5)); // closes the sheet
    await _frames(tester);

    await tester.tap(find.byTooltip('Not now'));
    await tester.pump();
    expect(banner, findsNothing);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
}

void _fixTests() {
  testWidgets('Fix shows the corrections per note; the accepted are applied', (
    tester,
  ) async {
    final s = _Setup(premium: true);
    late CaptureEvent event;
    await tester.runAsync(() async {
      await s.start(syncing: false);
      s.auth.signInAs('ana');
      await _until(() => s.ocr.premium);
      event = await s.library.update(
        (await _twoPages(s.library)).copyWith(tabText: _riffA),
      );
    });
    s.api.corrections = const AutocorrectResult(
      found: true,
      title: 'Made-up Riff',
      summary: 'Two notes misread.',
      corrections: [
        TabCorrection(id: 'c1', line: 0, column: 5, old: '0', replacement: '2'),
        TabCorrection(id: 'c2', line: 1, column: 7, old: '1', replacement: '3'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TabTextView(
            library: s.library,
            eventId: event.id,
            ocr: s.ocr,
            showFix: true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Fix'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Made-up Riff');
    await tester.tap(find.text('Check'));
    await tester.pump();
    await tester.pump();
    expect(s.api.checked.single, (song: 'Made-up Riff', text: _riffA));
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('0 → 2'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await tester.pump();
    expect(find.text('1 → 3'), findsOneWidget);
    await tester.tap(find.text('Reject'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(
      s.library.byId(event.id)!.tabText,
      'e|---2---3---|\nB|-1---1-----|\n',
    );
    expect(find.text('Copy'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });

  testWidgets('Fix without Premium offers the upgrade', (tester) async {
    final s = _Setup();
    late CaptureEvent event;
    await tester.runAsync(() async {
      await s.start(syncing: false);
      s.auth.signInAs('ana');
      await _until(() => s.ocr.status != null);
      event = await s.library.update(
        (await _twoPages(s.library)).copyWith(tabText: _riffA),
      );
    });
    var upgraded = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TabTextView(
            library: s.library,
            eventId: event.id,
            ocr: s.ocr,
            onUpgrade: () => upgraded = true,
            showFix: true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Fix'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text(
        'Tab lined up. Checking it against the song online is part of '
        'TabCam Premium.',
      ),
      findsOneWidget,
    );
    // The offer stays until it's taken or dismissed, as a SnackBar with
    // an action did.
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Upgrade'), findsOneWidget);
    await tester.tap(find.text('Upgrade'));
    await tester.pump();
    expect(upgraded, isTrue);
    expect(s.api.checked, isEmpty);
    await tester.pumpWidget(const SizedBox());

    // Without an upgrade offer (no sign-in), Fix only lines the tab up.
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: Scaffold(
          body: TabTextView(
            library: s.library,
            eventId: event.id,
            ocr: s.ocr,
            showFix: true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Fix'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text("The tab's strings already line up"), findsOneWidget);
    expect(find.text('Upgrade'), findsNothing);
    expect(s.api.checked, isEmpty);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
}
