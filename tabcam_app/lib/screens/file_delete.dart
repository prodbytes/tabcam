import 'package:flutter/material.dart';

import '../l10n/language.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import 'delete_confirm.dart';
import 'file_screen.dart';
import 'messages.dart';

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
/// It asks first ([confirmDelete]: [DeleteKind.file] for one of the
/// capture's, [DeleteKind.contribution] for one of the user's own), unless
/// the user ticked **Don't ask again** on that kind of delete.
///
/// [letGo] runs once the user confirms, before the file goes (a player
/// lets go of it). [run] runs the delete (the screen's progress bar and
/// error message); without it, a failure shows as a message.
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
  final messenger = Messenger.maybeOf(context);
  final own = event.pages.any((p) => p.id == page.id);
  if (own && event.pages.length == 1) {
    messenger?.show(l10n.eventKeepOnePage);
    return;
  }
  final sure = await confirmDelete(
    context,
    library: library,
    kind: own ? DeleteKind.file : DeleteKind.contribution,
    title: l10n.homeLibraryDeleteTitle(fileLabel(l10n, event, page)),
    confirm: l10n.eventDelete,
    cancel: l10n.eventCancel,
  );
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
    messenger?.show('${l10n.eventCouldntDelete}: $e');
  }
}
