import 'package:flutter/material.dart';

import '../library/library.dart';
import '../library/capture_event.dart';
import '../l10n/language.dart';

/// Asks for an event's song and artist, and saves them. An empty song keeps
/// the title it had; an empty artist clears it.
Future<void> renameEvent(
  BuildContext context,
  Library library,
  CaptureEvent event,
) async {
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (_) => RenameDialog(event: event),
  );
  if (result == null) return;
  final (title, artist) = result;
  await library.update(
    event.copyWith(title: title.isEmpty ? event.title : title, artist: artist),
  );
}

/// The rename dialog: Song and Artist fields, prefilled, with the song's
/// text selected so typing replaces it.
class RenameDialog extends StatefulWidget {
  const RenameDialog({super.key, required this.event});

  final CaptureEvent event;

  @override
  State<RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<RenameDialog> {
  late final _title = TextEditingController(text: widget.event.title)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.event.title.length,
    );
  late final _artist = TextEditingController(text: widget.event.artist);

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    super.dispose();
  }

  void _done() =>
      Navigator.pop(context, (_title.text.trim(), _artist.text.trim()));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.eventRename),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.eventSong),
            textInputAction: TextInputAction.next,
          ),
          TextField(
            controller: _artist,
            decoration: InputDecoration(labelText: l10n.eventArtist),
            onSubmitted: (_) => _done(),
          ),
        ],
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
