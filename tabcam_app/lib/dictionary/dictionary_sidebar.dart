/// The dictionary: a button at the top of every file viewer and Cam, and
/// the sidebar it opens on the right of the screen, as the play-along
/// player opens (or, turned by its Rotate button, the panel under the
/// screen), where the user types a chord, a scale or anything else.
/// A chord shows its notes and voicings, a scale its notes on the neck;
/// anything else is searched on YouTube (the one thing that leaves the
/// device): once typing stops for a couple of seconds, its results show
/// under the field ([YouTubeSearch]).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/language.dart';
import '../screens/link_page.dart';
import '../screens/sidebar_widths.dart';
import '../screens/split_handle.dart';
import 'diagrams.dart';
import 'music_theory.dart';
import 'voicings.dart';
import 'youtube_search.dart';

/// Whether the dictionary's sidebar shows, and what's typed in it,
/// app-wide: open on one screen, it's open on the next (the capture, a
/// file, Cam), with the same search.
class DictionaryState extends ChangeNotifier {
  DictionaryState._();

  /// The app's.
  static final DictionaryState instance = DictionaryState._();

  bool get open => _open;
  bool _open = false;

  /// What's typed in its field.
  String get query => _query;
  String _query = '';

  void toggle() {
    _open = !_open;
    notifyListeners();
  }

  void close() {
    if (!_open) return;
    _open = false;
    notifyListeners();
  }

  set query(String query) {
    if (query == _query) return;
    _query = query;
    notifyListeners();
  }

  /// Closed and empty (tests).
  @visibleForTesting
  void clear() {
    _open = false;
    _query = '';
    notifyListeners();
  }
}

/// The app bar's Dictionary button: shows or hides the dictionary's
/// sidebar ([DictionaryBeside]), in the primary colour while it shows;
/// [onClosed] after it hides (Cam takes its keys back).
class DictionaryButton extends StatelessWidget {
  const DictionaryButton({super.key, this.onClosed});

  final VoidCallback? onClosed;

  @override
  Widget build(BuildContext context) {
    final state = DictionaryState.instance;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final l10n = context.l10n;
        return IconButton(
          key: const Key('dictionary'),
          tooltip: state.open ? l10n.dictionaryHide : l10n.dictionary,
          isSelected: state.open,
          color: state.open ? Theme.of(context).colorScheme.primary : null,
          icon: const Icon(Icons.menu_book_outlined),
          onPressed: () {
            state.toggle();
            if (!state.open) onClosed?.call();
          },
        );
      },
    );
  }
}

/// YouTube's search for [query].
Uri youTubeSearch(String query) =>
    Uri.https('www.youtube.com', '/results', {'search_query': query.trim()});

/// [child], with the dictionary's sidebar on its right while it's open
/// ([DictionaryState]); its left edge is a separator to drag
/// ([SplitHandle]) to make it wider or narrower, the same on every screen
/// ([SidebarWidths]); a double tap puts its default width back. Turned by
/// its Rotate button ([SidebarWidths.isBelow]), it's a panel under
/// [child] instead, across the screen, its top edge the separator that
/// makes it taller or shorter.
class DictionaryBeside extends StatelessWidget {
  const DictionaryBeside({super.key, required this.child, this.onClosed});

  final Widget child;

  /// After the sidebar's own close button hides it.
  final VoidCallback? onClosed;

  /// The narrowest (or, over the panel, the shortest) [child] gets when
  /// the sidebar is dragged wider (taller).
  static const minChild = 96.0;

  /// The shortest the panel under the screen is dragged.
  static const minHeight = 120.0;

  /// What its search field's row takes: the panel keeps that much even
  /// where the screen is too short for [minChild] over it (a phone lying
  /// down with its keyboard up), so what's typed shows.
  static const fieldHeight = 64.0;

  /// The narrowest its content is laid out: narrower (a window with no
  /// room for it), the sidebar is cut, not squeezed.
  static const minContent = 160.0;

  /// The shortest the sidebar at the side is laid out (its title and its
  /// field), cut likewise.
  static const minSide = 112.0;

  /// Its default width on a screen [screen] wide: 40% of it, from 280 to
  /// 420 px.
  static double widthFor(double screen) => (screen * 0.4).clamp(280.0, 420.0);

  /// Its default height, under a screen [screen] tall: 40% of it, from
  /// 180 to 360 px.
  static double heightFor(double screen) => (screen * 0.4).clamp(180.0, 360.0);

