/// The dictionary: a button at the top of every file viewer, Cam and Home, and
/// the sidebar it opens on the right of the screen, as the play-along
/// player opens (or, turned by its Rotate button, the panel under the
/// screen), where the user types a chord, a scale or anything else.
/// A chord shows its notes and voicings, a scale its notes on the neck;
/// anything else is searched on YouTube and Cifra Club, and among
/// tabs.cam's public captures (the one thing that leaves the device): once
/// typing stops for a couple of seconds, their results show under the
/// field ([PublicSearch], when it finds any, [YouTubeSearch], then
/// [CifraClubSearch]).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../cloud/share_api.dart';
import '../export/incoming_links.dart';
import '../l10n/language.dart';
import '../library/dictionary_pin.dart';
import '../screens/link_page.dart';
import '../screens/sidebar_widths.dart';
import '../screens/split_handle.dart';
import 'cifraclub_search.dart';
import 'diagrams.dart';
import 'music_theory.dart';
import 'public_search.dart';
import 'voicings.dart';
import 'youtube_search.dart';

/// Where the dictionary's + writes a chord or a scale: the event screen's
/// Text view ([DictionaryState.writer]).
abstract interface class TabWriter {
  /// Writes [columns] into the tab: each a fret per string, low E to high
  /// E, null for a string not played (a chord's voicing is one column, a
  /// scale one per note), with [name] (the chord's or the scale's) above
  /// the phrase.
  void write(List<List<int?>> columns, {String? name});
}

/// Where the dictionary's + beside a YouTube or Cifra Club result adds it
/// as a link: the capture open on the event screen, while the user can
/// change it ([DictionaryState.linker]).
abstract interface class LinkAdder {
  /// Adds [url] to the capture as a link named [title], and says so (or
  /// that the capture already has it).
  Future<void> addLink(Uri url, {String? title});
}

/// The capture open on the event screen, which keeps what the user pins
/// in the dictionary for it ([CaptureEvent.pins], in its event.json, so
/// it syncs and is shared with it) ([DictionaryState.keeper]).
abstract interface class PinKeeper {
  /// What's pinned, oldest first.
  List<DictionaryPin> get pins;

  /// Whether the user can pin and unpin: not on a capture read only.
  bool get canPin;

  /// Pins [pin], or unpins it when it's pinned.
  Future<void> togglePin(DictionaryPin pin);

  /// Notifies when [pins] may have changed.
  Listenable get pinsChanged;
}

/// Whether the dictionary's sidebar shows, and what's typed in it,
/// app-wide: open on one screen, it's open on the next (Home, the capture,
/// a file, Cam), with the same search.
class DictionaryState extends ChangeNotifier {
  DictionaryState._();

  /// The app's.
  static final DictionaryState instance = DictionaryState._();

  bool get open => _open;
  bool _open = false;

  /// What's typed in its field.
  String get query => _query;
  String _query = '';

  /// Where a chord's voicing or a scale is written, its + pressed: the
  /// event's Text view while it shows and can be edited. Null elsewhere,
  /// and the results have no +.
  TabWriter? get writer => _writer;
  TabWriter? _writer;

  /// [writer] takes the dictionary's +, until it [detach]es.
  void attach(TabWriter writer) {
    if (identical(_writer, writer)) return;
    _writer = writer;
    _notifyLater();
  }

  void detach(TabWriter writer) {
    if (!identical(_writer, writer)) return;
    _writer = null;
    _notifyLater();
  }

  /// Where a result's + adds its link: the capture on the newest event
  /// screen that can take one (one opened over another's: the top one's).
  /// Null elsewhere (Home, a capture read only), and the results have no +.
  LinkAdder? get linker => _linkers.lastOrNull;
  final List<LinkAdder> _linkers = [];

  /// [linker] takes the results' +, until it [detachLinker]s.
  void attachLinker(LinkAdder linker) {
    if (_linkers.any((l) => identical(l, linker))) return;
    _linkers.add(linker);
    _notifyLater();
  }

