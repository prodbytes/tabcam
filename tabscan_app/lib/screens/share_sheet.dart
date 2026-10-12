import 'dart:async';

import 'package:flutter/material.dart';

import '../cloud/cloud_sync.dart';
import '../export/exporter.dart';
import '../l10n/language.dart';
import '../library/library.dart';
import '../library/capture_event.dart';
import 'people_sheet.dart';

/// Asks what to share the event as, then opens the system's share sheet:
/// its link (the default, with cloud sync), a PDF, the text, or a zip of
/// its files. Text is offered once the tab has been read or there are
/// links. Share with people (the user's own events, where sharing is set
/// up) opens the [PeopleSheet] instead.
Future<void> showShareSheet(
  BuildContext context,
  Library library,
  CaptureEvent event, {
  CloudSync? sync,
}) async {
  final hasText = Exporter.shareText(event) != null;
  // With the images hidden, a PDF or zip needs something else to hold.
  final hidden = event.hideImages;
  final hasFiles = event.visiblePages.any((p) => p.hasFile);
  final people = sync != null && sync.canShare && !event.isShared;
  final choice = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final l10n = context.l10n;
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(l10n.accountShareLink),
              subtitle: Text(
                sync == null
                    ? l10n.accountShareLinkNeedsSync
                    : l10n.accountShareLinkDetail,
              ),
              enabled: sync != null,
              // The default: first, and marked.
              selected: sync != null,
              autofocus: sync != null,
              onTap: () => Navigator.pop(context, ShareFormat.link),
            ),
            if (people)
              ListTile(
                leading: const Icon(Icons.group_add_outlined),
                title: Text(l10n.eventShareWithPeople),
                subtitle: Text(l10n.eventShareWithPeopleDetail),
                onTap: () => Navigator.pop(context, _people),
              ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(l10n.accountSharePdf),
              subtitle: Text(
                hidden
                    ? l10n.accountSharePdfHidden
                    : l10n.accountSharePdfDetail,
              ),
              enabled: !hidden || hasText,
              onTap: () => Navigator.pop(context, ShareFormat.pdf),
            ),
            ListTile(
              leading: const Icon(Icons.notes),
              title: Text(l10n.accountShareText),
              subtitle: Text(
                hasText
                    ? l10n.accountShareTextDetail
                    : l10n.accountShareTextNone,
              ),
              enabled: hasText,
              onTap: () => Navigator.pop(context, ShareFormat.text),
            ),
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: Text(l10n.accountShareFiles),
              subtitle: Text(
                hidden
                    ? l10n.accountShareFilesHidden
                    : l10n.accountShareFilesDetail,
              ),
              enabled: !hidden || hasText || hasFiles,
              onTap: () => Navigator.pop(context, ShareFormat.files),
            ),
          ],
        ),
      );
    },
  );
  if (choice == _people && context.mounted) {
    await showPeopleSheet(context, sync!, event);
    return;
  }
  if (choice is! ShareFormat) return;
  final format = choice;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.accountShareFailed('$e'))),
      );
    }
  }
}

/// The share sheet's choice of Share with people.
const Object _people = #people;