  @override
  Widget build(BuildContext context) {
    final state = DictionaryState.instance;
    final widths = SidebarWidths.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([state, widths]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final below = widths.isBelow(SidebarWidths.dictionary);
          final sizeKey = below
              ? SidebarWidths.dictionaryHeight
              : SidebarWidths.dictionary;
          final least = below ? minHeight : SidebarWidths.min;
          final screen = MediaQuery.sizeOf(context);
          final room =
              (below ? box.maxHeight : box.maxWidth) - SplitHandle.thickness;
          final max = below
              ? math.max(room - minChild, math.min(room, fieldHeight))
              : room - minChild;
          final extent = widths.widthOf(
            sizeKey,
            fallback: below ? heightFor(screen.height) : widthFor(screen.width),
            max: max,
            least: least,
          );
          // Laid out no smaller than its header needs, and cut to its
          // place.
          final laidOut = math.max(extent, below ? fieldHeight : minContent);
          final tall = box.maxHeight < minSide ? minSide : null;
          // One Flex either way, so turning it keeps [child] (the camera,
          // what plays) and what the sidebar shows.
          return Flex(
            direction: below ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: child),
              if (state.open) ...[
                SplitHandle(
                  key: const Key('dictionary-split'),
                  axis: below ? Axis.vertical : Axis.horizontal,
                  // Dragged left (up), the sidebar on the right (the panel
                  // underneath) gets wider (taller).
                  onDrag: (d) => widths.set(
                    sizeKey,
                    (extent - d).clamp(least, max < least ? least : max),
                  ),
                  onDragEnd: widths.save,
                  onReset: () => widths.reset(sizeKey),
                ),
                SizedBox(
                  width: below ? null : extent,
                  height: below ? extent : null,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: below
                          ? Alignment.topCenter
                          : Alignment.topLeft,
                      minWidth: below ? null : laidOut,
                      maxWidth: below ? null : laidOut,
                      minHeight: below ? laidOut : tall,
                      maxHeight: below ? laidOut : tall,
                      child: DictionarySidebar(
                        below: below,
                        onRotate: () =>
                            widths.setBelow(SidebarWidths.dictionary, !below),
                        onClose: () {
                          state.close();
                          onClosed?.call();
                        },
                      ),
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

/// The dictionary's sidebar: its title, its Rotate button (to the panel
/// under the screen and back, [onRotate]) and close button, the search
/// field, and under it the chord, the scale, or YouTube's results for
/// what was typed ([DictionaryState.query]), searched once typing stops
/// for [YouTubeSearch.wait]. [below] (the panel), the field and the
/// buttons share one row, and a chord's or a scale's neck lies down
/// beside its name.
class DictionarySidebar extends StatefulWidget {
  const DictionarySidebar({
    super.key,
    required this.onClose,
    this.onRotate,
    this.below = false,
  });

  final VoidCallback onClose;

  /// Turns it: to the panel under the screen, or back to the side. Null,
  /// it has no Rotate button.
  final VoidCallback? onRotate;

  /// Whether it's the panel under the screen.
  final bool below;

  @override
  State<DictionarySidebar> createState() => _DictionarySidebarState();
}

class _DictionarySidebarState extends State<DictionarySidebar> {
  final _state = DictionaryState.instance;
  late final _controller = TextEditingController(text: _state.query);

  /// The field's: turned (its row changes), it keeps the keyboard.
  final _focus = FocusNode();
  Lookup _lookup = const Other();
  List<Voicing> _voicings = const [];

  /// YouTube's results for what's typed, while it's not a chord or a
  /// scale: null until they come.
  List<YouTubeVideo>? _videos;
  bool _searching = false;
  bool _failed = false;

  /// Until typing has stopped for [YouTubeSearch.wait].
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    _read(_state.query);
  }

  @override
  void dispose() {
    _wait?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _read(String query) {
    _state.query = query;
    final lookup = Lookup.of(query);
    _wait?.cancel();
    final youTube = YouTubeSearch.instance;
    final searches =
        lookup is Other && query.trim().isNotEmpty && youTube.available;
    final cached = searches ? youTube.cached(query) : null;
    setState(() {
      _lookup = lookup;
      _voicings = switch (lookup) {
        ChordLookup(:final chord) => voicingsOf(chord),
        _ => const [],
      };
      _videos = cached;
      _searching = searches && cached == null;
      _failed = false;
    });
    if (_searching) {
      _wait = Timer(YouTubeSearch.wait, () => _searchYouTube(query));
    }
  }

  Future<void> _searchYouTube(String query) async {
    _wait?.cancel();
    List<YouTubeVideo>? videos;
    try {
      videos = await YouTubeSearch.instance.search(query);
    } on YouTubeSearchFailed {
      videos = null;
    }
    // Typed on meanwhile: those results are for another search.
    if (!mounted || _controller.text != query) return;
    setState(() {
      _videos = videos;
      _searching = false;
      _failed = videos == null;
    });
  }

  void _set(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _read(query);
  }

  /// Enter: a song (anything that's not a chord or a scale) is searched
  /// on YouTube now, without the wait; in a build that can't search, it
  /// opens YouTube's search.
  void _submit(String query) {
    if (_lookup is! Other || query.trim().isEmpty) return;
    if (!YouTubeSearch.instance.available) {
      openLink(context, youTubeSearch(query));
    } else if (_searching && _wait!.isActive) {
      _searchYouTube(query);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final query = _controller.text;
    final below = widget.below;
    final field = TextField(
      key: const Key('dictionary-query'),
      controller: _controller,
      focusNode: _focus,
      autofocus: true,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        isDense: true,
        hintText: l10n.dictionaryHint,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => _set(''),
              ),
        border: const OutlineInputBorder(),
      ),
      onChanged: _read,
      onSubmitted: _submit,
    );
    final buttons = [
      if (widget.onRotate case final rotate?)
        IconButton(
          key: const Key('dictionary-rotate'),
          tooltip: below ? l10n.dictionaryToSide : l10n.dictionaryToBottom,
          icon: Icon(
            below
                ? Icons.rotate_90_degrees_ccw_outlined
                : Icons.rotate_90_degrees_cw_outlined,
          ),
          onPressed: rotate,
        ),
      IconButton(
        key: const Key('dictionary-close'),
        tooltip: l10n.dictionaryHide,
        icon: const Icon(Icons.close),
        onPressed: widget.onClose,
      ),
    ];
    final book = Icon(
      Icons.menu_book_outlined,
      size: 18,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Material(
      key: const Key('dictionary-sidebar'),
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (below)
            // One row, to leave the panel's height to what it shows.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 4, 0),
              child: Row(
                children: [
                  book,
                  const SizedBox(width: 8),
                  Expanded(child: field),
                  ...buttons,
                ],
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
              child: Row(
                children: [
                  book,
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.dictionary,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ...buttons,
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: field,
            ),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                // What the panel leaves a neck lying in it.
                final room = below ? box.maxHeight - 24 : null;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: switch (_lookup) {
                    ChordLookup(:final chord) => _ChordResult(
                      chord: chord,
                      voicings: _voicings,
                      below: below,
                    ),
                    ScaleLookup(:final scale) => _ScaleResult(
                      scale: scale,
                      below: below,
                      room: room,
                    ),
                    Other() when query.trim().isEmpty => _Intro(
                      onExample: _set,
                    ),
                    Other() => _YouTubeResult(
                      query: query,
                      videos: _videos,
                      searching: _searching,
                      failed: _failed,
                    ),
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// What the dictionary does, and examples to tap.
class _Intro extends StatelessWidget {
  const _Intro({required this.onExample});

  final ValueChanged<String> onExample;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.dictionaryIntro),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final example in const [
              'C',
              'Am7',
              'F#m7b5',
              'G/B',
              'A minor pentatonic',
              'E blues',
              'D dorian',
            ])
              ActionChip(
                label: Text(example),
                onPressed: () => onExample(example),
              ),
          ],
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({
    required this.title,
    required this.kind,
    required this.notes,
    required this.degrees,
  });

  final String title;
  final String kind;
  final List<Note> notes;
  final List<Degree> degrees;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          '$kind · ${notes.map((n) => n.name).join('  ')}',
          style: theme.textTheme.bodyLarge,
        ),
        Text(
          degrees.map((d) => d.label).join('  '),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// A result's [heading] and, under it, its [picture]; in the panel under
/// the screen ([below]) wide enough for both, the picture is beside the
/// heading instead, so a short panel shows it without scrolling.
class _Result extends StatelessWidget {
  const _Result({
    super.key,
    required this.heading,
    required this.picture,
    required this.below,
  });

  final Widget heading;
  final Widget picture;
  final bool below;

  /// Narrower than this, the picture goes under the heading in the panel
  /// too (a phone held up).
  static const beside = 560.0;

  /// The heading's width beside the picture.
  static const headingWidth = 220.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        if (below && box.maxWidth >= beside) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: headingWidth, child: heading),
              const SizedBox(width: 16),
              Expanded(child: picture),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [heading, const SizedBox(height: 16), picture],
        );
      },
    );
  }
}

class _ChordResult extends StatelessWidget {
  const _ChordResult({
    required this.chord,
    required this.voicings,
    required this.below,
  });

  final Chord chord;
  final List<Voicing> voicings;
  final bool below;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Result(
      key: const Key('dictionary-chord'),
      below: below,
      heading: _Heading(
        title: chord.name,
        kind: l10n.dictionaryChord,
        notes: chord.notes,
        degrees: chord.quality.degrees,
      ),
      picture: voicings.isEmpty
          ? Text(l10n.dictionaryNoVoicings)
          : Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final v in voicings)
                  ChordDiagram(chord: chord, voicing: v, lying: below),
              ],
            ),
    );
  }
}

