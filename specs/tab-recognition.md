# Tab recognition

Every capture's tab is read **by itself** into its text tab, shown in the
[event screen](event-screen.md)'s **Text** view. With [TabCam
Premium](cloud-ocr.md) the cloud transcribes it as the pages sync;
otherwise ML Kit text recognition (Latin script) reads it on the device,
Android and iOS only (below).

## Reading by itself

`AutoReader` ([lib/recognition/auto_reader.dart](../tabcam_app/lib/recognition/auto_reader.dart))
watches the library and reads only the tabs not read yet: when the user
adds or changes the image or PDF pages of an event **without a text tab**
(a new capture, pages added to one with none, rotated, deleted or
reordered), that event is read, one event at a time ([PDFs](#pdfs)
below). An event that has a text tab (from a read, on the device or in
the cloud, or written by the user; a blank one counts as none) isn't
read again by itself when its pages change: only when the user asks
(**Read again** below). Pages changed while it was read are read again;
a read writes only the text, onto the event as it is then
(`Library.patch`), so pages added meanwhile aren't lost. Other changes
(the title, the view, the text) don't read, nor do events another device
changed (that device reads them), nor the events there were at launch.

- **Read again**: the Text view's **Read again** or **Read**, or the
  [Text tool](event-screen.md) tapped while the Text view shows a tab
  (it asks "Read the tab again?" first), reads the event now
  (`readSoon(id, again: true)`), replacing the text an earlier read left;
  with Premium the cloud reads every page again.
- **Rescan** (the Text view's, below) reads every page again
  (`readSoon(id, replace: true)`): a tab found replaces any text, the
  user's too; none found, or a failure, keeps the text as it was.
- **A text the user edited is never replaced** otherwise, nor one marked
  correct, not even by Read again. A read fills an empty text tab, or replaces one
  an earlier read left (`tabTextAuto`, synced: set by a read on the
  device or in the cloud, cleared by an edit).
- **Signed out** (in a build with sign-in): it waits, and reads when the
  user signs in ([signed out](cloud-sync.md#signed-out)).
- **Premium**: the pages go to the cloud transcription; the text comes
  with sync. Reading ends once it does (any library change, sync's too,
  that brings the event a text tab), or when the cloud's results are
  collected (`CloudOcr.collected`: a tab, or "No tab found").
- **Given up**: a read still on the device, or still waiting on the
  cloud, after `cloudReadTimeout` (three times the OCR worker's Lambda
  timeout, `Timeout: 900` in `tabcam_infra/ocr.yaml`: 45 minutes) fails
  ("Reading the tab failed.", with Read again). The timer is the
  reader's, so it runs while the user is away from the capture; a text
  that comes later still fills in, and then the failure is gone.
- **Gone**: a deleted event's reading state is dropped.
- **Neither** (the web without Premium): it says it can't read here.

The Text view says how it stands when there's no text yet: "Reading the
tab…" (with a spinner); "Transcribing in the cloud. The text appears here
when it's done."; "No tab found in the pages. Try rescanning closer and
flatter." or "Reading the tab failed.", with **Read again**; "Reading
tabs needs you signed in.", with **Sign in**; "Reading tabs needs the
Android or iOS app, or TabCam Premium."; "Nothing to read: add a scan or
a photo."; or, for an event never read (from before), "Not read yet."
with **Read**. Its log lines start with `TabCam: read tab:`.

## On the device

Each page (as scanned, not filtered) is turned upright, scaled to at most
2400 px and made grayscale. Staff lines are found in that image, and OCR
runs on the same image (through a temporary file, deleted after), so their
coordinates agree. Pages with tab are joined with a blank line. With
nothing found, the Text view says so; with a result, it's saved on the
event (and shows in the Text view, if it's open).

## Text tabs

Tabs printed from websites, where OCR reads whole lines (`e|--0--3--|`).
A line is tab when, after an optional string name and bar line, at least 4
characters remain, 80% of them are tab characters (digits, `-`, `|`, `h`,
`p`, `b`, `r`, `s`, `x`, `/`, `\`, `~`, brackets, `.`, `*`, `:`, spaces)
and 30% are dashes. Before the check, OCR's usual misreadings are fixed:
long dashes, `_` and `=` become `-`; `O`/`o` become `0`; `l`, `I`, `!`
become `1`; `S` becomes `5`.

Consecutive tab lines are a staff; other lines (titles, chord names,
lyrics, "Chorus") end it. Staves of fewer than four lines are dropped.
The lines are named `e B G D A E` (six lines) or `G D A E` (four, bass),
or kept unnamed for other counts, and every line of a staff ends at the
same column, so the strings line up and a chord's notes sit in one
column:

- **On a grid**, when OCR says where each character is (ML Kit's symbol
  boxes; an element without them has its box shared evenly between its
  characters): each character after the string name and bar goes at the
  column its x implies, measured from the staff's start (the median of
  where its lines' bodies start) in the staff's character pitch (the
  median gap between neighbouring characters). The dashes OCR dropped or
  doubled don't shift the notes after them; the gaps are dashes, a note
  never overwrites another (it takes the next free column), and every
  line is padded with dashes to the longest.
- **Otherwise** (no character positions), each line as read: spaces
  become dashes and the lines are padded with dashes to one length.

## Notations around the tab

The page's other notations are kept with the tab, where they are on the
page: titles, section names, chord names, lyrics. OCR's lines are taken
top to bottom. A line of text is kept when it has a letter and isn't
noise: a web address, a page number ("2", "Page 1/2", "1 of 3"), a
garbled tab line (30% or more dashes) or mostly stray marks (more than
20% characters other than letters, digits, spaces and `# / ( ) ' , . ! ?
: ; & + -`). On text tabs each word goes at the tab's column its position
implies (on the staff's grid, or measured from the tab lines' starts and
letter width), so chord
names stay over the notes they're played on; without positions the line
is kept as read.

Joined: a blank line between two staves and after a staff, none before a
staff (a chord line or a section name sits right above it):

```
Verse
   Am      G
e|-0-------3-|
B|-1-------0-|
...

la la la
```

A page with text but no tab still has no tab (no text tab is made). The
[cloud](cloud-ocr.md#transcription) keeps the same notations.

## Typeset tabs

Books and Guitar Pro printouts: fret numbers sit on drawn staff lines, and
OCR finds only the numbers.

- **Staff lines**: a row of pixels is part of a line when at least 45% of
  it is ink (staff lines cross most of the page, broken only by the
  numbers on them; a row through text is mostly paper). Adjacent rows
  make one line. Lines with about the same gap (within 30%, at most a
  tenth of the page height) form a group; groups of six (guitar) or four
  (bass) are staves. Five-line groups (standard notation) are ignored.
- **Frets**: each OCR word that's a fret (one or two digits, or `x` for a
  mute, after fixing `O`→0, `l`/`I`/`|`/`!`→1, `X`→x) is placed on its
  staff's nearest line, if it's within half a line gap of the staff.
- **Layout**: frets less than half a digit height apart in x form a
  column (a chord). Columns are written left to right, padded to their
  widest fret, with 1–8 dashes before each, by the distance from the
  previous column. Each staff becomes a block like:

  ```
  e|-----3--|
  B|-----1--|
  G|-----0--|
  D|---0----|
  A|-2------|
  E|3-------|
  ```

- **Notations**: OCR's text lines off the staves (more than half a line
  gap away), not made of frets only, and not noise (as above), go between
  the staves by their height on the page, as read.

Text tabs are tried first; typeset layout runs when no text tab is found.

## PDFs

A PDF page (Capture → Document, or Files) is read like a photo, into the
text tab ([lib/recognition/pdf_reader.dart](../tabcam_app/lib/recognition/pdf_reader.dart)):

1. **Its text**, where it has one (a tab printed from a website, a
   typeset book): each page's text and every character's box, from PDFium
   (`pdfrx`, on every platform, the web too), become lines with their
   words and positions ([lib/recognition/pdf_lines.dart](../tabcam_app/lib/recognition/pdf_lines.dart)),
   laid out as a text tab is ([text tabs](#text-tabs), with its
   [notations](#notations-around-the-tab): chord names at their columns,
   lyrics, titles).
2. **A scanned PDF**, with no tab in its text: its pages rendered at
   2400 px (the longer side), on white, and read by the device's OCR
   (Android and iOS; the web has none).

The event's pages are read in their order: each run of photos together,
each PDF on its own; the texts are joined by a blank line. On the web, a
PDF's text is read though photos can't be; a scanned PDF there says that
reading it needs the Android or iOS app, or TabCam Premium (not "no tab
found").

With **TabCam Premium**, PDFs are read as if their pages were
photographed, everywhere: an event of PDFs only first tries their text on
the device (exact, at once); a scanned PDF, or an event with photos, goes
to the [cloud](cloud-ocr.md#transcription), which renders each PDF page
and reads it as it reads a photo. "Nothing to read" now asks for
a scan, a photo or a PDF.

## Troubleshooting log

Reading logs each step, in lines starting `TabCam: read tab:` (on
Android: `devbox run android-log`; on the web: the browser's console):
the event's pages and whether the user is signed in; which reading it
takes (cloud for Premium, with the premium status, else on the device and
whether the platform can); per page, the bytes, the prepared image's size
and the drawn staves found, what OCR found (blocks, lines, frets, the
first five lines) and whether it read a text tab, a typeset tab or
neither, with the time taken. A failure is logged with its stack trace as
well as shown. Tokens are never logged.

## Text view

Tabs show in **Roboto Mono**, a fixed-width font shipped with the app
(SIL Open Font License, [assets/fonts/](../tabcam_app/assets/fonts/RobotoMono-OFL.txt);
[`monoFont`](../tabcam_app/lib/screens/mono_font.dart)), so a staff's
strings of the same length end together everywhere, the web included
(it has no system monospace font to use: before, it fell back to a
proportional one and the strings came out ragged). The Text view's tab is
15 px, the review's lines 17 px; the cards' and the list's previews use the
same font.

The event screen's Text view ([lib/screens/tab_text_view.dart](../tabcam_app/lib/screens/tab_text_view.dart)):
the read tab, unwrapped (long lines scroll sideways), in a
text editor to fix what OCR got wrong. Edits are saved a second after the
last one, and on leaving, and make the text the user's (no read replaces
it). A read that ends while the view shows fills it in, unless the user
has started editing. Read only for an event shared read only (no editing
tools, no Fix). Sharing is the event screen's **Share** in the app bar.

**Doubtful notes in red**: the notes the [cloud](cloud-ocr.md#doubtful-notes)
read with little confidence, likely wrong, are in red, bold, on a light
red background, and under the editing tools a line says so: "Notes in red
were read with low confidence and may be wrong: check them against the
page." (en, es, pt). They're kept on the event and sync with it
(`tabTextDoubts`: `[[line, column, note]]`), and a clone keeps them. A
note is red only while it's still where it was read and the same, a whole
note (not part of a longer one): once the user changes it, it's black, and
saving drops it; moving it (inserting before it on its line) does too.
Marking the text **Verified** shows none (the user checked it); a **Rescan**
that finds a tab replaces them with the text, and the new reading
brings its own. A read on
the device says nothing of how sure it is: its text has none
([lib/recognition/tab_doubts.dart](../tabcam_app/lib/recognition/tab_doubts.dart)).

Above the text, on one line, three compact buttons of one kind (four in
a build that shows Fix), in this order (on a screen too narrow for them the line is scaled down, never
wrapped):

- **Copy**: the text, to the clipboard.
- **Fix**, hidden for now (shown only in a build with `TABCAM_FIX=true`,
  see [auto-correct](autocorrect.md#hidden-for-now)): lines the tab up (each staff's strings named, bars lined up,
  every string ending together), for everyone; then, with Premium,
  [auto-correct](autocorrect.md): the song's tab found online proposes
  corrections, which the user reviews per note.
- **Rescan**: replaces the text with a new reading of every photo and
  PDF in the capture. It asks "Rescan the pages?" ("Every photo and PDF
  is read again. A tab found replaces the current text, even if you
  edited it or marked it verified; if none is found, the text is
  kept.", **Cancel** / **Rescan**), then reads every page again
  (`readSoon(id, replace: true)`, which reads again too; with Premium,
  in the cloud). The text stays until the read ends: meanwhile the Text
  view spins (a progress bar, "Rescanning the pages…"), and the text,
  Fix, Rescan and Verified wait. Only once a tab is found does it
  replace the text, as a read of its own (`tabTextAuto`), clearing
  Verified and the old doubts. If the read finds no tab, fails, or
  can't run (signed out, no OCR here), nothing changes and a message
  says why, ending "The text was kept.". Shown only when the event has
  photos or PDFs to read and the app can read them, and not on an event
  shared read only.
- **Verified**: a toggle marking the reading correct once the user has
  checked it: tonal like Copy while off, filled and ticked while on;
  tapping it again unmarks it. Saved at once. The mark is kept on the
  event and syncs with it (`tabTextCorrect`), and a clone keeps it. An
  event marked correct opens on its Text view (the Files tool goes back
  to its list of files); one that isn't opens on its list. No read, on the device
  or in the [cloud](cloud-ocr.md), replaces a text tab marked correct. On
  an event shared read only the mark is shown (when set) but can't be
  changed.

**Editing tools**, on the line under them, outlined so they read as
buttons (scaled down, like the line above, if too wide) ([lib/screens/tab_editing.dart](../tabcam_app/lib/screens/tab_editing.dart)):

- **−** and **+**: the fret number under the cursor (or just before it),
  one or two digits, goes down or up by one (15 + → 16, 5 + → 6), from 0
  to 99. Going from 9 to 10 takes the dash after it, from 10 to 9 leaves
  one, so the notes after it keep their columns. The cursor stays on the
  number, for the next press. With no number there, it says to put the
  cursor on one.
- **++** and **−−**: the note under the cursor (or just before it) moves
  to the string above (++) or below (−−), in the same column, cycling
  within its staff (the string lines next to each other): up from the
  first string is the last, down from the last the first. A string whose
  spot holds another note is skipped. Dashes fill the room it leaves, a
  string line too short to reach the column is lengthened with dashes,
  and the cursor follows the note. With no note there it says to put the
  cursor on one; with no other string free there, it says so.
- **Overtype**, a toggle button (on by default, filled while on and
  outlined while off; tap to switch to insert): typing replaces
  the characters after the cursor on its line instead of pushing them
  right, and backspace on a string line leaves a dash, so the columns
  stay lined up. Enter still breaks the line.
- The keyboard offers no suggestions or autocorrection, and dashes and
  quotes aren't made "smart".
