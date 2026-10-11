import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cloud/cloud_ocr.dart';
import '../cloud/ocr_api.dart';
import '../library/library.dart';
import 'tab_editing.dart';

/// The event screen's Text view: the tab read from the event's pages, to
/// check against them and fix, monospaced and unwrapped (long lines scroll
/// sideways). Edits are saved as they're made (after a second's pause) and
/// on leaving, and make the text the user's: no later read replaces it. A
/// read that ends while it shows fills it in, unless the user has started
/// editing. Read only for an event shared read only.
///
/// Above it: **Copy**; **Correct**, a toggle marking the text checked (the
/// event then opens on its Text view, and no read replaces it); and **Fix**
/// (Premium), auto-correct: the song's tab found online proposes
/// corrections, shown per note for the user to accept or reject. Editing
/// tools: **−** and **+** change the fret under the cursor, and
/// **Overtype** (on by default) makes typing replace characters instead of
/// pushing the line right.
class TabTextView extends StatefulWidget {
  const TabTextView({
    super.key,
    required this.library,
    required this.eventId,
    this.ocr,
    this.onUpgrade,
  });

  final Library library;
  final String eventId;

  /// Auto-correct's service (null: a build without it, no Fix).
  final CloudOcr? ocr;

  /// Opens the upgrade offer, for Fix without Premium.
  final VoidCallback? onUpgrade;

  @override
  State<TabTextView> createState() => _TabTextViewState();
}

class _TabTextViewState extends State<TabTextView> {
  final _text = TextEditingController();

  /// The text as last loaded or saved: what's on screen unless edited.
  String? _known;
  Timer? _saveSoon;
  bool _overtype = true;

  /// Fix is asking the service.
  bool _checking = false;

  /// Fix's answer, while the user reviews it.
  _Review? _review;

  String? get _stored => widget.library.byId(widget.eventId)?.tabText;

  @override
  void initState() {
    super.initState();
    _known = _stored;
    _text.text = _known ?? '';
    widget.library.addListener(_onLibrary);
  }

  /// A read (or another device) changed the text: shown, if the user
  /// hasn't edited it here.
  void _onLibrary() {
    final stored = _stored;
    if (stored == _known) return;
    if (_text.text == (_known ?? '') && _review == null && !_checking) {
      _text.text = stored ?? '';
      _known = stored;
    }
  }

  @override
  void dispose() {
    widget.library.removeListener(_onLibrary);
    _saveSoon?.cancel();
    _save();
    _review?.dispose();
    _text.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _saveSoon?.cancel();
    _saveSoon = Timer(const Duration(seconds: 1), _save);
  }

  void _save() {
    final event = widget.library.byId(widget.eventId);
    if (event == null || event.readOnly || _text.text == (_known ?? '')) {
      return;
    }
    _known = _text.text;
    widget.library.update(
      event.copyWith(tabText: _text.text, tabTextAuto: false),
    );
  }

  /// Marks the text tab correct, or no longer correct; saved right away.
  Future<void> _toggleCorrect() async {
    _save();
    final event = widget.library.byId(widget.eventId);
    if (event == null || event.readOnly) return;
    await widget.library.update(
      event.copyWith(tabTextCorrect: !event.tabTextCorrect),
    );
    if (mounted) setState(() {});
  }

