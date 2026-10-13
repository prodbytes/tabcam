import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cloud/cloud_sync.dart';
import '../export/capture_link.dart';
import '../l10n/language.dart';
import '../library/capture_event.dart';

/// **Share**: copies the capture's link (`…/app/?c=<id>`) to the
/// clipboard, nothing else, and says so. The capture is synced right away,
/// so the link opens it for whoever it's shared with.
Future<void> copyCaptureLink(
  BuildContext context,
  CaptureEvent event, {
  CloudSync? sync,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final copied = context.l10n.eventLinkCopied;
  unawaited(sync?.syncNow());
  await Clipboard.setData(ClipboardData(text: '${CaptureLink.of(event)}'));
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(copied)));
}
