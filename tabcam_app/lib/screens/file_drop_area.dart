import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/language.dart';

/// Whether files can be dragged into the app here: the web, desktops and
/// Android (`desktop_drop`); not iOS.
bool get canDropFiles =>
    kIsWeb ||
    switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.android => true,
      _ => false,
    };

/// Lets the user drag files from elsewhere (the desktop, a file manager)
/// onto [child] to add them: while they're over it, it's outlined with
/// "Drop files to add"; dropped, the files go to [onFiles] (folders don't:
/// they're counted in its `skipped`). Off when [enabled] is false, or
/// where files can't be dropped ([canDropFiles]).
class FileDropArea extends StatefulWidget {
  const FileDropArea({
    super.key,
    required this.onFiles,
    required this.child,
    this.enabled = true,
  });

  final void Function(List<XFile> files, int skipped) onFiles;
  final Widget child;
  final bool enabled;

  @override
  State<FileDropArea> createState() => _FileDropAreaState();
}

class _FileDropAreaState extends State<FileDropArea> {
  bool _over = false;

  void _drop(DropDoneDetails details) {
    setState(() => _over = false);
    final files = details.files.whereType<DropItemFile>().toList();
    final skipped = details.files.length - files.length;
    if (files.isEmpty && skipped == 0) return;
    widget.onFiles(files, skipped);
  }

  @override
  Widget build(BuildContext context) {
    if (!canDropFiles) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: _drop,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_over)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  key: const Key('drop-files'),
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    border: Border.all(color: scheme.primary, width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.file_download,
                        size: 48,
                        color: scheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.l10n.dropFilesToAdd,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
