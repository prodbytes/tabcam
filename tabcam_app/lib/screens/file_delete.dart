import 'package:flutter/material.dart';

import '../l10n/language.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import 'file_screen.dart';

/// Whether the user may delete [page] from [event]: one of the capture's
/// own files on a capture of theirs or one shared with them to edit; on
/// one shared with them to read, only what they added themselves (their
/// contribution's files, links and Cam's takes), never the owner's.
bool mayDeleteFile(CaptureEvent event, EventPage page) {
  if (event.pages.any((p) => p.id == page.id)) return !event.readOnly;
  return event.myContribution?.pages.any((p) => p.id == page.id) ?? false;
}

/// Deletes [page] from [event] once the user confirms, wherever it's
/// offered (the capture's list, the play-along sidebar): one of the
/// capture's own files ([Library.deletePage]; the last one stays, and
/// the user is told so), or one of the user's own contribution's
/// ([Library.deleteContributionPage]). Nothing for a file the user may
/// not delete ([mayDeleteFile]).
///
/// [letGo] runs once the user confirms, before the file goes (a player
/// lets go of it). [run] runs the delete (the screen's progress bar and
/// error message); without it, a failure shows in a snack bar.
Future<void> deleteFile(
  BuildContext context,
  Library library,
  CaptureEvent event,
  EventPage page, {
  Future<void> Function()? letGo,
  Future<void> Function(String failure, Future<void> Function() task)? run,
}) async {
  if (!mayDeleteFile(event, page)) return;
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final own = event.pages.any((p) => p.id == page.id);
  if (own && event.pages.length == 1) {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.eventKeepOnePage)));
    return;
  }
  final sure = await _confirm(context, event, page, contribution: !own);
  if (!sure || !context.mounted) return;
  await letGo?.call();
  Future<void> task() async {
    // As it is now: a read may have changed it meanwhile.
    final now = library.byId(event.id);
    if (now == null) return;
    if (own) {
      await library.deletePage(now, page);
    } else {
      await library.deleteContributionPage(now, page);
    }
  }

  if (run != null) return run(l10n.eventCouldntDelete, task);
  try {
    await task();
  } on Object catch (e, stack) {
    debugPrint('TabCam: ${l10n.eventCouldntDelete}: $e\n$stack');
    messenger?.showSnackBar(
      SnackBar(content: Text('${l10n.eventCouldntDelete}: $e')),
    );
  }
}

/// Asks before [page] is deleted: one of the capture's own files, or of
/// the user's [contribution]. The one place deleting a file asks.
Future<bool> _confirm(
  BuildContext context,
  CaptureEvent event,
  EventPage page, {
  required bool contribution,
}) async {
  final l10n = context.l10n;
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.homeLibraryDeleteTitle(fileLabel(l10n, event, page))),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.eventCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.eventDelete),
        ),
      ],
    ),
  );
  return sure == true;
}
