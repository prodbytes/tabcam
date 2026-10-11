import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../cloud/cloud_ocr.dart';
import '../cloud/cloud_sync.dart';
import '../cloud/ocr_api.dart';
import '../l10n/language.dart';
import 'premium_card.dart';

/// The [AccountPanel] in a bottom sheet, for places away from the Profile
/// tab (an event's Premium Upgrade, on the web); with Premium set up
/// ([ocr]), it checks again whether the user is premium (they may have just
/// upgraded).
Future<void> showAccountSheet(
  BuildContext context,
  AuthService auth,
  CloudSync sync,
  CloudOcr? ocr,
) {
  if (auth.user != null) ocr?.refresh();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: AccountPanel(auth: auth, sync: sync, ocr: ocr),
      ),
    ),
  );
}

/// The Profile tab's account: signing in, and once signed in, who it is,
/// how sync stands, Sync now and Sign out; with Premium set up ([ocr]),
/// the user's role ([roleLabel]) and the Premium card too (without the
/// upgrade offer in a [storeApp]).
class AccountPanel extends StatelessWidget {
  const AccountPanel({
    super.key,
    required this.auth,
    required this.sync,
    this.ocr,
    this.store,
  });

  final AuthService auth;
  final CloudSync sync;
  final CloudOcr? ocr;

  /// Whether to leave out the upgrade offer (null: [storeApp]).
  final bool? store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([auth, sync, ?ocr]),
    builder: (context, _) =>
        auth.user == null ? _signedOut(context) : _signedIn(context),
  );

  Widget _signedOut(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.accountSignIn, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(l10n.accountSignInIntro),
        if (ocr != null) ...[
          const SizedBox(height: 8),
          Text(l10n.accountSignInPremium),
        ],
        const SizedBox(height: 16),
        auth.buildSignInButton() ??
            FilledButton.icon(
              onPressed: auth.checking ? null : auth.signIn,
              icon: const Icon(Icons.login),
              label: Text(l10n.accountSignInWithGoogle),
            ),
        if (auth.error case final error?) ...[
          const SizedBox(height: 12),
          Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }

  Widget _signedIn(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final user = auth.user!;
    final photo = user.photoUrl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundImage: photo == null ? null : NetworkImage(photo),
            child: photo == null ? const Icon(Icons.person_outline) : null,
          ),
          title: Text(user.label),
          subtitle: user.label == user.email ? null : Text(user.email),
        ),
        if (ocr case final ocr?)
          if (roleLabel(ocr, l10n) case final role?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(l10n.accountRole(role), key: const Key('role')),
            ),
        Text(
          syncStatus(sync, l10n),
          style: sync.state == SyncState.failed
              ? TextStyle(color: theme.colorScheme.error)
              : theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        // Wraps on a small phone (and in longer languages).
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonalIcon(
              onPressed: sync.state == SyncState.syncing ? null : sync.syncNow,
              icon: const Icon(Icons.sync),
              label: Text(l10n.accountSyncNow),
            ),
            TextButton(
              onPressed: auth.signOut,
              child: Text(l10n.accountSignOut),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(l10n.accountSignOutNote, style: theme.textTheme.bodySmall),
        if (ocr case final ocr?) ...[
          const SizedBox(height: 16),
          PremiumCard(ocr: ocr, email: user.email, store: store),
        ],
      ],
    );
  }
}

/// The signed-in user's role in TabScan, as rbacr has it (through the
/// cloud OCR service): Premium, or else Free (`premium` implies `free`);
/// null before the first check. In [l10n]'s language (default: [appL10n]).
String? roleLabel(CloudOcr ocr, [AppLocalizations? l10n]) {
  final t = l10n ?? appL10n;
  return switch (ocr.status) {
    null => ocr.checking ? t.accountChecking : null,
    PremiumStatus(premium: true) => t.accountRolePremium,
    PremiumStatus(checked: false) => t.accountRoleFreeUnchecked,
    _ => t.accountRoleFree,
  };
}

/// The sync status line: "Syncing…", "Synced at 14:05 (2 uploaded)", or
/// why it failed. In [l10n]'s language (default: [appL10n]).
String syncStatus(CloudSync sync, [AppLocalizations? l10n]) {
  final l = l10n ?? appL10n;
  String two(int n) => n.toString().padLeft(2, '0');
  return switch (sync.state) {
    SyncState.signedOut => l.accountSyncOff,
    SyncState.syncing => l.accountSyncing,
    SyncState.failed => sync.message ?? l.accountSyncFailed,
    SyncState.synced => [
      if (sync.lastSynced case final t?)
        l.accountSyncedAt('${two(t.hour)}:${two(t.minute)}')
      else
        l.accountSynced,
      if (sync.message case final m?) ' ($m)',
    ].join(),
  };
}
