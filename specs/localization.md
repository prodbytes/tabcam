# Localization

The app speaks **English**, **Spanish** (neutral Latin American) and
**Portuguese** (Brazilian).

## Picking the language

- By default the app follows the device's language: Spanish or Portuguese
  devices get those (any region: `es-AR`, `pt-PT`, ...), every other
  language gets English.
- **Language** on the [Profile](navigation.md#profile) tab overrides it:
  the device's language, English, Español or Português (each in its own
  language). The app changes at once, and the choice is kept on the
  device (the library's `language` meta file), not synced.
- iOS lists the three languages (`CFBundleLocalizations` in
  `Info.plist`), so the system's per-app language setting offers them.

## The texts

- Every text the app shows is in the ARB files in
  [tabscan_app/lib/l10n/](../tabscan_app/lib/l10n): `app_en.arb` (the
  template, each text with a description), `app_es.arb`, `app_pt.arb`.
  Flutter's gen-l10n ([l10n.yaml](../tabscan_app/l10n.yaml)) generates
  `AppLocalizations` from them on `flutter pub get` and builds; the
  generated files are committed beside them.
- Widgets read them with `context.l10n` (English when a test pumps a
  widget without localizations); code without a widget (services' messages
  shown later) uses `appL10n`, the language the app last showed
  ([lib/l10n/language.dart](../tabscan_app/lib/l10n/language.dart)).
- Counts use ICU plurals; names, addresses and dates go in as
  placeholders.
- Kept as they are: the product names (TabScan, TabScan Premium), what's
  saved or synced (event titles, file names), tab text, and the log.
- The maintenance message follows the device's language.

## Adding a text or a language

- A text: add it to `app_en.arb` with a description, and its translation
  to the other two; `flutter gen-l10n` (or any build) regenerates.
- A language: an `app_<code>.arb` with every key, its name in
  `LanguageSetting.names`, and its code in `CFBundleLocalizations`.

## Verified

- Tests: the language picked is kept and reloaded, an unknown code is
  refused; Profile's Language switches the app at once; every language
  has every text. The existing widget tests run in English unchanged.
