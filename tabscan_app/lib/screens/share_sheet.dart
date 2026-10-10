import 'package:flutter/material.dart';

import '../export/exporter.dart';
import '../library/library.dart';
import '../library/capture_event.dart';

/// Asks what to share the event as, then opens the system's share sheet.
/// Text tab is offered once the tab has been read.
Future<void> showShareSheet(
  BuildContext context,
  Library library,
  CaptureEvent event,
) async {
  final format = await showModalBottomSheet<ShareFormat>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('PDF'),
            subtitle: const Text('Every photo and scan, plus the text tab'),
            onTap: () => Navigator.pop(context, ShareFormat.pdf),
          ),
          ListTile(
            leading: const Icon(Icons.notes),
            title: const Text('Text tab'),
            subtitle: Text(
              event.tabText == null
                  ? 'Read the tab first (Read tab on the event)'
                  : 'Plain text, pastes into any chat or editor',
            ),
            enabled: event.tabText != null,
            onTap: () => Navigator.pop(context, ShareFormat.text),
          ),
          ListTile(
            leading: const Icon(Icons.perm_media_outlined),
            title: const Text('Files'),
            subtitle: const Text('Each page as a picture, videos included'),
            onTap: () => Navigator.pop(context, ShareFormat.files),
          ),
        ],
      ),
    ),
  );
  if (format == null) return;
  try {
    await Exporter.share(
      event,
      format,
      (page) => library.filtered(event, page),
    );
  } on Object catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Couldn\'t share: $e')));
    }
  }
}