  void detachLinker(LinkAdder linker) {
    final before = _linkers.length;
    _linkers.removeWhere((l) => identical(l, linker));
    if (_linkers.length != before) _notifyLater();
  }

  /// The capture whose pins show at the dictionary's end, and that its
  /// pins pin to: the newest event screen's (one opened over another's:
  /// the top one's), on a capture read only too (its pins show, and none
  /// can be added). Null elsewhere (Home): nothing pinned shows, and
  /// there are no pins.
  PinKeeper? get keeper => _keepers.lastOrNull;
  final List<PinKeeper> _keepers = [];

  /// [keeper] keeps the pins, until it [detachKeeper]s.
  void attachKeeper(PinKeeper keeper) {
    if (_keepers.any((k) => identical(k, keeper))) return;
    _keepers.add(keeper);
    _notifyLater();
  }

  void detachKeeper(PinKeeper keeper) {
    final before = _keepers.length;
    _keepers.removeWhere((k) => identical(k, keeper));
    if (_keepers.length != before) _notifyLater();
  }

  /// After the frame: a view attaches and detaches as it's built and
  /// disposed, when the sidebar can't be rebuilt.
  void _notifyLater() {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => notifyListeners())
      ..ensureVisualUpdate();
  }

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
    _writer = null;
    _linkers.clear();
    _keepers.clear();
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
  const DictionaryBeside({
    super.key,
    required this.child,
    this.title,
    this.onClosed,
    this.enabled = true,
  });

  final Widget child;

  /// The capture's title, where there's a capture (its screen, a file,
  /// Cam): the sidebar's first pill with nothing typed. Null elsewhere.
  final String? title;

  /// After the sidebar's own close button hides it.
  final VoidCallback? onClosed;

  /// False, [child] shows alone (Home's tabs other than Home), keeping its
  /// state; the sidebar stays open app-wide, to show again where it's
  /// enabled.
  final bool enabled;

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

  /// The narrowest the panel under the screen is laid out, cut likewise
  /// (a phone with the metronome's sidebar open beside it): its one row
  /// is the book, the field and the two buttons.
  static const minBelow = 240.0;

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
          final wide = box.maxWidth < minBelow ? minBelow : null;
          // One Flex either way, so turning it keeps [child] (the camera,
          // what plays) and what the sidebar shows.
          return Flex(
            direction: below ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: child),
              if (state.open && enabled) ...[
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
                      alignment: Alignment.topLeft,
                      minWidth: below ? wide : laidOut,
                      maxWidth: below ? wide : laidOut,
                      minHeight: below ? laidOut : tall,
                      maxHeight: below ? laidOut : tall,
                      child: DictionarySidebar(
                        title: title,
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
    this.title,
    required this.onClose,
    this.onRotate,
    this.below = false,
  });

  /// The capture's title, its first pill with nothing typed; null with
  /// no capture.
  final String? title;

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

  /// Cifra Club's, likewise.
  List<CifraClubSong>? _songs;
  bool _searchingSongs = false;
  bool _failedSongs = false;

  /// tabs.cam's public captures, likewise (shown only once some are
  /// found).
  List<PublicCapture>? _captures;
  bool _searchingCaptures = false;

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
    final cifraClub = CifraClubSearch.instance;
    final tabsCam = PublicSearch.instance;
    final song = lookup is Other && query.trim().isNotEmpty;
    final searches = song && youTube.available;
    final cached = searches ? youTube.cached(query) : null;
    final cachedSongs = song ? cifraClub.cached(query) : null;
    final publicSearch =
        song && tabsCam.available && PublicSearch.searches(query);
    final cachedCaptures = publicSearch ? tabsCam.cached(query) : null;
    setState(() {
      _lookup = lookup;
      _voicings = switch (lookup) {
        ChordLookup(:final chord) => voicingsOf(chord),
        _ => const [],
      };
      _videos = cached;
      _searching = searches && cached == null;
      _failed = false;
      _songs = cachedSongs;
      _searchingSongs = song && cachedSongs == null;
      _failedSongs = false;
      _captures = cachedCaptures;
      _searchingCaptures = publicSearch && cachedCaptures == null;
    });
    if (_searching || _searchingSongs || _searchingCaptures) {
      _wait = Timer(YouTubeSearch.wait, () => _search(query));
    }
  }

  /// Searches now, on YouTube and Cifra Club, whichever hasn't answered.
  void _search(String query) {
    _wait?.cancel();
    if (_searching) unawaited(_searchYouTube(query));
    if (_searchingSongs) unawaited(_searchCifraClub(query));
    if (_searchingCaptures) unawaited(_searchPublic(query));
  }

  Future<void> _searchPublic(String query) async {
    List<PublicCapture>? captures;
    try {
      captures = await PublicSearch.instance.search(query);
    } on PublicSearchFailed {
      captures = null;
    }
    if (!mounted || _controller.text != query) return;
    setState(() {
      _captures = captures;
      _searchingCaptures = false;
    });
  }

  Future<void> _searchCifraClub(String query) async {
    List<CifraClubSong>? songs;
    try {
      songs = await CifraClubSearch.instance.search(query);
    } on CifraClubSearchFailed {
      songs = null;
    }
    if (!mounted || _controller.text != query) return;
    setState(() {
      _songs = songs;
      _searchingSongs = false;
      _failedSongs = songs == null;
    });
  }

  Future<void> _searchYouTube(String query) async {
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
  /// on YouTube and Cifra Club now, without the wait; in a build without
  /// YouTube's key, it opens YouTube's search (and searches Cifra Club).
  void _submit(String query) {
    if (_lookup is! Other || query.trim().isEmpty) return;
    if (!YouTubeSearch.instance.available) {
      openLink(context, youTubeSearch(query));
    }
    if (_wait?.isActive ?? false) _search(query);
  }

  /// How much smaller the dictionary's text is than the app's: a little,
  /// so more of a result fits (the panel below the screen is short).
  static const textScale = 0.9;

  @override
  Widget build(BuildContext context) {
    final app = Theme.of(context);
    // Every text in it (the field, the results, the pills) a step
    // smaller; the diagrams keep their own sizes.
    return Theme(
      data: app.copyWith(
        textTheme: app.textTheme.apply(fontSizeFactor: textScale),
      ),
      child: Builder(builder: _build),
    );
  }

  Widget _build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final query = _controller.text;
    final below = widget.below;
    // At the field's end, once something's typed: YouTube's search for it,
    // outside the app (its results come in the sidebar on their own),
    // then ✕. In the field, so it takes none of the field's width (the
    // panel below can leave it little).
    final ends = <Widget>[
      if (query.trim().isNotEmpty)
        IconButton(
          key: const Key('dictionary-search-youtube'),
          tooltip: l10n.dictionarySearchYouTube,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.search),
          onPressed: () => openLink(context, youTubeSearch(query)),
        ),
      if (query.isNotEmpty)
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.clear),
          onPressed: () => _set(''),
        ),
    ];
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
        suffixIcon: ends.isEmpty
            ? null
            : Row(mainAxisSize: MainAxisSize.min, children: ends),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _result(query, below: below, room: room),
                      // At the end: what's pinned to the capture open.
                      _Pinned(below: below, room: room, onLookUp: _set),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// What the query found: a chord, a scale, the pills to tap with
  /// nothing typed, or the searches' results.
  Widget _result(String query, {required bool below, double? room}) {
    return switch (_lookup) {
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
        title: widget.title,
        onExample: _set,
      ),
      // tabs.cam's public captures (when it finds some),
      // YouTube's videos, and Cifra Club's tabs under them.
      Other() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_captures case final captures? when captures.isNotEmpty) ...[
            _PublicResult(captures: captures),
            const SizedBox(height: 20),
          ],
          _YouTubeResult(
            query: query,
            videos: _videos,
            searching: _searching,
            failed: _failed,
          ),
          const SizedBox(height: 20),
          _CifraClubResult(
            songs: _songs,
            searching: _searchingSongs,
            failed: _failedSongs,
          ),
        ],
      ),
    };
  }
}

