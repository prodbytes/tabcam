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
    builder: (_) => RenameDialog(name: event.title),
  );
  if (name == null || name.isEmpty) return;
  await library.update(event.copyWith(title: name, artist: ''));
}

/// Asks for a page's name (a file, a photo, a link), prefilled with what it
/// shows now ([shown]); saves it on the page. Emptied, the page goes back
/// to its default name.
Future<void> renamePage(
  BuildContext context,
  Library library,
  CaptureEvent event,
  EventPage page,
  String shown,
) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => RenameDialog(name: page.title ?? shown),
  );
  if (name == null) return;
  await library.renamePage(event.id, page.id, name);
}

/// The rename dialog: one Name field, prefilled with [name], its text
/// selected so typing replaces it.
class RenameDialog extends StatefulWidget {
  const RenameDialog({super.key, required this.name});

  final String name;

  @override
  State<RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<RenameDialog> {
  late final _name = TextEditingController(
    text: widget.name,
  )..selection = TextSelection(baseOffset: 0, extentOffset: widget.name.length);

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
