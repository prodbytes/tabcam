import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../cloud/account_deletion.dart';
import '../cloud/cloud_sync.dart';

/// Profile's **Delete account**: asks first ([confirmAccountDeletion]),
/// then deletes it ([AccountDeletion]) in a dialog that shows how far it
/// is and, if it stops, why. Says so once the account is gone.
Future<void> deleteAccount(
  BuildContext context,
  CloudSync sync, {
  bool premium = false,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (!await confirmAccountDeletion(context, premium: premium)) return;
  if (!context.mounted) return;
  final deleted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DeletionDialog(deletion: AccountDeletion(sync)),
  );
  if (deleted ?? false) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Your TabScan account was deleted.')),
    );
  }
}

/// Whether the user confirms deleting their account, having been told what
/// goes, that it can't be undone, and what it doesn't touch (their Google
/// account; with Premium set up, a subscription, managed where it was
/// bought: no purchase links in the apps).
Future<bool> confirmAccountDeletion(
  BuildContext context, {
  bool premium = false,
}) async {
  final theme = Theme.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.delete_forever, color: theme.colorScheme.error),
      title: const Text('Delete your account?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This deletes:'),
            const SizedBox(height: 8),
            for (final line in const [
              'All your events, in the cloud and on this device.',
              'Your shares: the people you shared captures with lose them.',
              'The captures shared with you: they stop showing here.',
            ])
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Text('•  $line'),
              ),
            const SizedBox(height: 8),
            Text(
              "It can't be undone.",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            const Text("Your Google account isn't deleted."),
            if (premium) ...[
              const SizedBox(height: 8),
              Text(
                kIsWeb
                    ? "A TabScan Premium subscription isn't cancelled: "
                          'cancel it on Substack, where you subscribed.'
                    : "A TabScan Premium subscription isn't cancelled: "
                          "it's managed where you bought it.",
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'If TabScan is signed in on your other devices, sign out '
              "there first, so they don't upload their events again.",
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirm-delete-account'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete account'),
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
            : "Your account couldn't be deleted: $e";
        _deleted = e is AccountDeletionException && e.deleted;
        _signedOut = widget.deletion.sync.auth.user == null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;
    final p = _progress;
    return PopScope(
      canPop: error != null,
      child: AlertDialog(
        title: Text(
          error == null
              ? 'Deleting your account'
              : _deleted
              ? 'Account deleted'
              : 'Account not deleted',
        ),
        content: error == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.label),
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
              child: const Text('Close'),
            ),
            if (!_deleted && !_signedOut)
              FilledButton(onPressed: _run, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}
