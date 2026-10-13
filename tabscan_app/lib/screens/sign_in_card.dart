import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../l10n/language.dart';
import 'sign_in_buttons.dart';

/// Home's sign-in, signed out: what signing in is for and the sign-in
/// buttons (Google's, and Apple's where it's offered), above the captures.
/// Gone once signed in; nothing in a build without sign-in.
class SignInCard extends StatelessWidget {
  const SignInCard({super.key, required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: auth,
    builder: (context, _) {
      if (!auth.available || auth.user != null) return const SizedBox.shrink();
      final theme = Theme.of(context);
      final l10n = context.l10n;
      return Card(
        key: const Key('home-sign-in'),
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.accountSignIn, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(l10n.accountSignInIntro, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              SignInButtons(auth: auth),
              if (auth.error case final error?) ...[
                const SizedBox(height: 8),
                Text(error, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      );
    },
  );
}
