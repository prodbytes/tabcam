import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../auth/auth_service.dart';
import '../l10n/language.dart';

/// A sign-in button for each of [auth]'s providers, one under the other:
/// Sign in with Apple first where it's offered (iOS), drawn per Apple's
/// Human Interface Guidelines (black on light, white on dark, the same size
/// as Google's button), then Google's (on the web, Google's own button).
class SignInButtons extends StatelessWidget {
  const SignInButtons({super.key, required this.auth});

  final AuthService auth;

  static const double _height = 44;

  @override
  Widget build(BuildContext context) {
    final providers = auth.providers;
    final ordered = [
      if (providers.contains(AuthProvider.apple)) AuthProvider.apple,
      ...providers.where((p) => p != AuthProvider.apple),
    ];
    final buttons = [for (final p in ordered) _button(context, p)];
    // One provider: its button as before, at its natural width.
    if (buttons.length == 1) return buttons.single;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, b) in buttons.indexed) ...[
            if (i > 0) const SizedBox(height: 12),
            b,
          ],
        ],
      ),
    );
  }

  Widget _button(BuildContext context, AuthProvider provider) {
    final onPressed = auth.checking ? null : () => auth.signIn(provider);
    final own = auth.buildSignInButton(provider);
    if (own != null) return own;
    return switch (provider) {
      AuthProvider.apple => SignInWithAppleButton(
        key: const Key('sign-in-apple'),
        onPressed: onPressed,
        height: _height,
        text: context.l10n.accountSignInWithApple,
        style: Theme.of(context).brightness == Brightness.dark
            ? SignInWithAppleButtonStyle.white
            : SignInWithAppleButtonStyle.black,
      ),
      AuthProvider.google => FilledButton.icon(
        key: const Key('sign-in-google'),
        onPressed: onPressed,
        style: auth.providers.length > 1
            ? FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(_height),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              )
            : null,
        icon: const Icon(Icons.login),
        label: Text(context.l10n.accountSignInWithGoogle),
      ),
    };
  }
}
