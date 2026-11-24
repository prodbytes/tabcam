import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cloud/cloud_ocr.dart';
import '../cloud/ocr_api.dart';
import '../dictionary/dictionary_sidebar.dart' show DictionaryState, TabWriter;
import '../library/library.dart';
import '../recognition/tab_doubts.dart';
import '../recognition/tab_layout.dart';
import 'tab_editing.dart';
import '../l10n/language.dart';
import 'mono_font.dart';
import 'messages.dart';
import 'text_zoom.dart';

/// The event screen's Text view: the tab read from the event's pages, to
/// check against them and fix, monospaced and unwrapped (long lines scroll
/// sideways). The notes the read wasn't sure of (likely wrong) are in red,
/// until the user changes them or marks the text Verified. Edits are saved
/// as they're made (after a second's pause) and on leaving, and make the
/// text the user's: no later read replaces it. A
/// read that ends while it shows fills it in, unless the user has started
/// editing. Read only for an event shared read only.
///
/// Above it, in one row, on the right: first **Columns**, a toggle
/// showing the tab split in half, side by side, to read (not edit: the
/// editing tools hide while it's on), an icon alone set before the
/// labelled ones; **Copy**; **Fix** (off for now,
/// see [showFix]): lines the tab up, then with Premium auto-correct: the
/// song's tab found online proposes corrections, shown per note for the
/// user to accept or reject; **Rescan**, reading the tab from the pages
/// again (a timer counts while it reads); and **Verified**, a toggle marking the text checked (the event
/// then opens on its Text view, and no read replaces it). On the row's
/// left, the editing tools, round and outlined: first the **Overtype**
/// toggle (off by default: insert), making typing replace characters instead of
/// pushing the line right; the **Vertical selection** toggle, a drag then
/// selecting a block (the same columns on every line); **Select all**
/// (⌘A) and **Select phrase** (⌘L, again the next one too); **−** and
/// **+** change the fret under the
/// cursor, **++** and **−−** move its note to the line above or below,
/// **|** and **=** put a bar or a dash down the phrase, **|>** and **<|**
/// end every phrase's lines together at the last or the first end, and
/// **New phrase** adds an empty one. With notes selected, the tools (and
/// Copy) work on them alone ([_selected]). To check the
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
    this.rescanStarted,
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

  /// When Rescan's read started: while [rescanning], a timer after
  /// "Rescanning the pages…" counts from it (m:ss).
  final DateTime? rescanStarted;

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

class _TabTextViewState extends State<TabTextView> implements TabWriter {
  final _text = DoubtController();

  /// The text as last loaded or saved: what's on screen unless edited.
  String? _known;
  Timer? _saveSoon;
  bool _overtype = false;

  /// Vertical selection is on: a drag (or Shift and the arrows) selects a
  /// block, the same columns on each line ([TextBlock]), drawn by the
  /// controller ([DoubtController.block]) in place of the field's own.
  bool _vertical = false;

  /// The vertical selection, while [_vertical]; null with just a cursor.
  TextBlock? _block;

  /// The field's selection standing for [_block] (its corners): while the
  /// field's is still this one, the block stands; a new one (a drag, a
  /// tap) makes the block anew.
  TextSelection? _blockSelection;

  final _focus = FocusNode(debugLabel: 'Text view');

  /// Columns is on: the text shows split in half, side by side, to
  /// read; turned off to edit.
  bool _columns = false;

  /// How large the text shows: its usual size times this ([textZooms]).
  /// Not kept: the view opens at the usual size.
  double _zoom = 1;

  /// Drag to move is on: a drag moves the text instead of editing or
  /// selecting it ([TextMover]).
  bool _dragging = false;

  final _mover = GlobalKey<TextMoverState>();

  /// The editor's scrolls, down and sideways, and the two columns': down,
  /// and each column's sideways.
  final _down = ScrollController();
  final _across = ScrollController();
  final _columnsDown = ScrollController();
  final _leftAcross = ScrollController();
  final _rightAcross = ScrollController();

  /// The tab's text style at the [_zoom].
  TextStyle get _zoomed => _mono.copyWith(fontSize: _mono.fontSize! * _zoom);

  /// Fix is asking the service.
  bool _checking = false;

  /// Fix is looking online, or Rescan reading: the text can't be edited.
  bool get _busy => _checking || widget.rescanning;

  /// Fix's answer, while the user reviews it.
  _Review? _review;

  String? get _stored =>
      widget.sample ?? widget.library.byId(widget.eventId)?.tabText;

