/// The video editor's **Download settings**: what Download puts in the
/// file and how it sounds (what's drawn on the video, the fades, the
/// Master, the song's details), the **Download** tab of the editor's
/// sidebar ([SidebarTabs]): in Cam's view beside the play-along files
/// (`PlayAlongBeside`), in the editor alone a sidebar of its own
/// ([DownloadSidebarBeside]). A button in the editor's app bar shows it
/// ([DownloadSettingsButton]), as the metronome's and the dictionary's
/// do theirs.
library;

import 'package:flutter/material.dart';

import '../capture/play_along_sidebar.dart';
import '../l10n/language.dart';
import 'sidebar_tabs.dart';
import 'sidebar_widths.dart';
import 'split_handle.dart';

/// Whether the sidebar of the editor alone (its Download tab,
/// [DownloadSidebarBeside]) shows, app-wide for the session: open the
/// first time (where it leaves the editor its room: a phone opens it
/// hidden), and once hidden (its button, its ✕) hidden in this editor and
/// the next, until it's shown again. Not kept on the device: a new
/// session opens with it showing. (In Cam's view, the play-along
/// sidebar's own state says whether it shows, `PlayAlong.open`.)
class DownloadSettingsState extends ChangeNotifier {
  DownloadSettingsState._();

  /// The app's.
  static final DownloadSettingsState instance = DownloadSettingsState._();

  bool get open => _open;
  bool _open = true;

  void toggle() {
    _open = !_open;
    notifyListeners();
  }

  /// Shows it (a tap on the picture that opens one of its fields).
  void show() {
    if (_open) return;
    _open = true;
    notifyListeners();
  }

  void close() {
    if (!_open) return;
    _open = false;
    notifyListeners();
  }

  /// Showing, as a session starts (tests).
  @visibleForTesting
  void reset() {
    _open = true;
    notifyListeners();
  }
}

/// The editor's app bar button for its Download settings (a tune icon,
/// "Download settings"): shows the sidebar on its Download tab, or hides
/// it where that tab shows ([shown], then in the primary colour, "Hide
/// the download settings"). [onPressed] does it: the sidebar is the
/// editor's ([SidebarTabs]).
class DownloadSettingsButton extends StatelessWidget {
  const DownloadSettingsButton({
    super.key,
    required this.shown,
    required this.onPressed,
  });

  /// Whether the sidebar shows, on its Download tab.
  final bool shown;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return IconButton(
      key: const Key('video-edit-settings'),
      tooltip: shown ? l10n.downloadSettingsHide : l10n.downloadSettings,
      isSelected: shown,
      color: shown ? Theme.of(context).colorScheme.primary : null,
      icon: const Icon(Icons.tune),
      onPressed: onPressed,
    );
  }
}

/// [child] (the editor alone: no Cam, nothing to play along with) with
/// the editor's sidebar at its right, its Download tab alone
/// ([SidebarTabs], ✕ hiding it) over the Download settings ([panel],
/// built only while it shows), while it shows ([DownloadSettingsState])
/// and is [enabled]. As wide as Cam's play-along sidebar, the same width
/// ([SidebarWidths.playAlong]), never narrower than [minWidth]; its left
/// edge a separator to drag ([SplitHandle]), a double tap putting the
/// default back. Hidden, or not [enabled], [child] takes all the room.
class DownloadSidebarBeside extends StatelessWidget {
  const DownloadSidebarBeside({
    super.key,
    required this.child,
    required this.panel,
    required this.tab,
    this.enabled = true,
    this.onClosed,
  });

  final Widget child;

  /// The Download settings (built only while they show).
  final WidgetBuilder panel;

  /// The sidebar's tab ([StudioTab.download], the only one here).
  final ValueNotifier<StudioTab> tab;

  /// False, [child] shows alone (the sidebar's state kept app-wide).
  final bool enabled;

  /// After its ✕ hides it.
  final VoidCallback? onClosed;

  /// The narrowest the sidebar is ([downloadTabLeast], as on the Download
  /// tab in Cam's view).
  static const minWidth = downloadTabLeast;

  /// The narrowest [child] gets when the sidebar is dragged wider.
  static const minChild = PlayAlongBeside.minChild;

  @override
  Widget build(BuildContext context) {
    final state = DownloadSettingsState.instance;
    final widths = SidebarWidths.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([state, widths]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final open = state.open && enabled;
          final screen = MediaQuery.sizeOf(context).width;
          final max = box.maxWidth - minChild - SplitHandle.thickness;
          final width = widths.widthOf(
            SidebarWidths.playAlong,
            fallback: PlayAlongSidebar.widthFor(screen),
            max: max,
            least: minWidth,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: child),
              if (open) ...[
                SplitHandle(
                  key: const Key('video-edit-settings-split'),
                  axis: Axis.horizontal,
                  color: Colors.white38,
                  background: Colors.black,
                  // Dragged left, the sidebar (on the right) gets wider.
                  onDrag: (dx) => widths.set(
                    SidebarWidths.playAlong,
                    (width - dx).clamp(
                      minWidth,
                      max < minWidth ? minWidth : max,
                    ),
                  ),
                  onDragEnd: widths.save,
                  onReset: () => widths.reset(SidebarWidths.playAlong),
                ),
                SizedBox(
                  width: width,
                  child: Material(
                    key: const Key('video-edit-settings-panel'),
                    color: sidebarColor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SidebarTabs(
                          tab: tab,
                          playAlong: false,
                          onClose: () {
                            state.close();
                            onClosed?.call();
                          },
                        ),
                        Expanded(child: Builder(builder: panel)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
