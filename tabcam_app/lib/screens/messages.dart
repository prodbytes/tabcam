import 'dart:async';
import 'dart:collection';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The app's messages ("Link copied", "Saved … (Open)"): a banner at the
/// top of the screen, just under the app bar, floating over the page. It
/// moves and resizes nothing (no bottom navigation, button or FAB goes up
/// for it) and covers neither the app bar (its back button and actions)
/// nor the bottom navigation bar. One shows at a time; the others wait
/// their turn. Each goes by itself after its [Messenger.show] duration
/// (unless it persists), at once on a tap, or swiped up; its
/// [MessageAction] (Open, Upgrade) hides it too.
///
/// [TopMessages], around the app's navigator, shows them over every route
/// and dialog. Without it (a widget under test), they go on the root
/// [Overlay].
class TopMessages extends StatefulWidget {
  const TopMessages({super.key, required this.child});

  final Widget child;

  @override
  State<TopMessages> createState() => _TopMessagesState();
}

class _TopMessagesState extends State<TopMessages> {
  final _overlay = GlobalKey<OverlayState>();
  late final Messenger _messenger = Messenger._(
    () => _overlay.currentState,
    () => mounted,
  );

  @override
  Widget build(BuildContext context) => _MessengerScope(
    messenger: _messenger,
    child: Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        // Empty but for the banner: taps elsewhere reach the page.
        Overlay(key: _overlay),
      ],
    ),
  );
}

class _MessengerScope extends InheritedWidget {
  const _MessengerScope({required this.messenger, required super.child});

  final Messenger messenger;

  @override
  bool updateShouldNotify(_MessengerScope old) => old.messenger != messenger;
}

/// An action on a message, a text button at its end ("Open", "Upgrade").
class MessageAction {
  const MessageAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// How much of a message's background shows: 42% transparent.
const double messageOpacity = 0.58;

/// Where a message's top is: [messageGap] under the app bar, itself
/// under the status bar, so that the app bar's back button and actions
/// stay uncovered.
double messageTop(BuildContext context) =>
    MediaQuery.paddingOf(context).top +
    (AppBarTheme.of(context).toolbarHeight ?? kToolbarHeight) +
    messageGap;

/// The space between a message and the app bar above it.
const double messageGap = 8;

/// The space between a message and the safe area's sides.
const double messageSideMargin = 12;

/// Shows [text] as a message (see [TopMessages]), after the one showing.
/// It goes after [duration], or, if it [persist]s, once dismissed or
/// acted on.
void showMessage(
  BuildContext context,
  String text, {
  MessageAction? action,
  Duration duration = Messenger.defaultDuration,
  bool persist = false,
}) =>
    Messenger.maybeOf(context)
        ?.show(text, action: action, duration: duration, persist: persist);

/// Shows [text] as a message (see [TopMessages]) in place of the one
/// showing, which goes.
void replaceMessage(
  BuildContext context,
  String text, {
  MessageAction? action,
  Duration duration = Messenger.defaultDuration,
  bool persist = false,
}) => Messenger.maybeOf(context)
  ?..hide()
  ..show(text, action: action, duration: duration, persist: persist);

/// The queue of messages shown at the top of the screen (see
/// [TopMessages]). Get it with [maybeOf] before an `await`, as it stays
/// usable once the widget that asked is gone.
class Messenger {
  Messenger._(this._overlay, this._alive);

  /// How long a message shows, as a SnackBar's.
  static const Duration defaultDuration = Duration(seconds: 4);

  /// How long it takes to slide in or out.
  static const Duration transition = Duration(milliseconds: 250);

  static final Expando<Messenger> _onOverlay = Expando();

  /// The [TopMessages] around [context], or else its root [Overlay]'s.
  static Messenger? maybeOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_MessengerScope>();
    if (scope != null) return scope.messenger;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return null;
    return _onOverlay[overlay] ??= Messenger._(
      () => overlay.mounted ? overlay : null,
      () => overlay.mounted,
    );
  }

  final OverlayState? Function() _overlay;
  final bool Function() _alive;

  /// The messages to show; the first is the one showing, if [_entry].
  final _queue = Queue<_Message>();
  OverlayEntry? _entry;
  bool _waiting = false;

  /// Shows [text] once the messages before it have gone. It goes after
  /// [duration], or, if it [persist]s (an offer to keep in view), once
  /// dismissed, acted on or replaced.
  void show(
    String text, {
    MessageAction? action,
    Duration duration = defaultDuration,
    bool persist = false,
  }) {
    if (!_alive()) return;
    _queue.add(_Message(text, action, duration, persist: persist));
    _next();
  }

