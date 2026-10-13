import 'dart:async';

import 'file_drop_area.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/language.dart';
import '../app_version.dart';
import '../auth/auth_service.dart';
import '../capture/media.dart';
import '../capture/page_source.dart';
import '../cloud/cloud_ocr.dart';
import '../cloud/cloud_sync.dart';
import '../cloud/public_capture.dart';
import '../export/capture_link.dart';
import '../export/incoming_links.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import 'account_panel.dart';
import 'library_screen.dart';
import 'place.dart';
import 'public_capture_screen.dart';
import 'link_page.dart';

/// The app's tabs, in the bottom navigation bar's order.
enum HomeTab {
  home(Icons.home_outlined, Icons.home),
  capture(Icons.add_a_photo_outlined, Icons.add_a_photo),
  profile(Icons.person_outline, Icons.person);

  const HomeTab(this.icon, this.selectedIcon);
  final IconData icon;
  final IconData selectedIcon;

  /// This tab's name in the navigation bar, in [l10n]'s language.
  String label(AppLocalizations l10n) => switch (this) {
    home => l10n.homeTabHome,
    capture => l10n.homeTabCapture,
    profile => l10n.homeTabProfile,
  };

  /// The app bar's title on this tab.
  String title(AppLocalizations l10n) => this == home ? 'TabScan' : label(l10n);
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
    this.captures,
  });

  final Library library;

  /// Opens captures by their link (with its key) for a user they aren't
  /// shared with, read only; null in a build without the share API.
  final PublicCaptures? captures;

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
    unawaited(_restorePlace());
  }

  /// Where the user was before a reload or a restart: the tab, and the
  /// event that was open (its view and file). A capture's link wins.
  Future<void> _restorePlace() async {
    final place = await PlaceMemory.of(library).load();
    await library.ready;
    if (!mounted || _linked != null) return;
    final tab = HomeTab.values.where((t) => t.name == place.tab).firstOrNull;
    if (tab != null && tab != _tab) setState(() => _tab = tab);
    if (place.eventId case final id?) {
      if (library.byId(id) case final event?) {
        unawaited(
          openEvent(
            context,
            library,
            event,
            widget.sync,
            widget.ocr,
            place.fileId,
            place.text,
          ),
        );
      }
    }
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

  /// The capture a link named, until it's opened (or found missing), and
  /// the link.
  String? _linked;
  Uri? _link;
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
    _link = link;
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
      _snack(context.l10n.homeLinkNotHere);
      return;
    }
    if (widget.auth?.user == null) {
      if (!_askedToSignIn) {
        _askedToSignIn = true;
        _snack(context.l10n.homeLinkSignIn);
      }
      return;
    }
    switch (sync.state) {
      case SyncState.syncing:
        _passSinceLink = true;
      case SyncState.synced || SyncState.failed when _passSinceLink:
        final link = _link;
        _stopLink();
        // Not the user's, nor shared with them: by its key, read only.
        if (widget.captures case final captures?
            when link != null && PublicCaptures.opens(link)) {
          unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    PublicCaptureScreen(link: link, captures: captures),
              ),
            ),
          );
        } else {
          _snack(context.l10n.homeLinkNotShared);
        }
      case SyncState.synced || SyncState.failed:
        unawaited(sync.syncNow());
      case SyncState.signedOut:
        break; // the first pass hasn't started yet
    }
  }

  /// Runs [capture], which makes a new event (or null when cancelled), and
  /// shows it on Home.
  Future<void> _capture(
    String Function(AppLocalizations l10n, String error) failure,
    Future<CaptureEvent?> Function() capture,
  ) async {
    final CaptureEvent? event;
    try {
      event = await capture();
    } on Object catch (e) {
      if (mounted) _snack(failure(context.l10n, '$e'));
      return;
    }
    if (event == null || !mounted) return;
    PlaceMemory.of(library).update((p) => p.copyWith(tab: HomeTab.home.name));
    setState(() {
      _tab = HomeTab.home;
      _fresh = event!.id;
    });
    final l10n = context.l10n;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.homeSaved(event.title, contentsOf(event, l10n))),
          // Gone after a while, like the others: with an action, Flutter
          // would keep it until it's dismissed.
          persist: false,
          duration: savedMessageFor,
          action: SnackBarAction(
            label: l10n.homeOpen,
            onPressed: () =>
                openEvent(context, library, event!, widget.sync, widget.ocr),
          ),
        ),
      );
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _fresh == event!.id) setState(() => _fresh = null);
    });
  }

  Future<void> _scan() =>
      _capture((l10n, e) => l10n.homeScanFailed(e), () async {
        final pages = await PageSource.scan(context);
        return pages.isEmpty ? null : library.create(pages);
      });

  Future<void> _addMedia(Future<MediaPick> Function() picker) =>
      _capture((l10n, e) => l10n.homeAddFailed(e), () async {
        final pick = await picker();
        if (pick.skipped > 0 && mounted) {
          _snack(context.l10n.homeSkipped(pick.skipped));
        }
        if (pick.media.isEmpty) return null;
        return library.addMedia(await library.create(const []), pick.media);
      });

  Future<void> _addLink() async {
    final link = await askForLink(context);
    if (link == null) return;
    final (url, title) = link;
    await _capture((l10n, e) => l10n.homeAddFailed(e), () async {
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
          _tab.title(context.l10n),
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
          // Files dragged onto Capture make a new capture of them.
          FileDropArea(
            onFiles: (files, skipped) => _addMedia(() async {
              final pick = MediaPick.of(files);
              return MediaPick(pick.media, pick.skipped + skipped);
            }),
            child: CaptureView(
              onScan: _scan,
              onDocuments: () => _addMedia(MediaSource.documents),
              onPhotos: () => _addMedia(MediaSource.library),
              onFiles: () => _addMedia(MediaSource.files),
              onLink: _addLink,
            ),
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
              widget.sync?.profiles?.refresh();
            }
            setState(() => _tab = tab);
            PlaceMemory.of(library).update((p) => p.copyWith(tab: tab.name));
          },
        ),
      ),
    );
  }
}