/// Pills to tap, nothing typed: the capture's [title] first, where there
/// is one (a song's tabs and videos a tap away), then a few examples (two
/// plain chords, two with a sharp or a flat, three scales).
class _Intro extends StatelessWidget {
  const _Intro({this.title, required this.onExample});

  final String? title;
  final ValueChanged<String> onExample;

  static const examples = [
    'C',
    'Am',
    'F#m7b5',
    'Bb',
    'A minor pentatonic',
    'E blues',
    'D dorian',
  ];

  @override
  Widget build(BuildContext context) {
    final title = this.title?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, box) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (title.isNotEmpty)
                ActionChip(
                  key: const Key('dictionary-title'),
                  // Cut to the sidebar, however long the title.
                  label: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.max(40, box.maxWidth - 40),
                    ),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  onPressed: () => onExample(title),
                ),
              for (final example in examples)
                if (example != title)
                  ActionChip(
                    label: Text(example),
                    onPressed: () => onExample(example),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _Symbols(onExample: onExample),
      ],
    );
  }
}

/// The chord symbols a chart writes instead of letters (the cut circle,
/// the triangle…): what each one is, how else it's written, and how to
/// type it; a row's tap looks its example up.
class _Symbols extends StatelessWidget {
  const _Symbols({required this.onExample});

