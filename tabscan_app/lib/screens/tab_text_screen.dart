import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../auth/auth_service.dart';
import '../library/library.dart';
import 'sign_in_gate.dart';

/// The text tab read from an event, to check against the pages and fix:
/// monospaced, unwrapped (long lines scroll sideways), saved on leaving.
/// Read only for an event shared read only.
class TabTextScreen extends StatefulWidget {
  const TabTextScreen({
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
  State<TabTextScreen> createState() => _TabTextScreenState();
}

class _TabTextScreenState extends State<TabTextScreen> {
  late final _text = TextEditingController(
    text: widget.library.byId(widget.eventId)?.tabText ?? '',
  );

  @override
  void dispose() {
    _save();
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final event = widget.library.byId(widget.eventId);
    if (event != null && !event.readOnly && event.tabText != _text.text) {
      widget.library.update(event.copyWith(tabText: _text.text));
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text.text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Tab copied')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.library.byId(widget.eventId)?.title ?? 'Tab';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Text tab'),
        actions: [
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.ios_share),
            onPressed: () async {
              if (await requireSignIn(context, widget.auth, Gated.share)) {
                await SharePlus.instance.share(
                  ShareParams(text: _text.text, subject: title),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: _copy,
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
              ),
            ),
          ),
          Expanded(child: _editor(context)),
        ],
      ),
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
        child: TextField(
          controller: _text,
          readOnly: widget.library.byId(widget.eventId)?.readOnly ?? false,
          maxLines: null,
          expands: false,
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
    );
  }
}
