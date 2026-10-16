import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../cloud/cloud_ocr.dart';
import '../cloud/cloud_sync.dart';
import '../cloud/ocr_api.dart';
import '../l10n/language.dart';
import '../cloud/profile_service.dart';
import 'delete_account.dart';
import 'linked_accounts_sheet.dart';
import 'premium_card.dart';
import 'sign_in_buttons.dart';

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
/// upgrade offer in a [storeApp]); last, Delete account.
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
        SignInButtons(auth: auth),
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
          subtitle: switch ([
            if (user.label != user.email) user.email,
            if (user.provider != AuthProvider.google)
              l10n.accountSignedInWith(user.provider.label),
          ]) {
            [] => null,
            final lines => Text(lines.join('\n')),
          },
        ),
        if (sync.profiles case final profiles?)
          _ProfileLines(profiles: profiles)
        else if (ocr case final ocr?)
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
          PremiumCard(
            ocr: ocr,
            email: user.email,
            privateEmail: user.privateEmail,
            store: store,
          ),
        ],
        const SizedBox(height: 16),
        // Only a profile's owner deletes it: the others unlink.
        if (sync.profiles?.profile case final p? when !p.youOwn)
          Text(l10n.profileNotOwner, style: theme.textTheme.bodySmall)
        else ...[
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              padding: EdgeInsets.zero,
            ),
            onPressed: () => deleteAccount(
              context,
              sync,
              premium: ocr != null,
              store: store,
            ),
            icon: const Icon(Icons.delete_forever_outlined),
            label: Text(l10n.deleteAccountButton),
          ),
          Text(l10n.accountDeleteNote, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

/// The profile: its ID, its roles (every linked account's), and
/// **Linked accounts**.
class _ProfileLines extends StatelessWidget {
  const _ProfileLines({required this.profiles});

  final ProfileService profiles;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: profiles,
      builder: (context, _) {
        final p = profiles.profile;
        if (p == null) {
          return profiles.error == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    profiles.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(l10n.profileId(p.id), key: const Key('profile')),
              Text(
                l10n.profileRoles(p.roles.join(', ')),
                key: const Key('role'),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => showLinkedAccounts(context, profiles),
                icon: const Icon(Icons.link),
                label: Text(
                  '${l10n.profileLinkedAccounts} (${p.accounts.length})',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The signed-in user's role in TabCam, as rbacr has it (through the
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
