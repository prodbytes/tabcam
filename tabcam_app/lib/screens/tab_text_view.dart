import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cloud/cloud_ocr.dart';
import '../cloud/ocr_api.dart';
import '../library/library.dart';
import '../recognition/tab_doubts.dart';
import '../recognition/tab_layout.dart';
import 'tab_editing.dart';
import '../l10n/language.dart';
import 'mono_font.dart';

/// The event screen's Text view: the tab read from the event's pages, to
/// check against them and fix, monospaced and unwrapped (long lines scroll
/// sideways). The notes the read wasn't sure of (likely wrong) are in red,
/// until the user changes them or marks the text Verified. Edits are saved
/// as they're made (after a second's pause) and on leaving, and make the
/// text the user's: no later read replaces it. A
/// read that ends while it shows fills it in, unless the user has started
/// editing. Read only for an event shared read only.
///
/// Above it, in one row, on the right: **Copy**; **Fix** (off for now,
/// see [showFix]): lines the tab up, then with Premium auto-correct: the
/// song's tab found online proposes corrections, shown per note for the
/// user to accept or reject; **Rescan**, reading the tab from the pages
/// again; and **Verified**, a toggle marking the text checked (the event
/// then opens on its Text view, and no read replaces it). On the row's
/// left, the editing tools, outlined: **−** and **+** change the fret
/// under the cursor, **++** and **−−** move its note to the string above
/// or below, and the **Overtype** toggle (on by default) makes typing
/// replace characters instead of pushing the line right. To check the
/// reading against the page, the play-along sidebar beside the view
/// lists the capture's PDFs to follow, as Cam's does.
class TabTextView extends StatefulWidget {
  const TabTextView({
    super.key,
    required this.library,
    required this.eventId,
    this.ocr,
    this.onUpgrade,
    this.onRescan,
    this.rescanning = false,
    this.showFix = fixEnabled,
    this.sample,
    this.actions,
  });

  /// `TABCAM_FIX=true`: the build shows Fix. Off by default while its
  /// Claude cost per user is unmeasured and uncapped (specs/autocorrect.md).
  static const bool fixEnabled = bool.fromEnvironment('TABCAM_FIX');

  final Library library;
  final String eventId;

  /// Auto-correct's service (null: a build without it, no Fix).
  final CloudOcr? ocr;

  /// Opens the upgrade offer, for Fix without Premium. Null (no sign-in
  /// to offer it with): Fix only lines the tab up for them.
  final VoidCallback? onUpgrade;

  /// Reads the tab from the pages again (null: nothing to read, or no
  /// reader: no Rescan).
  final VoidCallback? onRescan;

  /// Rescan is reading the pages: it spins, and the text and its buttons
  /// wait (the text stays until a tab found replaces it).
  final bool rescanning;

  /// Whether the Fix button shows ([fixEnabled] unless a test says).
  final bool showFix;

  /// A text shown in the event's place and never saved: the preview of
  /// the view for a user without Premium ([PremiumGate]), where the
  /// event has no text tab.
  final String? sample;

  /// Where Copy, Fix, Rescan and Verified go: the event screen's app bar
  /// builds them from it ([TabTextActions.build]), and the line above the
  /// text has the editing tools alone. Null (the locked preview, tests):
  /// they're on that line, on its right.
  final TabTextActions? actions;

  @override
  State<TabTextView> createState() => _TabTextViewState();
}

/// The Text view's Copy, Fix, Rescan and Verified, for the event screen's
/// app bar: the view shown with it ([TabTextView.actions]) builds them,
/// and it notifies whenever they change (Verified toggled, Rescan or Fix
/// working).
class TabTextActions extends ChangeNotifier {
  _TabTextViewState? _view;

  /// The buttons, icons only when [compact] (a phone); none until the
  /// view shows.
  List<Widget> build(BuildContext context, {required bool compact}) =>
      _view?._actions(context, compact: compact) ?? const [];

  void _attach(_TabTextViewState? view) {
    _view = view;
    _changed();
  }

