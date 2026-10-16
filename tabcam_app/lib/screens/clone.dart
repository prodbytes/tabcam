import 'package:flutter/material.dart';

import '../library/capture_event.dart';
import '../library/library.dart';
import '../l10n/language.dart';

/// Clones [event] ([Library.clone]) and says so; null if it failed (also
/// said). The copy is a new event of the user's own, to change or share
/// apart from the original.
Future<CaptureEvent?> cloneEvent(
  BuildContext context,
  Library library,
  CaptureEvent event,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    final copy = await library.clone(event);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.eventClonedAs(copy.title))));
    return copy;
  } on Object catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.eventCouldntClone('$e'))),
    );
    return null;
  }
}
