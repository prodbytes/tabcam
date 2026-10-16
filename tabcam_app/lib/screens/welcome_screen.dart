import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../cloud/public_capture.dart';
import '../export/incoming_links.dart';
import '../l10n/language.dart';
import 'home_screen.dart';
import 'public_capture_screen.dart';
import 'sign_in_buttons.dart';

/// Signed out, the whole app is this: a welcome and the sign-in buttons.
/// TabCam's features (Home, Capture, Profile) are for signed-in users; a
/// build without sign-in skips it ([SignedInOnly]).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Scaffold(
      key: const Key('welcome'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ListenableBuilder(
                listenable: auth,
                builder: (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.queue_music_outlined,
                      size: 72,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text('TabCam', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      l10n.welcomeBody,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 32),
                    // At launch, while a saved session is restored.
                    if (auth.checking)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: LinearProgressIndicator(),
                      ),
                    SignInButtons(auth: auth),
                    if (auth.error case final error?) ...[
                      const SizedBox(height: 12),
                      Text(
                        error,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => openPrivacyPolicy(context),
                      child: Text(l10n.homePrivacyPolicy),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [signedIn] for a signed-in user; the [WelcomeScreen] for everyone else,
/// except that a capture's link with its key ([PublicCaptures]) opens the
/// capture, read only, until they choose **Sign in**. Without sign-in in
/// this build ([auth] null, or unavailable), [signedIn].
class SignedInOnly extends StatefulWidget {
  const SignedInOnly({
    super.key,
    required this.auth,
    required this.signedIn,
    this.captures,
  });

  final AuthService? auth;
  final Widget signedIn;

  /// Opens captures by their link, signed out; null in a build without the
  /// share API.
  final PublicCaptures? captures;

  @override
  State<SignedInOnly> createState() => _SignedInOnlyState();
}

class _SignedInOnlyState extends State<SignedInOnly> {
  /// The link being viewed signed out. It stays waiting in [IncomingLinks]
  /// too, so once signed in, Home opens it.
  Uri? _link;

  @override
  void initState() {
    super.initState();
    _link = _openable(IncomingLinks.instance.pending);
    IncomingLinks.instance.addListener(_incoming);
  }

  @override
  void dispose() {
    IncomingLinks.instance.removeListener(_incoming);
    super.dispose();
  }

  Uri? _openable(Uri? link) =>
      widget.captures != null && link != null && PublicCaptures.opens(link)
      ? link
      : null;

  void _incoming() {
    final link = _openable(IncomingLinks.instance.pending);
    if (link != null && widget.auth?.user == null) {
      setState(() => _link = link);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    if (auth == null || !auth.available) return widget.signedIn;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        if (auth.user != null) return widget.signedIn;
        final link = _link;
        final captures = widget.captures;
        if (link != null && captures != null) {
          return PublicCaptureScreen(
            key: ValueKey(link),
            link: link,
            captures: captures,
            onSignIn: () => setState(() => _link = null),
          );
        }
        return WelcomeScreen(auth: auth);
      },
    );
  }
}
