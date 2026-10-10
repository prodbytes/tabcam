import 'dart:async';

import 'package:flutter/material.dart';

import '../app_version.dart';
import '../auth/auth_service.dart';
import '../capture/media.dart';
import '../capture/page_source.dart';
import '../cloud/cloud_ocr.dart';
import '../cloud/cloud_sync.dart';
import '../export/capture_link.dart';
import '../export/incoming_links.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import 'account_panel.dart';
import 'library_screen.dart';
import 'link_page.dart';

/// The app's tabs, in the bottom navigation bar's order.
enum HomeTab {
  home('Home', Icons.home_outlined, Icons.home),
  capture('Capture', Icons.add_a_photo_outlined, Icons.add_a_photo),
  profile('Profile', Icons.person_outline, Icons.person);

  const HomeTab(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// The app bar's title on this tab.
  String get title => this == home ? 'TabScan' : label;
}

/// The app's frame, as Presence's: a bottom navigation bar flips between
/// Home (the events), Capture (Scan, and Add for uploads) and Profile (the
/// account and About), each with its name in the app bar. A capture lands
/// on Home, at the top of the list, outlined, with Open in the message
/// that confirms it.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.library,
    this.auth,
    this.sync,
    this.ocr,
  });

  final Library library;

  /// Sign-in and sync, in a build that has them; null otherwise.
  final AuthService? auth;
  final CloudSync? sync;

  /// TabScan Premium's cloud transcription, in a build that has it.
  final CloudOcr? ocr;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeTab _tab = HomeTab.home;

  /// The event just captured, outlined for a moment.
  String? _fresh;

  Library get library => widget.library;

  /// How long "Saved … (Open)" shows after a capture.
  static const Duration savedMessageFor = Duration(seconds: 6);

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  @override
  void initState() {
    super.initState();
    // Opened from a capture's link (…/app/?c=<id>), now or later.
    IncomingLinks.instance.addListener(_incoming);
    _incoming();
  }

  @override
  void dispose() {
    IncomingLinks.instance.removeListener(_incoming);
    _stopLink();
    super.dispose();
  }

  void _incoming() {
    if (IncomingLinks.instance.take() case final link?) openLink(link);
  }

  /// The capture a link named, until it's opened (or found missing).
  String? _linked;
  bool _askedToSignIn = false;
  bool _passSinceLink = false;

  /// Opens the capture [link] names ([CaptureLink]), found by its ID among
  /// the user's own and those shared with them: right away if it's here,
  /// else once signed in and a sync pass has brought it.
  void openLink(Uri link) {
    final id = CaptureLink.idIn(link);
    if (id == null) return;
    _stopLink();
    _linked = id;
    _askedToSignIn = false;
    _passSinceLink = false;
    library.addListener(_tryLink);
    widget.sync?.addListener(_tryLink);
    widget.auth?.addListener(_tryLink);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryLink());
  }

  void _stopLink() {
    _linked = null;
    library.removeListener(_tryLink);
    widget.sync?.removeListener(_tryLink);
    widget.auth?.removeListener(_tryLink);
  }

  void _tryLink() {
    final id = _linked;
    if (id == null || !mounted || !library.loaded) return;
    if (library.byId(id) case final event?) {
      _stopLink();
      openEvent(context, library, event, widget.sync, widget.ocr);
      return;
    }
    final sync = widget.sync;
    if (sync == null) {
      _stopLink();
      _snack('That capture isn\'t on this device.');
      return;
    }
    if (widget.auth?.user == null) {
      if (!_askedToSignIn) {
        _askedToSignIn = true;
        _snack('Sign in (Profile) to open the capture in this link.');
      }
      return;
    }
    switch (sync.state) {
      case SyncState.syncing:
        _passSinceLink = true;
      case SyncState.synced || SyncState.failed when _passSinceLink:
        _stopLink();
        _snack(
          'That capture isn\'t shared with you. Ask its owner to share it '
          'with your email address.',
        );
      case SyncState.synced || SyncState.failed:
        unawaited(sync.syncNow());
      case SyncState.signedOut:
        break; // the first pass hasn't started yet
    }
  }

  /// Runs [capture], which makes a new event (or null when cancelled), and
  /// shows it on Home.
  Future<void> _capture(
    String failure,
    Future<CaptureEvent?> Function() capture,
  ) async {
    final CaptureEvent? event;
    try {
      event = await capture();
    } on Object catch (e) {
      if (mounted) _snack('$failure: $e');
      return;
    }
    if (event == null || !mounted) return;
    setState(() {
      _tab = HomeTab.home;
      _fresh = event!.id;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Saved "${event.title}" (${contentsOf(event)})'),
          // Gone after a while, like the others: with an action, Flutter
          // would keep it until it's dismissed.
          persist: false,
          duration: savedMessageFor,
          action: SnackBarAction(
            label: 'Open',
            onPressed: () =>
                openEvent(context, library, event!, widget.sync, widget.ocr),
          ),
        ),
      );
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _fresh == event!.id) setState(() => _fresh = null);
    });
  }

  Future<void> _scan() => _capture('Couldn\'t scan', () async {
    final pages = await PageSource.scan(context);
    return pages.isEmpty ? null : library.create(pages);
  });

  Future<void> _addMedia({required bool files}) =>
      _capture('Couldn\'t add', () async {
        final pick = files
            ? await MediaSource.files()
            : await MediaSource.library();
        if (pick.skipped > 0 && mounted) {
          _snack(
            '${pick.skipped} '
            '${pick.skipped == 1 ? 'file isn\'t' : 'files aren\'t'} '
            'a photo or video, so not added.',
          );
        }
        if (pick.media.isEmpty) return null;
        return library.addMedia(await library.create(const []), pick.media);
      });

  Future<void> _addLink() async {
    final link = await askForLink(context);
    if (link == null) return;
    final (url, title) = link;
    await _capture('Couldn\'t add', () async {
      var event = await library.create(const []);
      event = await library.addLink(event, url, title: title);
      // A link's title names its event, when it has one.
      final name = title?.trim() ?? '';
      return name.isEmpty ? event : library.update(event.copyWith(title: name));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Text(
          _tab.title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
      ),
      body: IndexedStack(
        index: _tab.index,
        children: [
          LibraryView(
            library: library,
            sync: widget.sync,
            ocr: widget.ocr,
            fresh: _fresh,
          ),
          CaptureView(
            onScan: _scan,
            onPhotos: () => _addMedia(files: false),
            onFiles: () => _addMedia(files: true),
            onLink: _addLink,
          ),
          ProfileView(auth: widget.auth, sync: widget.sync, ocr: widget.ocr),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        // A hairline between the page and the bar.
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: _NavigationBar(
          tab: _tab,
          auth: widget.auth,
          onSelected: (tab) {
            // Opening Profile checks again whether the user is premium
            // (they may have just upgraded).
            if (tab == HomeTab.profile && widget.auth?.user != null) {
              widget.ocr?.refresh();
            }
            setState(() => _tab = tab);
          },
        ),
      ),
    );
  }
}

/// What an event holds, for messages: "2 pages", "1 video, 1 link".
String contentsOf(CaptureEvent event) {
  String count(int n, String one) => '$n $one${n == 1 ? '' : 's'}';
  final videos = event.pages.where((p) => p.isVideo).length;
  final links = event.pages.where((p) => p.isLink).length;
  final pages = event.pages.length - videos - links;
  return [
    if (pages > 0 || videos + links == 0) count(pages, 'page'),
    if (videos > 0) count(videos, 'video'),
    if (links > 0) count(links, 'link'),
  ].join(', ');
}

/// The bottom navigation bar: an icon over its label per tab, the open one
/// filled and in the accent color (the theme's `navigationBarTheme`). The
/// Profile tab's icon is the signed-in user's photo.
class _NavigationBar extends StatelessWidget {
  const _NavigationBar({
    required this.tab,
    required this.auth,
    required this.onSelected,
  });

  final HomeTab tab;
  final AuthService? auth;
  final ValueChanged<HomeTab> onSelected;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: auth ?? const _Never(),
    builder: (context, _) {
      final user = auth?.user;
      final accent = Theme.of(context).colorScheme.primary;
      return NavigationBar(
        selectedIndex: tab.index,
        onDestinationSelected: (i) => onSelected(HomeTab.values[i]),
        destinations: [
          for (final t in HomeTab.values)
            switch ((t, user)) {
              (HomeTab.profile, final user?) when user.photoUrl != null =>
                NavigationDestination(
                  icon: _Avatar(user: user, ring: null),
                  selectedIcon: _Avatar(user: user, ring: accent),
                  label: t.label,
                  tooltip: 'Signed in as ${user.identity}',
                ),
              _ => NavigationDestination(
                icon: Icon(t.icon),
                selectedIcon: Icon(t.selectedIcon),
                label: t.label,
              ),
            },
        ],
      );
    },
  );
}

