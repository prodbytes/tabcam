/// The dictionary: a button at the top of every file viewer and Cam, and
/// the sidebar it opens on the right of the screen, as the play-along
/// player opens, where the user types a chord, a scale or anything else.
/// A chord shows its notes and voicings, a scale its notes on the neck;
/// anything else is searched on YouTube (the one thing that leaves the
/// device).
library;

import 'package:flutter/material.dart';

import '../l10n/language.dart';
import '../screens/link_page.dart';
import '../screens/sidebar_widths.dart';
import '../screens/split_handle.dart';
import 'diagrams.dart';
import 'music_theory.dart';
import 'voicings.dart';

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
/// ([SidebarWidths]); a double tap puts its default width back.
class DictionaryBeside extends StatelessWidget {
  const DictionaryBeside({super.key, required this.child, this.onClosed});

  final Widget child;

  /// After the sidebar's own close button hides it.
  final VoidCallback? onClosed;

  /// The narrowest [child] gets when the sidebar is dragged wider.
  static const minChild = 96.0;

  /// Its default width on a screen [screen] wide: 40% of it, from 280 to
  /// 420 px.
  static double widthFor(double screen) => (screen * 0.4).clamp(280.0, 420.0);

  @override
  Widget build(BuildContext context) {
    final state = DictionaryState.instance;
    final widths = SidebarWidths.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([state, widths]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final max = box.maxWidth - minChild - SplitHandle.thickness;
          final width = widths.widthOf(
            SidebarWidths.dictionary,
            fallback: widthFor(MediaQuery.sizeOf(context).width),
            max: max,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: child),
              if (state.open) ...[
                SplitHandle(
                  key: const Key('dictionary-split'),
                  axis: Axis.horizontal,
                  // Dragged left, the sidebar (on the right) gets wider.
                  onDrag: (dx) => widths.set(
                    SidebarWidths.dictionary,
                    (width - dx).clamp(
                      SidebarWidths.min,
                      max < SidebarWidths.min ? SidebarWidths.min : max,
                    ),
                  ),
                  onDragEnd: widths.save,
                  onReset: () => widths.reset(SidebarWidths.dictionary),
                ),
                SizedBox(
                  width: width,
                  child: DictionarySidebar(
                    onClose: () {
                      state.close();
                      onClosed?.call();
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

/// The dictionary's sidebar: its title and close button, the search
/// field, and under it the chord, the scale, or the YouTube search for
/// what was typed ([DictionaryState.query]).
class DictionarySidebar extends StatefulWidget {
  const DictionarySidebar({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<DictionarySidebar> createState() => _DictionarySidebarState();
}

class _DictionarySidebarState extends State<DictionarySidebar> {
  final _state = DictionaryState.instance;
  late final _controller = TextEditingController(text: _state.query);
  Lookup _lookup = const Other();
  List<Voicing> _voicings = const [];

  @override
  void initState() {
    super.initState();
    _read(_state.query);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _read(String query) {
    _state.query = query;
    final lookup = Lookup.of(query);
    setState(() {
      _lookup = lookup;
      _voicings = switch (lookup) {
        ChordLookup(:final chord) => voicingsOf(chord),
        _ => const [],
      };
    });
  }

  void _set(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _read(query);
  }

  /// Enter: a song (anything that's not a chord or a scale) goes to
  /// YouTube.
  void _submit(String query) {
    if (_lookup is Other && query.trim().isNotEmpty) {
      openLink(context, youTubeSearch(query));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final query = _controller.text;
    return Material(
      key: const Key('dictionary-sidebar'),
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
            child: Row(
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.dictionary,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  key: const Key('dictionary-close'),
                  tooltip: l10n.dictionaryHide,
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: TextField(
              key: const Key('dictionary-query'),
              controller: _controller,
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
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: switch (_lookup) {
                ChordLookup(:final chord) => _ChordResult(
                  chord: chord,
                  voicings: _voicings,
                ),
                ScaleLookup(:final scale) => _ScaleResult(scale: scale),
                Other() when query.trim().isEmpty => _Intro(onExample: _set),
                Other() => _YouTubeResult(query: query),
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

class _ChordResult extends StatelessWidget {
  const _ChordResult({required this.chord, required this.voicings});

  final Chord chord;
  final List<Voicing> voicings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      key: const Key('dictionary-chord'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(
          title: chord.name,
          kind: l10n.dictionaryChord,
          notes: chord.notes,
          degrees: chord.quality.degrees,
        ),
        const SizedBox(height: 16),
        if (voicings.isEmpty)
          Text(l10n.dictionaryNoVoicings)
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final v in voicings) ChordDiagram(chord: chord, voicing: v),
            ],
          ),
      ],
    );
  }
}

class _ScaleResult extends StatelessWidget {
  const _ScaleResult({required this.scale});

  final Scale scale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      key: const Key('dictionary-scale'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(
          title: '${scale.root.name} ${scaleTypeName(l10n, scale.type)}',
          kind: l10n.dictionaryScale,
          notes: scale.notes,
          degrees: scale.type.degrees,
        ),
        const SizedBox(height: 16),
        ScaleFretboard(scale: scale),
      ],
    );
  }
}

class _YouTubeResult extends StatelessWidget {
  const _YouTubeResult({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
      ],
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
