/// The share API's address (tabscan-share-api's ApiUrl), set at build time
/// like the rest of the cloud settings. Empty means no sharing.
abstract final class ShareConfig {
  static const String apiUrl = String.fromEnvironment(
    'TABSCANNER_SHARE_API_URL',
  );
}
