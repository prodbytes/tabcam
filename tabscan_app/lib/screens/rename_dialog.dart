import 'package:flutter/material.dart';

import '../library/library.dart';
import '../library/capture_event.dart';
import '../l10n/language.dart';

/// Asks for an event's name, and saves it as the title, whatever the user
/// typed. The artist is cleared, so the name shows exactly as typed. An
/// empty name keeps the title it had.
Future<void> renameEvent(
  BuildContext context,
  Library library,
  CaptureEvent event,
) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => RenameDialog(event: event),
  );
  if (name == null || name.isEmpty) return;
  await library.update(event.copyWith(title: name, artist: ''));
}

/// The rename dialog: one Name field, prefilled with the title, its text
/// selected so typing replaces it.
class RenameDialog extends StatefulWidget {
  const RenameDialog({super.key, required this.event});

  final CaptureEvent event;

  @override
  State<RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<RenameDialog> {
  late final _name = TextEditingController(text: widget.event.title)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.event.title.length,
    );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() => Navigator.pop(context, _name.text.trim());

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.eventRename),
      content: TextField(
        controller: _name,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.eventName),
        onSubmitted: (_) => _done(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.eventCancel),
        ),
        FilledButton(onPressed: _done, child: Text(l10n.eventSave)),
      ],
    );
  }
}