class _ScaleResult extends StatelessWidget {
  const _ScaleResult({required this.scale, required this.below, this.room});

  final Scale scale;
  final bool below;

  /// In the panel, the height it leaves the neck.
  final double? room;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Result(
      key: const Key('dictionary-scale'),
      below: below,
      heading: _Heading(
        title: '${scale.root.name} ${scaleTypeName(l10n, scale.type)}',
        kind: l10n.dictionaryScale,
        notes: scale.notes,
        degrees: scale.type.degrees,
      ),
      picture: ScaleFretboard(scale: scale, lying: below, maxHeight: room),
    );
  }
}

/// Not a chord or a scale: the button to YouTube's search and, under it,
/// the videos it found ([videos]), each opening in a new tab.
class _YouTubeResult extends StatelessWidget {
  const _YouTubeResult({
    required this.query,
    required this.videos,
    required this.searching,
    required this.failed,
  });

  final String query;
  final List<YouTubeVideo>? videos;
  final bool searching;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final videos = this.videos;
    return Column(
      key: const Key('dictionary-youtube'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.dictionaryYouTube(query.trim())),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('dictionary-search-youtube'),
          icon: const Icon(Icons.open_in_new),
          label: Text(l10n.dictionarySearchYouTube),
          onPressed: () => openLink(context, youTubeSearch(query)),
        ),
        if (searching) ...[
          const SizedBox(height: 16),
          Text(l10n.dictionaryYouTubeSearching, style: muted),
          const SizedBox(height: 8),
          const LinearProgressIndicator(
            key: Key('dictionary-youtube-searching'),
          ),
        ] else if (failed) ...[
          const SizedBox(height: 16),
          Text(l10n.dictionaryYouTubeFailed, style: muted),
        ] else if (videos != null && videos.isEmpty) ...[
          const SizedBox(height: 16),
          Text(l10n.dictionaryYouTubeNone, style: muted),
        ] else if (videos != null) ...[
          const SizedBox(height: 12),
          for (final video in videos) _VideoTile(video: video),
        ],
      ],
    );
  }
}

