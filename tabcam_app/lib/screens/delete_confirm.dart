import 'dart:convert';

import 'package:flutter/material.dart';

import '../l10n/language.dart';
import '../library/library.dart';
import '../library/meta_names.dart';

/// The kinds of delete that ask first, each skipped on its own once the
/// user ticks **Don't ask again** ([DeleteConfirms]). Deleting the account
/// isn't one: it always asks.
enum DeleteKind {
  /// A capture of the user's own, from its card on Home.
  capture('capture'),

  /// A capture shared with the user, removed from their library.
  sharedCapture('shared-capture'),

  /// One of a capture's files, from its list.
  file('file'),

  /// One of the files a reader added to a capture shared with them.
  contribution('contribution');

  const DeleteKind(this.key);

  /// Its name in the meta file.
  final String key;
}

/// Which kinds of delete ([DeleteKind]) ask first, kept on this device (the
/// library's `deleteconfirms` meta file): all of them, until the user
/// ticks **Don't ask again** on one; Profile's **Ask before deleting**
/// turns them all back on.
class DeleteConfirms extends ChangeNotifier {
  DeleteConfirms._(this.library);

  static final Expando<DeleteConfirms> _of = Expando();

  /// The confirms of [library]'s app.
  static DeleteConfirms of(Library library) =>
      _of[library] ??= DeleteConfirms._(library);

  /// The meta file they're kept in. Letters and digits only: on the apps
  /// it names a file, and the store refuses anything else (`checkId`).
  static const String metaName = MetaNames.deleteConfirms;

  final Library library;
  final Set<DeleteKind> _skipped = {};
  Future<void>? _loading;

  /// Reads the device's setting (once).
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final json = await library.readMeta(metaName);
      if (json == null) return;
      final skip = (jsonDecode(json) as Map)['skip'];
      if (skip is! List) return;
      final before = _skipped.length;
      _skipped.addAll(DeleteKind.values.where((k) => skip.contains(k.key)));
      if (_skipped.length != before) notifyListeners();
    } on Object catch (e) {
      debugPrint('TabCam: delete confirms unreadable: $e');
    }
  }

  /// Whether deleting a [kind] asks first.
  bool asks(DeleteKind kind) => !_skipped.contains(kind);

  /// Whether every kind of delete asks first.
  bool get asksAll => _skipped.isEmpty;

  /// Deleting a [kind] no longer asks.
  Future<void> skip(DeleteKind kind) async {
    await load();
    if (!_skipped.add(kind)) return;
    notifyListeners();
    await _save();
  }

  /// Every kind of delete asks first again.
  Future<void> askAll() async {
    await load();
    if (_skipped.isEmpty) return;
    _skipped.clear();
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      await library.writeMeta(
        metaName,
        jsonEncode({
          'skip': [
            for (final k in DeleteKind.values)
              if (!asks(k)) k.key,
          ],
        }),
      );
    } on Object catch (e) {
      debugPrint('TabCam: delete confirms not saved: $e');
    }
  }
}

/// Whether to go ahead with deleting a [kind]: asks "[title]" (with
/// [body] under it, if any), [cancel] or [confirm], and a **Don't ask
/// again** checkbox; ticked and confirmed, that kind no longer asks on
/// this device ([DeleteConfirms]). One that no longer asks is true at once.
Future<bool> confirmDelete(
  BuildContext context, {
  required Library library,
  required DeleteKind kind,
  required String title,
  String? body,
  required String confirm,
  required String cancel,
}) async {
  final confirms = DeleteConfirms.of(library);
  await confirms.load();
  if (!confirms.asks(kind)) return true;
  if (!context.mounted) return false;
  final answer = await showDialog<_Answer>(
    context: context,
    builder: (context) => _DeleteDialog(
      title: title,
      body: body,
      confirm: confirm,
      cancel: cancel,
    ),
  );
  if (answer == null) return false;
  if (answer == _Answer.deleteAndStopAsking) await confirms.skip(kind);
  return true;
}

enum _Answer { delete, deleteAndStopAsking }

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({
    required this.title,
    required this.body,
    required this.confirm,
    required this.cancel,
  });

  final String title;
  final String? body;
  final String confirm;
  final String cancel;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  bool _stopAsking = false;

  @override
  Widget build(BuildContext context) {
    final body = widget.body;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (body != null) ...[Text(body), const SizedBox(height: 8)],
          CheckboxListTile(
            key: const Key('dont-ask-again'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            value: _stopAsking,
            onChanged: (on) => setState(() => _stopAsking = on ?? false),
            title: Text(context.l10n.deleteDontAskAgain),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _stopAsking ? _Answer.deleteAndStopAsking : _Answer.delete,
          ),
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}

/// Profile's **Ask before deleting**: on, every delete of a capture or a
/// file asks first; off once some kind no longer asks, and turning it on
/// brings every confirm back. Only on: it's off only by a confirm's
/// **Don't ask again**, so a stray tap never stops every confirm. Kept on
/// this device.
class AskBeforeDeleting extends StatefulWidget {
  const AskBeforeDeleting({super.key, required this.library});

  final Library library;

  @override
  State<AskBeforeDeleting> createState() => _AskBeforeDeletingState();
}

class _AskBeforeDeletingState extends State<AskBeforeDeleting> {
  DeleteConfirms get _confirms => DeleteConfirms.of(widget.library);

  @override
  void initState() {
    super.initState();
    _confirms.load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: _confirms,
      builder: (context, _) {
        final on = _confirms.asksAll;
        return SwitchListTile(
          key: const Key('ask-before-deleting'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.deleteAskTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(on ? l10n.deleteAskOn : l10n.deleteAskOff),
          value: on,
          onChanged: on ? null : (_) => _confirms.askAll(),
        );
      },
    );
  }
}