/// What an event holds, for messages: "2 pages", "1 video, 1 link"; in
/// [l10n]'s language (the app's when null).
String contentsOf(CaptureEvent event, [AppLocalizations? l10n]) {
  final texts = l10n ?? appL10n;
  int count(bool Function(EventPage) test) => event.pages.where(test).length;
  final videos = count((p) => p.isVideo);
  final audio = count((p) => p.isAudio);
  final pdfs = count((p) => p.isPdf);
  final links = count((p) => p.isLink);
  final pages = count((p) => p.isImage);
  return [
    if (pages > 0 || pages == event.pages.length) texts.homePages(pages),
    if (videos > 0) texts.homeVideos(videos),
    if (audio > 0) texts.homeAudio(audio),
    if (pdfs > 0) texts.homePdfs(pdfs),
    if (links > 0) texts.homeLinks(links),
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
      final l10n = context.l10n;
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
                  label: t.label(l10n),
                  tooltip: l10n.homeSignedInAs(user.identity),
                ),
              _ => NavigationDestination(
                icon: Icon(t.icon),
                selectedIcon: Icon(t.selectedIcon),
                label: t.label(l10n),
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
    required this.onDocuments,
    required this.onPhotos,
    required this.onFiles,
    required this.onLink,
  });

  final VoidCallback onScan;
  final VoidCallback onDocuments;
  final VoidCallback onPhotos;
  final VoidCallback onFiles;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
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
                  label: Text(l10n.homeScan),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.homeScanDetail,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                Text(l10n.homeAdd, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                _AddTile(
                  key: const Key('add-document'),
                  icon: Icons.picture_as_pdf_outlined,
                  title: l10n.homeAddDocument,
                  detail: l10n.homeAddDocumentDetail,
                  onTap: onDocuments,
                ),
                _AddTile(
                  icon: Icons.photo_library_outlined,
                  title: l10n.homeAddPhotos,
                  detail: l10n.homeAddPhotosDetail,
                  onTap: onPhotos,
                ),
                _AddTile(
                  icon: Icons.folder_open_outlined,
                  title: l10n.homeAddFiles,
                  detail: l10n.homeAddFilesDetail,
                  onTap: onFiles,
                ),
                _AddTile(
                  icon: Icons.link,
                  title: l10n.homeAddLink,
                  detail: l10n.homeAddLinkDetail,
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
    super.key,
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

/// TabScan's privacy policy (tabscan_index/site/privacy/), the same for
/// every build and site.
final Uri privacyPolicyUrl = Uri.parse('https://tabscan.nu01.com/privacy');

/// Opens TabScan's privacy policy in the browser.
Future<void> openPrivacyPolicy(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final couldNotOpen = context.l10n.textViewCouldNotOpen('$privacyPolicyUrl');
  if (!await launchUrl(
    privacyPolicyUrl,
    mode: LaunchMode.externalApplication,
  )) {
    messenger?.showSnackBar(SnackBar(content: Text(couldNotOpen)));
  }
}

/// The language setting: the device's language, or English, Spanish or
/// Portuguese; the app changes at once.
class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.language});

  final LanguageSetting language;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.languageTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        DropdownButton<String?>(
          key: const Key('language'),
          isExpanded: true,
          icon: const Icon(Icons.language),
          value: language.code,
          onChanged: language.set,
          items: [
            DropdownMenuItem(child: Text(l10n.languageSystem)),
            for (final MapEntry(:key, :value) in LanguageSetting.names.entries)
              DropdownMenuItem(value: key, child: Text(value)),
          ],
        ),
      ],
    );
  }
}

/// The Profile tab: the account (in a build with sign-in), the language,
/// then About.
class ProfileView extends StatelessWidget {
  const ProfileView({super.key, this.auth, this.sync, this.ocr});

  final AuthService? auth;
  final CloudSync? sync;
  final CloudOcr? ocr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
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
                  Text(l10n.homeNoSignIn, style: theme.textTheme.bodyMedium),
                if (LanguageScope.maybeOf(context) case final language?) ...[
                  const Divider(height: 48),
                  _LanguagePicker(language: language),
                ],
                const Divider(height: 48),
                Text(l10n.homeAbout, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  '${AppVersion.title} '
                  '${AppVersion.version.isEmpty ? l10n.homeDevelopmentBuild : AppVersion.version}',
                ),
                const SizedBox(height: 4),
                Text(l10n.homeAboutDetail, style: theme.textTheme.bodySmall),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: () => openPrivacyPolicy(context),
                      child: Text(l10n.homePrivacyPolicy),
                    ),
                    TextButton(
                      onPressed: () => showLicensePage(
                        context: context,
                        applicationName: AppVersion.title,
                        applicationVersion: AppVersion.version,
                      ),
                      child: Text(l10n.homeLicenses),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
