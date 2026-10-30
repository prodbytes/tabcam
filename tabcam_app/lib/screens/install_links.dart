import 'package:flutter/material.dart';

import '../l10n/language.dart';
import 'link_page.dart';

/// TabCam's latest release on GitHub, with the Android APK
/// (specs/release.md).
final Uri latestReleaseUrl = Uri.parse(
  'https://github.com/prodbytes/tabcam/releases/latest',
);

/// The README's iPhone install guide: the release's iOS app is unsigned,
/// so it's built and signed on a Mac.
final Uri iphoneGuideUrl = Uri.parse(
  'https://github.com/prodbytes/tabcam/blob/main/README.md#ios',
);

/// The Profile tab's last section until TabCam is in the app stores:
/// **iPhone** and **Android** links, each opening how to download the app
/// from GitHub and install it ([showInstallSteps]). Only outside a store
/// app (the same binaries go to the stores, which don't allow pointing to
/// other installs).
class InstallLinks extends StatelessWidget {
  const InstallLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.installTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(l10n.installIntro, style: theme.textTheme.bodySmall),
        Wrap(
          children: [
            TextButton.icon(
              key: const Key('install-iphone'),
              onPressed: () => showInstallSteps(context, InstallTarget.iphone),
              icon: const Icon(Icons.phone_iphone),
              label: Text(l10n.installIphone),
            ),
            TextButton.icon(
              key: const Key('install-android'),
              onPressed: () => showInstallSteps(context, InstallTarget.android),
              icon: const Icon(Icons.phone_android),
              label: Text(l10n.installAndroid),
            ),
          ],
        ),
      ],
    );
  }
}

/// The phones [InstallLinks] has steps for.
enum InstallTarget { iphone, android }

/// How to install TabCam from GitHub on [target], in a bottom sheet, with
/// a button to the release (Android) or the build guide (iPhone).
Future<void> showInstallSteps(BuildContext context, InstallTarget target) {
  final l10n = context.l10n;
  final (title, steps, button, url) = switch (target) {
    InstallTarget.iphone => (
      l10n.installIphoneTitle,
      l10n.installIphoneSteps,
      l10n.installOpenGuide,
      iphoneGuideUrl,
    ),
    InstallTarget.android => (
      l10n.installAndroidTitle,
      l10n.installAndroidSteps,
      l10n.installOpenRelease,
      latestReleaseUrl,
    ),
  };
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            SelectableText(steps),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => openLink(context, url),
              icon: const Icon(Icons.open_in_new),
              label: Text(button),
            ),
          ],
        ),
      ),
    ),
  );
}
