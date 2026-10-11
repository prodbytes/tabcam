import 'package:flutter/material.dart';

import '../cloud/account_deletion.dart';
import '../cloud/cloud_sync.dart';
import '../l10n/language.dart';
import 'premium_card.dart';

/// Profile's **Delete account**: asks first ([confirmAccountDeletion]),
/// then deletes it ([AccountDeletion]) in a dialog that shows how far it
/// is and, if it stops, why. Says so once the account is gone.
Future<void> deleteAccount(
  BuildContext context,
  CloudSync sync, {
  bool premium = false,
  bool? store,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final done = context.l10n.deleteAccountDone;
  if (!await confirmAccountDeletion(context, premium: premium, store: store)) {
    return;
  }
  if (!context.mounted) return;
  final deleted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DeletionDialog(deletion: AccountDeletion(sync)),
  );
  if (deleted ?? false) {
    messenger?.showSnackBar(SnackBar(content: Text(done)));
  }
}

/// Whether the user confirms deleting their account, having been told what
/// goes, that it can't be undone, and what it doesn't touch (their Google
/// account; with Premium set up, a subscription, managed where it was
/// bought: no purchase links in a [storeApp], [store] when null).
Future<bool> confirmAccountDeletion(
  BuildContext context, {
  bool premium = false,
  bool? store,
}) async {
  final theme = Theme.of(context);
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.delete_forever, color: theme.colorScheme.error),
      title: Text(l10n.deleteAccountTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.deleteAccountThisDeletes),
            const SizedBox(height: 8),
            for (final line in [
              l10n.deleteAccountEvents,
              l10n.deleteAccountShares,
              l10n.deleteAccountSharedWithYou,
            ])
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Text('•  $line'),
              ),
            const SizedBox(height: 8),
            Text(
              l10n.deleteAccountCantUndo,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(l10n.deleteAccountGoogleKept),
            if (premium) ...[
              const SizedBox(height: 8),
              Text(
                !(store ?? storeApp)
                    ? l10n.deleteAccountPremiumWeb
                    : l10n.deleteAccountPremiumStore,
              ),
            ],
            const SizedBox(height: 8),
            Text(l10n.deleteAccountOtherDevices),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.deleteAccountCancel),
        ),
        FilledButton(
          key: const Key('confirm-delete-account'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.deleteAccountButton),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Runs [deletion], showing its progress; on an error, what happened, with
/// **Try again** and **Close**. Pops true once the account is deleted.
class DeletionDialog extends StatefulWidget {
  const DeletionDialog({super.key, required this.deletion});

  final AccountDeletion deletion;

  @override
  State<DeletionDialog> createState() => _DeletionDialogState();
}

class _DeletionDialogState extends State<DeletionDialog> {
  DeletionProgress _progress = const DeletionProgress(DeletionStep.cloud);
  String? _error;

  /// The account was deleted though something went wrong, or the user
  /// signed out meanwhile: nothing to try again.
  bool _deleted = false;
  bool _signedOut = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _progress = const DeletionProgress(DeletionStep.cloud);
    });
    try {
      await widget.deletion.run(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) Navigator.pop(context, true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AccountDeletionException
            ? e.message
            : context.l10n.deleteAccountCouldnt('$e');
        _deleted = e is AccountDeletionException && e.deleted;
        _signedOut = widget.deletion.sync.auth.user == null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final error = _error;
    final p = _progress;
    return PopScope(
      canPop: error != null,
      child: AlertDialog(
        title: Text(
          error == null
              ? l10n.deleteAccountDeleting
              : _deleted
              ? l10n.deleteAccountDeleted
              : l10n.deleteAccountNotDeleted,
        ),
        content: error == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.label(l10n)),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: p.total > 0 ? p.done / p.total : null,
                  ),
                ],
              )
            : Text(error, style: TextStyle(color: theme.colorScheme.error)),
        actions: [
          if (error != null) ...[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.deleteAccountClose),
            ),
            if (!_deleted && !_signedOut)
              FilledButton(
                onPressed: _run,
                child: Text(l10n.deleteAccountTryAgain),
              ),
          ],
        ],
      ),
    );
  }
}
