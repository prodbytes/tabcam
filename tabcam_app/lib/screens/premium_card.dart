import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cloud/cloud_ocr.dart';
import '../l10n/language.dart';

/// Whether this is a store app (Android, iOS): it leaves out how to
/// install the phone app, which it is.
bool get storeApp => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Whether the Text view and Cam are locked for this user: Premium is set
/// up ([ocr]) and they don't have it. In a build without the service
/// (null) nothing is locked.
bool premiumLocked(CloudOcr? ocr) => ocr != null && !ocr.premium;

/// TabCam Premium: what it does, and for free users the upgrade offer
/// (subscribe, redeem a voucher, check again after), on every platform,
/// the store apps included. Over a locked feature ([PremiumGate]) it
/// starts with [lead], what the feature is, and ends with **Not now**
/// ([onClose]).
class PremiumCard extends StatelessWidget {
  const PremiumCard({
    super.key,
    required this.ocr,
    required this.email,
    this.privateEmail = false,
    this.lead,
    this.onClose,
  });

  final CloudOcr ocr;

  /// The signed-in address: Premium follows it, so it's the one to
  /// subscribe with. Null signed out (a capture opened by its link): the
  /// card says to sign in to subscribe.
  final String? email;

  /// [email] is Apple's private relay address: no subscription is under
  /// it, so the card says how to use Premium.
  final bool privateEmail;

  /// What the locked feature is, before the offer.
  final String? lead;

  /// Closes the card (**Not now**), where it's over a locked feature.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ocr,
    builder: (context, _) {
      final theme = Theme.of(context);
      final l10n = context.l10n;
      final status = ocr.status;
      final email = this.email;
      final children = <Widget>[
        Row(
          children: [
            Icon(
              ocr.premium ? Icons.workspace_premium : Icons.lock_outline,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(l10n.accountPremiumTitle, style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        if (lead case final lead?) ...[
          Text(lead, key: const Key('premium-lead')),
          const SizedBox(height: 8),
        ],
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
      } else if (email == null) {
        children.add(
          Text(
            l10n.premiumSignInToSubscribe,
            key: const Key('premium-sign-in'),
          ),
        );
      } else {
        children.addAll([
          Text(l10n.accountPremiumOffer(email)),
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
              if (status?.upgradeUrl case final url?)
                FilledButton.icon(
                  onPressed: () => _open(context, url),
                  icon: const Icon(Icons.upgrade),
                  label: Text(l10n.accountPremiumUpgrade),
                ),
              if (status?.voucherUrl case final url?)
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
      if (onClose case final close?) {
        children.addAll([
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('premium-not-now'),
              onPressed: close,
              child: Text(l10n.eventNotNow),
            ),
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

/// A Premium feature's screen for a user without Premium: [child], the
/// screen as it would be, shown but greyed out and taking no taps or keys
/// (a preview), with the [PremiumCard] over it saying what the feature is
/// ([lead]) and how to subscribe; **Not now** ([onClose]) leaves.
class PremiumGate extends StatelessWidget {
  const PremiumGate({
    super.key,
    required this.ocr,
    required this.email,
    required this.lead,
    required this.onClose,
    required this.child,
  });

  final CloudOcr ocr;
  final String? email;
  final String lead;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    key: const Key('premium-gate'),
    fit: StackFit.expand,
    children: [
      // The preview: on screen, but nothing in it works.
      ExcludeSemantics(
        child: IgnorePointer(child: Opacity(opacity: 0.4, child: child)),
      ),
      Positioned.fill(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.25),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: PremiumCard(
                  ocr: ocr,
                  email: email,
                  lead: lead,
                  onClose: onClose,
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// A made-up riff, the preview's tab where the capture has no text tab
/// yet (never a published song's).
const String premiumSampleTab = '''
[Intro]
    Am          F
e|--0---0---1---1---|
B|--1---1---1---1---|
G|--2---2---2---2---|
D|--2---2---3---3---|
A|--0---0---3---3---|
E|------------------|

[Riff]
e|--------------5-3-|
B|--3-5-3-5-3-------|
G|------------------|
D|------------------|
A|------------------|
E|------------------|
''';
