/// The share API's address (tabcam-share-api's ApiUrl), set at build time
/// like the rest of the cloud settings. Empty means no sharing.
abstract final class ShareConfig {
  static const String apiUrl = String.fromEnvironment(
    'TABCAM_SHARE_API_URL',
  );
}
