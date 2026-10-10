import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../cloud/cloud_sync.dart';

/// The Profile tab's account: signing in, and once signed in, who it is,
/// how sync stands, Sync now and Sign out.
class AccountPanel extends StatelessWidget {
  const AccountPanel({super.key, required this.auth, required this.sync});

  final AuthService auth;
  final CloudSync sync;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([auth, sync]),
    builder: (context, _) =>
        auth.user == null ? _signedOut(context) : _signedIn(context),
  );

  Widget _signedOut(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sign in', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Sign in to read tabs, share, and have your events backed up on '
          'every device you sign in on. Signed out, you can still capture; '
          'it stays on this device.',
        ),
        const SizedBox(height: 16),
        auth.buildSignInButton() ??
            FilledButton.icon(
              onPressed: auth.checking ? null : auth.signIn,
              icon: const Icon(Icons.login),
              label: const Text('Sign in with Google'),
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
        Text(
          syncStatus(sync),
          style: sync.state == SyncState.failed
              ? TextStyle(color: theme.colorScheme.error)
              : theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: sync.state == SyncState.syncing ? null : sync.syncNow,
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
            ),
            const SizedBox(width: 12),
            TextButton(onPressed: auth.signOut, child: const Text('Sign out')),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Signing out keeps your events on this device.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// The sync status line: "Syncing…", "Synced at 14:05 (2 uploaded)", or
/// why it failed.
String syncStatus(CloudSync sync) {
  String two(int n) => n.toString().padLeft(2, '0');
  return switch (sync.state) {
    SyncState.signedOut => 'Not syncing',
    SyncState.syncing => 'Syncing…',
    SyncState.failed => sync.message ?? 'Sync failed',
    SyncState.synced => [
      if (sync.lastSynced case final t?)
        'Synced at ${two(t.hour)}:${two(t.minute)}'
      else
        'Synced',
      if (sync.message case final m?) ' ($m)',
    ].join(),
  };
}