/// A listenable that never changes, for a build without sign-in.
class _Never implements Listenable {
  const _Never();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

/// The Profile tab's icon signed in: the user's photo, 24 dp, ringed in the
/// accent color while the tab is open.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, required this.ring});

  final AuthUser user;
  final Color? ring;

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    padding: const EdgeInsets.all(1.5),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: ring ?? Colors.transparent, width: 1.5),
    ),
    child: CircleAvatar(backgroundImage: NetworkImage(user.photoUrl!)),
  );
}

/// The Capture tab: Scan (the camera) and Add (uploads: photos and videos,
/// files, a link). Each makes a new event.
class CaptureView extends StatelessWidget {
  const CaptureView({
    super.key,
    required this.onScan,
    required this.onPhotos,
    required this.onFiles,
    required this.onLink,
  });

  final VoidCallback onScan;
  final VoidCallback onPhotos;
  final VoidCallback onFiles;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: onScan,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    textStyle: theme.textTheme.titleLarge,
                  ),
                  icon: const Icon(Icons.document_scanner_outlined, size: 32),
                  label: const Text('Scan'),
                ),
                const SizedBox(height: 8),
                Text(
                  'With the camera: the page is found, straightened and '
                  'cleaned up, and you can take several in a row.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                Text('Add', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                _AddTile(
                  icon: Icons.photo_library_outlined,
                  title: 'Photos & videos',
                  detail: 'From your photo library',
                  onTap: onPhotos,
                ),
                _AddTile(
                  icon: Icons.folder_open_outlined,
                  title: 'Files',
                  detail: 'Image and video files',
                  onTap: onFiles,
                ),
                _AddTile(
                  icon: Icons.link,
                  title: 'Link',
                  detail: 'A lesson, a recording, the song online',
                  onTap: onLink,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(detail),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

/// The Profile tab: the account (in a build with sign-in), then About.
class ProfileView extends StatelessWidget {
  const ProfileView({super.key, this.auth, this.sync, this.ocr});

  final AuthService? auth;
  final CloudSync? sync;
  final CloudOcr? ocr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((auth, sync) case (final auth?, final sync?))
                  AccountPanel(auth: auth, sync: sync, ocr: ocr)
                else
                  Text(
                    'Sign-in isn\'t set up in this build: your events stay '
                    'on this device.',
                    style: theme.textTheme.bodyMedium,
                  ),
                const Divider(height: 48),
                Text('About', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  '${AppVersion.title} '
                  '${AppVersion.version.isEmpty ? '(development build)' : AppVersion.version}',
                ),
                const SizedBox(height: 4),
                Text(
                  'Scan guitar tabs, read them as text, and share them.',
                  style: theme.textTheme.bodySmall,
                ),
                TextButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: AppVersion.title,
                    applicationVersion: AppVersion.version,
                  ),
                  child: const Text('Licenses'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