  final ValueChanged<String> onExample;

  /// The symbol, the example a tap looks up, and how else it's written.
  static const rows = [
    ('ø', 'Bø', 'Bø7 = Bm7b5 = Bm7(b5)'),
    ('Δ', 'CΔ7', 'CΔ = Cmaj7 = CM7 = C7M = C^7'),
    ('°', 'B°', 'Bdim = Bo'),
    ('°7', 'B°7', 'Bdim7 = Bo7'),
    ('+', 'C+', 'Caug = C(#5)'),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final names = {
      'ø': l10n.dictionaryHalfDiminished,
      'Δ': l10n.dictionaryMajorSeventh,
      '°': l10n.dictionaryDiminished,
      '°7': l10n.dictionaryDiminishedSeventh,
      '+': l10n.dictionaryAugmented,
    };
    return Column(
      key: const Key('dictionary-symbols'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.dictionarySymbols, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final (symbol, example, written) in rows)
          InkWell(
            key: Key('dictionary-symbol-$example'),
            onTap: () => onExample(example),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(
                      symbol,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${names[symbol]} · $example',
                          style: theme.textTheme.bodyLarge,
                        ),
                        Text(
                          written,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          l10n.dictionarySymbolsTyping,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The name in words of the qualities written with a symbol (`ø` is
/// half-diminished), or null.
String? chordQualityName(AppLocalizations l10n, ChordQuality quality) =>
    switch (quality.symbol) {
      'm7b5' => l10n.dictionaryHalfDiminished,
      'maj7' => l10n.dictionaryMajorSeventh,
      'm(maj7)' => l10n.dictionaryMinorMajorSeventh,
      'dim' => l10n.dictionaryDiminished,
      'dim7' => l10n.dictionaryDiminishedSeventh,
      'aug' => l10n.dictionaryAugmented,
      _ => null,
    };

class _Heading extends StatelessWidget {
  const _Heading({
    required this.title,
    required this.kind,
    required this.notes,
    required this.degrees,
    this.also,
    this.write,
  });

  final String title;
  final String kind;
  final List<Note> notes;
  final List<Degree> degrees;

  /// A chord's name in words and its other symbols, under the degrees.
  final String? also;

  /// Beside the title (a scale's): its + and its pin, each shown while
  /// there's a text to write in or a capture to pin to.
  final Widget? write;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(child: Text(title, style: theme.textTheme.headlineSmall)),
            ?write,
          ],
        ),
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
        if (also case final also?)
          Text(
            also,
            key: const Key('dictionary-also'),
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
    final named = chordQualityName(l10n, chord.quality);
    final others = chord.otherNames;
    final also = [
      ?named,
      if (others.isNotEmpty) l10n.dictionaryAlsoWritten(others.join(', ')),
    ].join(' · ');
    return _Result(
      key: const Key('dictionary-chord'),
      below: below,
      heading: _Heading(
        title: chord.name,
        kind: l10n.dictionaryChord,
        notes: chord.notes,
        degrees: chord.quality.degrees,
        also: also.isEmpty ? null : also,
      ),
      picture: voicings.isEmpty
          ? Text(l10n.dictionaryNoVoicings)
          : Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final v in voicings)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChordDiagram(chord: chord, voicing: v, lying: below),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _WriteButton(
                            key: Key('dictionary-write-${v.label}'),
                            tooltip: l10n.dictionaryWriteChord(v.label),
                            columns: () => [v.frets],
                            name: chord.name,
                          ),
                          _PinButton(
                            key: Key('dictionary-pin-${v.label}'),
                            pin: chordPin(chord, v),
                            name: '${chord.name} ${v.label}',
                          ),
                        ],
                      ),
                    ],
                  ),
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
    final title = '${scale.root.name} ${scaleTypeName(l10n, scale.type)}';
    return _Result(
      key: const Key('dictionary-scale'),
      below: below,
      heading: _Heading(
        title: title,
        kind: l10n.dictionaryScale,
        notes: scale.notes,
        degrees: scale.type.degrees,
        write: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _WriteButton(
              key: const Key('dictionary-write-scale'),
              tooltip: l10n.dictionaryWriteScale(title),
              columns: () => scalePosition(scale),
              name: title,
            ),
            _PinButton(
              key: const Key('dictionary-pin-scale'),
              pin: scalePin(scale),
              name: title,
            ),
          ],
        ),
      ),
      picture: ScaleFretboard(scale: scale, lying: below, maxHeight: room),
    );
  }
}

