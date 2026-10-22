import 'package:flutter/material.dart';

import '../l10n/language.dart';

/// Who TabCam is for, and whose tabs go in it: musicians practicing with
/// their own tabs, who must have the right to what they add (Home, its
/// empty list, and Capture).
class OwnTabsNote extends StatelessWidget {
  const OwnTabsNote({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const Key('own-tabs-note'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.ownTabsNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
