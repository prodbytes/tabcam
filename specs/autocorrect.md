# Auto-correct (Fix)

The [Text view](tab-recognition.md#text-view)'s **Fix**: first, for
everyone and on the device, it **lines the tab up**; then, with Premium,
it checks the tab against the song's tab published online and proposes
corrections, note by note, which the user accepts or rejects (nothing
changes until they do).

## Lining the tab up

`reformatTab` ([lib/recognition/tab_layout.dart](../tabscan_app/lib/recognition/tab_layout.dart)),
on the text as it is, saved as the user's edit:

- Two or more tab lines in a row are a staff; every other line (title,
  chord names, lyrics, notes, blank lines) stays exactly as it is, and so
  does a lone tab-like line.
- In a staff: OCR's usual slips fixed (long dashes, `O` for 0, `l` for 1,
  spaces as dashes); strings without a name named `e B G D A E` (bass
  `G D A E`), names written on every string kept as written; the bars
  lined up, each measure padded with dashes to its widest string, so a
  measure's notes stay in it and every string ends at the same column.
- It says "Tab lined up", or that the strings already line up. Without
  Premium (where the upgrade can be offered) it adds that checking it
  online is Premium's, with **Upgrade**.

## Checking it online (Premium)

### In the app

1. **Fix** shows on every event the user can edit; the online check runs
   for Premium users in builds with the [cloud OCR](cloud-ocr.md)
   service, after lining up.
2. It asks for the song and artist, filled in with the event's title, and
   saves any pending edit.
3. While it checks (up to about 4½ minutes) a progress bar says it's
   looking for the song's tab online; the text can't be edited meanwhile.
   If the text changed anyway (a sync), the answer is dropped and it says
   to tap Fix again.
4. No corrections: it says why (the service's summary, "The tab matches
   the one found online", or "Couldn't find this song's tab online").
   Errors: "Couldn't check online right now", "Sign in again", "Fix isn't
   available yet" (the service has no API key).
5. **Review**: the song found, the summary and links to the tabs compared
   with (opened in the browser) above the text; each proposed note marked
   in the text where it goes (pending, accepted in green, rejected shows
   the original), the selected one highlighted. Tapping a mark selects
   it. The panel below shows the selected change, old note → new note
   ("removed" for a note to delete), its line, string and column and the
   reason, with **Reject**, **Accept** (each moves on to the next
   undecided one), previous / next, **All…** (accept or reject all) and
   **Done (decided/total)**.
6. **Done** writes the accepted corrections into the text and saves it as
   the user's edit (no read replaces it); undecided ones are left out.
   Each correction keeps the columns: a longer note takes the dashes after
   it, a shorter or removed one leaves dashes. A correction whose note
   isn't where it was any more is skipped.

`CloudOcr.autocorrect` ([lib/cloud/cloud_ocr.dart](../tabscan_app/lib/cloud/cloud_ocr.dart))
calls `POST /autocorrect` ([lib/cloud/ocr_api.dart](../tabscan_app/lib/cloud/ocr_api.dart))
with the user's Google ID token and waits up to 5 minutes. The app's log
leaves the text out of the request line.

## The service

`POST /autocorrect {eventId, song, text}` on the cloud OCR service's
function URL ([tabscan_locr/locr/autocorrect.py](../tabscan_locr/locr/autocorrect.py)):
a signed-in user's Google ID token, Premium only (402 otherwise), a text
of up to 20,000 characters and a song name of up to 200 (400 otherwise).

1. **Notes**: every string line (an optional string name, then at least
   three dashes, bars and notes) is parsed, and each note (frets and
   techniques: `0-9 h p b r x t s v / \ ~ ( ) < > . ^ = *`) numbered
   `n1`, `n2`, ... with its line and column. Without string lines it
   answers at once, with no corrections.
2. **Claude** (`claude-opus-5-5`, adaptive thinking, effort medium,
   server-side refusal fallback) gets the song's name and the reading,
   line by line, with each line's notes (`n12@5 "3"`); text lines (chords,
   lyrics) are shown for context. It has web search and web fetch (up to
   6 uses each) and is told to search the popular tab sites first
   (Ultimate Guitar, Songsterr, 911Tabs, GuitarTabs.cc, AZ Chords,
   e-chords), then the web; pick the version that matches the reading;
   propose a correction only where that tab clearly disagrees; and never
   copy the published tab into its answer. It answers through a strict
   `submit_corrections` tool: found, title, artist, sources, summary and
   corrections, each `replace` (a note id and its new text), `delete` (a
   note id) or `insert` (a line, a column and the note), with a reason.
   Paused turns are continued; an answer without the tool is nudged once;
   it gives up after 270 s.
3. **Checked**: a correction is kept only if its note exists, its new text
   is a note and differs, an insert lands on dashes of a string line
   without touching a note (it would read as one), and it doesn't overlap
   another kept correction. At most 300.
4. **Answer**: `{found, title, artist, sources (https only, up to 5),
   summary, corrections: [{id, line, column, old, new, reason}], proposed,
   notes}`. 503 when no API key is configured, 502 when Claude or the
   web fails.

The Claude API key is in Secrets Manager (`tabscan/anthropic-api-key`);
[tabscan_infra/ocr.yaml](../tabscan_infra/ocr.yaml) gives
`tabscan-ocr-api` read access to it when `AnthropicKeySecretArn` is set
(the deploy script finds it by name; without it, Fix answers 503).

## Troubleshooting log

- **App**: `TabScan: OCR API: POST .../autocorrect` with the event and
  song (not the text), then its status, time and answer;
  `TabScan: auto-correct failed:` with the error.
- **Service**: the `http` line (path, status, identity, premium, the
  answer), and an `autocorrect` line: event, found, the notes parsed,
  corrections proposed and kept, and token and search usage.
  `autocorrect failed` carries the exception and traceback.

## Verified

- Service tests (pytest, made-up riff, a fake Claude): notes parsed on
  string lines only; corrections that don't fit the reading dropped
  (unknown notes, non-notes, no-ops, inserts on text lines, touching a
  note or on a bar, overlaps); the request carries the web tools, the
  model and the fallback; a paused turn is continued; one nudge, then
  "not found"; no string lines, no call; the route is Premium only,
  checks its body, answers 503 unset and 502 on failure.
- App tests: corrections applied keeping the columns, a moved note
  skipped; overtype, backspace and insert mode; − and + on one and two
  digits, 9 ↔ 10, and nothing to change; Fix's dialog, the review per
  note, Accept / Reject and Done write only the accepted; Fix without
  Premium offers the upgrade.
- Not yet run against Claude in a deployed stack.

## Known limitations

- Only string lines' notes are corrected, not chords or lyrics.
- The user names the song; a generic title (the default capture name)
  finds nothing.
- One request takes the API function for up to 4½ minutes and uses the
  account's Lambda concurrency (10 by default) like any other.
- Each run costs Claude API tokens and searches; there's no per-user
  limit yet beyond Premium.
