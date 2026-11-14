/// The names of the library's meta documents (`EventStore.readMeta`), all
/// in one place. On Android, iOS and the desktop each names a file, so it
/// must pass `checkId` (lowercase letters and digits only, 32 at most): the
/// store refuses anything else, and the setting would never be kept.
abstract final class MetaNames {
  /// Cam's settings (Auto-pass, the microphone chosen in Rec's menu).
  static const String cam = 'cam';

  /// The play-along player's settings (the count-in).
  static const String playAlong = 'playalong';

  /// The deletes that no longer ask ("Don't ask again").
  static const String deleteConfirms = 'deleteconfirms';

  /// The sidebars' widths, and the dictionary's turn.
  static const String sidebars = 'sidebars';

  /// Where the user was (the web keeps it in the page's address instead).
  static const String place = 'place';

  /// The language the user picked.
  static const String language = 'language';

  /// The metronome's tempo and time signature.
  static const String metronome = 'metronome';

  /// What cloud sync has synced, per event.
  static const String cloudSync = 'cloudsync';

  /// Whether the signed-in user has Premium, as the service last said
  /// (`CloudOcr.premiumNow`: believed for a week, offline).
  static const String premium = 'premium';

  /// What cloud OCR has filled, per event.
  static const String cloudOcr = 'cloudocr';

  /// The device's settings: small, and kept across reloads on the web too
  /// (in the browser's localStorage), where the captures are in memory.
  /// Cloud sync's and cloud OCR's states are not among them: they describe
  /// the captures here, which a reload loses on the web.
  static const Set<String> deviceSettings = {
    cam,
    playAlong,
    deleteConfirms,
    sidebars,
    place,
    language,
    metronome,
    premium,
  };

  /// Every meta name the app uses.
  static const Set<String> all = {...deviceSettings, cloudSync, cloudOcr};
}
