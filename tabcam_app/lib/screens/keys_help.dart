/// The keyboard shortcuts' help: a button in the app bar of the screens
/// that have keys (Cam, a capture's and a file's screens, the video
/// editor), and the **H** key there, open an overlay listing the screen's
/// keys; H, Esc or Close shuts it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/language.dart';

/// Which screen's keys the help lists.
enum KeysScreen {
  /// Cam: the tab's phrases, the takes and the play-along player.
  cam,

  /// A capture's screens and a file's: the play-along player's keys.
  player,

  /// The video editor: its preview.
  videoEdit,
}

/// The app bar's keyboard button (a keyboard icon, "Keyboard shortcuts
/// (H)"), and the H key while its screen is on top: both show
/// [showKeysHelp] for [screen]. The button shows where a keyboard is
/// likely (the web, a computer, a screen 600 px wide or more); the key
/// works everywhere. [onClosed] after the help shuts (Cam takes its keys
/// back).
class KeysHelpButton extends StatefulWidget {
  const KeysHelpButton({
    super.key,
    required this.screen,
    this.onClosed,
    this.hidden = false,
  });

  final KeysScreen screen;
  final VoidCallback? onClosed;

  /// No button (its app bar has no room: a phone's capture puts its
  /// buttons in a menu), only the key.
  final bool hidden;

  /// The key that opens (and shuts) the help.
  static final helpKey = LogicalKeyboardKey.keyH;

  @override
  State<KeysHelpButton> createState() => _KeysHelpButtonState();
}

class _KeysHelpButtonState extends State<KeysHelpButton> {
  /// The screen the button is in: under another (a dialog, a menu, the
  /// editor), H is that one's.
  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    // Before the screen's own keys: in Cam any other key turns the tab.
    FocusManager.instance.addEarlyKeyEventHandler(_key);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_key);
    super.dispose();
  }

  KeyEventResult _key(KeyEvent event) {
    if (event.logicalKey != KeysHelpButton.helpKey ||
        !(_route?.isCurrent ?? true) ||
        !mounted) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    // Typing in a field types the H.
    final field = FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<EditableText>();
    if (field != null && !field.readOnly) return KeyEventResult.ignored;
    if (event is KeyDownEvent) _open();
    return KeyEventResult.handled;
  }

  Future<void> _open() async {
    await showKeysHelp(context, widget.screen);
    widget.onClosed?.call();
  }

  /// Whether a keyboard is likely: the web, a computer, a tablet.
  bool _keyboardLikely(BuildContext context) {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return MediaQuery.sizeOf(context).shortestSide >= 600;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hidden || !_keyboardLikely(context)) {
      return const SizedBox.shrink();
    }
    return IconButton(
      key: const Key('keys-help'),
      tooltip: context.l10n.keysHelpTooltip,
      icon: const Icon(Icons.keyboard_outlined),
      onPressed: _open,
    );
  }
}

/// Shows the overlay listing [screen]'s keys; H, Esc or Close shuts it.
Future<void> showKeysHelp(BuildContext context, KeysScreen screen) =>
    showDialog<void>(
      context: context,
      builder: (context) => _KeysHelp(screen: screen),
    );

/// A row of the help: the keys (each its own cap; one with a + in it,
/// `Shift + ←`, a cap per key) and what they do.
typedef _Row = (List<String> keys, String does);

class _KeysHelp extends StatelessWidget {
  const _KeysHelp({required this.screen});

  final KeysScreen screen;

  /// The shortcuts' key: ⌘ on macOS and iOS, Ctrl elsewhere.
  static String _command(AppLocalizations l10n) =>
      defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.iOS
      ? '⌘'
      : l10n.keyCtrl;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final playAlong = (
      screen == KeysScreen.cam
          ? l10n.keysPlayAlongCam
          : l10n.keysPlayAlongPlayer,
      <_Row>[
        ([l10n.keySpace, '1'], l10n.keysPlayPause),
        (['0'], l10n.keysRestart),
        (['←', '→'], l10n.keysSkip),
      ],
    );
    final sections = <(String, List<_Row>)>[
      if (screen == KeysScreen.cam) ...[
        (
          l10n.keysTab,
          [
            ([l10n.keyAnyKey, '↓'], l10n.keysNextPhrase),
            (['↑', l10n.keyBackspace, l10n.keyPageUp], l10n.keysPreviousPhrase),
          ],
        ),
        (
          l10n.keysTakes,
          [
            (['.'], l10n.keysRetake),
            (['/', ','], l10n.keysCut),
          ],
        ),
        playAlong,
      ],
      if (screen == KeysScreen.player) ...[
        playAlong,
        // The Text view's, in its text: ⌘ on Apple's systems, Ctrl
        // elsewhere.
        (
          l10n.keysTextView,
          [
            (['${_command(l10n)} + A'], l10n.keysSelectAll),
            (['${_command(l10n)} + L'], l10n.keysSelectPhrase),
          ],
        ),
      ],
      if (screen == KeysScreen.videoEdit)
        (
          l10n.keysPreview,
          [
            ([l10n.keySpace], l10n.keysPlayPausePreview),
            ([l10n.keyHome], l10n.keysToStart),
            ([l10n.keyEnd], l10n.keysToEnd),
            (['←', '→'], l10n.keysStepTenth),
            (
              ['${l10n.keyShift} + ←', '${l10n.keyShift} + →'],
              l10n.keysStepSecond,
            ),
          ],
        ),
      (
        l10n.keysGeneral,
        [
          (['H'], l10n.keysShowHelp),
        ],
      ),
    ];
    final theme = Theme.of(context);
    void close() => Navigator.of(context).pop();
    return CallbackShortcuts(
      bindings: {SingleActivator(KeysHelpButton.helpKey): close},
      child: Focus(
        autofocus: true,
        child: AlertDialog(
          key: const Key('keys-help-overlay'),
          title: Text(l10n.keysHelp),
          scrollable: true,
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, (title, rows)) in sections.indexed) ...[
                  if (i > 0) const SizedBox(height: 16),
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final (keys, does) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [for (final k in keys) _KeyCap(k)],
                          ),
                          Text(does),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                Text(
                  l10n.keysInFields,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: close,
              child: Text(MaterialLocalizations.of(context).closeButtonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// A key as on the keyboard: its name in a rounded box.
class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 28),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFamily: 'RobotoMono',
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
