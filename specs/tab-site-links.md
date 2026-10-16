# Tab site links

A link added to a capture (Capture → **Link**, or an event's Add →
**Link**) that points to a page on a known tab site is also **imported as
a PDF print of the page**, added after the link, and then read for tab as
any PDF is ([PDFs](tab-recognition.md#pdfs)). The link stays, to open the
page itself. Links to any other site are only links: nothing is fetched.

## The tab sites

The most popular tab sites in the app's languages
([lib/import/tab_sites.dart](../tabcam_app/lib/import/tab_sites.dart));
a link is one of theirs when its host is the domain or under it
(`tabs.ultimate-guitar.com`), over `http` or `https`:

| Site | Domains |
| --- | --- |
| Ultimate Guitar | `ultimate-guitar.com` |
| Songsterr | `songsterr.com` |
| 911Tabs | `911tabs.com` |
| GuitarTabs.cc | `guitartabs.cc` |
| AZ Chords | `azchords.com` |
| E-Chords | `e-chords.com` |
| Guitaretab | `guitaretab.com` |
| Chordie | `chordie.com` |
| Tabs4Acoustic | `tabs4acoustic.com` |
| Big Bass Tabs | `bigbasstabs.com` |
| Classtab | `classtab.org` |
| Cifra Club | `cifraclub.com.br`, `cifraclub.com` |
| Cifras | `cifras.com.br` |
| LaCuerda | `lacuerda.net` |

The cloud service's `TAB_SITES` ([tabcam_locr/locr/pages.py](../tabcam_locr/locr/pages.py))
is the same list; the two are kept the same by hand.

## Fetching the page

Following the [design guidelines](../CLAUDE.md#design-guidelines), the
device does the work ([lib/import/tab_page_import.dart](../tabcam_app/lib/import/tab_page_import.dart)):

- **Android, iOS (and desktops)**: the app fetches the page itself, as a
  mobile browser (its User-Agent), up to 20 s and 5 MB; no server is
  involved, for everyone.
- **The web**: the browser can't fetch other sites' pages (CORS), so the
  cloud OCR service's `POST /page` fetches it, for **TabCam Premium**
  users only ([cloud OCR](cloud-ocr.md#tab-sites-pages-for-the-web)).
  Without Premium, the link is added and it says "Link added. On the web,
  importing the page from {site} needs TabCam Premium."
- A Premium user's device asks the service too when its own fetch fails.

While it fetches, it says "Importing the page from {site}…".

## The tab in the page

[lib/import/tab_page.dart](../tabcam_app/lib/import/tab_page.dart):

- **Ultimate Guitar**: the tab is in the page's data (the `js-store`
  element's `data-content`, HTML-escaped JSON:
  `store.page.data.tab_view.wiki_tab.content`), with `[tab]` and `[ch]`
  marks, which are dropped; the title is "{song} by {artist}".
- **The other sites**: every `<pre>` block of more than one line, in page
  order, a blank line between them, tags dropped (`<br>` a new line) and
  HTML's character references decoded; the title is the page's
  `og:title`, or its `<title>`.
- **A plain-text page** (Classtab's `.txt`): the page is the tab.
- The text keeps its spacing (chords stay over their syllables), tabs as
  four spaces, no trailing spaces, at most one blank line in a row, up to
  200,000 characters.

A page with none of that (Songsterr's, drawn by scripts; a bot check
instead of the page) isn't imported: "Link added. Couldn't import the
page from {site}."

## The PDF

[lib/import/tab_page_pdf.dart](../tabcam_app/lib/import/tab_page_pdf.dart),
as a browser prints a page: A4, the title in bold, then the text in
Courier (columns stay lined up), 9 pt or smaller so the longest line fits
(4 pt at least; a blank line keeps its height), over as many pages as it
takes, with the page's address, the date and the page number at the foot
of each. Characters outside Latin-1 (the PDF's standard fonts) become
their plain equivalents (quotes, dashes, ♭ ♯ as `b` `#`) or `?`.

It's added as a PDF page named after the page's title (the site's name
when it has none), and the capture is named after it too when it was made
from the link and the user gave no title. "The page from {site} was added
as a PDF, to read its tab." Reading it ([PDFs](tab-recognition.md#pdfs))
finds the tab in its text, on the device, on every platform; staves one
right under another are told apart ([text tabs](tab-recognition.md#text-tabs)).

## Troubleshooting log

`TabCam: tab page import:` with the address and what happened (fetched for
Premium only on the web, the HTTP status and size, no tab's text in the
page, fetching failed, or the characters read and the PDF's size).

## Verified

- App tests: the site list (subdomains; look-alikes, other hosts and
  schemes refused); Ultimate Guitar's data, `<pre>` blocks with tags and
  entities, a plain-text page, a page without tab; the PDF's text read
  back as the tab (where PDFium loads in tests); importing adds a named
  PDF, leaves other links alone, adds nothing on a 403, fetches nothing on
  the web without Premium, and on the web with Premium asks the service.
- Service tests: see [cloud OCR](cloud-ocr.md#verified).
- A PDF of a made-up riff printed and checked by eye: title, columns,
  accents, footer.
- Not yet tried against the live sites, which may turn some clients away.

## Known limitations

- Sites change their pages: a site whose tab moves out of `<pre>` (or out
  of Ultimate Guitar's data) stops importing until the reader follows.
- Sites that draw their tabs with scripts (Songsterr) or check for bots
  import nothing; the link stays.
- A chord sheet (chords over lyrics, no staff) is imported, but reading
  finds no tab in it ("no tab").
- Only the page linked is imported, not a multi-page tab's other pages.
- For Premium users, a capture's PDFs still go to the cloud OCR as they
  sync, an imported one too, though its text is read on the device.
