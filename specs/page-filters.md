# Page filters

Each page keeps the image as scanned; a filter is applied when it's shown,
shared or exported, and can be changed at any time, one image at a
time, with the file screen's view (**Original** or **Scan**, which is the
Tab filter; see [event screen](event-screen.md#file-screen)).

- **Tab** (the default for new pages): black ink on white paper. The page
  is turned upright (EXIF orientation), scaled to at most 2400 px on its
  long side, and thresholded adaptively: a pixel is ink when it's darker
  than 88% of the mean brightness around it (a box 1/24 of the page width,
  computed with an integral image). So shadows, uneven light and paper
  tint drop out, and thin tab lines and small fret numbers stay sharp.
  Output is PNG.
- **Original**: the page as scanned.

Filtering runs off the UI isolate (`compute`).
