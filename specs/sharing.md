# Sharing

**Share** (scan screen app bar, or a library card's menu) asks what to share
the scan as, then opens the system share sheet (`share_plus`):

- **PDF**: every image page, with its filter, fitted to an A4 page (18 pt
  margins; videos are left out); then, if the tab has been read, the text tab under the title
  in 9 pt Courier, on as many pages as it needs. The PDF's title is the
  scan's, its author the artist, its creator "TabScan".
- **Text tab**: the text tab as plain text; off (greyed, saying to read
  the tab first) until it has been read.
- **Files**: each page as a file: images with their filter (PNG for Tab,
  their own format for Original), videos as they are.

Files are named from the title and artist (`My riff - Me.pdf`,
`My riff - Me 1.png`, `My riff - Me 2.mov`), keeping only letters, digits, spaces, `.`, `_` and
`-`; `tab` if nothing is left. The subject is the scan's title.