  /// The message showing goes (slides out), and the next one shows.
  void hide() {
    if (_queue.isEmpty) return;
    final current = _queue.first;
    final banner = current.banner;
    if (banner != null) {
      banner.leave();
    } else {
      _gone(current);
    }
  }

  void _next() {
    if (_entry != null || _queue.isEmpty || _waiting) return;
    if (!_alive()) {
      _queue.clear();
      return;
    }
    final overlay = _overlay();
    final scheduler = SchedulerBinding.instance;
    // Not while a frame is built (shown from a build or initState), nor
    // before the overlay is there (the app's first frame).
    if (overlay == null ||
        scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      _waiting = true;
      scheduler
        ..addPostFrameCallback((_) {
          _waiting = false;
          _next();
        })
        ..ensureVisualUpdate();
      return;
    }
    final message = _queue.first;
    final entry = OverlayEntry(
      builder: (_) => _Banner(message: message, onGone: () => _gone(message)),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  void _gone(_Message message) {
    if (!_queue.contains(message)) return;
    final showing = _entry != null && identical(_queue.first, message);
    _queue.remove(message);
    if (showing) {
      _entry!
        ..remove()
        ..dispose();
      _entry = null;
    }
    _next();
  }
}

class _Message {
  _Message(this.text, this.action, this.duration, {required this.persist});

  final String text;
  final MessageAction? action;
  final Duration duration;
  final bool persist;

  /// The banner showing it, once built.
  _BannerState? banner;
}

class _Banner extends StatefulWidget {
  const _Banner({required this.message, required this.onGone});

  final _Message message;
  final VoidCallback onGone;

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with SingleTickerProviderStateMixin {
  late final AnimationController _shown = AnimationController(
    vsync: this,
    duration: Messenger.transition,
  );
  late final CurvedAnimation _eased = CurvedAnimation(
    parent: _shown,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    widget.message.banner = this;
    _shown.forward().then((_) {
      if (mounted && !_leaving && !widget.message.persist) {
        _timer = Timer(widget.message.duration, leave);
      }
    });
  }

  /// Slides out, then the next message shows.
  void leave() {
    if (_leaving || !mounted) return;
    _leaving = true;
    _timer?.cancel();
    _shown.reverse().then((_) {
      if (mounted) widget.onGone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (identical(widget.message.banner, this)) widget.message.banner = null;
    _eased.dispose();
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snack = theme.snackBarTheme;
    final message = widget.message;
    final action = message.action;
    final background = (snack.backgroundColor ?? scheme.inverseSurface)
        .withValues(alpha: messageOpacity);
    final foreground = snack.contentTextStyle?.color ?? scheme.onInverseSurface;
    final textStyle = (theme.textTheme.bodyMedium ?? const TextStyle())
        .merge(snack.contentTextStyle)
        .copyWith(color: foreground);
    final radius = BorderRadius.circular(12);
    final safe = MediaQuery.paddingOf(context);
    // Under the app bar, not over its back button and actions; inside the
    // safe area's sides.
    return Positioned(
      top: messageTop(context),
      left: safe.left + messageSideMargin,
      right: safe.right + messageSideMargin,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: FadeTransition(
            opacity: _eased,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, -0.5),
                end: Offset.zero,
              ).animate(_eased),
              child: Dismissible(
                key: ObjectKey(message),
                direction: DismissDirection.up,
                onDismissed: (_) {
                  _leaving = true;
                  _timer?.cancel();
                  widget.onGone();
                },
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  child: GestureDetector(
                    onTap: leave,
                    child: ClipRRect(
                      borderRadius: radius,
                      // What's behind shows through, blurred, so that the
                      // text stays readable over it.
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                        child: Material(
                          key: const Key('top-message'),
                          color: background,
                          borderRadius: radius,
                          child: Padding(
                            padding: EdgeInsetsDirectional.only(
                              start: 16,
                              end: action == null ? 16 : 8,
                              top: action == null ? 12 : 4,
                              bottom: action == null ? 12 : 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(message.text, style: textStyle),
                                ),
                                if (action != null) ...[
                                  const SizedBox(width: 8),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          snack.actionTextColor ??
                                          scheme.inversePrimary,
                                    ),
                                    onPressed: () {
                                      leave();
                                      action.onPressed();
                                    },
                                    child: Text(action.label),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
