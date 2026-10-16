import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/cloud/cloud_sync.dart';
import 'package:tabcam_app/main.dart';

import 'fakes.dart';

import 'package:image/image.dart' as img;
import 'package:tabcam_app/l10n/language.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/event_screen.dart';
import 'package:tabcam_app/screens/home_screen.dart';
import 'package:tabcam_app/screens/tab_text_view.dart';

/// Every language's longer texts still fit a small phone (360 dp): an
/// overflow fails the test.
void main() {
  Widget localized(String code, Widget home) => MaterialApp(
    locale: Locale(code),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  for (final code in LanguageSetting.names.keys) {
    testWidgets('$code fits a small phone', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final library = Library(PlatformEventStore(), null, (_) async => null);
      late String id;
      await tester.runAsync(() async {
        await library.load();
        final event = await library.create([
          img.encodeJpg(img.Image(width: 8, height: 8)),
        ]);
        id = (await library.update(
          event.copyWith(tabText: 'e|--0--3--|\nB|--1-----|'),
        )).id;
      });

      final l10n = lookupAppLocalizations(Locale(code));
      await tester.pumpWidget(
        localized(code, EventScreen(library: library, eventId: id)),
      );
      await frames(tester);
      await tester.pumpWidget(
        localized(
          code,
          Scaffold(
            body: TabTextView(library: library, eventId: id),
          ),
        ),
      );
      await frames(tester);
      expect(find.text(l10n.textViewCopy), findsOneWidget);

      await tester.pumpWidget(
        localized(
          code,
          LanguageScope(
            setting: LanguageSetting(),
            child: const Scaffold(body: ProfileView()),
          ),
        ),
      );
      await frames(tester);
      expect(find.text(l10n.languageTitle), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final code in LanguageSetting.names.keys) {
    testWidgets('$code: Home and Profile fit a small phone', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final library = Library(PlatformEventStore());
      final language = LanguageSetting();
      final auth = FakeAuth();
      late CloudSync sync;
      await tester.runAsync(() async {
        await library.load();
        await library.create([img.encodeJpg(img.Image(width: 8, height: 8))]);
        await language.set(code);
        sync = CloudSync(
          library: library,
          auth: auth,
          bucket: FakeBucket(),
          credentials: FakeCredentials(),
          period: const Duration(days: 1),
        )..start();
      });
      final l10n = lookupAppLocalizations(Locale(code));
      await tester.pumpWidget(
        TabCamApp(library: library, auth: auth, sync: sync, language: language),
      );
      await frames(tester);
      // Signed out: the welcome, alone.
      expect(find.text(l10n.welcomeBody), findsOneWidget);
      await tester.runAsync(() async {
        auth.signInAs('ana');
        while (sync.state != SyncState.synced) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await frames(tester);
      await tester.tap(find.text(l10n.homeTabProfile).last);
      await frames(tester);
      expect(find.text(l10n.languageTitle), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      sync.dispose();
    });
  }
}
