import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../l10n/language.dart';
import '../screens/mono_font.dart';
import 'cam_session.dart';
import 'level_meter.dart';
import 'take_recorder.dart';

/// What Cam says for [note] ([CamSession.onNote]), in [l10n]'s language,
/// with its [detail] (a take's name, why it failed) where it has one.
String camNoteText(AppLocalizations l10n, CamNote note, [String? detail]) {
  final d = detail ?? '';
  return switch (note) {
    CamNote.noSound => l10n.camNoSound,
    CamNote.couldntRecord => l10n.camCouldntRecord(d),
    CamNote.micFailed => l10n.camMicFailed(d),
    CamNote.discarded => l10n.camTakeDiscarded,
    CamNote.saved => l10n.camSaved(d),
    CamNote.takeNoSound => l10n.camTakeNoSound(d),
    CamNote.soundWarning => l10n.camTakeSoundWarning(d),
    CamNote.notH264 => l10n.camTakeNotH264(d),
    CamNote.cantPlay => l10n.textViewCantPlay,
  };
}

// The widgets below show a [CamSession]; the screen that has them rebuilds
// them as the session changes (it listens to it).

/// Cam's view: the camera (or why it didn't open, with Try again), the
/// take playing back in its place, and, on iOS, a card while the take
/// just recorded is made H.264.
class CamView extends StatelessWidget {
  const CamView({super.key, required this.cam});

  final CamSession cam;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(child: _view(context)),
        if (cam.converting)
          Card(
            color: Colors.black87,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  // Wraps where the camera is narrow (the sidebar beside
                  // it).
                  Flexible(
                    child: Text(
                      l10n.camConvertingTake,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _view(BuildContext context) {
    final player = cam.player;
    if (player != null) {
      return AspectRatio(
        aspectRatio: player.value.aspectRatio,
        child: VideoPlayer(player),
      );
    }
    return switch ((cam.error, cam.controller)) {
      (final error?, _) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: Colors.white70,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            // Once the other app lets go of the camera, say.
            if (!cam.gated) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                key: const Key('cam-try-again'),
                onPressed: cam.tryAgain,
                child: Text(context.l10n.camTryAgain),
              ),
            ],
          ],
        ),
      ),
      (_, final controller?) => CameraPreview(controller),
      _ when cam.gated => const Icon(
        key: Key('cam-preview'),
        Icons.videocam_outlined,
        color: Colors.white24,
        size: 96,
      ),
      _ => const CircularProgressIndicator(),
    };
  }
}

/// The tab, one phrase (neckline) at a time, along the bottom: a tap
/// passes to the next, the arrows beside it to either side.
class CamPhrase extends StatelessWidget {
  const CamPhrase({super.key, required this.cam});

