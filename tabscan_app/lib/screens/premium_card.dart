import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cloud/cloud_ocr.dart';

/// TabScan Premium in the account sheet: what it does, and for free users
/// the upgrade offer (subscribe, redeem a voucher, check again after).
class PremiumCard extends StatelessWidget {
  const PremiumCard({super.key, required this.ocr, required this.email});

  final CloudOcr ocr;

  /// The signed-in address: Premium follows it, so it's the one to
  /// subscribe with.
  final String email;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ocr,
    builder: (context, _) {
      final theme = Theme.of(context);
      final status = ocr.status;
      final children = <Widget>[
        Row(
          children: [
            Icon(
              ocr.premium ? Icons.workspace_premium : Icons.auto_awesome,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text('TabScan Premium', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
      ];
      if (ocr.premium) {
        children.add(
          Text(
            [
              'Your scans are transcribed in the cloud as they sync: the '
                  'text tab appears on the event by itself.',
              if (status?.expiresAt case final t?)
                ' Premium until ${_date(t)}.',
            ].join(),
          ),
        );
      } else if (status == null && ocr.checking) {
        children.add(const Text('Checking…'));
      } else {
        children.addAll([
          Text(
            'Have every scan transcribed automatically in the cloud, more '
            'accurately than on the phone, and read tabs on the web too. '
            'Subscribe with $email.',
          ),
          if (ocr.error case final e?) ...[
            const SizedBox(height: 8),
            Text(e, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status?.upgradeUrl case final url?)
                FilledButton.icon(
                  onPressed: () => _open(context, url),
                  icon: const Icon(Icons.upgrade),
                  label: const Text('Upgrade'),
                ),
              if (status?.voucherUrl case final url?)
                OutlinedButton(
                  onPressed: () => _open(context, url),
                  child: const Text('Redeem a voucher'),
                ),
              TextButton(
                onPressed: ocr.checking ? null : ocr.refresh,
                child: const Text('Check again'),
              ),
            ],
          ),
        ]);
      }
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      );
    },
  );

  static String _date(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  static Future<void> _open(BuildContext context, Uri url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      messenger?.showSnackBar(SnackBar(content: Text('Couldn\'t open $url')));
    }
  }
}
