import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_version.dart';
import '../l10n/language.dart';

/// Whether an admin has put the system in maintenance mode: the site's
/// `/status.json` (`{"maintenance": true, "message": "…"}`), which
/// scripts/maintenance.sh writes. Checked at start, then every [period]
/// and whenever the app comes back to the foreground.
///
/// It fails open: if the status can't be read (offline, no file, not
/// JSON), the app runs, so capturing without a network keeps working.
class MaintenanceCheck extends ChangeNotifier with WidgetsBindingObserver {
  MaintenanceCheck({
    required this.url,
    http.Client? client,
    this.period = const Duration(minutes: 2),
    this.timeout = const Duration(seconds: 4),
  }) : _client = client ?? http.Client();

  /// The build's status URL: TABCAM_STATUS_URL when set; on the web,
  /// the site the app is served from; otherwise the site of its stage
  /// (the RC's for `rc`, production's for any other build).
  static Uri defaultUrl() {
    const override = String.fromEnvironment('TABCAM_STATUS_URL');
    if (override.isNotEmpty) return Uri.parse(override);
    if (kIsWeb) return Uri.base.resolve('/status.json');
    return Uri.parse(
      AppVersion.stage == 'rc'
          ? 'https://rc.tabcam.nu01.com/status.json'
          : 'https://tabcam.nu01.com/status.json',
    );
  }

  final Uri url;
  final Duration period;

  /// How long the first check may hold back the app.
  final Duration timeout;
  final http.Client _client;

  /// Whether the first check has finished (or failed).
  bool get checked => _checked;
  bool _checked = false;

  /// Whether the system is in maintenance mode.
  bool get on => _on;
  bool _on = false;

  /// The admin's message for users, if any.
  String? get message => _message;
  String? _message;

  Timer? _periodic;
  bool _started = false;
  bool _disposed = false;

  /// Whether the app is in front: behind (a hidden tab), no checks.
  bool _foreground = true;

  /// Checks now, then every [period] while in front, and on resume.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(check());
    _periodic = Timer.periodic(period, (_) {
      if (_foreground) unawaited(check());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        unawaited(check());
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        _foreground = false;
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// Reads the status. A failed read keeps what was known (the app runs
  /// if nothing was).
  Future<void> check() async {
    // A fresh copy: the browser mustn't answer from its cache.
    final fresh = url.replace(
      queryParameters: {
        ...url.queryParameters,
        't': '${DateTime.now().millisecondsSinceEpoch}',
      },
    );
    try {
      final response = await _client
          .get(fresh, headers: const {'Cache-Control': 'no-cache'})
          .timeout(timeout);
      if (response.statusCode == 200) {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        if (body is Map) {
          final message = body['message'];
          _update(
            on: body['maintenance'] == true,
            message: message is String && message.trim().isNotEmpty
                ? message.trim()
                : null,
          );
          return;
        }
      }
      // No status file (the site answers 403 or 404): not in maintenance.
      if (response.statusCode == 403 || response.statusCode == 404) {
        _update(on: false, message: null);
        return;
      }
    } catch (_) {
      // Offline, timed out, or not JSON: keep what was known.
    }
    _update(on: _on, message: _message);
  }

  void _update({required bool on, required String? message}) {
    if (_disposed) return;
    final changed = !_checked || on != _on || message != _message;
    _checked = true;
    _on = on;
    _message = message;
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _periodic?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _client.close();
    super.dispose();
  }
}

/// Shows the app only while the system isn't in maintenance mode. Until
/// the first check is done it shows nothing; in maintenance mode, only
/// [MaintenanceScreen]. [onEnter] runs when maintenance mode hides a
/// running app (to stop its background work); the app is built again
/// with [app] when it ends.
class MaintenanceGate extends StatefulWidget {
  const MaintenanceGate({
    super.key,
    required this.check,
    required this.app,
    this.onEnter,
  });

  final MaintenanceCheck check;
  final WidgetBuilder app;
  final VoidCallback? onEnter;

  @override
  State<MaintenanceGate> createState() => _MaintenanceGateState();
}

class _MaintenanceGateState extends State<MaintenanceGate> {
  bool _appShown = false;

  @override
  void initState() {
    super.initState();
    widget.check.addListener(_changed);
  }

  @override
  void dispose() {
    widget.check.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (widget.check.on && _appShown) {
      _appShown = false;
      widget.onEnter?.call();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final check = widget.check;
    if (!check.checked) {
      return const ColoredBox(color: MaintenanceScreen.background);
    }
    if (check.on) return MaintenanceScreen(message: check.message);
    _appShown = true;
    return widget.app(context);
  }
}

/// The only thing shown in maintenance mode: a sorry message.
class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key, this.message});

  static const background = Color(0xFF121212);

  /// The message when the admin gave none, in the app's language (English
  /// until the app has shown one); the screen shows it in the device's.
  static String get defaultMessage => appL10n.homeMaintenanceDefault;

  /// The admin's message; the default one ([defaultMessage]) when null.
  final String? message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppVersion.title,
      debugShowCheckedModeBanner: false,
      // Its own app, outside the app's: in the device's language.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE0A030),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: background,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Builder(
                builder: (context) => Text(
                  message ?? context.l10n.homeMaintenanceDefault,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, height: 1.4),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
