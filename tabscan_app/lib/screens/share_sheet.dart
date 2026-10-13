import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cloud/cloud_sync.dart';
import '../export/capture_link.dart';
import '../l10n/language.dart';
import '../library/capture_event.dart';
import 'sign_in_gate.dart';

/// **Share**: copies the capture's link (`…/app/?c=<id>`) to the
/// clipboard, nothing else, and says so. Signed in (or in a build without
/// sign-in) it copies at once, on the tap itself: nothing comes before the
/// copy (a browser lets a page write the clipboard only right after a
/// tap). Signed out, it asks to sign in first. Then the capture is synced,
/// so the link opens it for whoever it's shared with.
Future<void> shareCapture(
  BuildContext context,
  CaptureEvent event, {
  CloudSync? sync,
}) async {
  final auth = sync?.auth;
  if (auth == null || !auth.available || auth.user != null) {
    return copyCaptureLink(context, event, sync: sync);
  }
  if (await requireSignIn(context, auth, Gated.share) && context.mounted) {
    await copyCaptureLink(context, event, sync: sync);
  }
}

/// Copies the link (the copy first, before anything else), says so, and
/// syncs.
Future<void> copyCaptureLink(
  BuildContext context,
  CaptureEvent event, {
  CloudSync? sync,
}) async {
  final copying = Clipboard.setData(
    ClipboardData(text: CaptureLink.of(event).toString()),
  );
  final messenger = ScaffoldMessenger.maybeOf(context);
  final copied = context.l10n.eventLinkCopied;
  await copying;
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(copied)));
  unawaited(sync?.syncNow());
}
