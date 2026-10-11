# Tab recognition

Every capture's tab is read **by itself** into its text tab, shown in the
[event screen](event-screen.md)'s **Text** view. With [TabScan
Premium](cloud-ocr.md) the cloud transcribes it as the pages sync;
otherwise ML Kit text recognition (Latin script) reads it on the device,
Android and iOS only (below).

## Reading by itself

`AutoReader` ([lib/recognition/auto_reader.dart](../tabscan_app/lib/recognition/auto_reader.dart))
watches the library: whenever the user adds or changes an event's image
pages (a new capture, pages added, rotated or deleted), that event is
read, one event at a time. Other changes (the title, the view, the text)
don't read again, nor do events another device changed (that device reads
them), nor the events there were at launch.

- **A text the user edited is never replaced.** A read fills an empty
  text tab, or replaces one an earlier read left (`tabTextAuto`, synced:
  set by a read on the device or in the cloud, cleared by an edit).
- **Signed out** (in a build with sign-in): it waits, and reads when the
  user signs in ([signed out](cloud-sync.md#signed-out)).
- **Premium**: the pages go to the cloud transcription; the text comes
  with sync.
- **Neither** (the web without Premium): it says it can't read here.

The Text view says how it stands when there's no text yet: "Reading the
tab…" (with a spinner); "Transcribing in the cloud. The text appears here
when it's done."; "No tab found in the pages. Try rescanning closer and
flatter." or "Reading the tab failed.", with **Read again**; "Reading
tabs needs you signed in.", with **Sign in**; "Reading tabs needs the
Android or iOS app, or TabScan Premium."; "Nothing to read: add a scan or
a photo."; or, for an event never read (from before), "Not read yet."
with **Read**. Its log lines start with `TabScan: read tab:`.

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

Consecutive tab lines are a staff; other lines (titles, "Chorus") end it.
Staves of fewer than four lines are dropped. Each staff's lines are padded
with dashes to one length, spaces become dashes, and the lines are named
`e B G D A E` (six lines) or `G D A E` (four, bass), or kept unnamed for
other counts.

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

Text tabs are tried first; typeset layout runs when no text tab is found.

## Troubleshooting log

Reading logs each step, in lines starting `TabScan: read tab:` (on
Android: `devbox run android-log`; on the web: the browser's console):
the event's pages and whether the user is signed in; which reading it
takes (cloud for Premium, with the premium status, else on the device and
whether the platform can); per page, the bytes, the prepared image's size
and the drawn staves found, what OCR found (blocks, lines, frets, the
first five lines) and whether it read a text tab, a typeset tab or
neither, with the time taken. A failure is logged with its stack trace as
well as shown. Tokens are never logged.

## Text view

The event screen's Text view ([lib/screens/tab_text_view.dart](../tabscan_app/lib/screens/tab_text_view.dart)):
the read tab, monospaced and unwrapped (long lines scroll sideways),
editable to fix what OCR got wrong, with **Copy** (to the clipboard)
above it; sharing is the event screen's **Share** in the app bar. Edits are saved a second after the last one,
and on leaving, and make the text the user's (no read replaces it). A
read that ends while the view shows fills it in, unless the user has
started editing. Read only for an event shared read only.

**Mark correct**, next to Copy and the same kind of button, is a toggle
that marks the reading correct once the user has checked it: tonal like
Copy while off, filled and reading **Correct**, ticked, while on; tapping
it again unmarks it. Saved at once. The mark is kept on the event and syncs with
it (`tabTextCorrect`), and a clone keeps it. An event marked correct
opens on its Text view (the Text tool goes back to its pages); one that
isn't opens on its pages. No read, on the device or in the
[cloud](cloud-ocr.md), replaces a text tab marked correct. On an event
shared read only the mark is shown (when set) but can't be changed.
