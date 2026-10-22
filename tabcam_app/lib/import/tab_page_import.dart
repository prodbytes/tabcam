import 'dart:async';
import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../capture/media.dart';
import '../cloud/cloud_ocr.dart';
import '../library/capture_event.dart';
import '../library/library.dart';
import 'tab_page.dart';
import 'tab_page_pdf.dart';
import 'tab_sites.dart';

export 'tab_sites.dart' show TabSite, tabSiteOf;

/// Whether this build imports tab sites' pages: the web app and desktops,
/// not the iOS and Android store apps. There a tab site's link stays a
/// link, opened in the browser, and no one's tab is fetched into the app
/// (App Review, guideline 5.2.1: third-party sheet music). Tests set it.
bool importsTabSites =
    kIsWeb ||
    (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS);

/// The tab site [url] is on, when this build imports its pages
/// ([importsTabSites]); null otherwise.
TabSite? importableTabSite(Uri url) => importsTabSites ? tabSiteOf(url) : null;

/// How importing a tab site's page went.
enum TabImportOutcome {
  /// The page's tab was added, as a PDF.
  imported,

  /// On the web, without Premium: the browser can't fetch other sites'
  /// pages, and the service fetches them for Premium users only.
  needsPremium,

  /// The page couldn't be fetched, or had no tab's text.
  failed,
}

/// What importing [site]'s page did; [event] as it is now.
typedef TabImport = ({
  TabSite site,
  TabImportOutcome outcome,
  CaptureEvent event,
  TabPage? page,
});

/// Imports a link to a tab site ([tabSites]) as a PDF print of its page,
/// which the event's reading then reads as any PDF ([AutoReader]).
///
/// The device fetches the page itself (Android, iOS, desktops): no server
/// is involved. The web can't (other sites don't allow it, CORS), so there
/// the cloud OCR service fetches it ([CloudOcr.fetchPage]), for Premium
/// users only; it's also asked when the device's fetch fails, for them.
class TabPageImporter {
  TabPageImporter({this.ocr, this.client, bool? onDevice})
    : _onDevice = onDevice ?? !kIsWeb;

  /// Makes the screens' importer (tests give theirs a fake client).
  static TabPageImporter Function(CloudOcr? ocr) create = (ocr) =>
      TabPageImporter(ocr: ocr);

  final CloudOcr? ocr;

  /// Fetches the pages; null: a new client per page.
  final http.Client? client;
  final bool _onDevice;

  /// The largest page fetched.
  static const int maxBytes = 5 << 20;

  /// Sites answer a browser; some turn other clients away.
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.8',
  };

  /// Adds [url]'s page to [event] as a PDF, when [url] is on a tab site
  /// and this build imports them ([importsTabSites]); null otherwise
  /// (nothing is fetched).
  Future<TabImport?> addTo(Library library, CaptureEvent event, Uri url) async {
    final site = importableTabSite(url);
    if (site == null) return null;
    TabImport done(TabImportOutcome outcome, [TabPage? page]) =>
        (site: site, outcome: outcome, event: event, page: page);
    final premium = ocr?.premium ?? false;
    if (!_onDevice && !premium) {
      _log('$url: on the web, fetched for Premium only');
      return done(TabImportOutcome.needsPremium);
    }
    TabPage? page;
    if (_onDevice) page = await _onDeviceFetch(url, site);
    if (page == null && premium) page = await _cloudFetch(url, site);
    if (page == null) return done(TabImportOutcome.failed);
    final pdf = await tabPagePdf(page);
    final name = page.title.isEmpty ? site.name : page.title;
    // A reader's print is their contribution's, as the link is.
    final before = {for (final p in Library.addedPages(event)) p.id};
    event = await library.addMedia(event, [
      Media(
        XFile.fromData(pdf, name: '$name.pdf', mimeType: 'application/pdf'),
        PageKind.pdf,
        'pdf',
      ),
    ]);
    // Named after the page (a file from bytes has no name everywhere).
    final added = Library.addedPages(event)
        .lastWhere((p) => !before.contains(p.id));
    event = await library.renamePage(event.id, added.id, name) ?? event;
    _log('$url: ${page.text.length} characters, a PDF of ${pdf.length} bytes');
    return done(TabImportOutcome.imported, page);
  }

  Future<TabPage?> _onDeviceFetch(Uri url, TabSite site) async {
    final client = this.client ?? http.Client();
    try {
      final r = await client
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200 || r.bodyBytes.length > maxBytes) {
        _log('$url: HTTP ${r.statusCode}, ${r.bodyBytes.length} bytes');
        return null;
      }
      final type = r.headers['content-type'];
      final page = parseTabPage(
        _decode(r.bodyBytes, type),
        url,
        site,
        contentType: type,
      );
      if (page == null) _log('$url: no tab\'s text in the page');
      return page;
    } on Object catch (e) {
      _log('$url: fetching on the device failed: $e');
      return null;
    } finally {
      if (this.client == null) client.close();
    }
  }

  Future<TabPage?> _cloudFetch(Uri url, TabSite site) async {
    try {
      final fetched = await ocr!.fetchPage(url);
      final page = parseTabPage(
        fetched.body,
        url,
        site,
        contentType: fetched.contentType,
      );
      if (page == null) _log('$url: no tab\'s text in the page (cloud)');
      return page;
    } on Object catch (e) {
      _log('$url: fetching in the cloud failed: $e');
      return null;
    }
  }

  static String _decode(Uint8List bytes, String? contentType) {
    final charset = RegExp(
      r'charset=([\w-]+)',
      caseSensitive: false,
    ).firstMatch(contentType ?? '')?.group(1)?.toLowerCase();
    return switch (charset) {
      'iso-8859-1' || 'latin1' || 'windows-1252' => latin1.decode(bytes),
      _ => utf8.decode(bytes, allowMalformed: true),
    };
  }

  static void _log(String message) =>
      debugPrint('TabCam: tab page import: $message');
}
