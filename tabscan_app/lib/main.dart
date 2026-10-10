import 'package:flutter/material.dart';

import 'app_version.dart';
import 'auth/auth_service.dart';
import 'auth/google_auth_service.dart';
import 'auth/google_config.dart';
import 'cloud/cloud_config.dart';
import 'cloud/cloud_ocr.dart';
import 'cloud/cloud_sync.dart';
import 'cloud/cognito.dart';
import 'cloud/ocr_api.dart';
import 'cloud/s3.dart';
import 'cloud/share_api.dart';
import 'cloud/share_config.dart';
import 'cloud/sigv4.dart';
import 'library/library.dart';
import 'maintenance/maintenance.dart';
import 'recognition/auto_reader.dart';
import 'screens/home_screen.dart';

void main() {
  // The maintenance check watches the app's lifecycle (WidgetsBinding)
  // before runApp, which would otherwise make the binding: without this,
  // the app crashes at launch.
  WidgetsFlutterBinding.ensureInitialized();
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
        return TabScanApp(
          library: s.library,
          auth: s.auth,
          sync: s.sync,
          ocr: s.ocr,
          reader: s.reader,
        );
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
    reader = AutoReader(library: library, auth: auth, ocr: () => ocr)..start();
  }

  /// Reads every capture's tab by itself.
  late final AutoReader reader;

  static bool get _cloud =>
      CloudConfig.enabled && GoogleConfig.webClientId.isNotEmpty;

  final Library library;
  AuthService? auth;
  CloudSync? sync;
  CloudOcr? ocr;

  /// Starts syncing (and TabScan Premium's cloud OCR, in a build that has
  /// the service set up), if this build syncs and it isn't already.
  void startSync() {
    final auth = this.auth;
    if (auth == null || sync != null) return;
    final bucket = S3Bucket(
      bucket: CloudConfig.userDataBucket,
      region: CloudConfig.region,
    );
    final credentials = CognitoCredentials(
      region: CloudConfig.region,
      identityPoolId: CloudConfig.identityPoolId,
      now: AwsClock.shared.now,
    );
    final started = sync = CloudSync(
      library: library,
      auth: auth,
      bucket: bucket,
      credentials: credentials,
      shares: ShareConfig.apiUrl.isEmpty
          ? null
          : ShareApi(baseUrl: Uri.parse(ShareConfig.apiUrl)),
    )..start();
    if (CloudConfig.ocrUrl.startsWith('https://')) {
      ocr = CloudOcr(
        library: library,
        auth: auth,
        sync: started,
        bucket: bucket,
        credentials: credentials,
        api: HttpOcrApi(Uri.parse(CloudConfig.ocrUrl)),
      )..start();
    }
  }

  /// Stops syncing and cloud OCR (in maintenance mode).
  void stopSync() {
    ocr?.dispose();
    ocr = null;
    sync?.dispose();
    sync = null;
  }
}

class TabScanApp extends StatelessWidget {
  const TabScanApp({
    super.key,
    required this.library,
    this.auth,
    this.sync,
    this.ocr,
    this.reader,
  });

  final Library library;
  final AuthService? auth;
  final CloudSync? sync;
  final CloudOcr? ocr;

  /// Reads every capture's tab by itself (null in tests: no reading).
  final AutoReader? reader;

  @override
  Widget build(BuildContext context) {
    // Amber, like a maple fretboard; dark by default for dim rehearsal rooms.
    ThemeData theme(Brightness brightness) {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFFE0A030),
        brightness: brightness,
      );
      Color tint(Set<WidgetState> states) =>
          states.contains(WidgetState.selected)
          ? scheme.primary
          : scheme.onSurfaceVariant;
      return ThemeData(
        colorScheme: scheme,
        // As Presence's: flat and compact, every label shown, the open tab
        // marked by color only (no pill behind its icon).
        navigationBarTheme: NavigationBarThemeData(
          height: 64,
          elevation: 0,
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          indicatorColor: Colors.transparent,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(size: 24, color: tint(states)),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              overflow: TextOverflow.ellipsis,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: tint(states),
            ),
          ),
        ),
      );
    }

    final app = MaterialApp(
      title: AppVersion.title,
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: HomeScreen(library: library, auth: auth, sync: sync, ocr: ocr),
    );
    final reader = this.reader;
    return reader == null ? app : AutoReaderScope(notifier: reader, child: app);
  }
}