/// A +: writes [columns], and [name] above them, into the event's text ([DictionaryState.writer]);
/// nothing shows while there's no text to write in.
class _WriteButton extends StatelessWidget {
  const _WriteButton({
    super.key,
    required this.tooltip,
    required this.columns,
    this.name,
  });

  final String tooltip;
  final List<List<int?>> Function() columns;

  /// The chord's or the scale's name, written above the phrase.
  final String? name;

  @override
  Widget build(BuildContext context) {
    final state = DictionaryState.instance;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final writer = state.writer;
        if (writer == null) return const SizedBox.shrink();
        return IconButton(
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          color: Theme.of(context).colorScheme.primary,
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => writer.write(columns(), name: name),
        );
      },
    );
  }
}

/// What pins [voicing] of [chord]: the chord's name, which the dictionary
/// reads back, and the voicing's frets.
DictionaryPin chordPin(Chord chord, Voicing voicing) =>
    DictionaryPin(chord.name, List.unmodifiable(voicing.frets));

/// What pins [scale]: its root and type in English, which the dictionary
/// reads back whatever the app's language (`A minor pentatonic scale`).
DictionaryPin scalePin(Scale scale) =>
    DictionaryPin('${scale.root.name} ${scale.type.key} scale');

/// A pin: pins [pin] to the capture open ([DictionaryState.keeper]), or
/// unpins it, filled while it's pinned; nothing shows without a capture
/// the user can change.
class _PinButton extends StatelessWidget {
  const _PinButton({super.key, required this.pin, required this.name});

  final DictionaryPin pin;

  /// What its tooltip calls it: `C x32010`, `A Minor pentatonic`.
  final String name;