  /// Notified after the frame: the view changes while it builds, and the
  /// app bar mustn't be marked to rebuild then.
  void _changed() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) notifyListeners();
    });
  }
}

class _TabTextViewState extends State<TabTextView> {
  final _text = DoubtController();

  /// The text as last loaded or saved: what's on screen unless edited.
  String? _known;
  Timer? _saveSoon;
  bool _overtype = true;

  /// Fix is asking the service.
  bool _checking = false;

  /// Fix is looking online, or Rescan reading: the text can't be edited.
  bool get _busy => _checking || widget.rescanning;

  /// Fix's answer, while the user reviews it.
  _Review? _review;

  String? get _stored =>
      widget.sample ?? widget.library.byId(widget.eventId)?.tabText;

  /// The doubtful notes to show in red: none once the text is Verified.
  List<TabDoubt> get _doubts {
    final event = widget.library.byId(widget.eventId);
    if (event == null || event.tabTextCorrect) return const [];
    return event.tabTextDoubts;
  }

  @override
  void initState() {
    super.initState();
    widget.actions?._attach(this);
    _known = _stored;
    _text.doubts = _doubts;
    _text.text = _known ?? '';
    widget.library.addListener(_onLibrary);
    widget.ocr?.addListener(_onPremium);
  }

  /// Premium's status came: Fix shows or hides.
  void _onPremium() {
    if (mounted) setState(() {});
  }

  /// A read (or another device) changed the text: shown, if the user
  /// hasn't edited it here.
  void _onLibrary() {
    widget.actions?._changed();
    _text.doubts = _doubts;
    final stored = _stored;
    if (stored == _known) return;
    if (_text.text == (_known ?? '') && _review == null && !_checking) {
      _text.text = stored ?? '';
      _known = stored;
    }
  }

  @override
  void didUpdateWidget(TabTextView old) {
    super.didUpdateWidget(old);
    if (old.actions != widget.actions) {
      if (old.actions?._view == this) old.actions!._attach(null);
      widget.actions?._attach(this);
    } else {
      // Rescan may have started or ended.
      widget.actions?._changed();
    }
  }

