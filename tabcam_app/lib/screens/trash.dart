import 'dart:async';

import 'package:flutter/material.dart';

import '../cloud/cloud_sync.dart';
import '../l10n/language.dart';
import '../library/capture_event.dart';
import '../library/file_label.dart';
import '../library/library.dart';
import 'messages.dart';

/// What's in the trash, as a line ("2 captures, 3 files, kept until you
/// purge them."), or that there's nothing.
String trashSummary(BuildContext context, Library library) {
  final l10n = context.l10n;
  final captures = library.trashed.length;
  final files = library.withDeletedPages.fold(
    0,
    (n, e) => n + e.deletedPages.length,
  );
  if (captures == 0 && files == 0) return l10n.trashEmpty;
  return l10n.trashSummary(
    [
      if (captures > 0) l10n.trashCaptures(captures),
      if (files > 0) l10n.trashFiles(files),
    ].join(', '),
  );
}

/// Profile's **Deleted**: what the user deleted (captures, and files of
/// their captures) is kept, hidden, until they purge it here
/// ([Library.purge]): **Show** lists it to restore ([TrashScreen]),
/// **Purge** deletes it for good, after asking.
class DeletedSection extends StatelessWidget {
  const DeletedSection({super.key, required this.library, this.sync});

  final Library library;

  /// Cloud sync, to send a purge at once (null: none).
  final CloudSync? sync;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final any = library.hasTrash;
        return Column(
          key: const Key('deleted-section'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.trashTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(trashSummary(context, library)),
            if (any) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    key: const Key('trash-show'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            TrashScreen(library: library, sync: sync),
                      ),
                    ),
                    child: Text(l10n.trashShow),
                  ),
                  FilledButton.tonal(
                    key: const Key('trash-purge'),
                    onPressed: () => purgeTrash(context, library, sync: sync),
                    child: Text(l10n.trashPurge),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// **Purge**: asks (always: it can't be undone), then deletes everything
/// in the trash for good ([Library.purge]) and syncs, so it goes from the
/// cloud and the user's other devices too. True once purged.
Future<bool> purgeTrash(
  BuildContext context,
  Library library, {
  CloudSync? sync,
}) async {
  final l10n = context.l10n;
  final messenger = Messenger.maybeOf(context);
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.trashPurgeTitle),
      content: Text(l10n.trashPurgeBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.eventCancel),
        ),
        FilledButton(
          key: const Key('purge-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.trashPurge),
        ),
      ],
    ),
  );
  if (sure != true) return false;
  try {
    await library.purge();
  } on Object catch (e, stack) {
    debugPrint('TabCam: purge: $e\n$stack');
    messenger?.show(l10n.trashCouldntPurge('$e'));
    return false;
  }
  messenger?.show(l10n.trashPurged);
  if (sync != null) unawaited(sync.syncNow());
  return true;
}

/// The trash: the user's deleted captures (the latest first), then the
/// files deleted from each capture they still have, each with
/// **Restore**; **Purge** in the app bar deletes it all for good.
class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key, required this.library, this.sync});

  final Library library;
  final CloudSync? sync;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final trashed = library.trashed;
        final withFiles = library.withDeletedPages;
        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.trashTitle),
            actions: [
              if (library.hasTrash)
                TextButton(
                  key: const Key('trash-screen-purge'),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    if (await purgeTrash(context, library, sync: sync)) {
                      navigator.maybePop();
                    }
                  },
                  child: Text(l10n.trashPurge),
                ),
            ],
          ),
          body: !library.hasTrash
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l10n.trashEmpty, textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    if (trashed.isNotEmpty)
                      _Heading(l10n.trashCapturesHeading, theme: theme),
                    for (final event in trashed)
                      ListTile(
                        key: ValueKey('trashed-${event.id}'),
                        leading: const Icon(Icons.library_music_outlined),
                        title: Text(
                          event.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          l10n.trashDeletedOn(
                            MaterialLocalizations.of(context)
                                .formatMediumDate(event.trashed!),
                          ),
                        ),
                        trailing: TextButton(
                          key: ValueKey('restore-${event.id}'),
                          onPressed: () => _restore(
                            context,
                            event.title,
                            () => library.restore(event),
                          ),
                          child: Text(l10n.trashRestore),
                        ),
                      ),
                    for (final event in withFiles) ...[
                      _Heading(l10n.trashFilesOf(event.title), theme: theme),
                      for (final page in event.deletedPages)
                        ListTile(
                          key: ValueKey('deleted-${event.id}-${page.id}'),
                          leading: Icon(_iconOf(page)),
                          title: Text(
                            fileLabel(l10n, event, page),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: TextButton(
                            key: ValueKey('restore-${event.id}-${page.id}'),
                            onPressed: () => _restore(
                              context,
                              fileLabel(l10n, event, page),
                              () => library.restorePage(event.id, page),
                            ),
                            child: Text(l10n.trashRestore),
                          ),
                        ),
                    ],
                  ],
                ),
        );
      },
    );
  }

  Future<void> _restore(
    BuildContext context,
    String name,
    Future<Object?> Function() restore,
  ) async {
    final l10n = context.l10n;
    final messenger = Messenger.maybeOf(context);
    await restore();
    messenger?.show(l10n.trashRestored(name));
  }

  static IconData _iconOf(EventPage page) => switch (page.kind) {
    PageKind.video => Icons.videocam_outlined,
    PageKind.audio => Icons.mic_none,
    PageKind.pdf => Icons.picture_as_pdf_outlined,
    PageKind.link => Icons.link,
    PageKind.image => Icons.image_outlined,
  };
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.primary,
      ),
    ),
  );
}
