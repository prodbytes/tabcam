import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_version.dart';
import 'auth/apple_auth_service.dart';
import 'auth/apple_config.dart';
import 'auth/email_auth_service.dart';
import 'auth/email_config.dart';
import 'auth/auth_service.dart';
import 'auth/google_auth_service.dart';
import 'auth/google_config.dart';
import 'auth/multi_auth_service.dart';
import 'cloud/cdn.dart';
import 'cloud/cloud_config.dart';
import 'cloud/cloud_ocr.dart';
import 'cloud/cloud_sync.dart';
import 'cloud/cognito.dart';
import 'cloud/ocr_api.dart';
import 'cloud/s3.dart';
import 'cloud/profile_service.dart';
import 'cloud/public_capture.dart';
import 'cloud/share_api.dart';
import 'cloud/share_config.dart';
import 'cloud/sigv4.dart';
import 'l10n/language.dart';
import 'library/library.dart';
import 'maintenance/maintenance.dart';
import 'export/incoming_links.dart';
import 'recognition/auto_reader.dart';
import 'screens/home_screen.dart';
import 'screens/welcome_screen.dart';

void main() {
  // The maintenance check watches the app's lifecycle (WidgetsBinding)
  // before runApp, which would otherwise make the binding: without this,
  // the app crashes at launch.
  WidgetsFlutterBinding.ensureInitialized();
  // Before runApp, so capture links reach it before the Navigator.
  IncomingLinks.instance.start();
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
        return TabCamApp(
          library: s.library,
          auth: s.auth,
          sync: s.sync,
          ocr: s.ocr,
          reader: s.reader,
          language: s.language,
          captures: s.captures,
        );
      },
      onEnter: () => services?.stopSync(),
    ),
  );
}

/// The running app's services.
class AppServices {
  AppServices() : library = Library()..load() {
    language = LanguageSetting(library)..load();
    // Sign-in and sync only in a build that has both set up (.env, or the
    // deploys' repository variables); otherwise events stay on the device.
    if (_cloud) auth = _signIn()..init();
    // Anyone with a capture's link (with its key) may open it, read only.
    if (_cloud && ShareConfig.apiUrl.isNotEmpty) {
      captures = PublicCaptures(
        api: ShareApi(baseUrl: Uri.parse(ShareConfig.apiUrl)),
        bucket: _linkBucket = _bucket(),
      );
    }
    reader = AutoReader(library: library, auth: auth, ocr: () => ocr)..start();
  }

  /// Reads every capture's tab by itself.
  late final AutoReader reader;
  late final LanguageSetting language;

