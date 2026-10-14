import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../l10n/language.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import 'video_page.dart';

/// Plays a capture's videos and recordings right from its file list, one
/// at a time: playing another stops the one playing.
class ListPlayer extends ChangeNotifier {
  ListPlayer(this.library);

  final Library library;

  /// The file playing (or paused), and its player once it's loaded.
  String? get pageId => _pageId;
  String? _pageId;
  VideoPlayerController? get controller => _controller;
  VideoPlayerController? _controller;

  /// Whether [pageId]'s file is being loaded.
  bool get loading => _loading;
  bool _loading = false;

  /// What failed, for the file that couldn't play.
  Object? get error => _error;
  Object? _error;

  bool _disposed = false;

  /// Whether [page] is the one this player holds.
  bool holds(EventPage page) => _pageId == page.id;

  /// Plays [page] (stopping any other), or pauses and resumes it.
  Future<void> toggle(CaptureEvent event, EventPage page) async {
    final current = _controller;
    if (holds(page) && current != null) {
      if (current.value.isPlaying) return current.pause();
      final v = current.value;
      if (v.duration > Duration.zero && v.position >= v.duration) {
        await current.seekTo(Duration.zero);
      }
      return current.play();
    }
    if (holds(page) && _loading) return;
    await stop();
    _pageId = page.id;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final controller = await openPlayer(library, event, page);
      if (_disposed || _pageId != page.id) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      await controller.play();
    } on Object catch (e) {
      debugPrint('TabScan: ${page.fileName} can\'t play here: $e');
      if (_pageId == page.id) _error = e;
    } finally {
      if (_pageId == page.id) _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Stops and lets go of what's playing.
  Future<void> stop() async {
    final controller = _controller;
    _controller = null;
    _pageId = null;
    _loading = false;
    _error = null;
    if (!_disposed) notifyListeners();
    await controller?.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }
}

/// A video's or recording's play / pause button in the file list.
class MiniPlayButton extends StatelessWidget {
  const MiniPlayButton({
    super.key,
    required this.player,
    required this.event,
    required this.page,
  });

  final ListPlayer player;
  final CaptureEvent event;
  final EventPage page;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final controller = player.holds(page) ? player.controller : null;
        if (player.holds(page) && player.loading) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        Widget button(bool playing) => IconButton.filledTonal(
          key: ValueKey('mini-play-${page.id}'),
          tooltip: playing ? l10n.textViewPause : l10n.textViewPlay,
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          onPressed: () => player.toggle(event, page),
        );
        if (controller == null) return button(false);
        return ValueListenableBuilder(
          valueListenable: controller,
          builder: (context, value, _) => button(value.isPlaying),
        );
      },
    );
  }
}

/// Under the file's name while it plays in the list: a progress bar to
/// scrub, and the time ("0:12 / 3:04"); or that it can't play here.
class MiniProgress extends StatelessWidget {
  const MiniProgress({super.key, required this.player, required this.page});

  final ListPlayer player;
  final EventPage page;

  static String _time(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: player,
    builder: (context, _) {
      if (!player.holds(page)) return const SizedBox.shrink();
      if (player.error != null) {
        return Text(
          page.kind == PageKind.audio
              ? context.l10n.textViewCantPlayAudio
              : context.l10n.textViewCantPlay,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        );
      }
      final controller = player.controller;
      if (controller == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Expanded(
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder(
              valueListenable: controller,
              builder: (context, value, _) => Text(
                '${_time(value.position)} / ${_time(value.duration)}',
                key: ValueKey('mini-time-${page.id}'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// A video playing in the list, in place of its thumbnail; [thumbnail]
/// otherwise.
class MiniVideo extends StatelessWidget {
  const MiniVideo({
    super.key,
    required this.player,
    required this.page,
    required this.thumbnail,
  });

  final ListPlayer player;
  final EventPage page;
  final Widget thumbnail;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: player,
    builder: (context, _) {
      final controller = player.holds(page) ? player.controller : null;
      final size = controller?.value.size;
      if (controller == null || size == null || size.isEmpty) return thumbnail;
      return SizedBox.square(
        dimension: fileThumbnailSize,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ColoredBox(
            color: Colors.black,
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// The side of a file's thumbnail in its capture's list.
const double fileThumbnailSize = 80;