  /// The doubtful notes to show in red: none once the text is Verified
  /// (marking it clears them; this also hides any a text verified before
  /// that, or on an older app, still has).
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
    _text.addListener(_onText);
    widget.library.addListener(_onLibrary);
    widget.ocr?.addListener(_onPremium);
    // The dictionary's + writes here, in a text that can be changed (not
    // the locked preview's sample, or a capture shared to read).
    final event = widget.library.byId(widget.eventId);
    if (widget.sample == null && event != null && !event.readOnly) {
      DictionaryState.instance.attach(this);
    }
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
    DictionaryState.instance.detach(this);
    if (widget.actions?._view == this) widget.actions!._attach(null);
    widget.library.removeListener(_onLibrary);
    widget.ocr?.removeListener(_onPremium);
    _saveSoon?.cancel();
    _save();
    _review?.dispose();
    _text.dispose();
    _focus.dispose();
    for (final c in [_down, _across, _columnsDown, _leftAcross, _rightAcross]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The text or its selection changed: with vertical selection on, a new
  /// selection (a drag, Shift and an arrow, a tap) makes the block anew,
  /// its corners where the selection starts and ends; a cursor ends it.
  void _onText() {
    if (!_vertical) return;
    final selection = _text.selection;
    if (selection != _blockSelection) {
      _blockSelection = selection;
      _block = selection.isValid && !selection.isCollapsed
          ? TextBlock.corners(_text.text, selection)
          : null;
    }
    _paintBlock();
  }

  /// The block drawn where it is in the text now.
  void _paintBlock() {
    final block = _vertical ? _block : null;
    _text.block = block == null
        ? const []
        : block.ranges(_text.text.split('\n'));
  }

  /// Selects [block] (with vertical selection on), in [text] when given:
  /// an edit's, which takes the place of the text.
  void _selectBlock(TextBlock block, [String? text]) {
    final now = text ?? _text.text;
    final selection = block.selectionIn(now.split('\n'));
    _block = block;
    _blockSelection = selection;
    _text.value = TextEditingValue(text: now, selection: selection);
    _paintBlock();
  }

  void _toggleVertical() {
    setState(() => _vertical = !_vertical);
    // On, what's selected becomes a block, the selection's ends its
    // corners; off, the field's selection shows again.
    final selection = _text.selection;
    _blockSelection = selection;
    _block = _vertical && selection.isValid && !selection.isCollapsed
        ? TextBlock.corners(_text.text, selection)
        : null;
    _paintBlock();
  }

  /// What the tools act on: the selected notes' lines and columns, the
  /// vertical selection's or the text selected (that one while the text
  /// has the focus: unfocused, it doesn't show). Null with nothing
  /// selected: they act at the cursor.
  List<LineSpan>? get _selected {
    final block = _vertical ? _block : null;
    if (block != null) return block.spans(_text.text.split('\n'));
    final selection = _text.selection;
    if (!_focus.hasFocus || selection.isCollapsed) return null;
    final spans = selectionSpans(_text.text, selection);
    return spans.isEmpty ? null : spans;
  }

  /// The vertical selection, if that's what [_selected] is.
  TextBlock? get _selectedBlock => _vertical ? _block : null;

  /// [text] in the text's place, after an edit that kept its lines where
  /// they were: the selection kept on the same lines and columns, moved
  /// right by one on the [shifted] lines from column [from] on (where |
  /// and = put a column in).
  void _keepSelection(
    String text, {
    Set<int> shifted = const {},
    int from = 0,
  }) {
    final block = _selectedBlock;
    if (block != null) {
      _selectBlock(
        shifted.isEmpty
            ? block
            : block.copyWith(left: block.left + 1, right: block.right + 1),
        text,
      );
    } else {
      final old = _text.text;
      final selection = _text.selection;
      int kept(int offset) {
        final (line, column) = lineColumn(old, offset);
        final moved = shifted.contains(line) && column >= from;
        return offsetAt(text, line, moved ? column + 1 : column);
      }

      _text.value = TextEditingValue(
        text: text,
        selection: TextSelection(
          baseOffset: kept(selection.baseOffset),
          extentOffset: kept(selection.extentOffset),
        ),
      );
    }
    _changed(text);
  }

  /// Whether the keys' shortcuts use ⌘ (macOS, iOS) rather than Ctrl.
  static bool get _apple =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// A shortcut's name for the tooltips: ⌘A, or Ctrl+A.
  static String _shortcut(String key) => _apple ? '⌘$key' : 'Ctrl+$key';

  /// Select all (⌘A): the whole text, as a block with vertical selection
  /// on.
  void _selectAll() {
    final text = _text.text;
    if (text.isEmpty) return;
    _focus.requestFocus();
    if (_vertical) {
      final lines = text.split('\n');
      _selectBlock(TextBlock.whole(lines, 0, lines.length - 1));
    } else {
      _text.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    }
  }

  /// Select phrase (⌘L): with nothing selected, the cursor's phrase (or
  /// else the next one below it, or the last above); with a selection, the
  /// phrases it reaches, whole, and when it's just them already, the next
  /// phrase too.
  void _selectPhrase() {
    final text = _text.text;
    final lines = text.split('\n');
    final spans = _selected;
    ({int top, int bottom})? phrases;
    if (spans == null) {
      final at = _text.selection.isValid
          ? lineColumn(text, _text.selection.extentOffset).$1
          : 0;
      phrases =
          phrasesAround(lines, at, at) ??
          phraseBelow(lines, at) ??
          phraseAbove(lines, at);
    } else {
      final (top, bottom) = (spans.first.line, spans.last.line);
      phrases = phrasesAround(lines, top, bottom);
      if (phrases == null) {
        phrases = phraseBelow(lines, bottom) ?? phraseAbove(lines, top);
      } else if (_selectsWhole(lines, phrases)) {
        final next = phraseBelow(lines, phrases.bottom);
        if (next == null) {
          _say(context.l10n.textViewNoMorePhrases);
          return;
        }
        phrases = (top: phrases.top, bottom: next.bottom);
      }
    }
    if (phrases == null) {
      _say(context.l10n.textViewNoPhrase);
      return;
    }
    _focus.requestFocus();
    if (_vertical) {
      _selectBlock(TextBlock.whole(lines, phrases.top, phrases.bottom));
    } else {
      _text.selection = TextSelection(
        baseOffset: offsetAt(text, phrases.top, 0),
        extentOffset: offsetAt(
          text,
          phrases.bottom,
          lines[phrases.bottom].length,
        ),
      );
    }
  }

  /// Whether the selection is lines [lines]'s [phrases], whole, already.
  bool _selectsWhole(List<String> lines, ({int top, int bottom}) phrases) {
    final block = _selectedBlock;
    if (block != null) {
      return block == TextBlock.whole(lines, phrases.top, phrases.bottom);
    }
    final text = _text.text;
    final selection = _text.selection;
    return selection.start == offsetAt(text, phrases.top, 0) &&
        selection.end ==
            offsetAt(text, phrases.bottom, lines[phrases.bottom].length);
  }

  /// The Text view's keys, in the text: ⌘A (Ctrl+A off Apple's systems)
  /// selects all, ⌘L the phrase (again, the next one too); with a vertical
  /// selection ⌘C and ⌘X copy and cut it (the field's own, or the
  /// browser's, would take the text from its first corner to its last).
  KeyEventResult _key(KeyEvent event, {required bool editable}) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final command = _apple ? keys.isMetaPressed : keys.isControlPressed;
    final other = _apple ? keys.isControlPressed : keys.isMetaPressed;
    if (!command || other || keys.isAltPressed || keys.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyA) {
      _selectAll();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyL) {
      _selectPhrase();
      return KeyEventResult.handled;
    }
    if (_selectedBlock == null) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.keyC) {
      _copy(quiet: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyX && editable) {
      _cutBlock();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Cut, with a vertical selection: its text copied, then its columns
  /// cleared on each of its lines ([replaceBlock], as Backspace does).
  void _cutBlock() {
    final block = _selectedBlock;
    if (block == null) return;
    final lines = _text.text.split('\n');
    Clipboard.setData(
      ClipboardData(text: spansText(lines, block.spans(lines))),
    );
    final (:text, :cursor) = replaceBlock(
      _text.text,
      block,
      typed: '',
      overtype: _overtype,
    );
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor),
    );
    _changed(text);
  }

