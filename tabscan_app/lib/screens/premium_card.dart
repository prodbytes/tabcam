import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cloud/cloud_ocr.dart';

/// Whether this is a store app (Android, iOS): App Store and Google Play
/// rules don't let it point to buying Premium, which is sold on the web,
/// so it shows no Upgrade, voucher or subscribe wording. Premium bought
/// on the web still works in it.
bool get storeApp => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// TabScan Premium in the account sheet: what it does, and for free users
/// the upgrade offer (subscribe, redeem a voucher, check again after); in
/// a [storeApp], only that it isn't active, and Check again.
class PremiumCard extends StatelessWidget {
  const PremiumCard({
    super.key,
    required this.ocr,
    required this.email,
    this.privateEmail = false,
    this.store,
  });

  final CloudOcr ocr;

  /// The signed-in address: Premium follows it, so it's the one to
  /// subscribe with.
  final String email;

  /// [email] is Apple's private relay address: no subscription is under
  /// it, so the card says how to use Premium.
  final bool privateEmail;

  /// Whether to leave out the upgrade offer (null: [storeApp]).
  final bool? store;

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
        final store = this.store ?? storeApp;
        children.addAll([
          Text(
            store
                ? 'TabScan Premium isn\'t active for $email.'
                : 'Have every scan transcribed automatically in the cloud, '
                      'more accurately than on the phone, and read tabs on '
                      'the web too. Subscribe with $email.',
          ),
          if (privateEmail) ...[
            const SizedBox(height: 8),
            const Text(
              'Premium goes by email address, and you signed in with '
              'Apple\'s private relay address, which has none. If your '
              'Premium is under your own address, sign in with Google, or '
              'with Apple sharing that address.',
              key: Key('private-email'),
            ),
          ],
          if (ocr.error case final e?) ...[
            const SizedBox(height: 8),
            Text(e, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status?.upgradeUrl case final url? when !store)
                FilledButton.icon(
                  onPressed: () => _open(context, url),
                  icon: const Icon(Icons.upgrade),
                  label: const Text('Upgrade'),
                ),
              if (status?.voucherUrl case final url? when !store)
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
