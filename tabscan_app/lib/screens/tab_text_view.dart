import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../auth/auth_service.dart';
import '../library/library.dart';
import 'sign_in_gate.dart';

/// The event screen's Text view: the tab read from the event's pages, to
/// check against them and fix, monospaced and unwrapped (long lines scroll
/// sideways), with Copy and Share. Edits are saved as they're made (after
/// a second's pause) and on leaving, and make the text the user's: no
/// later read replaces it. A read that ends while it shows fills it in,
/// unless the user has started editing. Once checked, the user marks it
/// correct (**Mark correct**): the event then opens on its Text view, and
/// no read replaces it. Read only for an event shared read only.
class TabTextView extends StatefulWidget {
  const TabTextView({
    super.key,
    required this.library,
    required this.eventId,
    this.auth,
  });

  final Library library;
  final String eventId;

  /// Sharing needs the user signed in (null: a build without sign-in).
  final AuthService? auth;

  @override
  State<TabTextView> createState() => _TabTextViewState();
}

class _TabTextViewState extends State<TabTextView> {
  final _text = TextEditingController();

  /// The text as last loaded or saved: what's on screen unless edited.
  String? _known;
  Timer? _saveSoon;

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
    if (_text.text == (_known ?? '')) {
      _text.text = stored ?? '';
      _known = stored;
    }
  }

  @override
  void dispose() {
    widget.library.removeListener(_onLibrary);
    _saveSoon?.cancel();
    _save();
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

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text.text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Tab copied')));
    }
  }

  Future<void> _share() async {
    final title = widget.library.byId(widget.eventId)?.title ?? 'Tab';
    if (await requireSignIn(context, widget.auth, Gated.share)) {
      await SharePlus.instance.share(
        ShareParams(text: _text.text, subject: title),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.library.byId(widget.eventId);
    final correct = event?.tabTextCorrect ?? false;
    final editable = !(event?.readOnly ?? false);
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
                FilterChip(
                  tooltip: correct
                      ? 'Marked correct: the event opens on its text'
                      : 'Mark the reading correct',
                  avatar: Icon(
                    correct ? Icons.check_circle : Icons.check_circle_outline,
                  ),
                  showCheckmark: false,
                  label: Text(correct ? 'Correct' : 'Mark correct'),
                  selected: correct,
                  onSelected: editable ? (_) => _toggleCorrect() : null,
                ),
              TextButton.icon(
                onPressed: _share,
                icon: const Icon(Icons.ios_share),
                label: const Text('Share text'),
              ),
            ],
          ),
        ),
        Expanded(child: _editor(context)),
      ],
    );
  }

  /// The tab text, unwrapped: long lines scroll sideways.
  Widget _editor(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.sizeOf(context).width,
          maxWidth: 1600,
        ),
        child: SingleChildScrollView(
          child: TextField(
            controller: _text,
            readOnly: widget.library.byId(widget.eventId)?.readOnly ?? false,
            onChanged: _changed,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: ['Menlo', 'Courier New', 'Courier'],
              fontSize: 13,
              height: 1.25,
            ),
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
