/// The video editor's **Download settings**: what Download puts in the
/// file and how it sounds (what's drawn on the video, the fades, the
/// Master, the song's details), in a sidebar that a button in the
/// editor's app bar shows and hides, as the metronome's and the
/// dictionary's do. Beside the viewer where the editor's room is wide,
/// under it where it's narrow.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/language.dart';
import 'sidebar_widths.dart';
import 'split_handle.dart';

/// Whether the editor's Download settings show, app-wide for the session:
/// open the first time, and once hidden (its button, its ✕) hidden in
/// this editor and the next, until it's shown again. Not kept on the
/// device: a new session opens with it showing.
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

/// The editor's app bar button for its Download settings (a tune icon):
/// shows or hides them ([DownloadSettingsBeside]), in the primary colour
/// while they show; [onClosed] after they hide (the editor takes its
/// keys back).
class DownloadSettingsButton extends StatelessWidget {
  const DownloadSettingsButton({super.key, this.onClosed});

  final VoidCallback? onClosed;

  @override
  Widget build(BuildContext context) {
    final state = DownloadSettingsState.instance;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final l10n = context.l10n;
        return IconButton(
          key: const Key('video-edit-settings'),
          tooltip: state.open
              ? l10n.downloadSettingsHide
              : l10n.downloadSettings,
          isSelected: state.open,
          color: state.open ? Theme.of(context).colorScheme.primary : null,
          icon: const Icon(Icons.tune),
          onPressed: () {
            state.toggle();
            if (!state.open) onClosed?.call();
          },
        );
      },
    );
  }
}

/// [viewer], with the Download settings ([panel], under their title and
/// ✕, [DownloadSettingsPanel]) while they show ([DownloadSettingsState]):
/// [beside] it, on its right, their left edge a separator to drag
/// ([SplitHandle]) to make them wider or narrower, kept with the other
/// sidebars' widths ([SidebarWidths.downloadSettings]), a double tap
/// putting the default back; or under it, the viewer [viewerHeight] high
/// and the settings taking the rest. Hidden, or not [enabled], the viewer
/// takes all the room. One Flex either way, the viewer first, so showing,
/// hiding or turning them keeps the viewer (the video's picture) as it is.
class DownloadSettingsBeside extends StatelessWidget {
  const DownloadSettingsBeside({
    super.key,
    required this.beside,
    required this.viewer,
    required this.panel,
    required this.viewerHeight,
    this.enabled = true,
    this.onClosed,
  });

  /// Whether they're beside the viewer (a wide room), else under it.
  final bool beside;

  final Widget viewer;

  /// The settings, under their title (built only while they show).
  final WidgetBuilder panel;

  /// How high the viewer is with the settings under it.
  final double viewerHeight;

  /// False, the viewer shows alone (the settings' state kept app-wide).
  final bool enabled;

  /// After their own ✕ hides them.
  final VoidCallback? onClosed;

  /// The narrowest the viewer gets when they're dragged wider.
  static const minViewer = 96.0;

  /// Their default width beside a room [room] wide: 40% of it, at most
  /// 320 px.
  static double widthFor(double room) => math.min(320.0, room * 0.4);

  @override
  Widget build(BuildContext context) {
    final state = DownloadSettingsState.instance;
    final widths = SidebarWidths.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([state, widths]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final open = state.open && enabled;
          final max = box.maxWidth - minViewer - SplitHandle.thickness;
          final width = widths.widthOf(
            SidebarWidths.downloadSettings,
            fallback: widthFor(box.maxWidth),
            max: max,
          );
          Widget sidebar() => DownloadSettingsPanel(
            onClose: () {
              state.close();
              onClosed?.call();
            },
            child: Builder(builder: panel),
          );
          return Flex(
            direction: beside ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: viewer),
              if (open && beside) ...[
                SplitHandle(
                  key: const Key('video-edit-settings-split'),
                  axis: Axis.horizontal,
                  // Dragged left, the settings (on the right) get wider.
                  onDrag: (dx) => widths.set(
                    SidebarWidths.downloadSettings,
                    (width - dx).clamp(
                      SidebarWidths.min,
                      max < SidebarWidths.min ? SidebarWidths.min : max,
                    ),
                  ),
                  onDragEnd: widths.save,
                  onReset: () => widths.reset(SidebarWidths.downloadSettings),
                ),
                SizedBox(width: width, child: sidebar()),
              ] else if (open)
                SizedBox(
                  height: math.max(0.0, box.maxHeight - viewerHeight),
                  child: sidebar(),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The Download settings' sidebar: its title ("Download settings") and
/// ✕, then [child] (the settings, which scroll). In a place too short for
/// its title (a phone on its side with the keyboard up), it's cut, not
/// squeezed.
class DownloadSettingsPanel extends StatelessWidget {
  const DownloadSettingsPanel({
    super.key,
    required this.child,
    required this.onClose,
  });

  final Widget child;
  final VoidCallback onClose;

  /// The least it's laid out in: its title, at large text sizes too.
  static const minHeight = 72.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final height = math.max(box.maxHeight, minHeight);
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: height,
            maxHeight: height,
            child: Material(
              key: const Key('video-edit-settings-panel'),
              color: theme.colorScheme.surfaceContainerLow,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.tune,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.downloadSettings,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          key: const Key('video-edit-settings-close'),
                          tooltip: l10n.downloadSettingsHide,
                          icon: const Icon(Icons.close),
                          onPressed: onClose,
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
