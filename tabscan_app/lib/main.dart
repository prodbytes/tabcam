import 'package:flutter/material.dart';

import 'app_version.dart';
import 'auth/auth_service.dart';
import 'auth/google_auth_service.dart';
import 'auth/google_config.dart';
import 'cloud/cloud_config.dart';
import 'cloud/cloud_sync.dart';
import 'cloud/cognito.dart';
import 'cloud/s3.dart';
import 'cloud/share_api.dart';
import 'cloud/share_config.dart';
import 'cloud/sigv4.dart';
import 'library/library.dart';
import 'maintenance/maintenance.dart';
import 'screens/library_screen.dart';

void main() {
  final maintenance = MaintenanceCheck(url: MaintenanceCheck.defaultUrl())
    ..start();
  // Nothing starts (library, sign-in, sync) until the status says the
  // system isn't in maintenance mode.
  AppServices? services;
  runApp(
    MaintenanceGate(
      check: maintenance,
      app: (context) {
        final s = services ??= AppServices();
        s.startSync();
        return TabScanApp(library: s.library, auth: s.auth, sync: s.sync);
      },
      onEnter: () => services?.stopSync(),
    ),
  );
}

/// The running app's services.
class AppServices {
  AppServices() : library = Library()..load() {
    // Sign-in and sync only in a build that has both set up (.env, or the
    // deploys' repository variables); otherwise events stay on the device.
    if (_cloud) auth = GoogleAuthService()..init();
  }

  static bool get _cloud =>
      CloudConfig.enabled && GoogleConfig.webClientId.isNotEmpty;

  final Library library;
  AuthService? auth;
  CloudSync? sync;

  /// Starts syncing, if this build syncs and it isn't already.
  void startSync() {
    final auth = this.auth;
    if (auth == null || sync != null) return;
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
      shares: ShareConfig.apiUrl.isEmpty
          ? null
          : ShareApi(baseUrl: Uri.parse(ShareConfig.apiUrl)),
    )..start();
  }

  /// Stops syncing (in maintenance mode).
  void stopSync() {
    sync?.dispose();
    sync = null;
  }
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