  // Every change here shows in the app bar's buttons too.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    widget.actions?._changed();
  }

  @override
  void dispose() {
    if (widget.actions?._view == this) widget.actions!._attach(null);
    widget.library.removeListener(_onLibrary);
    widget.ocr?.removeListener(_onPremium);
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
    if (event == null ||
        event.readOnly ||
        widget.sample != null ||
        _text.text == (_known ?? '')) {
      return;
    }
    _known = _text.text;
    widget.library.update(
      event.copyWith(
        tabText: _text.text,
        tabTextAuto: false,
        // The notes the user changed aren't doubtful any more.
        tabTextDoubts: standingDoubts(_text.text, event.tabTextDoubts),
      ),
    );
  }

  /// A tap on a red note, or right beside it: the user has looked at it,
  /// so it's no longer marked doubtful (saved right away).
  void _tapped() {
    final selection = _text.selection;
    if (!selection.isValid || !selection.isCollapsed) return;
    final event = widget.library.byId(widget.eventId);
    if (event == null || event.readOnly || _doubts.isEmpty) return;
    final doubt = doubtAt(_text.text, _text.doubts, selection.baseOffset);
    if (doubt == null) return;
    _saveSoon?.cancel();
    _save();
    final now = widget.library.byId(widget.eventId) ?? event;
    widget.library.update(
      now.copyWith(
        tabTextDoubts: [
          for (final d in now.tabTextDoubts)
            if (d != doubt) d,
        ],
      ),
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
    if (!mounted) return;
    _say(context.l10n.textViewTabCopied);
  }

  void _bump(int delta) {
    final value = bumpNumber(_text.value, delta);
    if (value == null) {
      _say(context.l10n.textViewPutCursorOnFret);
      return;
    }
    _text.value = value;
    _changed(value.text);
  }

  /// ++ and −−: the note under the cursor up or down a string.
  void _move(int delta) {
    final (:moved, :failure) = moveNote(_text.value, delta);
    if (moved == null) {
      _say(
        failure == MoveNoteFailure.noRoom
            ? context.l10n.textViewNoStringFree
            : context.l10n.textViewPutCursorOnNote,
      );
      return;
    }
    _text.value = moved;
    _changed(moved.text);
  }

  /// |: a bar line across the cursor's staff, at its column.
  void _bar() {
    final value = insertBar(_text.value);
    if (value == null) {
      _say(context.l10n.textViewPutCursorOnString);
      return;
    }
    _text.value = value;
    _changed(value.text);
  }

  /// ||: every staff's strings end together, at the longest.
  void _alignEnds() {
    final value = alignEnds(_text.value);
    if (value == null) {
      _say(context.l10n.textViewNoStaff);
      return;
    }
    if (value.text == _text.text) {
      _say(context.l10n.textViewEndsAligned);
      return;
    }
    _text.value = value;
    _changed(value.text);
  }

  /// =: an empty six-string staff under the cursor's line or staff.
  void _newStaff() {
    final value = newStaff(_text.value);
    _text.value = value;
    _changed(value.text);
  }

  /// Fix: asks which song this is, then for its corrections.
  Future<void> _autocorrect() async {
    final ocr = widget.ocr;
    final event = widget.library.byId(widget.eventId);
    if (event == null) return;
    // First, here and for everyone: the strings lined up (reformatTab).
    final l10n = context.l10n;
    final tidy = reformatTab(_text.text);
    final lined = tidy != _text.text;
    if (lined) {
      _text.text = tidy;
      _saveSoon?.cancel();
      _save();
    }
    if (ocr == null || !ocr.premium) {
      // The check against the song online is Premium's.
      final offer = ocr != null && widget.onUpgrade != null;
      _say(
        offer
            ? l10n.textViewFixLinedUpPremium
            : lined
            ? l10n.textViewFixLinedUp
            : l10n.textViewFixAlreadyLinedUp,
        action: offer
            ? SnackBarAction(
                label: l10n.textViewUpgrade,
                onPressed: widget.onUpgrade!,
              )
            : null,
      );
      return;
    }
    if (lined) _say(l10n.textViewFixLinedUp);
    final song = await _askSong(event.title);
    if (song == null || !mounted) return;
    _saveSoon?.cancel();
    _save();
    final sent = _text.text;
    setState(() => _checking = true);
    AutocorrectResult? result;
    String Function(AppLocalizations l10n)? failed;
    try {
      result = await ocr.autocorrect(event, song: song, text: sent);
    } on OcrApiException catch (e) {
      debugPrint('TabCam: auto-correct failed: $e');
      failed = e.needsPremium
          ? (l) => l.textViewFixPremium
          : e.needsSignIn
          ? (l) => l.textViewFixSignIn
          : e.statusCode == 503
          ? (l) => l.textViewFixUnavailable
          : (l) => l.textViewCheckFailed;
    } on Object catch (e) {
      debugPrint('TabCam: auto-correct failed: $e');
      failed = (l) => l.textViewCheckFailed;
    }
    if (!mounted) return;
    setState(() => _checking = false);
    if (failed != null) _say(failed(context.l10n));
    if (result == null) return;
    if (_text.text != sent) {
      _say(context.l10n.textViewTextChanged);
    } else if (result.corrections.isEmpty) {
      _say(
        result.summary.isNotEmpty
            ? result.summary
            : result.found
            ? context.l10n.textViewTabMatches
            : context.l10n.textViewTabNotFound,
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
    _say(context.l10n.textViewApplied(accepted.length));
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.library.byId(widget.eventId);
    final editable = !(event?.readOnly ?? false);
    final review = _review;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The editing tools; Copy, Fix, Rescan and Verified on their
        // right, or in the app bar ([TabTextView.actions]). Part of the
        // text field's tap region: a press on a button keeps the keyboard
        // focus, and the cursor, in the text (on a computer a tap outside
        // the field would unfocus it, and the keys would go nowhere until
        // the text is clicked again).
        TextFieldTapRegion(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: widget.actions != null
                ? (editable && review == null
                      ? _tools(wrap: true)
                      : const SizedBox.shrink())
                : Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: editable && review == null
                              ? _tools()
                              : const SizedBox.shrink(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 3,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: _actions(context, compact: false),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (_busy) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              _checking
                  ? context.l10n.textViewLookingOnline
                  : context.l10n.textViewRescanning,
            ),
          ),
        ],
        Expanded(
          child: review == null
              ? _editor(context, editable && !_busy)
              : _ReviewView(
                  review: review,
                  onChanged: () => setState(() {}),
                  onDone: _finishReview,
                ),
        ),
      ],
    );
  }

  /// Rescan: the edits so far saved first, then the event screen asks.
  void _rescan() {
    _saveSoon?.cancel();
    _save();
    widget.onRescan!();
  }

  /// Copy, Fix (when shown), Rescan (when there's something to read) and
  /// Verified: labelled buttons, or icons with their tooltips when
  /// [compact]. In the text field's tap region, so a press keeps the
  /// cursor in the text.
  List<Widget> _actions(BuildContext context, {required bool compact}) {
    final l10n = context.l10n;
    final event = widget.library.byId(widget.eventId);
    final correct = event?.tabTextCorrect ?? false;
    final editable = !(event?.readOnly ?? false);
    final review = _review;
    final idle = !_busy && review == null;
    final buttons = <Widget>[
      if (compact)
        IconButton(
          tooltip: l10n.textViewCopy,
          onPressed: _copy,
          icon: const Icon(Icons.copy),
        )
      else
        FilledButton.tonalIcon(
          onPressed: _copy,
          icon: const Icon(Icons.copy),
          label: Text(l10n.textViewCopy),
        ),
      // Fix lines the strings up for everyone; with Premium, it also
      // checks the tab against the song online.
      if (editable && widget.showFix)
        compact
            ? IconButton(
                tooltip: l10n.textViewFix,
                onPressed: idle ? _autocorrect : null,
                icon: const Icon(Icons.auto_fix_high),
              )
            : FilledButton.tonalIcon(
                onPressed: idle ? _autocorrect : null,
                icon: const Icon(Icons.auto_fix_high),
                label: Text(l10n.textViewFix),
              ),
      if (editable && widget.onRescan != null)
        compact
            ? IconButton(
                tooltip: l10n.textViewRescanTip,
                onPressed: idle ? _rescan : null,
                icon: const Icon(Icons.document_scanner_outlined),
              )
            : Tooltip(
                message: l10n.textViewRescanTip,
                child: FilledButton.tonalIcon(
                  onPressed: idle ? _rescan : null,
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: Text(l10n.textViewRescan),
                ),
              ),
      if (editable || correct)
        _correctToggle(
          correct,
          editable && review == null && !widget.rescanning,
          compact: compact,
        ),
    ];
    return [
      TextFieldTapRegion(
        child: Theme(
          data: Theme.of(context).copyWith(
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: compact ? 0 : 8,
            children: buttons,
          ),
        ),
      ),
    ];
  }

  /// Verified, a toggle shaped like Copy: tonal while off, filled while on.
  /// [compact]: a check icon, filled and in the primary colour while on.
  Widget _correctToggle(bool correct, bool enabled, {bool compact = false}) {
    final onPressed = enabled ? _toggleCorrect : null;
    final label = Text(context.l10n.textViewCorrect);
    if (compact) {
      return Semantics(
        toggled: correct,
        child: IconButton(
          key: const Key('text-verified'),
          tooltip: correct
              ? context.l10n.textViewMarkedCorrect
              : context.l10n.textViewMarkCorrect,
          isSelected: correct,
          color: correct ? Theme.of(context).colorScheme.primary : null,
          onPressed: onPressed,
          icon: const Icon(Icons.check_circle_outline),
          selectedIcon: const Icon(Icons.check_circle),
        ),
      );
    }
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
          ? context.l10n.textViewMarkedCorrect
          : context.l10n.textViewMarkCorrect,
      child: Semantics(toggled: correct, child: button),
    );
  }

  /// The editing tools, outlined so they read as buttons, on the left of
  /// the line: − and + on the fret under the cursor, ++ and −− moving its
  /// note up or down a string, | adding a bar line across the staff, ||
  /// ending every string together, = adding an empty six-string staff, and
  /// Overtype, a toggle (filled while on).
  /// [children] in a row [gap] apart; when [wrap], onto more lines
  /// rather than past the edge (the tools at their full size, the play-along
  /// sidebar beside them on a phone).
  static Widget _toolLine({
    required bool wrap,
    required double gap,
    required List<Widget> children,
  }) => wrap
      ? Wrap(spacing: gap, runSpacing: 4, children: children)
      : Row(mainAxisSize: MainAxisSize.min, spacing: gap, children: children);

  Widget _tools({bool wrap = false}) {
    final enabled = !_busy;
    final scheme = Theme.of(context).colorScheme;
    // On a phone, with the line to themselves, closer together and
    // Overtype an icon (its tooltip says which mode), so all of them fit
    // at their full size.
    final phone = MediaQuery.sizeOf(context).width < 600;
    final gap = phone ? 4.0 : 8.0;
    final overtypeStyle = _overtype
        ? OutlinedButton.styleFrom(
            backgroundColor: scheme.secondaryContainer,
            foregroundColor: scheme.onSecondaryContainer,
          )
        : null;
    final overtypeIcon = Icon(
      _overtype ? Icons.keyboard : Icons.keyboard_outlined,
    );
    void toggleOvertype() => setState(() => _overtype = !_overtype);
    // On a phone each tool's tap area is its 40 px button, not 48: eight
    // fit across the screen.
    return Theme(
      data: phone
          ? Theme.of(
              context,
            ).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)
          : Theme.of(context),
      child: _toolLine(
        wrap: wrap,
        gap: gap,
        children: [
          IconButton.outlined(
            tooltip: context.l10n.textViewFretDown,
            onPressed: enabled ? () => _bump(-1) : null,
            icon: const Icon(Icons.remove),
          ),
          IconButton.outlined(
            tooltip: context.l10n.textViewFretUp,
            onPressed: enabled ? () => _bump(1) : null,
            icon: const Icon(Icons.add),
          ),
          IconButton.outlined(
            tooltip: context.l10n.textViewNoteUp,
            onPressed: enabled ? () => _move(-1) : null,
            icon: const _Glyph('++'),
          ),
          IconButton.outlined(
            tooltip: context.l10n.textViewNoteDown,
            onPressed: enabled ? () => _move(1) : null,
            icon: const _Glyph('−−'),
          ),
          IconButton.outlined(
            tooltip: context.l10n.textViewBar,
            onPressed: enabled ? _bar : null,
            icon: const _Glyph('|'),
          ),
          IconButton.outlined(
            tooltip: context.l10n.textViewAlignEnds,
            onPressed: enabled ? _alignEnds : null,
            icon: const _Glyph('||'),
          ),
          IconButton.outlined(
            tooltip: context.l10n.textViewNewStaff,
            onPressed: enabled ? _newStaff : null,
            icon: const _Glyph('='),
          ),
          Tooltip(
            message: _overtype
                ? context.l10n.textViewOvertypeOn
                : context.l10n.textViewOvertypeOff,
            child: Semantics(
              toggled: _overtype,
              child: phone
                  ? IconButton.outlined(
                      key: const Key('text-overtype'),
                      onPressed: enabled ? toggleOvertype : null,
                      isSelected: _overtype,
                      style: overtypeStyle,
                      icon: overtypeIcon,
                    )
                  : OutlinedButton.icon(
                      key: const Key('text-overtype'),
                      onPressed: enabled ? toggleOvertype : null,
                      style: overtypeStyle,
                      icon: overtypeIcon,
                      label: Text(context.l10n.textViewOvertype),
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
        onTap: editable ? _tapped : null,
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

/// The Text view's text, its doubtful notes ([doubts], where they still
/// stand: doubtRanges) drawn in red.
class DoubtController extends TextEditingController {
  List<TabDoubt> _doubts = const [];
  List<TabDoubt> get doubts => _doubts;
  set doubts(List<TabDoubt> doubts) {
    if (listEquals(doubts, _doubts)) return;
    _doubts = doubts;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final ranges = doubtRanges(text, doubts);
    // While a word is being composed, the platform's underline matters more.
    if (ranges.isEmpty || (withComposing && value.isComposingRangeValid)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final doubtful = TextStyle(
      color: scheme.error,
      backgroundColor: scheme.errorContainer,
      fontWeight: FontWeight.bold,
    );
    final spans = <TextSpan>[];
    var at = 0;
    for (final (start, end) in ranges) {
      if (start > at) spans.add(TextSpan(text: text.substring(at, start)));
      spans.add(TextSpan(text: text.substring(start, end), style: doubtful));
      at = end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: spans);
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
      title: Text(context.l10n.textViewSongDialogTitle),
      content: TextField(
        controller: _song,
        autofocus: true,
        decoration: InputDecoration(
          labelText: context.l10n.textViewSongLabel,
          helperText: context.l10n.textViewSongHelper,
        ),
        onSubmitted: (s) => Navigator.pop(context, s.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.textViewCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _song.text.trim()),
          child: Text(context.l10n.textViewCheck),
        ),
      ],
    );
  }
}

const _mono = TextStyle(fontFamily: monoFont, fontSize: 15, height: 1.25);

class _Unwrapped extends StatelessWidget {
  const _Unwrapped({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // The view's width (the play-along sidebar may take some of the
      // screen's), or the screen's where unbounded.
      final width = box.hasBoundedWidth
          ? box.maxWidth
          : MediaQuery.sizeOf(context).width;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          // At least the view's width; at most 1600, or the view's when
          // wider than that.
          constraints: BoxConstraints(
            minWidth: width,
            maxWidth: width > 1600 ? width : 1600,
          ),
          child: SingleChildScrollView(child: child),
        ),
      );
    },
  );
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
    final l10n = context.l10n;
    final now = c.replacement.isEmpty ? l10n.textViewRemoved : c.replacement;
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
                    tooltip: l10n.textViewPrevious,
                    onPressed: () {
                      review.move(-1);
                      onChanged();
                    },
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(l10n.textViewPosition(i, n)),
                  IconButton(
                    tooltip: l10n.textViewNext,
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
                        style: _mono.copyWith(fontSize: 17),
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
                    label == null
                        ? l10n.textViewLineColumn(c.line + 1, c.column + 1)
                        : l10n.textViewLineStringColumn(
                            c.line + 1,
                            label,
                            c.column + 1,
                          ),
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
                    child: Text(
                      decision == false
                          ? l10n.textViewRejected
                          : l10n.textViewReject,
                    ),
                  ),
                  FilledButton(
                    onPressed: () {
                      review.decide(true);
                      onChanged();
                    },
                    child: Text(
                      decision == true
                          ? l10n.textViewAccepted
                          : l10n.textViewAccept,
                    ),
                  ),
                  PopupMenuButton<bool>(
                    tooltip: l10n.textViewAll,
                    onSelected: (accept) {
                      review.setAll(accept);
                      onChanged();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: true,
                        child: Text(l10n.textViewAcceptAll),
                      ),
                      PopupMenuItem(
                        value: false,
                        child: Text(l10n.textViewRejectAll),
                      ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Text(l10n.textViewAllMenu),
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: onDone,
                    child: Text(
                      review.decided < n
                          ? l10n.textViewDoneCount(review.decided, n)
                          : l10n.textViewDone,
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

/// A tool's text in place of an icon (`++`, `||`), in an icon's 24 px box
/// (scaled down to fit), so every tool is as wide as one with an icon.
class _Glyph extends StatelessWidget {
  const _Glyph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 24,
    child: FittedBox(fit: BoxFit.scaleDown, child: Text(text)),
  );
}