  void _say(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text.text));
    _say('Tab copied');
  }

  void _bump(int delta) {
    final value = bumpNumber(_text.value, delta);
    if (value == null) {
      _say('Put the cursor on a fret number');
      return;
    }
    _text.value = value;
    _changed(value.text);
  }

  /// Fix: asks which song this is, then for its corrections.
  Future<void> _autocorrect() async {
    final ocr = widget.ocr;
    final event = widget.library.byId(widget.eventId);
    if (ocr == null || event == null) return;
    if (!ocr.premium) {
      _say(
        'Fix is part of TabScan Premium',
        action: widget.onUpgrade == null
            ? null
            : SnackBarAction(label: 'Upgrade', onPressed: widget.onUpgrade!),
      );
      return;
    }
    final song = await _askSong(event.title);
    if (song == null || !mounted) return;
    _saveSoon?.cancel();
    _save();
    final sent = _text.text;
    setState(() => _checking = true);
    AutocorrectResult? result;
    try {
      result = await ocr.autocorrect(event, song: song, text: sent);
    } on OcrApiException catch (e) {
      debugPrint('TabScan: auto-correct failed: $e');
      if (e.needsPremium) {
        _say('Fix is part of TabScan Premium');
      } else if (e.needsSignIn) {
        _say('Sign in again to use Fix');
      } else if (e.statusCode == 503) {
        _say('Fix isn\'t available yet');
      } else {
        _say('Couldn\'t check online right now. Try again later.');
      }
    } on Object catch (e) {
      debugPrint('TabScan: auto-correct failed: $e');
      _say('Couldn\'t check online right now. Try again later.');
    }
    if (!mounted) return;
    setState(() => _checking = false);
    if (result == null) return;
    if (_text.text != sent) {
      _say('The text changed meanwhile: tap Fix again');
    } else if (result.corrections.isEmpty) {
      _say(
        result.summary.isNotEmpty
            ? result.summary
            : result.found
            ? 'The tab matches the one found online'
            : 'Couldn\'t find this song\'s tab online',
      );
    } else {
      setState(() => _review = _Review(sent, result!));
    }
  }

  Future<String?> _askSong(String title) => showDialog<String>(
    context: context,
    builder: (context) => _SongDialog(title: title),
  );

  /// Ends the review: the accepted corrections go into the text.
  void _finishReview() {
    final review = _review;
    if (review == null) return;
    final accepted = review.accepted.toList();
    setState(() => _review = null);
    review.dispose();
    if (accepted.isEmpty) return;
    _text.text = applyCorrections(review.text, accepted);
    _save();
    _say(
      '${accepted.length} correction${accepted.length == 1 ? '' : 's'} '
      'applied',
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.library.byId(widget.eventId);
    final correct = event?.tabTextCorrect ?? false;
    final editable = !(event?.readOnly ?? false);
    final review = _review;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: _copy,
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
              ),
              if (editable || correct)
                _correctToggle(correct, editable && review == null),
              if (editable && widget.ocr != null)
                FilledButton.tonalIcon(
                  onPressed: _checking || review != null ? null : _autocorrect,
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Fix'),
                ),
            ],
          ),
        ),
        if (editable && review == null) _tools(),
        if (_checking) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Looking for the song\'s tab online…'),
          ),
        ],
        Expanded(
          child: review == null
              ? _editor(context, editable && !_checking)
              : _ReviewView(
                  review: review,
                  onChanged: () => setState(() {}),
                  onDone: _finishReview,
                ),
        ),
      ],
    );
  }

  /// Correct, a toggle shaped like Copy: tonal while off, filled while on.
  Widget _correctToggle(bool correct, bool enabled) {
    final onPressed = enabled ? _toggleCorrect : null;
    const label = Text('Correct');
    final button = correct
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.check_circle),
            label: label,
          )
        : FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: const Icon(Icons.check_circle_outline),
            label: label,
          );
    return Tooltip(
      message: correct
          ? 'Marked correct: the event opens on its text'
          : 'Mark the reading correct',
      child: Semantics(toggled: correct, child: button),
    );
  }

  /// The editing tools: − and + on the fret under the cursor, Overtype.
  Widget _tools() {
    final enabled = !_checking;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Fret down (the number under the cursor)',
            onPressed: enabled ? () => _bump(-1) : null,
            icon: const Icon(Icons.remove),
          ),
          IconButton(
            tooltip: 'Fret up (the number under the cursor)',
            onPressed: enabled ? () => _bump(1) : null,
            icon: const Icon(Icons.add),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: _overtype
                ? 'Overtype: typing replaces characters, columns stay put'
                : 'Insert: typing pushes the line right',
            child: Semantics(
              toggled: _overtype,
              child: TextButton.icon(
                onPressed: enabled
                    ? () => setState(() => _overtype = !_overtype)
                    : null,
                icon: Icon(
                  _overtype ? Icons.check_box : Icons.check_box_outline_blank,
                ),
                label: const Text('Overtype'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The tab text, unwrapped: long lines scroll sideways.
  Widget _editor(BuildContext context, bool editable) {
    return _Unwrapped(
      child: TextField(
        controller: _text,
        readOnly: !editable,
        onChanged: _changed,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        // Tabs aren't prose: no suggestions, and dashes stay dashes.
        autocorrect: false,
        enableSuggestions: false,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        inputFormatters: [OvertypeFormatter(() => _overtype)],
        style: _mono,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(16),
        ),
      ),
    );
  }
}

/// Asks which song the tab is, for Fix to look up.
class _SongDialog extends StatefulWidget {
  const _SongDialog({required this.title});

  final String title;

  @override
  State<_SongDialog> createState() => _SongDialogState();
}

class _SongDialogState extends State<_SongDialog> {
  late final _song = TextEditingController(text: widget.title);

  @override
  void dispose() {
    _song.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Fix from the song\'s tab'),
      content: TextField(
        controller: _song,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Song and artist',
          helperText: 'Looked up on tab sites to correct the reading',
        ),
        onSubmitted: (s) => Navigator.pop(context, s.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _song.text.trim()),
          child: const Text('Check'),
        ),
      ],
    );
  }
}

