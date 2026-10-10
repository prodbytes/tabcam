# Sharing

**Share** (event screen app bar, or a library card's menu) asks what to share
the event as, then opens the system share sheet (`share_plus`). Signed
out, it asks to sign in first ([signed out](cloud-sync.md#signed-out)):

- **PDF**: every image page, with its filter, fitted to an A4 page (18 pt
  margins; videos are left out); then the links, if any, under "Links",
  one per line ("Title: address", or the address), each a clickable link;
  then, if the tab has been read, the text tab under the title in 9 pt
  Courier, on as many pages as it needs. The PDF's title is the
  event's, its author the artist, its creator "TabScan".
- **Text**: the text tab, then a blank line and the links, one per line
  ("Title: address", or the address), as plain text; off (greyed, saying
  to read the tab first) while there's neither.
- **Files**: each image and video as a file: images with their filter
  (PNG for Tab, their own format for Original), videos as they are; links
  are left out (they're in Text and the PDF).

Files are named from the title and artist (`My riff - Me.pdf`,
`My riff - Me 1.png`, `My riff - Me 2.mov`), keeping only letters, digits, spaces, `.`, `_` and
`-`; `tab` if nothing is left. The subject is the event's title.
