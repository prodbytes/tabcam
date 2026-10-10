import 'package:flutter/material.dart';

import 'app_version.dart';
import 'auth/auth_service.dart';
import 'auth/google_auth_service.dart';
import 'auth/google_config.dart';
import 'cloud/cloud_config.dart';
import 'cloud/cloud_sync.dart';
import 'cloud/cognito.dart';
import 'cloud/s3.dart';
import 'cloud/sigv4.dart';
import 'library/library.dart';
import 'screens/library_screen.dart';

void main() {
  final library = Library()..load();
  // Sign-in and sync only in a build that has both set up (.env, or the
  // deploys' repository variables); otherwise scans stay on the device.
  AuthService? auth;
  CloudSync? sync;
  if (CloudConfig.enabled && GoogleConfig.webClientId.isNotEmpty) {
    auth = GoogleAuthService()..init();
    sync = CloudSync(
      library: library,
      auth: auth,
      bucket: S3Bucket(
        bucket: CloudConfig.userDataBucket,
        region: CloudConfig.region,
      ),
      credentials: CognitoCredentials(
        region: CloudConfig.region,
        identityPoolId: CloudConfig.identityPoolId,
        now: AwsClock.shared.now,
      ),
    )..start();
  }
  runApp(TabScanApp(library: library, auth: auth, sync: sync));
}

class TabScanApp extends StatelessWidget {
  const TabScanApp({super.key, required this.library, this.auth, this.sync});

  final Library library;
  final AuthService? auth;
  final CloudSync? sync;

  @override
  Widget build(BuildContext context) {
    // Amber, like a maple fretboard; dark by default for dim rehearsal rooms.
    ThemeData theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFE0A030),
        brightness: brightness,
      ),
    );
    return MaterialApp(
      title: AppVersion.title,
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: LibraryScreen(library: library, auth: auth, sync: sync),
    );
  }
}
