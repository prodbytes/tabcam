import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../library/library.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

/// The app's language: the device's (the default), or one the user picked
/// on the Profile tab, kept on this device (the library's `language` meta
/// file). The texts are in the ARB files beside this one.
class LanguageSetting extends ChangeNotifier {
  LanguageSetting([this._library]);

  final Library? _library;

  /// The languages the app speaks, by code, with their own names.
  static const Map<String, String> names = {
    'en': 'English',
    'es': 'Español',
    'pt': 'Português',
  };

  /// The meta file it's kept in.
  static const String metaName = 'language';

  String? _code;

  /// The language picked, or null for the device's.
  String? get code => _code;
  Locale? get locale => _code == null ? null : Locale(_code!);

  Future<void> load() async {
    try {
      final json = await _library?.readMeta(metaName);
      if (json == null) return;
      final code = (jsonDecode(json) as Map)['code'];
      if (code is String && names.containsKey(code) && code != _code) {
        _code = code;
        notifyListeners();
      }
    } on Object catch (e) {
      debugPrint('TabScan: language setting unreadable: $e');
    }
  }

  /// Picks [code] (one of [names]), or the device's language (null).
  Future<void> set(String? code) async {
    if (code != null && !names.containsKey(code)) return;
    if (code == _code) return;
    _code = code;
    notifyListeners();
    await _library?.writeMeta(metaName, jsonEncode({'code': code}));
  }
}

/// Gives the widgets below it the [LanguageSetting] (the Profile tab's
/// setting reads and changes it).
class LanguageScope extends InheritedNotifier<LanguageSetting> {
  const LanguageScope({
    super.key,
    required LanguageSetting setting,
    required super.child,
  }) : super(notifier: setting);

  static LanguageSetting? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanguageScope>()?.notifier;
}

extension AppL10n on BuildContext {
  /// The texts in the app's language; English where no localizations are
  /// set up (tests that pump a bare widget).
  AppLocalizations get l10n =>
      AppLocalizations.of(this) ?? lookupAppLocalizations(const Locale('en'));
}

AppLocalizations? _shown;

/// For code without a BuildContext (services' messages shown later): the
/// texts in the language the app last showed; English until it has.
AppLocalizations get appL10n =>
    _shown ?? lookupAppLocalizations(const Locale('en'));

/// Called by the app as it builds (MaterialApp's builder) with the
/// language it shows.
void showingL10n(AppLocalizations? l10n) => _shown = l10n ?? _shown;