  /// The field's menu (a long press, on a phone): with a vertical
  /// selection, its Copy and Cut take the block, and Select all makes one.
  Widget _menu(BuildContext context, EditableTextState field) {
    final block = _selectedBlock;
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: field.contextMenuAnchors,
      buttonItems: [
        for (final item in field.contextMenuButtonItems)
          switch (item.type) {
            ContextMenuButtonType.selectAll when _vertical => item.copyWith(
              onPressed: () {
                _selectAll();
                field.hideToolbar();
              },
            ),
            ContextMenuButtonType.copy when block != null => item.copyWith(
              onPressed: () {
                _copy(quiet: true);
                field.hideToolbar();
              },
            ),
            ContextMenuButtonType.cut when block != null => item.copyWith(
              onPressed: () {
                _cutBlock();
                field.hideToolbar();
              },
            ),
            _ => item,
          },
      ],
    );
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
  /// Marking it clears every red note for good: the user has checked them
  /// all, so unmarking it doesn't bring them back.
  Future<void> _toggleCorrect() async {
    _save();
    final event = widget.library.byId(widget.eventId);
    if (event == null || event.readOnly) return;
    final correct = !event.tabTextCorrect;
    await widget.library.update(
      event.copyWith(
        tabTextCorrect: correct,
        tabTextDoubts: correct ? const [] : null,
      ),
    );
    if (mounted) setState(() {});
  }

  /// Shows [message] in place of the one showing. With an [action] (the
  /// Premium offer's Upgrade) it stays until it's dismissed or acted on,
  /// as the SnackBar it was did.
  void _say(String message, {MessageAction? action}) {
    if (!mounted) return;
    replaceMessage(context, message, action: action, persist: action != null);
  }