  @override
  Widget build(BuildContext context) {
    final state = DictionaryState.instance;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final keeper = state.keeper;
        if (keeper == null || !keeper.canPin) return const SizedBox.shrink();
        return ListenableBuilder(
          listenable: keeper.pinsChanged,
          builder: (context, _) {
            final l10n = context.l10n;
            final pinned = keeper.pins.contains(pin);
            return Semantics(
              toggled: pinned,
              child: IconButton(
                tooltip: pinned
                    ? l10n.dictionaryUnpin(name)
                    : l10n.dictionaryPin(name),
                visualDensity: VisualDensity.compact,
                color: Theme.of(context).colorScheme.primary,
                isSelected: pinned,
                icon: const Icon(Icons.push_pin_outlined),
                selectedIcon: const Icon(Icons.push_pin),
                onPressed: () => unawaited(keeper.togglePin(pin)),
              ),
            );
          },
        );
      },
    );
  }
}

/// At the dictionary's end: what's pinned to the capture open
/// ([DictionaryState.keeper]), oldest first, under "Pinned": a chord's
/// voicing as its diagram, a scale as its neck, each with its name (a
/// tap looks it up, [onLookUp]), its + (while there's a text to write
/// in) and its pin (a tap unpins it; none on a capture read only).
/// Nothing without a capture, or with nothing pinned; a pin the
/// dictionary can't read back is left out.
class _Pinned extends StatelessWidget {
  const _Pinned({required this.below, required this.onLookUp, this.room});

  final bool below;

  /// In the panel, the height it leaves a scale's neck.
  final double? room;
  final ValueChanged<String> onLookUp;

