import 'dart:async';

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
/// While it shows, it looks for the owner's changes every [refreshEvery]
/// and as the app comes back to the front, so a rename or a file added
/// shows within seconds.
class PublicCaptureScreen extends StatefulWidget {
  const PublicCaptureScreen({
    super.key,
    required this.link,
    required this.captures,
    this.onSignIn,
    this.refreshEvery = const Duration(seconds: 10),
  });

  final Uri link;
  final PublicCaptures captures;

  /// Signed out: leaves for the welcome, to sign in. Null signed in.
  final VoidCallback? onSignIn;

  final Duration refreshEvery;

  @override
  State<PublicCaptureScreen> createState() => _PublicCaptureScreenState();
}

class _PublicCaptureScreenState extends State<PublicCaptureScreen>
    with WidgetsBindingObserver {
  final Library _library = Library(memory.PlatformEventStore())..load();
  late Future<CaptureEvent> _opening = widget.captures.open(
    widget.link,
    _library,
  );
  Timer? _refresh;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh = Timer.periodic(widget.refreshEvery, (_) => _refreshNow());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshNow();
  }

  /// Brings in the owner's changes, once the capture shows. A failed look
  /// (offline, say) keeps what shows; the next one tries again.
  Future<void> _refreshNow() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await _opening;
      await widget.captures.refresh(widget.link, _library);
    } on Object {
      // Not open yet, or this look failed: nothing changes.
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refresh?.cancel();
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
          appBar: AppBar(title: const Text('TabCam')),
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
