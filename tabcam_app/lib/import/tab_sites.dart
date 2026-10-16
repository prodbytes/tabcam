/// A website that publishes guitar tabs: a link to one of its pages is
/// imported as a PDF of the page's tab ([TabPageImporter]).
class TabSite {
  const TabSite(this.name, this.domains);

  /// The site's name, for messages ("Ultimate Guitar").
  final String name;

  /// Its domains: a host is the site's when it is one of them or under one
  /// (`tabs.ultimate-guitar.com`).
  final List<String> domains;

  bool hosts(String host) =>
      domains.any((d) => host == d || host.endsWith('.$d'));
}

/// The most popular tab sites, in English, Spanish and Portuguese (the
/// app's languages). The cloud OCR service fetches pages for the web from
/// these same domains only (`TAB_SITES` in tabcam_locr/locr/pages.py):
/// keep the two lists the same.
const List<TabSite> tabSites = [
  TabSite('Ultimate Guitar', ['ultimate-guitar.com']),
  TabSite('Songsterr', ['songsterr.com']),
  TabSite('911Tabs', ['911tabs.com']),
  TabSite('GuitarTabs.cc', ['guitartabs.cc']),
  TabSite('AZ Chords', ['azchords.com']),
  TabSite('E-Chords', ['e-chords.com']),
  TabSite('Guitaretab', ['guitaretab.com']),
  TabSite('Chordie', ['chordie.com']),
  TabSite('Tabs4Acoustic', ['tabs4acoustic.com']),
  TabSite('Big Bass Tabs', ['bigbasstabs.com']),
  TabSite('Classtab', ['classtab.org']),
  TabSite('Cifra Club', ['cifraclub.com.br', 'cifraclub.com']),
  TabSite('Cifras', ['cifras.com.br']),
  TabSite('LaCuerda', ['lacuerda.net']),
];

/// The tab site [url] is on, or null (any other site, or not a web link).
TabSite? tabSiteOf(Uri url) {
  if (url.scheme != 'https' && url.scheme != 'http') return null;
  final host = url.host.toLowerCase();
  for (final site in tabSites) {
    if (site.hosts(host)) return site;
  }
  return null;
}
