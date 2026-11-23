/// The tabs at the top of the video editor's sidebar (`StudioView`):
/// **Play along** (the files to play along, the play-along sidebar's) and
/// **Download** (the Download settings), and ✕ to hide the sidebar.
library;

import 'package:flutter/material.dart';

import '../l10n/language.dart';

/// The tabs of the video editor's sidebar ([SidebarTabs]).
enum StudioTab {
  /// The files to play along, in Cam's view (`PlayAlongSidebar`).
  playAlong,

  /// The Download settings: what Download puts in the file and how it
  /// sounds.
  download,
}

/// The narrowest the video editor's sidebar is on its Download tab: where
/// the Master's slider keeps some room beside its Mute and its level, at
/// the largest text size too (at the other sidebars' least, 160, it would
/// have none).
const downloadTabLeast = 224.0;

/// The background of the video editor's sidebar, whichever tab shows: the
/// play-along sidebar's.
const sidebarColor = Color(0xFF1C1C1C);

/// The tabs at the top of the video editor's sidebar: **Play along**
/// (♫) and **Download** (a tune icon), the one showing ([tab]) in the
/// primary colour and underlined, a tap on the other showing it; then ✕
/// ([onClose]), which hides the sidebar. Without [playAlong] (the editor
/// alone, where there's nothing to play along with), Download alone.
/// Where the sidebar is too narrow for their names ([labelsFrom]), the
/// tabs are their icons, their names in tooltips; in one too short
/// ([shownFrom]), the sidebar has none.
class SidebarTabs extends StatelessWidget {
  const SidebarTabs({
    super.key,
    required this.tab,
    required this.onClose,
    this.playAlong = true,
  });

  /// Which tab shows.
  final ValueNotifier<StudioTab> tab;

  /// ✕: hides the sidebar.
  final VoidCallback onClose;

  /// Whether the Play along tab is there.
  final bool playAlong;

  /// How wide the sidebar is before the tabs show their names beside
  /// their icons.
  static const labelsFrom = 240.0;

  /// How high the sidebar is before the tabs show at its top: in a shorter
  /// one (a phone on its side) they'd leave the play-along player no room,
  /// so there are none, and the app bar's buttons (♫ and Download
  /// settings) show one tab or the other.
  static const shownFrom = 400.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<StudioTab>(
      valueListenable: tab,
      builder: (context, shown, _) => LayoutBuilder(
        builder: (context, box) {
          final labels = box.maxWidth >= labelsFrom;
          Widget item(StudioTab which, IconData icon, String name) {
            final selected = (playAlong ? shown : StudioTab.download) == which;
            final color = selected
                ? Theme.of(context).colorScheme.primary
                : Colors.white70;
            final button = Semantics(
              selected: selected,
              button: true,
              child: InkWell(
                key: Key('sidebar-tab-${which.name}'),
                onTap: () => tab.value = which,
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: selected ? color : Colors.white12,
                        width: selected ? 2 : 1,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 20, color: color),
                      if (labels) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: color),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
            return Expanded(
              child: labels ? button : Tooltip(message: name, child: button),
            );
          }

          // As high as the tallest (✕, or a name at a large text size), the
          // tabs' lines along their bottom.
          return IntrinsicHeight(
            child: Row(
              key: const Key('sidebar-tabs'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (playAlong)
                  item(
                    StudioTab.playAlong,
                    Icons.queue_music,
                    l10n.sidebarPlayAlong,
                  ),
                item(StudioTab.download, Icons.tune, l10n.sidebarDownload),
                Container(
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white12)),
                  ),
                  child: IconButton(
                    key: const Key('sidebar-close'),
                    tooltip: l10n.sidebarHide,
                    color: Colors.white70,
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
