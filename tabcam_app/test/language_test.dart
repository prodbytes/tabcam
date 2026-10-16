import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/l10n/language.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/home_screen.dart';

Widget _app(LanguageSetting language) => LanguageScope(
  setting: language,
  child: ListenableBuilder(
    listenable: language,
    builder: (context, _) => MaterialApp(
      locale: language.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: ProfileView()),
    ),
  ),
);

void main() {
  test('the language picked is kept on the device', () async {
    final library = Library(PlatformEventStore());
    await library.load();
    final language = LanguageSetting(library);
    expect(language.code, isNull);
    await language.set('pt');
    expect(language.locale, const Locale('pt'));

    final again = LanguageSetting(library);
    await again.load();
    expect(again.code, 'pt');

    await again.set('fr'); // not one of the app's
    expect(again.code, 'pt');
    await again.set(null);
    final third = LanguageSetting(library);
    await third.load();
    expect(third.code, isNull);
  });

  testWidgets('Profile switches the language at once', (tester) async {
    final language = LanguageSetting();
    await tester.pumpWidget(_app(language));
    expect(find.text('Language'), findsOneWidget);

    await tester.tap(find.byKey(const Key('language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Español').last);
    await tester.pumpAndSettle();
    expect(language.code, 'es');
    expect(find.text('Idioma'), findsOneWidget);

    await tester.tap(find.byKey(const Key('language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Português').last);
    await tester.pumpAndSettle();
    expect(find.text('Idioma'), findsOneWidget);
    expect(find.text('Idioma do dispositivo'), findsNothing);
    expect(
      AppLocalizations.of(tester.element(find.byType(ProfileView)))!.localeName,
      'pt',
    );
  });

  test('every language has every text', () {
    final en = lookupAppLocalizations(const Locale('en'));
    for (final code in LanguageSetting.names.keys) {
      final l10n = lookupAppLocalizations(Locale(code));
      expect(l10n.localeName, code);
      expect(l10n.languageTitle, isNotEmpty);
    }
    expect(en.languageSystem, 'Device\'s language');
  });
}