  /// Copy: what's selected (a vertical selection a line of it per line),
  /// or else the whole text. [quiet] (⌘C) says nothing, as copying in any
  /// field.
  Future<void> _copy({bool quiet = false}) async {
    final spans = _selected;
    final block = _selectedBlock;
    final text = spans == null
        ? _text.text
        : block != null
        ? spansText(_text.text.split('\n'), spans)
        : _text.selection.textInside(_text.text);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted || quiet) return;
    _say(
      spans == null
          ? context.l10n.textViewTabCopied
          : context.l10n.textViewSelectionCopied,
    );
  }

  void _bump(int delta) {
    if (_selected case final spans?) {
      final (:text, :failure) = bumpSelected(_text.text, spans, delta);
      if (text == null) {
        _say(
          failure == SelectionFailure.outOfRange
              ? context.l10n.textViewFretLimit
              : context.l10n.textViewNoNotesSelected,
        );
      } else {
        _keepSelection(text);
      }
      return;
    }
    final value = bumpNumber(_text.value, delta);
    if (value == null) {
      _say(context.l10n.textViewPutCursorOnFret);
      return;
    }
    _text.value = value;
    _changed(value.text);
  }

  /// ++ and −−: the note under the cursor up or down a string; with notes
  /// selected, all of them. A vertical selection follows them: its
  /// columns on the lines they went to.
  void _move(int delta) {
    if (_selected case final spans?) {
      final (:text, :rows, :failure) = moveSelected(_text.text, spans, delta);
      if (text == null || rows == null) {
        _say(
          failure == SelectionFailure.noRoom
              ? context.l10n.textViewNoRoomSelected
              : context.l10n.textViewNoNotesSelected,
        );
        return;
      }
      if (_selectedBlock case final block?) {
        _selectBlock(
          block.copyWith(
            top: rows.reduce(math.min),
            bottom: rows.reduce(math.max),
          ),
          text,
        );
        _changed(text);
      } else {
        _keepSelection(text);
      }
      return;
    }
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

  /// | and = on a selection: [put] into its string lines alone, at its
  /// first column; the selection moves right with what it had.
  void _putOnSelected(
    List<LineSpan> spans,
    String? Function(String text, Iterable<int> rows, int column) put,
  ) {
    final rows = [for (final s in spans) s.line];
    final column = _selectedBlock?.left ?? spans.first.start;
    final text = put(_text.text, rows, column);
    if (text == null) {
      _say(context.l10n.textViewSelectStrings);
      return;
    }
    _keepSelection(text, shifted: rows.toSet(), from: column);
  }

  /// |: a bar line across the cursor's staff, at its column; with a
  /// selection, on its lines alone.
  void _bar() {
    if (_selected case final spans?) return _putOnSelected(spans, barOnLines);
    final value = insertBar(_text.value);
    if (value == null) {
      _say(context.l10n.textViewPutCursorOnString);
      return;
    }
    _text.value = value;
    _changed(value.text);
  }

  /// =: a dash down the cursor's phrase, at its column; with a selection,
  /// on its lines alone.
  void _spacer() {
    if (_selected case final spans?) {
      return _putOnSelected(spans, spacerOnLines);
    }
    final value = insertSpacer(_text.value);
    if (value == null) {
      _say(context.l10n.textViewPutCursorOnString);
      return;
    }
    _text.value = value;
    _changed(value.text);
  }

  /// |> and <|: every phrase's lines end together, at the last end
  /// ([alignEnds]) or the first ([trimEnds]); with a selection, only its
  /// lines.
  void _endTogether(
    TextEditingValue? Function(
      TextEditingValue value, {
      ({int top, int bottom})? lines,
    })
    end,
  ) {
    final spans = _selected;
    final value = end(
      _text.value,
      lines: spans == null
          ? null
          : (top: spans.first.line, bottom: spans.last.line),
    );
    if (value == null) {
      _say(context.l10n.textViewNoStaff);
      return;
    }
    if (value.text == _text.text) {
      _say(context.l10n.textViewEndsAligned);
      return;
    }
    if (spans != null) return _keepSelection(value.text);
    _text.value = value;
    _changed(value.text);
  }

  /// New phrase: an empty six-line phrase under the cursor's line or
  /// phrase; with a selection, under its last line's.
  void _newStaff() {
    var value = _text.value;
    if (_selected case final spans?) {
      value = value.copyWith(
        selection: TextSelection.collapsed(
          offset: offsetAt(value.text, spans.last.line, 0),
        ),
      );
    }
    value = newStaff(value);
    _text.value = value;
    _changed(value.text);
  }

  /// The dictionary's +: a chord's voicing or a scale written at the
  /// cursor's phrase, or in a new phrase, its name above the phrase
  /// ([writeColumns]); the cursor
  /// after it, so the next one follows. Not while Rescan reads or Fix's
  /// review shows.
  @override
  void write(List<List<int?>> columns, {String? name}) {
    if (!mounted) return;
    if (_busy || _review != null || _columns) {
      _say(context.l10n.dictionaryWriteBusy);
      return;
    }
    final value = writeColumns(_text.value, columns, name: name);
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
      // Offered only to a user the service said has no Premium.
      final offer = ocr != null && ocr.free && widget.onUpgrade != null;
      _say(
        offer
            ? l10n.textViewFixLinedUpPremium
            : lined
            ? l10n.textViewFixLinedUp
            : l10n.textViewFixAlreadyLinedUp,
        action: offer
            ? MessageAction(
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
                ? (editable && review == null && !_columns
                      ? _tools(wrap: true)
                      : const SizedBox.shrink())
                : Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: editable && review == null && !_columns
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
            child: _checking
                ? Text(context.l10n.textViewLookingOnline)
                : Row(
                    children: [
                      Flexible(child: Text(context.l10n.textViewRescanning)),
                      if (widget.rescanStarted case final since?) ...[
                        const SizedBox(width: 8),
                        _Elapsed(key: const Key('rescan-timer'), since: since),
                      ],
                    ],
                  ),
          ),
        ],
        Expanded(
          child: review != null
              ? _ReviewView(
                  review: review,
                  onChanged: () => setState(() {}),
                  onDone: _finishReview,
                )
              : _zoomable(
                  _columns
                      ? _twoColumns(context)
                      : _editor(context, editable && !_busy),
                ),
        ),
      ],
    );
  }

  /// The text (the editor, or the two columns) zoomable and movable
  /// ([TextMover]), with Drag to move, Zoom in and Zoom out over its
  /// bottom right ([TextViewControls]), as a PDF's.
  Widget _zoomable(Widget text) {
    final across = !_columns
        ? [_across]
        : [_leftAcross, if (splitInHalf(_text.text) != null) _rightAcross];
    return Stack(
      children: [
        Positioned.fill(
          child: TextMover(
            key: _mover,
            zoom: _zoom,
            onZoom: (zoom) => setState(() => _zoom = zoom),
            dragging: _dragging,
            down: _columns ? _columnsDown : _down,
            across: across,
            child: text,
          ),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          // In the text field's tap region: zooming keeps the cursor in
          // the text.
          child: TextFieldTapRegion(
            child: TextViewControls(
              zoom: _zoom,
              onZoom: (zoom) => _mover.currentState?.zoomTo(zoom),
              dragging: _dragging,
              onDragging: (on) {
                // Moving, not typing: the keyboard goes.
                if (on) FocusScope.of(context).unfocus();
                setState(() => _dragging = on);
              },
            ),
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

  /// Columns (an icon, first, before the labelled ones), Copy, Fix
  /// (when shown), Rescan (when there's something to read) and Verified:
  /// labelled buttons, or icons with their tooltips when
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
      _columnsToggle(enabled: review == null, compact: compact),
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
      // Off while the text is Verified, so a checked tab isn't read over
      // (unmark it to rescan).
      if (editable && widget.onRescan != null)
        compact
            ? IconButton(
                key: const Key('text-rescan'),
                tooltip: correct
                    ? l10n.textViewRescanVerified
                    : l10n.textViewRescanTip,
                onPressed: idle && !correct ? _rescan : null,
                icon: const Icon(Icons.document_scanner_outlined),
              )
            : Tooltip(
                message: correct
                    ? l10n.textViewRescanVerified
                    : l10n.textViewRescanTip,
                child: FilledButton.tonalIcon(
                  key: const Key('text-rescan'),
                  onPressed: idle && !correct ? _rescan : null,
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

  /// Columns, a toggle: a round icon button, tonal while off and
  /// filled while on, its name in the tooltip; [compact], a plain icon,
  /// filled and in the primary colour while on, as Verified. Its icon is
  /// two columns ([_columnsIcon]), as the text shows with it on.
  Widget _columnsToggle({required bool enabled, required bool compact}) {
    final l10n = context.l10n;
    final onPressed = enabled
        ? () {
            // Pending edits saved first: the columns show what's saved.
            _saveSoon?.cancel();
            _save();
            FocusScope.of(context).unfocus();
            setState(() => _columns = !_columns);
          }
        : null;
    final tip = _columns ? l10n.textViewColumnsOn : l10n.textViewColumnsTip;
    if (compact) {
      return Semantics(
        toggled: _columns,
        child: IconButton(
          key: const Key('text-columns'),
          tooltip: tip,
          isSelected: _columns,
          color: _columns ? Theme.of(context).colorScheme.primary : null,
          onPressed: onPressed,
          icon: _columnsIcon(filled: false),
          selectedIcon: _columnsIcon(filled: true),
        ),
      );
    }
    // Round, an icon alone, so the app bar keeps room for the title.
    final button = _columns
        ? IconButton.filled(
            key: const Key('text-columns'),
            tooltip: tip,
            onPressed: onPressed,
            icon: _columnsIcon(filled: true),
          )
        : IconButton.filledTonal(
            key: const Key('text-columns'),
            tooltip: tip,
            onPressed: onPressed,
            icon: _columnsIcon(filled: false),
          );
    return Semantics(toggled: _columns, child: button);
  }

  /// Two columns side by side, filled or outlined: Material's two
  /// stacked bars turned upright (its column icon has three).
  static Widget _columnsIcon({required bool filled}) => RotatedBox(
    quarterTurns: 1,
    child: Icon(filled ? Icons.view_agenda : Icons.view_agenda_outlined),
  );

  /// Columns: the text split in half ([splitInHalf]), the first half
  /// on the left and the second on the right, scrolling down together;
  /// each column's long lines scroll sideways on their own. The red notes
  /// stay red. To read, not edit (the text can still be selected).
  Widget _twoColumns(BuildContext context) {
    final text = _text.text;
    final split = splitInHalf(text);
    final scheme = Theme.of(context).colorScheme;
    final ranges = doubtRanges(text, _text.doubts);
    final doubtful = TextStyle(
      color: scheme.error,
      backgroundColor: scheme.errorContainer,
      fontWeight: FontWeight.bold,
    );
    // [text] from [from] to [to], its red notes in red, scrolling sideways
    // with [across].
    Widget column(int from, int to, Key key, ScrollController across) {
      final spans = <TextSpan>[];
      var at = from;
      for (final (start, end) in ranges) {
        final s = start < from ? from : start;
        final e = end > to ? to : end;
        if (s >= e) continue;
        if (s > at) spans.add(TextSpan(text: text.substring(at, s)));
        spans.add(TextSpan(text: text.substring(s, e), style: doubtful));
        at = e;
      }
      if (at < to) spans.add(TextSpan(text: text.substring(at, to)));
      return SingleChildScrollView(
        key: key,
        controller: across,
        physics: const TextZoomScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(16),
        child: Text.rich(
          TextSpan(style: _zoomed, children: spans),
          softWrap: false,
        ),
      );
    }

    return SelectionArea(
      child: SingleChildScrollView(
        controller: _columnsDown,
        physics: const TextZoomScrollPhysics(),
        child: split == null
            ? Align(
                alignment: Alignment.topLeft,
                child: column(
                  0,
                  text.length,
                  const Key('text-column-left'),
                  _leftAcross,
                ),
              )
            : Stack(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: column(
                          0,
                          split.leftEnd,
                          const Key('text-column-left'),
                          _leftAcross,
                        ),
                      ),
                      Expanded(
                        child: column(
                          split.rightStart,
                          text.length,
                          const Key('text-column-right'),
                          _rightAcross,
                        ),
                      ),
                    ],
                  ),
                  // A line down the middle, as tall as the longer column.
                  Positioned.fill(
                    child: Center(
                      child: Container(width: 1, color: scheme.outlineVariant),
                    ),
                  ),
                ],
              ),
      ),
    );
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

  /// The editing tools, round and outlined so they read as buttons, on
  /// the left of the line: Overtype first, a toggle (filled while on);
  /// − and + on the fret under the cursor, ++ and −− moving its note up or
  /// down a line, | a bar and = a dash down the phrase, |> and <| ending
  /// every phrase's lines together at the last or the first end, and New
  /// phrase adding an empty one.
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
    // On a phone, with the line to themselves, closer together, so as
    // many as can fit at their full size do.
    final phone = MediaQuery.sizeOf(context).width < 600;
    final gap = phone ? 4.0 : 8.0;
    // On a phone each tool's tap area is its 40 px button, not 48.
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
          // First, set apart from the edits: how typing works.
          Tooltip(
            message: _overtype
                ? context.l10n.textViewOvertypeOn
                : context.l10n.textViewOvertypeOff,
            child: Semantics(
              toggled: _overtype,
              child: IconButton.outlined(
                key: const Key('text-overtype'),
                onPressed: enabled
                    ? () => setState(() => _overtype = !_overtype)
                    : null,
                isSelected: _overtype,
                style: _overtype
                    ? IconButton.styleFrom(
                        backgroundColor: scheme.secondaryContainer,
                        foregroundColor: scheme.onSecondaryContainer,
                      )
                    : null,
                icon: const Icon(Icons.keyboard_outlined),
                selectedIcon: const Icon(Icons.keyboard),
              ),
            ),
          ),
          // Then how selecting works, and the two quick selections.
          Tooltip(
            message: _vertical
                ? context.l10n.textViewVerticalOn
                : context.l10n.textViewVerticalOff,
            child: Semantics(
              toggled: _vertical,
              child: IconButton.outlined(
                key: const Key('text-vertical'),
                onPressed: enabled ? _toggleVertical : null,
                isSelected: _vertical,
                style: _vertical
                    ? IconButton.styleFrom(
                        backgroundColor: scheme.secondaryContainer,
                        foregroundColor: scheme.onSecondaryContainer,
                      )
                    : null,
                icon: const Icon(Icons.highlight_alt),
              ),
            ),
          ),
          IconButton.outlined(
            key: const Key('text-select-all'),
            tooltip: context.l10n.textViewSelectAll(_shortcut('A')),
            onPressed: enabled ? _selectAll : null,
            icon: const Icon(Icons.select_all),
          ),
          IconButton.outlined(
            key: const Key('text-select-phrase'),
            tooltip: context.l10n.textViewSelectPhrase(_shortcut('L')),
            onPressed: enabled ? _selectPhrase : null,
            icon: const Icon(Icons.view_headline),
          ),
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
            key: const Key('text-spacer'),
            tooltip: context.l10n.textViewSpacer,
            onPressed: enabled ? _spacer : null,
            icon: const _Glyph('='),
          ),
          IconButton.outlined(
            key: const Key('text-ends-last'),
            tooltip: context.l10n.textViewEndsLast,
            onPressed: enabled ? () => _endTogether(alignEnds) : null,
            icon: const _Glyph('|>'),
          ),
          IconButton.outlined(
            key: const Key('text-ends-first'),
            tooltip: context.l10n.textViewEndsFirst,
            onPressed: enabled ? () => _endTogether(trimEnds) : null,
            icon: const _Glyph('<|'),
          ),
          IconButton.outlined(
            key: const Key('text-new-phrase'),
            tooltip: context.l10n.textViewNewStaff,
            onPressed: enabled ? _newStaff : null,
            icon: const Icon(Icons.playlist_add),
          ),
        ],
      ),
    );
  }

  /// The tab text, unwrapped: long lines scroll sideways. The column
  /// ruler over it ([_ColumnRuler]).
  Widget _editor(BuildContext context, bool editable) {
    return _Unwrapped(
      zoom: _zoom,
      down: _down,
      across: _across,
      ruler: _ColumnRuler(text: _text, style: _zoomed, zoom: _zoom),
      // Its keys first, before the app's: ⌘A, ⌘L, and ⌘C and ⌘X on a
      // vertical selection ([_key]).
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) => _key(event, editable: editable),
        // With vertical selection on, the field's selection (from the
        // block's first corner to its last) is invisible: the controller
        // draws the block. Always here, so the field isn't rebuilt anew
        // (and unfocused) when it's turned on or off.
        child: DefaultSelectionStyle.merge(
          selectionColor: _vertical ? Colors.transparent : null,
          child: TextField(
            controller: _text,
            focusNode: _focus,
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
            inputFormatters: [
              BlockFormatter(() => _selectedBlock, overtype: () => _overtype),
              OvertypeFormatter(() => _overtype),
            ],
            contextMenuBuilder: _menu,
            style: _zoomed,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
            ),
          ),
        ),
      ),
    );
  }
}