  final CamSession cam;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Colors.black87, child: _phrase(context));

  Widget _phrase(BuildContext context) {
    final l10n = context.l10n;
    const color = Colors.white;
    final lines = cam.lines;
    final line = cam.line;
    // A take playing back shows its own neckline where the capture's tab
    // no longer has it.
    final played = cam.playedLine;
    if (lines.isEmpty && played == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          l10n.camNoTab,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    return Row(
      children: [
        IconButton(
          tooltip: l10n.camPrevious,
          color: color,
          disabledColor: Colors.white24,
          icon: const Icon(Icons.chevron_left),
          onPressed: line > 0 ? () => unawaited(cam.pass(-1)) : null,
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(cam.pass(1)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // As wide as the screen: a long staff shrinks to fit.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      played ?? lines[line],
                      key: const Key('neckline'),
                      softWrap: false,
                      style: const TextStyle(
                        fontFamily: monoFont,
                        color: color,
                        fontSize: 18,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (played == null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${line + 1} / ${lines.length}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: l10n.camNext,
          color: color,
          disabledColor: Colors.white24,
          icon: const Icon(Icons.chevron_right),
          onPressed: line < lines.length - 1
              ? () => unawaited(cam.pass(1))
              : null,
        ),
      ],
    );
  }
}

/// Cam's controls, along the bottom: Rec (with the microphone's level
/// beside it, tapped for the input volume, and an arrow for the
/// microphone), Play, Tab and Auto-pass, in [foreground] (white, on
/// black, by default; the theme's on its surface in the view's dock).
/// [onUse] runs after a tap that leaves the keys elsewhere (the screen
/// takes them back).
class CamStrip extends StatelessWidget {
  const CamStrip({
    super.key,
    required this.cam,
    required this.onUse,
    this.foreground = Colors.white,
  });

  final CamSession cam;
  final VoidCallback onUse;

  /// The colour of its icons and names (Rec stays red, Auto-pass on the
  /// primary colour).
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final playing = cam.player != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _Control(
              key: const Key('cam-rec'),
              icon: cam.recording ? Icons.stop : Icons.fiber_manual_record,
              color: Colors.red,
              foreground: foreground,
              label: cam.recording ? l10n.camStop : l10n.camRec,
              tooltip: cam.recording ? l10n.camStopKey : l10n.camRecKey,
              onPressed: cam.canRec ? cam.rec : null,
              menu: cam.micChoosable
                  ? (
                      key: const Key('cam-rec-device'),
                      tooltip: l10n.camMicChoose,
                      onPressed: cam.canChooseMic
                          ? (anchor) => _micMenu(context, anchor)
                          : null,
                    )
                  : null,
              meter: switch (cam.level) {
                // Tapped, the input volume's menu.
                final read? => Builder(
                  builder: (anchor) => InkResponse(
                    key: const Key('cam-rec-gain'),
                    radius: 18,
                    onTap: cam.canSetGain
                        ? () => _gainMenu(context, anchor)
                        : null,
                    child: Padding(
                      // As tall as Rec, and the arrow's width.
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: LevelMeter(
                        key: const Key('cam-rec-level'),
                        read: read,
                        tooltip: l10n.camMicLevel,
                      ),
                    ),
                  ),
                ),
                null => null,
              },
            ),
            // The . and / keys' buttons: the next take with the song back
            // at its start, after its count-in ([CamSession.nextTake]).
            // Redo throws the take recording away, so it's only on while
            // one records; New take keeps it (not recording, it starts a
            // take with the song from its start).
            _Control(
              key: const Key('cam-redo'),
              icon: Icons.replay,
              color: foreground,
              foreground: foreground,
              label: l10n.camRedo,
              tooltip: l10n.camRedoTip,
              onPressed: cam.recording && cam.canRec
                  ? () {
                      unawaited(cam.nextTake(keep: false));
                      onUse();
                    }
                  : null,
            ),
            _Control(
              key: const Key('cam-new-take'),
              icon: Icons.video_call_outlined,
              color: foreground,
              foreground: foreground,
              label: l10n.camNewTake,
              tooltip: cam.recording
                  ? l10n.camNewTakeTip
                  : l10n.camNewTakeIdleTip,
              onPressed: cam.canRec
                  ? () {
                      unawaited(cam.nextTake());
                      onUse();
                    }
                  : null,
            ),
            _Control(
              key: const Key('cam-play'),
              // Opening: Stop lets it go.
              icon: playing || cam.opening ? Icons.stop : Icons.play_arrow,
              color: foreground,
              foreground: foreground,
              label: playing || cam.opening ? l10n.camStop : l10n.camPlay,
              onPressed:
                  cam.take == null ||
                      cam.recording ||
                      cam.saving ||
                      cam.nextTaking
                  ? null
                  : cam.play,
            ),
            _Control(
              key: const Key('cam-tab'),
              icon: cam.tabShown ? Icons.subtitles : Icons.subtitles_off,
              color: foreground,
              foreground: foreground,
              label: cam.tabShown ? l10n.camHideTab : l10n.camShowTab,
              onPressed: () {
                cam.toggleTab();
                onUse();
              },
            ),
            _Control(
              key: const Key('cam-auto-pass'),
              icon: cam.autoPassOn ? Icons.auto_mode : Icons.motion_photos_off,
              color: cam.autoPassOn
                  ? Theme.of(context).colorScheme.primary
                  : foreground,
              foreground: foreground,
              label: l10n.camAutoPass,
              tooltip: cam.autoPassOn
                  ? l10n.camAutoPassOn
                  : l10n.camAutoPassOff,
              onPressed: cam.gated
                  ? null
                  : () {
                      unawaited(cam.toggleAutoPass());
                      onUse();
                    },
            ),
          ],
        ),
      ),
    );
  }

  /// [db] as the level meter's menu shows it: +6, 0, −6.
  static String _dbText(int db) => switch (db) {
    > 0 => '+$db',
    < 0 => '−${-db}',
    _ => '0',
  };

  /// Where a menu opens by [anchor].
  static RelativeRect _menuPosition(BuildContext anchor) {
    final box = anchor.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(anchor).context.findRenderObject()! as RenderBox;
    return RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
  }

  /// The level meter's menu (the meter tapped, [anchor]): the input
  /// volume, in dB, and a slider to set it, up louder, down quieter, from
  /// -[CamSession.maxGainDb] to +[CamSession.maxGainDb] dB; Reset puts it
  /// back to 0 dB (as the microphone gives it). It changes as the slider
  /// moves (the meter shows it at once), and is kept in Cam's settings.
  Future<void> _gainMenu(BuildContext context, BuildContext anchor) async {
    if (!cam.canSetGain) return;
    final l10n = context.l10n;
    final was = cam.gainDb;
    await showMenu<void>(
      context: context,
      position: _menuPosition(anchor),
      items: [
        PopupMenuItem(enabled: false, height: 32, child: Text(l10n.camMicGain)),
        _GainEntry(
          db: cam.gainDb,
          max: CamSession.maxGainDb,
          label: (db) => l10n.camMicGainDb(_dbText(db)),
          reset: l10n.camMicGainReset,
          onChanged: cam.setGainDb,
        ),
      ],
    );
    onUse();
    if (!cam.disposed && cam.gainDb != was) unawaited(cam.saveSettings());
  }

  /// [mic]'s name in Rec's menu, the [n]th listed.
  static String _micName(AppLocalizations l10n, TakeMic mic, int n) {
    if (mic.builtIn) {
      return mic.name.isEmpty
          ? l10n.camMicBuiltIn
          : '${l10n.camMicBuiltIn} (${mic.name})';
    }
    return mic.name.isEmpty ? l10n.camMicUnnamed(n) : mic.name;
  }

  /// Rec's menu (its arrow, [anchor]): the microphones takes can record
  /// from, the default first, the one they record from checked. Picking
  /// another opens it, for the takes from now on, and keeps it in Cam's
  /// settings; one that won't open leaves the default open, and says so.
  Future<void> _micMenu(BuildContext context, BuildContext anchor) async {
    if (!cam.canChooseMic) return;
    final mics = await cam.microphones();
    if (!context.mounted || !anchor.mounted || !cam.canChooseMic) return;
    final l10n = context.l10n;
    final position = _menuPosition(anchor);
    final current = cam.mic;
    final chosen = mics.any((m) => m.id == current) ? current : null;
    final picked = await showMenu<({String? id})>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          enabled: false,
          height: 32,
          child: Text(l10n.camMicHeading),
        ),
        CheckedPopupMenuItem(
          key: const Key('cam-mic-default'),
          value: (id: null),
          checked: chosen == null,
          child: Text(l10n.camMicDefault),
        ),
        for (final (i, mic) in mics.indexed)
          CheckedPopupMenuItem(
            key: Key('cam-mic-${mic.id}'),
            value: (id: mic.id),
            checked: chosen == mic.id,
            child: Text(
              _micName(l10n, mic, i + 1),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
    onUse();
    if (picked == null || !context.mounted) return;
    if (picked.id == chosen && picked.id == cam.mic) return;
    await cam.chooseMic(
      picked.id,
      picked.id == null
          ? l10n.camMicDefault
          : _micName(
              l10n,
              mics.firstWhere((m) => m.id == picked.id),
              mics.indexWhere((m) => m.id == picked.id) + 1,
            ),
    );
  }
}

