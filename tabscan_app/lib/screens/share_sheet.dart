import 'dart:async';

import 'package:flutter/material.dart';

import '../cloud/cloud_sync.dart';
import '../export/exporter.dart';
import '../library/library.dart';
import '../library/capture_event.dart';

/// Asks what to share the event as, then opens the system's share sheet:
/// its link (the default, with cloud sync), a PDF, the text, or a zip of
/// its files. Text is offered once the tab has been read or there are
/// links.
Future<void> showShareSheet(
  BuildContext context,
  Library library,
  CaptureEvent event, {
  CloudSync? sync,
}) async {
  final hasText = Exporter.shareText(event) != null;
  // With the images hidden, a PDF or zip needs something else to hold.
  final hidden = event.hideImages;
  final hasVideos = event.pages.any((p) => p.isVideo);
  final format = await showModalBottomSheet<ShareFormat>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Link'),
            subtitle: Text(
              sync == null
                  ? 'Needs sign-in and cloud sync'
                  : 'Opens this capture in TabScan, for you and the people '
                        'it\'s shared with',
            ),
            enabled: sync != null,
            // The default: first, and marked.
            selected: sync != null,
            autofocus: sync != null,
            onTap: () => Navigator.pop(context, ShareFormat.link),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('PDF'),
            subtitle: Text(
              hidden
                  ? 'The text tab and links (the photos and scans are hidden)'
                  : 'Every photo and scan in one PDF, plus the text tab and '
                        'links',
            ),
            enabled: !hidden || hasText,
            onTap: () => Navigator.pop(context, ShareFormat.pdf),
          ),
          ListTile(
            leading: const Icon(Icons.notes),
            title: const Text('Text'),
            subtitle: Text(
              hasText
                  ? 'The text tab and links, as plain text'
                  : 'Read the tab first (Read tab on the event)',
            ),
            enabled: hasText,
            onTap: () => Navigator.pop(context, ShareFormat.text),
          ),
          ListTile(
            leading: const Icon(Icons.folder_zip_outlined),
            title: const Text('Files'),
            subtitle: Text(
              hidden
                  ? 'A zip of the videos, the text tab and links (the photos '
                        'and scans are hidden)'
                  : 'A zip of everything: photos, scans, videos, the text tab '
                        'and links',
            ),
            enabled: !hidden || hasText || hasVideos,
            onTap: () => Navigator.pop(context, ShareFormat.files),
          ),
        ],
      ),
    ),
  );
  if (format == null) return;
  // A link opens the capture from the cloud: make sure it gets there.
  if (format == ShareFormat.link) unawaited(sync?.syncNow());
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
