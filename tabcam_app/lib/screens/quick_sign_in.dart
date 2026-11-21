import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../auth/auth_service.dart';
import '../l10n/language.dart';

/// The app's [AuthService], for [QuickSignIn] on every screen (the app puts
/// it above its navigator, so pushed screens have it too).
class SignInScope extends InheritedWidget {
  const SignInScope({super.key, required this.auth, required super.child});

  final AuthService auth;

  static AuthService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SignInScope>()?.auth;

  @override
  bool updateShouldNotify(SignInScope oldWidget) => auth != oldWidget.auth;
}

/// Signed out, the one-click sign-in at the top right of every screen (the
/// welcome, and a capture or file opened by its link): one tap signs in,
/// where the user is. Signed in, or without sign-in in this build, nothing.
///
/// It signs in with [quickProvider]: on the web Google's own button
/// (Google's popup), on Android the "Sign in with Google" sheet, on iOS
/// Sign in with Apple. On a phone (under 600 dp) it's an icon alone. The
/// other ways in stay on the welcome.
class QuickSignIn extends StatelessWidget {
  const QuickSignIn({super.key, this.auth});

  /// Whose sign-in; else the [SignInScope]'s.
  final AuthService? auth;

  /// Where an icon replaces the button.
  static const double compactWidth = 600;

  /// The provider of the one-click sign-in among [providers]: Apple on iOS
  /// and macOS where it's offered, else Google, else Apple. None for email
  /// alone (a code to type isn't one click).
  static AuthProvider? quickProvider(
    List<AuthProvider> providers,
    TargetPlatform platform,
  ) {
    final apple = providers.contains(AuthProvider.apple);
    if (apple &&
        (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS)) {
      return AuthProvider.apple;
    }
    if (providers.contains(AuthProvider.google)) return AuthProvider.google;
    return apple ? AuthProvider.apple : null;
  }

  @override
  Widget build(BuildContext context) {
    final auth = this.auth ?? SignInScope.maybeOf(context);
    if (auth == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        if (!auth.available || auth.user != null) {
          return const SizedBox.shrink();
        }
        final provider = quickProvider(auth.providers, defaultTargetPlatform);
        if (provider == null) return const SizedBox.shrink();
        final icon = MediaQuery.sizeOf(context).width < compactWidth;
        return Padding(
          key: const Key('quick-sign-in'),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(child: _button(context, auth, provider, icon: icon)),
        );
      },
    );
  }

  Widget _button(
    BuildContext context,
    AuthService auth,
    AuthProvider provider, {
    required bool icon,
  }) {
    final own = icon
        ? auth.buildIconSignInButton(provider) ??
              auth.buildSignInButton(provider)
        : auth.buildSignInButton(provider);
    if (own != null) return own;
    final l10n = context.l10n;
    final onPressed = auth.checking ? null : () => auth.signIn(provider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch ((provider, icon)) {
      // Apple's logo-only button: black on light, white on dark.
      (AuthProvider.apple, true) => IconButton.filled(
        key: const Key('quick-sign-in-apple'),
        tooltip: l10n.accountSignInWithApple,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: dark ? Colors.white : Colors.black,
          foregroundColor: dark ? Colors.black : Colors.white,
        ),
        icon: const Icon(Icons.apple),
      ),
      (AuthProvider.apple, false) => SizedBox(
        width: 200,
        child: SignInWithAppleButton(
          key: const Key('quick-sign-in-apple'),
          onPressed: onPressed,
          height: 36,
          text: l10n.accountSignInWithApple,
          style: dark
              ? SignInWithAppleButtonStyle.white
              : SignInWithAppleButtonStyle.black,
        ),
      ),
      (_, true) => IconButton.filled(
        key: const Key('quick-sign-in-google'),
        tooltip: l10n.accountSignInWithGoogle,
        onPressed: onPressed,
        icon: const Icon(Icons.login),
      ),
      (_, false) => FilledButton.icon(
        key: const Key('quick-sign-in-google'),
        onPressed: onPressed,
        icon: const Icon(Icons.login),
        label: Text(l10n.accountSignInWithGoogle),
      ),
    };
  }
}