/// One of YouTube's results: its thumbnail, title and channel; a tap
/// opens it outside the app (a new tab on the web).
class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.video});

  final YouTubeVideo video;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumbnail = video.thumbnail;
    return Tooltip(
      message: context.l10n.dictionaryYouTubeOpen,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        key: Key('dictionary-video-${video.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => openLink(context, video.url),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: LayoutBuilder(
            builder: (context, box) {
              // A third of the sidebar, from 72 to 160 px.
              final width = (box.maxWidth * 0.36).clamp(72.0, 160.0);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: width,
                      height: width * 9 / 16,
                      child: ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: thumbnail == null
                            ? const Icon(Icons.smart_display_outlined)
                            : Image.network(
                                '$thumbnail',
                                fit: BoxFit.cover,
                                webHtmlElementStrategy:
                                    WebHtmlElementStrategy.fallback,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.smart_display_outlined),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          video.channel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.open_in_new,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// [type]'s name in the app's language.
String scaleTypeName(AppLocalizations l10n, ScaleType type) =>
    switch (type.key) {
      'major' => l10n.dictionaryScaleMajor,
      'minor' => l10n.dictionaryScaleMinor,
      'harmonic minor' => l10n.dictionaryScaleHarmonicMinor,
      'melodic minor' => l10n.dictionaryScaleMelodicMinor,
      'major pentatonic' => l10n.dictionaryScaleMajorPentatonic,
      'minor pentatonic' => l10n.dictionaryScaleMinorPentatonic,
      'blues' => l10n.dictionaryScaleBlues,
      'major blues' => l10n.dictionaryScaleMajorBlues,
      'dorian' => l10n.dictionaryScaleDorian,
      'phrygian' => l10n.dictionaryScalePhrygian,
      'lydian' => l10n.dictionaryScaleLydian,
      'mixolydian' => l10n.dictionaryScaleMixolydian,
      'locrian' => l10n.dictionaryScaleLocrian,
      'phrygian dominant' => l10n.dictionaryScalePhrygianDominant,
      'lydian dominant' => l10n.dictionaryScaleLydianDominant,
      'harmonic major' => l10n.dictionaryScaleHarmonicMajor,
      'double harmonic' => l10n.dictionaryScaleDoubleHarmonic,
      'whole tone' => l10n.dictionaryScaleWholeTone,
      'diminished' => l10n.dictionaryScaleDiminished,
      'dominant diminished' => l10n.dictionaryScaleDominantDiminished,
      'chromatic' => l10n.dictionaryScaleChromatic,
      _ => type.key,
    };
