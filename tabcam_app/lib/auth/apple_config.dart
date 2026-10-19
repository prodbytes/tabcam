import '../cloud/share_config.dart';

/// Sign in with Apple, set at build time like the Google client IDs
/// (`.env`, through `scripts/dart-defines.sh`).
abstract final class AppleConfig {
  /// `TABCAM_APPLE_SIGN_IN=1`: the identity pool and the share API trust
  /// Apple, and on iOS the build has the Sign in with Apple capability (a
  /// paid Apple Developer Program team, the App ID's capability, the
  /// entitlement), so iOS and Android offer Sign in with Apple. Off by
  /// default: a build without it would show a button that can only fail.
  static const String _flag = String.fromEnvironment('TABCAM_APPLE_SIGN_IN');

  static bool get enabled => _flag == '1' || _flag.toLowerCase() == 'true';

  /// The ID tokens' audience on iOS (native sign-in): the bundle ID.
  static const String bundleId = 'com.nu01.tabcam';

  /// The ID tokens' audience on Android, where Apple's web flow runs: the
  /// Services ID, grouped under the bundle ID's App ID (so a user has the
  /// same Apple user ID on both).
  static const String servicesId = 'com.nu01.tabcam.signin';

  /// Where Apple posts the web flow's reply: the share API, which sends it
  /// back to the app. The Services ID's return URL. Null without a share
  /// API: then there's no Sign in with Apple on Android.
  static Uri? get webRedirectUri => ShareConfig.apiUrl.isEmpty
      ? null
      : Uri.parse('${ShareConfig.apiUrl}/apple/callback');
}
