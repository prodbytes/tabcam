import 'package:flutter/material.dart';

import '../library/library.dart';
import '../library/scan.dart';

/// Asks for a scan's song and artist, and saves them. An empty song keeps
/// the title it had; an empty artist clears it.
Future<void> renameScan(
  BuildContext context,
  Library library,
  Scan scan,
) async {
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (_) => RenameDialog(scan: scan),
  );
  if (result == null) return;
  final (title, artist) = result;
  await library.update(
    scan.copyWith(title: title.isEmpty ? scan.title : title, artist: artist),
  );
}

/// The rename dialog: Song and Artist fields, prefilled, with the song's
/// text selected so typing replaces it.
class RenameDialog extends StatefulWidget {
  const RenameDialog({super.key, required this.scan});

  final Scan scan;

  @override
  State<RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<RenameDialog> {
  late final _title = TextEditingController(text: widget.scan.title)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.scan.title.length,
    );
  late final _artist = TextEditingController(text: widget.scan.artist);

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
    return AlertDialog(
      title: const Text('Rename'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Song'),
            textInputAction: TextInputAction.next,
          ),
          TextField(
            controller: _artist,
            decoration: const InputDecoration(labelText: 'Artist'),
            onSubmitted: (_) => _done(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _done, child: const Text('Save')),
      ],
    );
  }
}