/// The input volume in the level meter's menu ([CamStrip._gainMenu]):
/// what it is ([label] of the dB), over a slider from -[max] to +[max] dB,
/// up louder, and [reset] to 0 dB. Each change goes to [onChanged] as the
/// slider moves.
class _GainEntry extends PopupMenuEntry<Never> {
  const _GainEntry({
    required this.db,
    required this.max,
    required this.label,
    required this.reset,
    required this.onChanged,
  });

  final int db;
  final int max;
  final String Function(int db) label;
  final String reset;
  final ValueChanged<int> onChanged;

  @override
  double get height => 240;

  @override
  bool represents(Never? value) => false;

  @override
  State<_GainEntry> createState() => _GainEntryState();
}

class _GainEntryState extends State<_GainEntry> {
  late int _db = widget.db;

  void _set(int db) {
    if (db == _db) return;
    setState(() => _db = db);
    widget.onChanged(db);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label(_db),
          key: const Key('cam-gain-value'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SizedBox(
          height: 160,
          // Upright: up, louder.
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              key: const Key('cam-gain'),
              value: _db.toDouble(),
              min: -widget.max.toDouble(),
              max: widget.max.toDouble(),
              divisions: widget.max * 2,
              semanticFormatterCallback: (v) => widget.label(v.round()),
              onChanged: (v) => _set(v.round()),
            ),
          ),
        ),
        TextButton(
          key: const Key('cam-gain-reset'),
          onPressed: _db == 0 ? null : () => _set(0),
          child: Text(widget.reset),
        ),
      ],
    ),
  );
}