/// [elapsed] as m:ss (h:mm:ss from an hour on): Rescan's timer, and how
/// long it took.
String elapsedText(Duration elapsed) {
  String two(int n) => n.toString().padLeft(2, '0');
  final s = elapsed.isNegative ? 0 : elapsed.inSeconds;
  return s >= 3600
      ? '${s ~/ 3600}:${two(s ~/ 60 % 60)}:${two(s % 60)}'
      : '${s ~/ 60}:${two(s % 60)}';
}

/// The time since [since] ([elapsedText]), counting each second, in
/// figures of one width so it doesn't jiggle.
class _Elapsed extends StatefulWidget {
  const _Elapsed({super.key, required this.since});

  final DateTime since;

  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    elapsedText(DateTime.now().difference(widget.since)),
    style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
  );
}

/// The Text view's text, its doubtful notes ([doubts], where they still
/// stand: doubtRanges) drawn in red, and a vertical selection ([block])
/// in the selection's colour.
class DoubtController extends TextEditingController {
  List<TabDoubt> _doubts = const [];
  List<TabDoubt> get doubts => _doubts;
  set doubts(List<TabDoubt> doubts) {
    if (listEquals(doubts, _doubts)) return;
    _doubts = doubts;
    notifyListeners();
  }

  /// A vertical selection's characters, as ranges of offsets (a line's
  /// part each, top to bottom: [TextBlock.ranges]); none without one.
  List<(int, int)> _block = const [];
  List<(int, int)> get block => _block;
  set block(List<(int, int)> ranges) {
    if (listEquals(ranges, _block)) return;
    _block = ranges;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final doubtful = doubtRanges(text, doubts);
    final selected = [
      for (final (s, e) in _block)
        if (s < e && e <= text.length) (s, e),
    ];
    // While a word is being composed, the platform's underline matters more.
    if ((doubtful.isEmpty && selected.isEmpty) ||
        (withComposing && value.isComposingRangeValid)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final doubt = TextStyle(
      color: scheme.error,
      backgroundColor: scheme.errorContainer,
      fontWeight: FontWeight.bold,
    );
    final highlight =
        theme.textSelectionTheme.selectionColor ??
        scheme.primary.withValues(alpha: 0.4);
    // Cut where either kind starts or ends; each piece styled by what
    // it's in (a selected red note keeps its red, on the selection).
    final cuts = <int>{
      0,
      text.length,
      for (final (s, e) in [...doubtful, ...selected]) ...[s, e],
    }.toList()..sort();
    final spans = <TextSpan>[];
    var d = 0, b = 0;
    for (var i = 0; i + 1 < cuts.length; i++) {
      final (from, to) = (cuts[i], cuts[i + 1]);
      while (d < doubtful.length && doubtful[d].$2 <= from) {
        d++;
      }
      while (b < selected.length && selected[b].$2 <= from) {
        b++;
      }
      final inDoubt = d < doubtful.length && doubtful[d].$1 <= from;
      final inBlock = b < selected.length && selected[b].$1 <= from;
      spans.add(
        TextSpan(
          text: text.substring(from, to),
          style: inDoubt
              ? (inBlock ? doubt.copyWith(backgroundColor: highlight) : doubt)
              : inBlock
              ? TextStyle(backgroundColor: highlight)
              : null,
        ),
      );
    }
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
  const _Unwrapped({
    this.zoom = 1,
    this.down,
    this.across,
    this.ruler,
    required this.child,
  });

  /// The text's zoom: its widest lines as many times wider.
  final double zoom;

  /// Its scrolls, down and sideways (Fix's review has its own).
  final ScrollController? down;
  final ScrollController? across;

  /// Over the text, scrolling sideways with it but not down: the column
  /// ruler, in the editor.
  final Widget? ruler;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // The view's width (the play-along sidebar may take some of the
      // screen's), or the screen's where unbounded.
      final width = box.hasBoundedWidth
          ? box.maxWidth
          : MediaQuery.sizeOf(context).width;
      // At least the view's width; at most 1600 (times the zoom), or the
      // view's when wider than that.
      final most = 1600 * zoom;
      final text = SingleChildScrollView(
        controller: down,
        physics: const TextZoomScrollPhysics(),
        child: child,
      );
      final ruler = this.ruler;
      return SingleChildScrollView(
        controller: across,
        physics: const TextZoomScrollPhysics(),
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: width,
            maxWidth: width > most ? width : most,
          ),
          child: ruler == null
              ? text
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ruler,
                    Expanded(child: text),
                  ],
                ),
        ),
      );
    },
  );
}

