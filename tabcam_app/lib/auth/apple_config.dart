/// Sign in with Apple, set at build time like the Google client IDs
/// (`.env`, through `scripts/dart-defines.sh`).
abstract final class AppleConfig {
  /// `TABCAM_APPLE_SIGN_IN=1`: the build has the Sign in with Apple
  /// capability (a paid Apple Developer Program team, the App ID's
  /// capability, the entitlement) and the identity pool trusts Apple, so
  /// iOS offers Sign in with Apple. Off by default: a build without the
  /// capability would show a button that can only fail.
  static const String _flag = String.fromEnvironment(
    'TABCAM_APPLE_SIGN_IN',
  );

  static bool get enabled => _flag == '1' || _flag.toLowerCase() == 'true';

  /// The ID tokens' audience, which the identity pool and the share API
  /// trust: the bundle ID (native sign-in on iOS).
  static const String bundleId = 'com.nu01.tabcam';
}
