/// The metronome: a button at the top of every file viewer, Cam and Home, and
/// the sidebar it opens on the right of the screen, as the dictionary
/// does: the tempo (BPM), the time signature, the beats lit as they click,
/// and Start / Stop.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/language.dart';
import '../library/library.dart';
import '../screens/sidebar_widths.dart';
import '../screens/split_handle.dart';
import 'click_track.dart';
import 'metronome_sound.dart';

/// The metronome, app-wide: whether its sidebar shows, its tempo and time
/// signature (kept on the device, the library's `metronome` meta file),
/// and whether it plays. It plays only while its sidebar shows on some
/// screen: closing it, or leaving the screens that have it, stops it.
class MetronomeState extends ChangeNotifier {
  MetronomeState._();

  /// The app's.
  static final MetronomeState instance = MetronomeState._();

  static const minBpm = 30;
  static const maxBpm = 250;
  static const defaultBpm = 80;
  static const defaultSignature = TimeSignature.fourFour;

  /// The meta file the tempo and time signature are kept in.
  static const metaName = 'metronome';

  /// What plays the clicks (a fake in tests).
  MetronomeSound sound = PlatformMetronomeSound();

  bool get open => _open;
  bool _open = false;

  int get bpm => _bpm;
  int _bpm = defaultBpm;

  TimeSignature get signature => _signature;
  TimeSignature _signature = defaultSignature;

  bool get playing => _playing;
  bool _playing = false;

  /// Why it couldn't play, until it's started again.
  String? get error => _error;
  String? _error;

  /// The beat clicking now (0: the bar's first), null while stopped.
  final ValueNotifier<int?> beat = ValueNotifier(null);

  Library? _library;
  Timer? _ticker;
  int _hosts = 0;

  /// Each start: an older one finishing late doesn't start the lights.
  int _generation = 0;

  void toggle() => _open ? close() : _show();

  void _show() {
    _open = true;
    notifyListeners();
  }

  void close() {
    if (!_open) return;
    _open = false;
    unawaited(stop());
    notifyListeners();
  }

  /// Sets the tempo (within [minBpm] and [maxBpm]); playing, it goes on at
  /// the new one, unless [apply] is false (a slider being dragged: then
  /// [applyBpm] when it's let go).
  void setBpm(int bpm, {bool apply = true}) {
    bpm = bpm.clamp(minBpm, maxBpm);
    if (bpm == _bpm) return;
    _bpm = bpm;
    notifyListeners();
    if (apply) _changed();
  }

  /// The tempo set while dragging, now played and kept.
  void applyBpm() => _changed();

  void setSignature(TimeSignature signature) {
    if (signature == _signature) return;
    _signature = signature;
    notifyListeners();
    _changed();
  }

  void _changed() {
    _save();
    if (_playing) unawaited(play());
  }

  Future<void> togglePlaying() => _playing ? stop() : play();

  /// Plays from the bar's first beat (again, if it plays).
  Future<void> play() async {
    final generation = ++_generation;
    _ticker?.cancel();
    _error = null;
    _playing = true;
    notifyListeners();
    try {
      await sound.start(_bpm, _signature);
    } catch (e) {
      debugPrint('TabCam: the metronome failed: $e');
      if (generation != _generation) return;
      _playing = false;
      _error = appL10n.metronomeFailed('$e');
      beat.value = null;
      notifyListeners();
      return;
    }
    if (generation != _generation || !_playing) {
      // Stopped while it was starting: silent again.
      if (!_playing) unawaited(sound.stop());
      return;
    }
    // The lights follow the clicks from the first.
    final beats = _signature.beats;
    beat.value = 0;
    _ticker = Timer.periodic(beatLength(_bpm), (_) {
      beat.value = ((beat.value ?? -1) + 1) % beats;
    });
  }

  Future<void> stop() async {
    _generation++;
    _ticker?.cancel();
    _ticker = null;
    beat.value = null;
    if (!_playing) return;
    _playing = false;
    notifyListeners();
    await sound.stop();
  }

  /// A screen showing the sidebar's place ([MetronomeBeside]) came; [detach]
  /// when it goes. With none left, it stops: after the screen has gone
  /// (the widget tree can't be told while it's being taken down), and only
  /// if no other came meanwhile (one screen replacing another).
  void attach() => _hosts++;

  void detach() {
    _hosts = _hosts > 0 ? _hosts - 1 : 0;
    if (_hosts > 0) return;
    scheduleMicrotask(() {
      if (_hosts == 0) unawaited(stop());
    });
  }

