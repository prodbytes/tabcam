import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/capture/play_along_screen.dart';
import 'package:tabcam_app/capture/take_sound.dart';
import 'package:tabcam_app/cloud/cloud_ocr.dart';
import 'package:tabcam_app/cloud/cloud_sync.dart';
import 'package:tabcam_app/cloud/ocr_api.dart';
import 'package:tabcam_app/export/incoming_links.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/main.dart';
import 'package:tabcam_app/screens/event_screen.dart';
import 'package:tabcam_app/screens/place.dart';

import 'cloud_ocr_test.dart' show FakeOcrApi;
import 'fake_camera.dart';
import 'fakes.dart';
import 'place_address_test.dart' show FakeAddress, app, frames, riff, settle;

/// The service, answering whether the user has Premium only once [gate]
/// opens (a reload: the first answer takes a moment).
class _SlowApi extends FakeOcrApi {
  _SlowApi({super.premium});

  final gate = Completer<void>();

  @override
  Future<PremiumStatus> account(String idToken) async {
    await gate.future;
    return super.account(idToken);
  }
}

/// A reload with Cam open opens Cam again: the place keeps it (`cam=1` in
/// the web's address, `cam` in the apps' meta file) while Cam is open.
void main() {
  late Library library;
  late FakeAddress address;

  /// Head gestures' face detector (ML Kit, on Android: the tests'
  /// platform), which Cam opens and closes.
  const faces = MethodChannel('google_mlkit_face_detector');

  setUp(() {
    library = Library(PlatformEventStore(), null, (_) async => null);
    CameraPlatform.instance = FakeCameraPlatform();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(faces, (call) async => null);
    // The camera records the take's sound (the app's side isn't here).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          TakeSound.channel,
          (call) async => call.method == 'prepare'
              ? {'ok': false, 'reason': 'not in tests'}
              : null,
        );
  });
  tearDown(() {
    PlaceMemory.address = null;
    IncomingLinks.instance.take();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TakeSound.channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(faces, null);
  });

  Future<CaptureEvent> riffEvent(WidgetTester tester) async {
    late CaptureEvent event;
    await tester.runAsync(() async {
      await library.load();
      final made = await library.create([
        img.encodeJpg(img.Image(width: 8, height: 8)),
      ]);
      event = await library.update(
        made.copyWith(title: 'Made-up riff', tabText: riff),
      );
    });
    return event;
  }

  test('Cam reads back from the address and the meta file; another event '
      'closes it', () {
    const place = Place(eventId: 'abc123', cam: true);
    final at = place.inAddress(Uri.parse(app));
    expect(at.toString(), '$app?open=abc123&view=files&cam=1');
    expect(Place.fromAddress(at).cam, isTrue);
    expect(Place.fromJson(place.toJson()).cam, isTrue);
    // No event, no Cam.
    expect(Place.fromAddress(Uri.parse('$app?cam=1')).cam, isFalse);
    expect(place.copyWith(eventId: () => 'other').cam, isFalse);
    expect(place.copyWith(eventId: () => null).toJson(), isEmpty);
    expect(place.copyWith(text: true).cam, isTrue);
  });

  testWidgets('opening Cam puts it in the address; a reload there opens it '
      'again; closed, it leaves the address', (tester) async {
    final event = await riffEvent(tester);
    PlaceMemory.address = address = FakeAddress(
      '$app?open=${event.id}&view=files',
    );
    await tester.pumpWidget(TabCamApp(library: library));
    await settle(tester);
    await tester.tap(find.byKey(const Key('cam')));
    await settle(tester);
    expect(find.byType(PlayAlongScreen), findsOneWidget);
    expect(address.query, {'open': event.id, 'view': 'files', 'cam': '1'});

    // The reload: a new app (its library brought down again) at that
    // address.
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    library = Library(PlatformEventStore(), null, (_) async => null);
    final again = await riffEvent(tester);
    PlaceMemory.address = address = FakeAddress(
      '$app?open=${again.id}&view=files&cam=1',
    );
    await tester.pumpWidget(TabCamApp(library: library));
    await settle(tester);
    expect(find.byType(PlayAlongScreen), findsOneWidget);
    expect(address.query, {'open': again.id, 'view': 'files', 'cam': '1'});

    await tester.pageBack();
    await settle(tester);
    expect(find.byType(PlayAlongScreen), findsNothing);
    expect(find.byType(EventScreen), findsOneWidget);
    expect(address.query, {'open': again.id, 'view': 'files'});
  });

  group('with the Premium service', () {
    late CloudSync sync;
    late CloudOcr ocr;
    late FakeAuth auth;

    void premium(FakeOcrApi api) {
      auth = FakeAuth();
      sync = CloudSync(
        library: library,
        auth: auth,
        bucket: FakeBucket(),
        credentials: FakeCredentials(),
        period: const Duration(days: 1),
      );
      ocr = CloudOcr(
        library: library,
        auth: auth,
        sync: sync,
        bucket: FakeBucket(),
        credentials: FakeCredentials(),
        api: api,
      )..start();
      auth.signInAs('ana');
      addTearDown(() {
        ocr.dispose();
        sync.dispose();
      });
    }

    Widget screen(String id) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: EventScreen(
        library: library,
        eventId: id,
        ocr: ocr,
        initialCam: true,
      ),
    );

    testWidgets('Cam waits for Premium\'s answer, then opens (never as the '
        'preview)', (tester) async {
      final event = await riffEvent(tester);
      final api = _SlowApi(premium: true);
      premium(api);
      await tester.pumpWidget(screen(event.id));
      await settle(tester);
      expect(find.byType(PlayAlongScreen), findsNothing);

      api.gate.complete();
      await settle(tester);
      expect(find.byType(PlayAlongScreen), findsOneWidget);
      expect(
        tester.widget<PlayAlongScreen>(find.byType(PlayAlongScreen)).gate,
        isNull,
      );
    });

    testWidgets('without Premium, Cam doesn\'t open, and the place forgets '
        'it', (tester) async {
      final event = await riffEvent(tester);
      PlaceMemory.of(library)
          .update((p) => p.copyWith(eventId: () => event.id, cam: true));
      premium(FakeOcrApi(premium: false));
      await tester.pumpWidget(screen(event.id));
      await settle(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await frames(tester);
      expect(find.byType(PlayAlongScreen), findsNothing);
      expect(PlaceMemory.of(library).place.cam, isFalse);
    });
  });
}
