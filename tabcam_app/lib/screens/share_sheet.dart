import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cloud/cloud_sync.dart';
import '../export/capture_link.dart';
import '../l10n/language.dart';
import '../cloud/public_capture.dart';
import '../library/capture_event.dart';
import 'sign_in_gate.dart';
import 'messages.dart';

/// **Share**: copies the capture's link (`…/app/?c=<id>&k=<key>`; a
/// [file]'s with `f=<file id>`, its [edit] view's with `e=1` too) to the
/// clipboard, the URL alone, and says so. Signed in (or in a build without
/// sign-in) it copies at once, on the tap itself: nothing comes before the
/// copy (a browser lets a page write the clipboard only right after a
/// tap). Signed out, it asks to sign in first. Then the capture is synced,
/// so the link opens it for whoever may open it ([PublicCaptures]).
///
/// For the capture's owner, in a build with sharing, a sheet then shows
/// who may open it by the link, to change: Public, Unlisted or Private,
/// as on YouTube ([CaptureVisibility]). The link stays the same whichever
/// it is.
Future<void> shareCapture(
  BuildContext context,
  CaptureEvent event, {
  CloudSync? sync,
  EventPage? file,
  bool edit = false,
}) async {
  final auth = sync?.auth;
  if (auth != null && auth.available && auth.user == null) {
    if (!await requireSignIn(context, auth, Gated.share) || !context.mounted) {
      return;
    }
  }
  final keyed = withLinkKey(event, sync);
  final copying = copyCaptureLink(
    context,
    event,
    sync: sync,
    file: file,
    edit: edit,
    keyed: keyed,
  );
  if (sync != null && choosesVisibility(event, sync) && context.mounted) {
    await showVisibilitySheet(context, keyed, sync);
  }
  await copying;
}

/// Whether the user chooses who may open [event] by its link: it's theirs
/// (not shared with them, nor opened by its link), signed in, with a
/// share API.
bool choosesVisibility(CaptureEvent event, CloudSync sync) =>
    sync.canShare && !event.isShared && !event.readOnly;

/// [event] with the link key its link is copied with: its own, or, the
/// first time its owner copies it in a build with sharing (or with a key
/// from before short links), a new one.
CaptureEvent withLinkKey(CaptureEvent event, CloudSync? sync) {
  final key = event.linkKey;
  return (key == null || !isShortLinkKey(key)) &&
          !event.isShared &&
          sync?.shares != null
      ? event.copyWith(linkKey: newLinkKey())
      : event;
}

/// Copies the link (the copy first, before anything else), says so, and
/// syncs. The owner's first copy, in a build with sharing, makes the
/// link's key: it's saved on the capture (so every device of theirs copies
/// the same link) and recorded by the share API, so anyone holding the
/// link can open it, read only. A key from before short links gets a short
/// one the same way (links with the old one keep working). A clone's files
/// that are still the original's become its own first ([Library.ownFiles]).
Future<void> copyCaptureLink(
  BuildContext context,
  CaptureEvent event, {
  CloudSync? sync,
  EventPage? file,
  bool edit = false,
  CaptureEvent? keyed,
}) async {
  final key = event.linkKey;
  keyed ??= withLinkKey(event, sync);
  final copying = Clipboard.setData(
    ClipboardData(
      text: CaptureLink.of(keyed, file: file, edit: edit).toString(),
    ),
  );
  final messenger = Messenger.maybeOf(context);
  final copied = context.l10n.eventLinkCopied;
  await copying;
  messenger
    ?..hide()
    ..show(copied);
  if (sync == null) return;
  // The link's holders read only its own folder: a clone's files still
  // the original's (copy on write) are copied into it first.
  if (!event.isShared && event.sharesFiles) {
    await sync.library.ownFiles(event);
  }
  if (keyed.linkKey != key) {
    final made = keyed.linkKey;
    await sync.library.patch(
      event.id,
      (now) => now.linkKey == key ? now.copyWith(linkKey: made) : now,
    );
  }
  if (!event.isShared) await sync.publishLink(keyed);
  unawaited(sync.syncNow());
}

/// Who may open the capture by its link, the owner's to change
/// ([CaptureVisibility]): Public, Unlisted and Private, each with what it
/// means, the capture's chosen. A choice applies at once
/// ([setCaptureVisibility]); Done (or anywhere outside) closes it.
Future<void> showVisibilitySheet(
  BuildContext context,
  CaptureEvent keyed,
  CloudSync sync,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  // As tall as it needs (it scrolls on a short screen), not 9/16 of it:
  // the three choices and Done all show.
  isScrollControlled: true,
  builder: (_) => _VisibilitySheet(keyed: keyed, sync: sync),
);

/// Sets who may open [event] by its link: saved on the capture (synced to
/// the owner's devices) and recorded by the share API, which is what
/// counts. Its link key stays (made now, if it has none), so the same
/// link works again once it's no longer private. The link's holders read
/// only its own folder: a clone's files still the original's (copy on
/// write) become its own first.
Future<void> setCaptureVisibility(
  CloudSync sync,
  CaptureEvent event,
  CaptureVisibility visibility,
) async {
  final library = sync.library;
  final now = library.byId(event.id) ?? event;
  if (now.isShared || now.readOnly) return;
  if (visibility != CaptureVisibility.private && now.sharesFiles) {
    await library.ownFiles(now);
  }
  final key = now.linkKey ?? event.linkKey ?? newLinkKey();
  final set = await library.patch(
    event.id,
    (now) => now.copyWith(visibility: visibility, linkKey: now.linkKey ?? key),
  );
  if (set != null) await sync.publishLink(set);
  unawaited(sync.syncNow());
}

class _VisibilitySheet extends StatefulWidget {
  const _VisibilitySheet({required this.keyed, required this.sync});

  /// The capture, with the key its link was copied with.
  final CaptureEvent keyed;
  final CloudSync sync;

  @override
  State<_VisibilitySheet> createState() => _VisibilitySheetState();
}

class _VisibilitySheetState extends State<_VisibilitySheet> {
  late CaptureVisibility _chosen = () {
    final now = widget.sync.library.byId(widget.keyed.id);
    return (now?.visibility != null ? now! : widget.keyed).shownVisibility;
  }();

  void _choose(CaptureVisibility? visibility) {
    if (visibility == null || visibility == _chosen) return;
    setState(() => _chosen = visibility);
    unawaited(setCaptureVisibility(widget.sync, widget.keyed, visibility));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          key: const Key('share-visibility'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.shareWhoCanOpen, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            RadioGroup<CaptureVisibility>(
              groupValue: _chosen,
              onChanged: _choose,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final v in CaptureVisibility.values)
                    RadioListTile<CaptureVisibility>(
                      key: Key('share-${v.name}'),
                      value: v,
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(switch (v) {
                        CaptureVisibility.public => Icons.public,
                        CaptureVisibility.unlisted => Icons.link,
                        CaptureVisibility.private => Icons.lock_outline,
                      }),
                      title: Text(switch (v) {
                        CaptureVisibility.public => l10n.sharePublic,
                        CaptureVisibility.unlisted => l10n.shareUnlisted,
                        CaptureVisibility.private => l10n.sharePrivate,
                      }),
                      subtitle: Text(switch (v) {
                        CaptureVisibility.public => l10n.sharePublicDetail,
                        CaptureVisibility.unlisted => l10n.shareUnlistedDetail,
                        CaptureVisibility.private => l10n.sharePrivateDetail,
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.shareDone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