/// Rec, Play, Tab or Auto-pass: an icon over its label, in [foreground]
/// (dimmed while it can't be pressed); Rec with an arrow beside it for
/// its [menu] (the microphone), and the microphone's level ([meter]) on
/// its other side.
class _Control extends StatelessWidget {
  const _Control({
    super.key,
    required this.icon,
    required this.color,
    required this.foreground,
    required this.label,
    this.tooltip,
    this.onPressed,
    this.menu,
    this.meter,
  });

  final IconData icon;
  final Color color;
  final Color foreground;
  final String label;

  /// What its tooltip says; null: its [label].
  final String? tooltip;
  final VoidCallback? onPressed;

  /// The arrow's key, tooltip and what it opens, given where the arrow is
  /// (to open the menu by it); null: no arrow.
  final ({
    Key key,
    String tooltip,
    void Function(BuildContext anchor)? onPressed,
  })?
  menu;

  /// The level meter, left of the button (with a [menu] only); null: a
  /// space as wide as the arrow.
  final Widget? meter;

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null;
    final button = IconButton(
      tooltip: tooltip ?? label,
      iconSize: 36,
      color: color,
      disabledColor: foreground.withValues(alpha: 0.24),
      icon: Icon(icon),
      onPressed: onPressed,
    );
    // Narrow (a PDF beside the camera), the labels shorten, not overflow.
    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (menu case final menu?)
            // Narrow, the two shrink together rather than overflow.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // As wide as the arrow, so Rec stays over its label.
                  SizedBox(width: 28, child: Center(child: meter)),
                  button,
                  Builder(
                    builder: (anchor) => IconButton(
                      key: menu.key,
                      tooltip: menu.tooltip,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 48,
                      ),
                      padding: EdgeInsets.zero,
                      iconSize: 24,
                      color: foreground,
                      disabledColor: foreground.withValues(alpha: 0.24),
                      icon: const Icon(Icons.expand_less),
                      onPressed: switch (menu.onPressed) {
                        final open? => () => open(anchor),
                        null => null,
                      },
                    ),
                  ),
                ],
              ),
            )
          else
            button,
          _Label(
            label,
            style: TextStyle(
              color: on ? foreground : foreground.withValues(alpha: 0.38),
            ),
          ),
        ],
      ),
    );
  }
}

/// A control's name, on one line: at its size where it fits, else
/// smaller, down to [least] of it (six controls share a small phone's
/// width), and only then cut short.
class _Label extends StatelessWidget {
  const _Label(this.text, {required this.style});

  final String text;
  final TextStyle style;

  /// The smallest it gets before it's cut short.
  static const least = 0.8;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final base = DefaultTextStyle.of(context).style.merge(style);
      var scale = 1.0;
      if (box.hasBoundedWidth) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: base),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final width = painter.width;
        painter.dispose();
        if (width > box.maxWidth) {
          scale = math.max(least, (box.maxWidth - 0.5) / width);
        }
      }
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: base.copyWith(fontSize: (base.fontSize ?? 14) * scale),
      );
    },
  );
}