  @override
  Widget build(BuildContext context) {
    final state = DictionaryState.instance;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final keeper = state.keeper;
        if (keeper == null) return const SizedBox.shrink();
        return ListenableBuilder(
          listenable: keeper.pinsChanged,
          builder: (context, _) => _build(context, keeper.pins),
        );
      },
    );
  }

  Widget _build(BuildContext context, List<DictionaryPin> pins) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final chords = <Widget>[];
    final scales = <Widget>[];
    for (final pin in pins) {
      switch (Lookup.of(pin.query)) {
        case ChordLookup(:final chord)
            when pin.frets != null && fingersOf(pin.frets!) != null:
          final voicing = Voicing(pin.frets!);
          chords.add(
            Column(
              key: Key('dictionary-pinned-${chord.name}-${voicing.label}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                _name(context, chord.name),
                ChordDiagram(chord: chord, voicing: voicing, lying: below),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _WriteButton(
                      tooltip: l10n.dictionaryWriteChord(voicing.label),
                      columns: () => [voicing.frets],
                      name: chord.name,
                    ),
                    _PinButton(
                      pin: pin,
                      name: '${chord.name} ${voicing.label}',
                    ),
                  ],
                ),
              ],
            ),
          );
        case ScaleLookup(:final scale) when pin.frets == null:
          final title = '${scale.root.name} ${scaleTypeName(l10n, scale.type)}';
          scales.add(
            Column(
              key: Key('dictionary-pinned-${pin.query}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: _name(context, title, look: pin.query)),
                    _WriteButton(
                      tooltip: l10n.dictionaryWriteScale(title),
                      columns: () => scalePosition(scale),
                      name: title,
                    ),
                    _PinButton(pin: pin, name: title),
                  ],
                ),
                ScaleFretboard(scale: scale, lying: below, maxHeight: room),
              ],
            ),
          );
        default:
          break;
      }
    }
    if (chords.isEmpty && scales.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('dictionary-pinned'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Row(
          children: [
            Icon(
              Icons.push_pin_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(l10n.dictionaryPinned, style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        if (chords.isNotEmpty)
          Wrap(spacing: 12, runSpacing: 12, children: chords),
        for (final scale in scales) ...[const SizedBox(height: 12), scale],
      ],
    );
  }

  /// A pinned chord's or scale's [name]: tapped, it's looked up ([look],
  /// or the name).
  Widget _name(BuildContext context, String name, {String? look}) => TextButton(
    onPressed: () => onLookUp(look ?? name),
    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
    child: Tooltip(
      message: context.l10n.dictionaryLookUp(name),
      child: Text(name, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

/// Not a chord or a scale: the videos YouTube found ([videos]), each
/// opening in a new tab (its own search is the magnifying glass at the
/// field's end).
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
                  _AddLinkButton(
                    key: Key('dictionary-video-add-${video.id}'),
                    url: video.url,
                    title: video.title,
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

/// Over YouTube's results, once it finds some: tabs.cam's public captures
/// ([captures]), each opening in the app as its link does (signed in, it
/// joins it: it's then in Home's Shared with me).
class _PublicResult extends StatelessWidget {
  const _PublicResult({required this.captures});

  final List<PublicCapture> captures;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      key: const Key('dictionary-public'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.dictionaryPublic, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final capture in captures)
          Tooltip(
            message: l10n.dictionaryPublicOpen,
            waitDuration: const Duration(milliseconds: 600),
            child: InkWell(
              key: Key('dictionary-public-${capture.captureId}'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => IncomingLinks.instance.open(capture.link()),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.public),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            capture.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                          if (capture.artist.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              capture.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Under YouTube's results, Cifra Club's: the songs it has tabs of
/// ([songs]), each opening its page outside the app.
class _CifraClubResult extends StatelessWidget {
  const _CifraClubResult({
    required this.songs,
    required this.searching,
    required this.failed,
  });

  final List<CifraClubSong>? songs;
  final bool searching;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final songs = this.songs;
    return Column(
      key: const Key('dictionary-cifraclub'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.dictionaryCifraClub, style: theme.textTheme.titleSmall),
        if (searching) ...[
          const SizedBox(height: 12),
          Text(l10n.dictionaryCifraClubSearching, style: muted),
          const SizedBox(height: 8),
          const LinearProgressIndicator(
            key: Key('dictionary-cifraclub-searching'),
          ),
        ] else if (failed) ...[
          const SizedBox(height: 12),
          Text(l10n.dictionaryCifraClubFailed, style: muted),
        ] else if (songs != null && songs.isEmpty) ...[
          const SizedBox(height: 12),
          Text(l10n.dictionaryCifraClubNone, style: muted),
        ] else if (songs != null) ...[
          const SizedBox(height: 8),
          for (final song in songs) _SongTile(song: song),
        ],
      ],
    );
  }
}

/// One of Cifra Club's results: the artist's picture, the song's title
/// and artist; a tap opens its page outside the app (a new tab on the
/// web).
class _SongTile extends StatelessWidget {
  const _SongTile({required this.song});

  final CifraClubSong song;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = song.image;
    const fallback = Icon(Icons.queue_music_outlined);
    return Tooltip(
      message: context.l10n.dictionaryCifraClubOpen,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        key: Key('dictionary-song-${song.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => openLink(context, song.url),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: image == null
                        ? fallback
                        : Image.network(
                            '$image',
                            fit: BoxFit.cover,
                            webHtmlElementStrategy:
                                WebHtmlElementStrategy.fallback,
                            errorBuilder: (_, _, _) => fallback,
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
                      song.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _AddLinkButton(
                key: Key('dictionary-song-add-${song.id}'),
                url: song.url,
                title: song.artist.isEmpty
                    ? song.title
                    : '${song.title} – ${song.artist}',
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.open_in_new,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A result's +, just before its open mark: adds [url] to the capture open
/// ([DictionaryState.linker]) as a link named [title]. Nothing shows
/// where there's no capture to add it to.
class _AddLinkButton extends StatelessWidget {
  const _AddLinkButton({super.key, required this.url, required this.title});

  final Uri url;
  final String title;

  @override
  Widget build(BuildContext context) {
    final state = DictionaryState.instance;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final linker = state.linker;
        if (linker == null) return const SizedBox.shrink();
        return IconButton(
          tooltip: context.l10n.dictionaryAddLink,
          visualDensity: VisualDensity.compact,
          color: Theme.of(context).colorScheme.primary,
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => linker.addLink(url, title: title),
        );
      },
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
