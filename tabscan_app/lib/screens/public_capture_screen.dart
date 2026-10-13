import 'package:flutter/material.dart';

import '../cloud/public_capture.dart';
import '../l10n/language.dart';
import '../library/capture_event.dart';
import '../library/event_store_memory.dart' as memory;
import '../library/library.dart';
import 'event_screen.dart';

/// A capture opened by its link ([PublicCaptures]), read only: for
/// someone signed out (it's then the whole app, with **Sign in**), or
/// signed in but not one of the people it's shared with. It's kept in
/// memory only, apart from the user's library, and goes when this does.
class PublicCaptureScreen extends StatefulWidget {
  const PublicCaptureScreen({
    super.key,
    required this.link,
    required this.captures,
    this.onSignIn,
  });

  final Uri link;
  final PublicCaptures captures;

  /// Signed out: leaves for the welcome, to sign in. Null signed in.
  final VoidCallback? onSignIn;

  @override
  State<PublicCaptureScreen> createState() => _PublicCaptureScreenState();
}

class _PublicCaptureScreenState extends State<PublicCaptureScreen> {
  final Library _library = Library(memory.PlatformEventStore())..load();
  late Future<CaptureEvent> _opening = widget.captures.open(
    widget.link,
    _library,
  );

  @override
  void dispose() {
    _library.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<CaptureEvent>(
      future: _opening,
      builder: (context, snapshot) {
        if (snapshot.data case final event?) {
          return EventScreen(
            library: _library,
            eventId: event.id,
            byLink: true,
            onSignIn: widget.onSignIn,
          );
        }
        final failed = snapshot.hasError;
        return Scaffold(
          key: const Key('link-capture'),
          appBar: AppBar(title: const Text('TabScan')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: failed
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.link_off, size: 48),
                        const SizedBox(height: 16),
                        Text(l10n.linkUnavailable, textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        OutlinedButton(
                          onPressed: () => setState(() {
                            _opening = widget.captures.open(
                              widget.link,
                              _library,
                            );
                          }),
                          child: Text(l10n.linkTryAgain),
                        ),
                        if (widget.onSignIn case final signIn?) ...[
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: signIn,
                            child: Text(l10n.linkSignIn),
                          ),
                        ],
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(l10n.linkOpening),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}
