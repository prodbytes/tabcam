import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../cloud/cloud_sync.dart';

/// The library's account button: the cloud, as sync stands, opening the
/// [AccountSheet].
class AccountButton extends StatelessWidget {
  const AccountButton({super.key, required this.auth, required this.sync});

  final AuthService auth;
  final CloudSync sync;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([auth, sync]),
    builder: (context, _) {
      final (icon, tooltip) = switch (sync.state) {
        _ when auth.user == null => (Icons.cloud_off_outlined, 'Sign in'),
        SyncState.syncing => (Icons.cloud_sync_outlined, 'Syncing…'),
        SyncState.failed => (Icons.sync_problem_outlined, 'Sync failed'),
        _ => (Icons.cloud_done_outlined, 'Synced'),
      };
      return IconButton(
        tooltip: tooltip,
        icon: Icon(icon),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (_) => AccountSheet(auth: auth, sync: sync),
        ),
      );
    },
  );
}

/// Signing in to sync events, and once signed in, who it is, how sync
/// stands, Sync now and Sign out.
class AccountSheet extends StatelessWidget {
  const AccountSheet({super.key, required this.auth, required this.sync});

  final AuthService auth;
  final CloudSync sync;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([auth, sync]),
    builder: (context, _) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: auth.user == null ? _signedOut(context) : _signedIn(context),
      ),
    ),
  );

  Widget _signedOut(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sync your tabs', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Sign in to back up your events and have them on every device '
          'you sign in on. Without signing in, they stay on this device.',
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