const _mono = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Menlo', 'Courier New', 'Courier'],
  fontSize: 13,
  height: 1.25,
);

class _Unwrapped extends StatelessWidget {
  const _Unwrapped({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.sizeOf(context).width,
          maxWidth: 1600,
        ),
        child: SingleChildScrollView(child: child),
      ),
    );
  }
}

/// Fix's corrections under review: each one accepted, rejected, or not
/// decided yet (null).
class _Review {
  _Review(this.text, this.result)
    : selected = result.corrections.first.id,
      decisions = {for (final c in result.corrections) c.id: null};

  /// The text the corrections are for.
  final String text;
  final AutocorrectResult result;
  final Map<String, bool?> decisions;
  String selected;
  final Map<String, TapGestureRecognizer> _taps = {};

  List<TabCorrection> get corrections => result.corrections;
  TabCorrection get current => corrections.firstWhere((c) => c.id == selected);
  int get decided => decisions.values.where((d) => d != null).length;

  Iterable<TabCorrection> get accepted =>
      corrections.where((c) => decisions[c.id] == true);

  void decide(bool accept) {
    decisions[selected] = accept;
    // On to the next undecided one, after this one, then from the start.
    final i = corrections.indexWhere((c) => c.id == selected);
    final next = [
      ...corrections.skip(i + 1),
      ...corrections.take(i),
    ].where((c) => decisions[c.id] == null);
    if (next.isNotEmpty) selected = next.first.id;
  }

  void move(int by) {
    final i = corrections.indexWhere((c) => c.id == selected);
    selected = corrections[(i + by) % corrections.length].id;
  }

  void setAll(bool accept) {
    for (final id in decisions.keys) {
      decisions[id] = accept;
    }
  }

  /// One recognizer per correction, kept while the review lasts.
  TapGestureRecognizer tap(String id, VoidCallback onTap) =>
      (_taps[id] ??= TapGestureRecognizer())..onTap = onTap;

  void dispose() {
    for (final r in _taps.values) {
      r.dispose();
    }
  }
}

/// The text with each proposed note marked where it goes (its columns
/// kept), and the selected one's change below: old note → new note, with
/// Accept and Reject.
class _ReviewView extends StatelessWidget {
  const _ReviewView({
    required this.review,
    required this.onChanged,
    required this.onDone,
  });

  final _Review review;
  final VoidCallback onChanged;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final result = review.result;
    final song = [
      result.title,
      result.artist,
    ].where((s) => s.isNotEmpty).join(' – ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (song.isNotEmpty)
                Text(song, style: Theme.of(context).textTheme.titleSmall),
              if (result.summary.isNotEmpty) Text(result.summary),
              for (final url in result.sources.take(2))
                InkWell(
                  onTap: () =>
                      launchUrl(url, mode: LaunchMode.externalApplication),
                  child: Text(
                    url.host,
                    style: TextStyle(
                      color: scheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _Unwrapped(child: _marked(context, scheme))),
        _panel(context, scheme),
      ],
    );
  }