  /// Google everywhere; on iOS and Android, in a build with
  /// `TABCAM_APPLE_SIGN_IN`, Sign in with Apple too (on Android through the
  /// share API, which takes Apple's reply); everywhere, in a build with the
  /// email user pool (`TABCAM_EMAIL_USER_POOL_ID`), sign in with email,
  /// whose emailed link finishes a sign-in waiting here ([IncomingLinks]).
  static AuthService _signIn() {
    final apple =
        !kIsWeb &&
        AppleConfig.enabled &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            (defaultTargetPlatform == TargetPlatform.android &&
                AppleConfig.webRedirectUri != null));
    final email = EmailConfig.enabled
        ? EmailAuthService(site: kIsWeb ? Uri.base.origin : null)
        : null;
    if (email != null) {
      void link() {
        if (IncomingLinks.instance.takeSignInCode() case final code?) {
          unawaited(email.completeWithLink(code));
        }
      }

      IncomingLinks.instance.addListener(link);
      // A link the app was opened with: once the waiting sign-in is back.
      email.addListener(() {
        if (!email.checking) link();
      });
    }
    if (!apple && email == null) return GoogleAuthService();
    return MultiAuthService([
      if (apple) AppleAuthService(),
      GoogleAuthService(),
      ?email,
    ]);
  }

  static bool get _cloud =>
      CloudConfig.enabled && GoogleConfig.webClientId.isNotEmpty;

  /// The user-data bucket, read through the site's CloudFront where the
  /// share API grants it (CdnConfig), and kept on the device as the files'
  /// Cache-Control says.
  static S3Bucket _bucket() => S3Bucket(
    bucket: CloudConfig.userDataBucket,
    region: CloudConfig.region,
    cdnSite: CdnConfig.site,
  );

  S3Bucket? _linkBucket;
  String? _cachedFor;

  /// What the device keeps of users' folders is the signed-in user's: it
  /// goes when they sign out, or another account signs in.
  void _clearCacheOnSignOut(AuthService auth, S3Bucket bucket) {
    _cachedFor = auth.user?.id;
    auth.addListener(() {
      final id = auth.user?.id;
      if (_cachedFor != null && id != _cachedFor) {
        unawaited(bucket.clearCache());
        unawaited(_linkBucket?.clearCache());
      }
      _cachedFor = id;
    });
  }

  final Library library;
  AuthService? auth;
  PublicCaptures? captures;
  CloudSync? sync;
  CloudOcr? ocr;

  /// Starts syncing (and TabCam Premium's cloud OCR, in a build that has
  /// the service set up), if this build syncs and it isn't already.
  void startSync() {
    final auth = this.auth;
    if (auth == null || sync != null) return;
    final bucket = _bucket();
    _clearCacheOnSignOut(auth, bucket);
    final shares = ShareConfig.apiUrl.isEmpty
        ? null
        : ShareApi(baseUrl: Uri.parse(ShareConfig.apiUrl));
    // With the share API, the folder is the profile's (every linked
    // sign-in's); without it (local web builds), the sign-in's own.
    final credentials = shares == null
        ? CognitoCredentials(
            region: CloudConfig.region,
            identityPoolId: CloudConfig.identityPoolId,
            now: AwsClock.shared.now,
          )
        : ProfileCredentials(
            region: CloudConfig.region,
            identityPoolId: CloudConfig.identityPoolId,
            shares: shares,
            now: AwsClock.shared.now,
          );
    final started = sync = CloudSync(
      library: library,
      auth: auth,
      bucket: bucket,
      credentials: credentials,
      shares: shares,
    )..start();
    if (shares != null) {
      // Linking changes the profile's addresses: Premium is checked again.
      started.profiles = ProfileService(
        sync: started,
        onChanged: () => ocr?.refresh(),
      )..start();
    }
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
    sync?.profiles?.dispose();
    sync?.dispose();
    sync = null;
  }
}

class TabCamApp extends StatelessWidget {
  const TabCamApp({
    super.key,
    required this.library,
    this.auth,
    this.sync,
    this.ocr,
    this.reader,
    this.language,
    this.captures,
  });

  /// Opens captures by their link, read only (null: not in this build).
  final PublicCaptures? captures;

  final Library library;
  final AuthService? auth;
  final CloudSync? sync;
  final CloudOcr? ocr;

  /// Reads every capture's tab by itself (null in tests: no reading).
  final AutoReader? reader;

  /// The language picked on the Profile tab (null in tests: the device's).
  final LanguageSetting? language;

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

    final language = this.language;
    Widget materialApp(BuildContext context) => MaterialApp(
      title: AppVersion.title,
      locale: language?.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        showingL10n(AppLocalizations.of(context));
        return child!;
      },
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: ThemeMode.dark,
      // Not the launch link's path (an App Link's /app/?c=…): there are no
      // named routes. IncomingLinks opens the capture.
      initialRoute: '/',
      // Signed out (in a build with sign-in): only the welcome, or a
      // capture opened by its link.
      home: SignedInOnly(
        auth: auth,
        captures: captures,
        signedIn: HomeScreen(
          library: library,
          auth: auth,
          sync: sync,
          ocr: ocr,
          captures: captures,
        ),
      ),
    );
    final app = language == null
        ? materialApp(context)
        : LanguageScope(
            setting: language,
            child: ListenableBuilder(
              listenable: language,
              builder: (c, _) => materialApp(c),
            ),
          );
    final reader = this.reader;
    return reader == null ? app : AutoReaderScope(notifier: reader, child: app);
  }
}
