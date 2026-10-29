import 'package:flutter/material.dart';

import '../library/library.dart';
import '../library/capture_event.dart';
import '../library/search.dart';
import '../l10n/language.dart';

/// Asks for an event's name, and saves it as the title, whatever the user
/// typed. The artist is cleared, so the name shows exactly as typed. An
/// empty name keeps the title it had. On the user's own events, it also
/// asks for its study (optional, the user's studies suggested); emptied,
/// the event is in none.
Future<void> renameEvent(
  BuildContext context,
  Library library,
  CaptureEvent event,
) async {
  final own = !event.isShared;
  final names = await showDialog<RenameResult>(
    context: context,
    builder: (_) => RenameDialog(
      name: event.title,
      study: own ? event.study : null,
      studies: library.studies,
    ),
  );
  if (names == null) return;
  final now = library.byId(event.id) ?? event;
  final name = names.name.isEmpty ? null : names.name;
  final study = names.study;
  if (name == null && (study == null || study == now.study)) return;
  await library.update(
    now.copyWith(title: name, artist: name == null ? null : '', study: study),
  );
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
  final names = await showDialog<RenameResult>(
    context: context,
    builder: (_) => RenameDialog(name: page.title ?? shown),
  );
  if (names == null) return;
  await library.renamePage(event.id, page.id, names.name);
}

/// What the rename dialog gives back, trimmed: the name, and the study
/// when it asked for one.
typedef RenameResult = ({String name, String? study});

/// The rename dialog: a Name field, prefilled with [name], its text
/// selected so typing replaces it; with a [study], below it a Study field,
/// suggesting the [studies] that match what's typed.
class RenameDialog extends StatefulWidget {
  const RenameDialog({
    super.key,
    required this.name,
    this.study,
    this.studies = const [],
  });

  final String name;
  final String? study;
  final List<String> studies;

  @override
  State<RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<RenameDialog> {
  late final _name = TextEditingController(
    text: widget.name,
  )..selection = TextSelection(baseOffset: 0, extentOffset: widget.name.length);

  late final _study = TextEditingController(text: widget.study);
  final _studyFocus = FocusNode();

  @override
  void dispose() {
    _name.dispose();
    _study.dispose();
    _studyFocus.dispose();
    super.dispose();
  }

  void _done() => Navigator.pop(context, (
    name: _name.text.trim(),
    study: widget.study == null ? null : _study.text.trim(),
  ));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.eventRename),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.eventName),
            onSubmitted: (_) => _done(),
          ),
          if (widget.study != null) ...[
            const SizedBox(height: 16),
            RawAutocomplete<String>(
              textEditingController: _study,
              focusNode: _studyFocus,
              optionsBuilder: (value) {
                final typed = fold(value.text.trim());
                return [
                  for (final s in widget.studies)
                    if (s != value.text && fold(s).contains(typed)) s,
                ];
              },
              fieldViewBuilder: (context, controller, focus, _) => TextField(
                key: const Key('event-study'),
                controller: controller,
                focusNode: focus,
                decoration: InputDecoration(
                  labelText: l10n.eventStudy,
                  helperText: l10n.eventStudyHelp,
                  prefixIcon: const Icon(Icons.folder_outlined),
                ),
                onSubmitted: (_) => _done(),
              ),
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: AlignmentDirectional.topStart,
                child: Material(
                  elevation: 4,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 200,
                      maxWidth: 280,
                    ),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: [
                        for (final option in options)
                          ListTile(
                            dense: true,
                            title: Text(option),
                            onTap: () => onSelected(option),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
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