  Widget _marked(BuildContext context, ColorScheme scheme) {
    final lines = review.text.split('\n');
    final byLine = <int, List<TabCorrection>>{};
    for (final c in review.corrections) {
      byLine.putIfAbsent(c.line, () => []).add(c);
    }
    final spans = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: '\n'));
      final line = lines[i];
      var at = 0;
      final here = [...?byLine[i]]
        ..sort((a, b) => a.column.compareTo(b.column));
      for (final c in here) {
        final end = c.column + c.old.length;
        if (c.column < at || end > line.length) continue;
        spans.add(TextSpan(text: line.substring(at, c.column)));
        final decision = review.decisions[c.id];
        final shown = decision == false
            ? (c.old.isEmpty ? '-' : c.old)
            : (c.replacement.isEmpty
                  ? '-' * c.old.length.clamp(1, 9)
                  : c.replacement);
        final selected = c.id == review.selected;
        spans.add(
          TextSpan(
            text: shown,
            recognizer: review.tap(c.id, () {
              review.selected = c.id;
              onChanged();
            }),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: decision == false ? scheme.outline : scheme.onSurface,
              backgroundColor: selected
                  ? scheme.tertiaryContainer
                  : decision == true
                  ? Colors.green.withValues(alpha: 0.35)
                  : decision == false
                  ? null
                  : scheme.primaryContainer,
              decoration: selected ? TextDecoration.underline : null,
            ),
          ),
        );
        at = c.column + (c.old.isEmpty ? c.replacement.length : c.old.length);
      }
      if (at < line.length) spans.add(TextSpan(text: line.substring(at)));
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text.rich(TextSpan(style: _mono, children: spans)),
    );
  }

  Widget _panel(BuildContext context, ColorScheme scheme) {
    final c = review.current;
    final decision = review.decisions[c.id];
    final lines = review.text.split('\n');
    final label = c.line < lines.length ? _stringName(lines[c.line]) : null;
    final i = review.corrections.indexOf(c) + 1;
    final n = review.corrections.length;
    final old = c.old.isEmpty ? '–' : c.old;
    final now = c.replacement.isEmpty ? 'removed' : c.replacement;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous',
                    onPressed: () {
                      review.move(-1);
                      onChanged();
                    },
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('$i of $n'),
                  IconButton(
                    tooltip: 'Next',
                    onPressed: () {
                      review.move(1);
                      onChanged();
                    },
                    icon: const Icon(Icons.chevron_right),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: _mono.copyWith(fontSize: 15),
                        children: [
                          TextSpan(
                            text: old,
                            style: TextStyle(
                              color: scheme.error,
                              decoration: c.old.isEmpty
                                  ? null
                                  : TextDecoration.lineThrough,
                            ),
                          ),
                          const TextSpan(text: ' → '),
                          TextSpan(
                            text: now,
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  [
                    'Line ${c.line + 1}${label == null ? '' : ' ($label)'}, '
                        'column ${c.column + 1}',
                    if (c.reason.isNotEmpty) c.reason,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      review.decide(false);
                      onChanged();
                    },
                    child: Text(decision == false ? 'Rejected' : 'Reject'),
                  ),
                  FilledButton(
                    onPressed: () {
                      review.decide(true);
                      onChanged();
                    },
                    child: Text(decision == true ? 'Accepted' : 'Accept'),
                  ),
                  PopupMenuButton<bool>(
                    tooltip: 'All',
                    onSelected: (accept) {
                      review.setAll(accept);
                      onChanged();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: true, child: Text('Accept all')),
                      PopupMenuItem(value: false, child: Text('Reject all')),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Text('All…'),
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: onDone,
                    child: Text(
                      review.decided < n
                          ? 'Done (${review.decided}/$n)'
                          : 'Done',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The string a line is for, from its label ("e|---"), if it has one.
  static String? _stringName(String line) =>
      RegExp(r'^\s*([A-Ga-g][#b]?)\s*[|:]').firstMatch(line)?.group(1);
}
