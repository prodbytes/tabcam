import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../library/library.dart';
import '../library/capture_event.dart';
import '../l10n/language.dart';
import 'video_page.dart';

/// A recording's page: a card with a play / pause button, a scrubbable
/// progress bar and the time. It loads when first played (from the page's
/// file, or from memory on the web), and is let go when the page scrolls
/// away.
class AudioPage extends StatefulWidget {
  const AudioPage({
    super.key,
    required this.library,
    required this.event,
    required this.page,
  });

  final Library library;
  final CaptureEvent event;
  final EventPage page;

  @override
  State<AudioPage> createState() => _AudioPageState();
}

class _AudioPageState extends State<AudioPage> {
  VideoPlayerController? _controller;
  Object? _error;
  bool _loading = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _loading = true);
    try {
      final controller = await openPlayer(
        widget.library,
        widget.event,
        widget.page,
      );
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      await controller.play();
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final controller = _controller;
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _error != null ? Icons.error_outline : Icons.music_note,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                _error != null
                    ? l10n.textViewCantPlayAudio
                    : l10n.textViewAudio,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              if (_error == null) ...[
                const SizedBox(height: 16),
                if (controller != null)
                  _Controls(controller)
                else if (_loading)
                  const CircularProgressIndicator()
                else
                  IconButton.filled(
                    key: const Key('play-pause'),
                    iconSize: 40,
                    tooltip: l10n.textViewPlay,
                    icon: const Icon(Icons.play_arrow),
                    onPressed: _start,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Play / pause, the progress bar, and "0:12 / 3:04".
class _Controls extends StatelessWidget {
  const _Controls(this.controller);

  final VideoPlayerController controller;

  static String _time(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Row(
        children: [
          PlayPauseButton(controller, size: 40),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                ValueListenableBuilder(
                  valueListenable: controller,
                  builder: (context, value, _) => Text(
                    '${_time(value.position)} / ${_time(value.duration)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
