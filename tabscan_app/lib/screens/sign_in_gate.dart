import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../l10n/language.dart';
import 'sign_in_buttons.dart';

/// What needs signing in: reading tabs and sharing. Signed out, the user
/// can still capture (scan, import, add photos, videos and links), kept on
/// the device only.
enum Gated {
  readTab,
  share;

  String title(AppLocalizations l10n) => switch (this) {
    readTab => l10n.eventGateReadTabTitle,
    share => l10n.eventGateShareTitle,
  };

  String detail(AppLocalizations l10n) => switch (this) {
    readTab => l10n.eventGateReadTabDetail,
    share => l10n.eventGateShareDetail,
  };
}

/// True when the user may do [what]: signed in, or in a build without
/// sign-in ([auth] null or unavailable), where everything stays open.
/// Signed out, it asks them to sign in first and is true once they have.
Future<bool> requireSignIn(
  BuildContext context,
  AuthService? auth,
  Gated what,
) async {
  if (auth == null || !auth.available || auth.user != null) return true;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _SignInSheet(auth: auth, what: what),
  );
  return auth.user != null;
}

class _SignInSheet extends StatefulWidget {
  const _SignInSheet({required this.auth, required this.what});

  final AuthService auth;
  final Gated what;

  @override
  State<_SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends State<_SignInSheet> {
  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_changed);
  }

  @override
  void dispose() {
    widget.auth.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // Signed in: back to what they were doing.
    if (widget.auth.user != null) {
      Navigator.of(context).pop();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = widget.auth;
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.what.title(l10n), style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(l10n.eventGateBody(widget.what.detail(l10n))),
            const SizedBox(height: 16),
            SignInButtons(auth: auth),
            if (auth.error case final error?) ...[
              const SizedBox(height: 12),
              Text(error, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