/// The editor's column ruler, over its text: the columns numbered every
/// five, a dot on each of the others ([columnRuler]), in the text's own
/// font and size ([style], zoomed with it) and from its left margin, so
/// each stands over its column, scrolling sideways with the text and
/// staying put as it scrolls down. The cursor's column (the character
/// it's before) is marked. Across the whole width; to look at, not read
/// out, and a tap on it keeps the cursor in the text.
class _ColumnRuler extends StatelessWidget {
  const _ColumnRuler({
    required this.text,
    required this.style,
    required this.zoom,
  });

  final TextEditingController text;
  final TextStyle style;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    // The text field's style: the theme's bodyLarge under the text's, as
    // a Material 3 field has it (its letter spacing too), so each column
    // is as wide as the text's.
    final style = (theme.textTheme.bodyLarge ?? const TextStyle()).merge(
      this.style,
    );
    return TextFieldTapRegion(
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              // As many columns as the width holds.
              final probe = TextPainter(
                text: TextSpan(text: '0' * 10, style: style),
                textDirection: TextDirection.ltr,
                textScaler: scaler,
              )..layout();
              final column = probe.width / 10;
              probe.dispose();
              final ruler = columnRuler(
                column > 0 ? ((box.maxWidth - 16) / column).ceil() : 0,
              );
              return ListenableBuilder(
                listenable: text,
                builder: (context, _) {
                  final at = cursorColumn(text.value);
                  final dim = style.copyWith(color: scheme.onSurfaceVariant);
                  return Padding(
                    padding: EdgeInsets.fromLTRB(16, 6 * zoom, 0, 2 * zoom),
                    child: Text.rich(
                      key: const Key('text-ruler'),
                      TextSpan(
                        style: dim,
                        children: [
                          if (at == null || at >= ruler.length)
                            TextSpan(text: ruler)
                          else ...[
                            TextSpan(text: ruler.substring(0, at)),
                            TextSpan(
                              text: ruler[at],
                              style: TextStyle(
                                color: scheme.onPrimaryContainer,
                                backgroundColor: scheme.primaryContainer,
                              ),
                            ),
                            TextSpan(text: ruler.substring(at + 1)),
                          ],
                        ],
                      ),
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      textScaler: scaler,
                    ),
                  );
                },
              );
            },
          ),
        ),
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
