import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cloud/cloud_ocr.dart';
import '../l10n/language.dart';

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
    this.store,
  });

  final CloudOcr ocr;

  /// The signed-in address: Premium follows it, so it's the one to
  /// subscribe with.
  final String email;

  /// Whether to leave out the upgrade offer (null: [storeApp]).
  final bool? store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ocr,
    builder: (context, _) {
      final theme = Theme.of(context);
      final l10n = context.l10n;
      final status = ocr.status;
      final children = <Widget>[
        Row(
          children: [
            Icon(
              ocr.premium ? Icons.workspace_premium : Icons.auto_awesome,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(l10n.accountPremiumTitle, style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
      ];
      if (ocr.premium) {
        children.add(
          Text(
            [
              l10n.accountPremiumActive,
              if (status?.expiresAt case final t?)
                ' ${l10n.accountPremiumUntil(_date(t))}',
            ].join(),
          ),
        );
      } else if (status == null && ocr.checking) {
        children.add(Text(l10n.accountChecking));
      } else {
        final store = this.store ?? storeApp;
        children.addAll([
          Text(
            store
                ? l10n.accountPremiumInactive(email)
                : l10n.accountPremiumOffer(email),
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
              if (status?.upgradeUrl case final url? when !store)
                FilledButton.icon(
                  onPressed: () => _open(context, url),
                  icon: const Icon(Icons.upgrade),
                  label: Text(l10n.accountPremiumUpgrade),
                ),
              if (status?.voucherUrl case final url? when !store)
                OutlinedButton(
                  onPressed: () => _open(context, url),
                  child: Text(l10n.accountPremiumVoucher),
                ),
              TextButton(
                onPressed: ocr.checking ? null : ocr.refresh,
                child: Text(l10n.accountPremiumCheckAgain),
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
    final l10n = context.l10n;
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.accountPremiumCouldntOpen('$url'))),
      );
    }
  }
}