  /// Reads the tempo and time signature kept in [library], and keeps them
  /// there from now on.
  Future<void> load(Library library) async {
    _library = library;
    try {
      final json = await library.readMeta(metaName);
      if (json == null) return;
      final map = jsonDecode(json);
      if (map is! Map) return;
      if (map['bpm'] case final int bpm) _bpm = bpm.clamp(minBpm, maxBpm);
      if (TimeSignature.byLabel(map['signature'] as String?) case final s?) {
        _signature = s;
      }
      notifyListeners();
    } on Object catch (e) {
      debugPrint('TabCam: metronome settings unreadable: $e');
    }
  }

  void _save() {
    final library = _library;
    if (library == null) return;
    unawaited(
      library
          .writeMeta(
            metaName,
            jsonEncode({'bpm': _bpm, 'signature': _signature.label}),
          )
          .catchError((Object e) {
            debugPrint('TabCam: metronome settings not saved: $e');
          }),
    );
  }

  /// Closed, stopped, at the defaults, kept nowhere (tests).
  @visibleForTesting
  void reset(MetronomeSound sound) {
    _ticker?.cancel();
    _generation++;
    this.sound = sound;
    _open = false;
    _playing = false;
    _error = null;
    _bpm = defaultBpm;
    _signature = defaultSignature;
    _library = null;
    _hosts = 0;
    beat.value = null;
    notifyListeners();
  }
}

/// The app bar's Metronome button: shows or hides the metronome's sidebar
/// ([MetronomeBeside]), in the primary colour while it shows; [onClosed]
/// after it hides (Cam takes its keys back).
class MetronomeButton extends StatelessWidget {
  const MetronomeButton({super.key, this.onClosed});

  final VoidCallback? onClosed;

  @override
  Widget build(BuildContext context) {
    final state = MetronomeState.instance;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final l10n = context.l10n;
        return IconButton(
          key: const Key('metronome'),
          tooltip: state.open ? l10n.metronomeHide : l10n.metronome,
          isSelected: state.open,
          color: state.open ? Theme.of(context).colorScheme.primary : null,
          icon: const Icon(Icons.av_timer),
          onPressed: () {
            state.toggle();
            if (!state.open) onClosed?.call();
          },
        );
      },
    );
  }
}

/// [child], with the metronome's sidebar on its right while it's open
/// ([MetronomeState]); its left edge is a separator to drag
/// ([SplitHandle]) to make it wider or narrower, the same on every screen
/// ([SidebarWidths]); a double tap puts its default width back.
class MetronomeBeside extends StatefulWidget {
  const MetronomeBeside({
    super.key,
    required this.child,
    this.onClosed,
    this.enabled = true,
  });

  final Widget child;

  /// After the sidebar's own close button hides it.
  final VoidCallback? onClosed;

  /// False, [child] shows alone, and this isn't a place that has the
  /// metronome (Home's tabs other than Home): with none left, it stops, as
  /// when the screen goes, or is covered by one without it. [child] keeps
  /// its state either way.
  final bool enabled;

  /// The narrowest [child] gets when the sidebar is dragged wider.
  static const minChild = 96.0;

  /// Its default width: 30% of a screen [screen] wide, from 260 to 340 px.
  static double widthFor(double screen) => (screen * 0.3).clamp(260.0, 340.0);

  @override
  State<MetronomeBeside> createState() => _MetronomeBesideState();
}

class _MetronomeBesideState extends State<MetronomeBeside> {
  final _state = MetronomeState.instance;

  /// Whether this is a place that has the metronome now ([attach]ed):
  /// [MetronomeBeside.enabled], and on screen, not covered by a screen
  /// opened over it (its route offstage, its tickers off; a dialog or a
  /// menu over it doesn't count). Covered by one that has the metronome
  /// too (a capture over Home, a file over its capture), that one has
  /// attached by then, so it plays on; covered by one that hasn't, it
  /// stops.
  bool _hosting = false;

  void _host() {
    final hosting = widget.enabled && TickerMode.valuesOf(context).enabled;
    if (hosting == _hosting) return;
    _hosting = hosting;
    hosting ? _state.attach() : _state.detach();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _host();
  }

  @override
  void didUpdateWidget(MetronomeBeside old) {
    super.didUpdateWidget(old);
    _host();
  }

