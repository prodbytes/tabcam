# Tab recognition

**Read tab** on the [event screen](event-screen.md) turns an event's pages into
plain-text tab, on the device, with Google ML Kit text recognition (Latin
script). Android and iOS only; on the web it says reading tabs needs the
app, or TabScan Premium.

With [TabScan Premium](cloud-ocr.md) the text tab comes from the cloud
instead, by itself, as the pages sync, and Read tab asks for it; the rest
of this page is the on-device reading everyone else has.

Each page (as scanned, not filtered) is turned upright, scaled to at most
2400 px and made grayscale. Staff lines are found in that image, and OCR
runs on the same image (through a temporary file, deleted after), so their
coordinates agree. Pages with tab are joined with a blank line. With
nothing found, a message suggests the Tab filter, or rescanning closer and
flatter. With a result, it's saved on the event and the text tab editor
opens.

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

## Text tab editor

The read tab, monospaced and unwrapped (long lines scroll sideways),
editable to fix what OCR got wrong. **Copy** puts it on the clipboard;
**Share** shares it as text. Edits are saved on the event when leaving.
