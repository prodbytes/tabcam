/// Where signed-in users' events are synced: the Cognito identity pool and
/// the S3 bucket from `tabscan_infra/` (stacks `tabscan-identity` and
/// `tabscan-user-data`).
///
/// Public identifiers, not secrets, set at build time like the Google
/// client IDs (`.env` locally, repository variables for the deploys).
/// Empty means cloud sync is off, and so is sign-in.
abstract final class CloudConfig {
  static const String region = String.fromEnvironment(
    'AWS_REGION',
    defaultValue: 'us-east-1',
  );

  static const String identityPoolId = String.fromEnvironment(
    'COGNITO_IDENTITY_POOL_ID',
  );

  static const String userDataBucket = String.fromEnvironment(
    'USER_DATA_BUCKET',
  );

  static bool get enabled =>
      identityPoolId.isNotEmpty && userDataBucket.isNotEmpty;
}