  @override
  void dispose() {
    if (_hosting) _state.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final widths = SidebarWidths.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([_state, widths]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final max =
              box.maxWidth - MetronomeBeside.minChild - SplitHandle.thickness;
          final width = widths.widthOf(
            SidebarWidths.metronome,
            fallback: MetronomeBeside.widthFor(
              MediaQuery.sizeOf(context).width,
            ),
            max: max,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: widget.child),
              if (_state.open && widget.enabled) ...[
                SplitHandle(
                  key: const Key('metronome-split'),
                  axis: Axis.horizontal,
                  // Dragged left, the sidebar (on the right) gets wider.
                  onDrag: (dx) => widths.set(
                    SidebarWidths.metronome,
                    (width - dx).clamp(
                      SidebarWidths.min,
                      max < SidebarWidths.min ? SidebarWidths.min : max,
                    ),
                  ),
                  onDragEnd: widths.save,
                  onReset: () => widths.reset(SidebarWidths.metronome),
                ),
                SizedBox(
                  width: width,
                  child: MetronomeSidebar(
                    onClose: () {
                      _state.close();
                      widget.onClosed?.call();
                    },
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

/// The metronome's sidebar: its title and close button, the tempo (−, a
/// slider, +), the time signatures, a light per beat, and Start / Stop.
class MetronomeSidebar extends StatelessWidget {
  const MetronomeSidebar({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final state = MetronomeState.instance;
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Material(
      key: const Key('metronome-sidebar'),
      color: theme.colorScheme.surfaceContainerLow,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.av_timer,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.metronome,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    key: const Key('metronome-close'),
                    tooltip: l10n.metronomeHide,
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${state.bpm}',
                              style: theme.textTheme.displaySmall,
                            ),
                            TextSpan(
                              text: ' BPM',
                              style: theme.textTheme.titleMedium,
                            ),
                          ],
                        ),
                        key: const Key('metronome-bpm'),
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          key: const Key('metronome-slower'),
                          tooltip: l10n.metronomeSlower,
                          icon: const Icon(Icons.remove),
                          onPressed: state.bpm > MetronomeState.minBpm
                              ? () => state.setBpm(state.bpm - 1)
                              : null,
                        ),
                        Expanded(
                          child: Slider(
                            key: const Key('metronome-slider'),
                            min: MetronomeState.minBpm.toDouble(),
                            max: MetronomeState.maxBpm.toDouble(),
                            divisions:
                                MetronomeState.maxBpm - MetronomeState.minBpm,
                            value: state.bpm.toDouble(),
                            label: '${state.bpm}',
                            semanticFormatterCallback: (v) =>
                                '${v.round()} BPM',
                            onChanged: (v) =>
                                state.setBpm(v.round(), apply: false),
                            onChangeEnd: (_) => state.applyBpm(),
                          ),
                        ),
                        IconButton(
                          key: const Key('metronome-faster'),
                          tooltip: l10n.metronomeFaster,
                          icon: const Icon(Icons.add),
                          onPressed: state.bpm < MetronomeState.maxBpm
                              ? () => state.setBpm(state.bpm + 1)
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.metronomeTimeSignature,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in TimeSignature.common)
                          ChoiceChip(
                            key: Key('metronome-signature-${s.label}'),
                            label: Text(s.label),
                            selected: s == state.signature,
                            onSelected: (_) => state.setSignature(s),
                          ),
                      ],
                    ),
                    if (state.signature.unit == 8) ...[
                      const SizedBox(height: 8),
                      Text(
                        l10n.metronomeEighths,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _Lights(signature: state.signature, beat: state.beat),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      key: const Key('metronome-play'),
                      icon: Icon(state.playing ? Icons.stop : Icons.play_arrow),
                      label: Text(
                        state.playing
                            ? l10n.metronomeStop
                            : l10n.metronomeStart,
                      ),
                      onPressed: state.togglePlaying,
                    ),
                    if (state.error case final error?) ...[
                      const SizedBox(height: 8),
                      Text(
                        error,
                        key: const Key('metronome-error'),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A light per beat of the bar, bigger for the accented ones, lit as it
/// clicks.
class _Lights extends StatelessWidget {
  const _Lights({required this.signature, required this.beat});

  final TimeSignature signature;
  final ValueListenable<int?> beat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accents = signature.accents;
    return ValueListenableBuilder(
      valueListenable: beat,
      builder: (context, now, _) => Wrap(
        key: const Key('metronome-lights'),
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < accents.length; i++)
            AnimatedContainer(
              key: Key('metronome-light-$i'),
              duration: const Duration(milliseconds: 60),
              width: switch (accents[i]) {
                Accent.bar => 22,
                Accent.group => 18,
                Accent.beat => 14,
              },
              height: switch (accents[i]) {
                Accent.bar => 22,
                Accent.group => 18,
                Accent.beat => 14,
              },
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: now == i
                    ? scheme.primary
                    : scheme.onSurfaceVariant.withValues(alpha: 0.25),
              ),
            ),
        ],
      ),
    );
  }
}
