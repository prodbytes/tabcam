import 'package:flutter/material.dart';

import '../library/capture_event.dart';

/// The text tab as a page of an event whose images are hidden
/// ([CaptureEvent.hideImages]): monospaced and unwrapped (a long line
/// scales the text down to fit), with Open for the editor; or, before the
/// tab is read, what to do.
class TextPage extends StatelessWidget {
  const TextPage({super.key, required this.event, required this.onOpen});

  final CaptureEvent event;

  /// Opens the text tab editor.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = event.tabText;
    if (text == null || text.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notes, size: 48),
            const SizedBox(height: 12),
            Text('No text tab yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              event.readOnly
                  ? 'The images are hidden, and the tab hasn\'t been read.'
                  : 'The images are hidden. They\'re still read: the text appears here.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.notes),
            title: const Text('Text tab'),
            trailing: FilledButton.tonal(
              onPressed: onOpen,
              child: const Text('Open'),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              // Scaled down to fit, not scrolled sideways: a sideways
              // swipe goes to the next page.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: SelectableText(
                  text,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontFamilyFallback: ['Menlo', 'Courier New', 'Courier'],
                    fontSize: 13,
                    height: 1.25,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
