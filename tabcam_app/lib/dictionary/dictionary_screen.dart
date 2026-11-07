/// The dictionary: a button at the top of every file viewer and Cam, and
/// the screen it opens, where the user types a chord, a scale or
/// anything else. A chord shows its notes and voicings, a scale its
/// notes on the neck; anything else is searched on YouTube (the one
/// thing that leaves the device).
library;

import 'package:flutter/material.dart';

import '../l10n/language.dart';
import '../screens/link_page.dart';
import 'diagrams.dart';
import 'music_theory.dart';
import 'voicings.dart';

/// The app bar's Dictionary button: opens [DictionaryScreen] over the
/// screen, and calls [onClosed] when it's left (Cam takes its keys back).
class DictionaryButton extends StatelessWidget {
  const DictionaryButton({super.key, this.onClosed});

  final VoidCallback? onClosed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('dictionary'),
    tooltip: context.l10n.dictionary,
    icon: const Icon(Icons.menu_book_outlined),
    onPressed: () async {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const DictionaryScreen(),
        ),
      );
      onClosed?.call();
    },
  );
}

/// YouTube's search for [query].
Uri youTubeSearch(String query) =>
    Uri.https('www.youtube.com', '/results', {'search_query': query.trim()});

/// The dictionary screen: the search field, and under it the chord, the
/// scale, or the YouTube search for what was typed.
class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  Lookup _lookup = const Other();
  List<Voicing> _voicings = const [];

  @override
  void initState() {
    super.initState();
    _read(widget.initialQuery);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _read(String query) {
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
    final query = _controller.text;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dictionary)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              key: const Key('dictionary-query'),
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
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
              padding: const EdgeInsets.all(16),
              // Under the field, from its left; no wider than reads well.
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: SizedBox(
                    width: double.infinity,
                    child: switch (_lookup) {
                      ChordLookup(:final chord) => _ChordResult(
                        chord: chord,
                        voicings: _voicings,
                      ),
                      ScaleLookup(:final scale) => _ScaleResult(scale: scale),
                      Other() when query.trim().isEmpty => _Intro(
                        onExample: _set,
                      ),
                      Other() => _YouTubeResult(query: query),
                    },
                  ),
                ),
              ),
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
        Text(title, style: theme.textTheme.headlineMedium),
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
