# Dictionary

A **Dictionary** button (a book icon, first in the app bar) at the top of
every file viewer, of Cam and of Home: the [event screen](event-screen.md)
in all its views (Files, Text, and the locked previews), the
[file screen](event-screen.md#file-screen) for any file, Cam
([cam.md](cam.md)) with or without Premium, a capture opened by its
link, and Home's captures ([navigation](navigation.md); not the Capture
and Profile tabs, where the sidebar doesn't show but stays open). It's free for everyone, and takes nothing from tabs.cam's servers:
the chords and scales are worked out on the device
([`lib/dictionary/`](../tabcam_app/lib/dictionary/)); only a song's
searches leave it, from the device straight to YouTube and Cifra Club.

It shows and hides the **Dictionary sidebar**: on the right of the
screen, as the play-along player's sidebar opens
([Cam](cam.md#playing-along-with-a-file)), or, once turned by its
**Rotate** button (below), a panel under the screen. The viewer stays
beside it, on the left (or over the panel), and goes on working (the
camera, the tab, what plays along). At the side, where the play-along
sidebar shows too, the dictionary is the one at the right edge.
The button is in the primary colour while the sidebar shows. The
sidebar is **app-wide**: open on one screen, it's open on the next (Home,
the capture, a file, Cam) with the same search, until the button or the
sidebar's own **✕** hides it. In Cam, typing in it doesn't turn the tab,
and once it's hidden the keys turn the tab again.

**Its width**: 40% of the screen's, from 280 to 420 px, until the user
drags its left edge, a **separator** (`SplitHandle`, a line with a grip,
12 px wide to take a finger, a resize cursor on a computer): dragged
left it gets wider, right narrower, from 160 px up to leaving the
viewer 96 px. A double tap on the edge puts the default width back. The
width the user sets is the same on every screen and kept on the device
between sessions ([`SidebarWidths`](../tabcam_app/lib/screens/sidebar_widths.dart),
the library's `sidebars` meta file), as the play-along sidebar's is.

**Rotate**, a button beside the sidebar's **✕** ("Show the dictionary at
the bottom"), turns it into a **panel under the screen**, across its
width, with the viewer over it; there the button ("Show the dictionary
at the side") puts it back on the right. Turning it keeps the viewer as
it is (the camera, what plays), what was typed and the keyboard. The
choice is app-wide, as the widths are, and kept on the device with them
(the `sidebars` meta file's `below` list), so the dictionary opens where
it was left, on every screen and in the next session. As a panel:

- **Its height** is 40% of the screen's, from 180 to 360 px, until the
  user drags its top edge, the same separator lying down: up it gets
  taller, down shorter, from 120 px up to leaving the viewer 96 px; a
  double tap puts the default back. The height is kept apart from the
  side's width (`dictionaryHeight`), each for its own layout.
- The search field and the buttons share **one row** (no title), to
  leave the height to what it shows.
- **The necks lie down**: a chord's diagrams and a scale's fretboard are
  drawn with the nut at the left and the frets going right, the high E
  at the top as in a tab (see below), and where the panel is 560 px wide
  or more they're beside the chord's or scale's name, notes and degrees
  (220 px), not under them, so a short panel shows them without
  scrolling. At the side they stand, as before.
- The other sidebars stay where they are: the play-along player's is in
  the viewer, over the panel; the [metronome](metronome.md)'s is at the
  right of both, the screen's whole height.

On a small phone neither layout overflows: where the screen leaves less
than the sidebar's content needs (160 px wide; its title and field, 112
px, tall), the content is cut at its edge, not squeezed; so is the
panel's where it's left less than 240 px wide (a phone with the
metronome's sidebar open beside it), its row laid out from the left, the
field first; and where a
screen is too short for the viewer's 96 px over the panel (a phone lying
down with its keyboard up), the panel keeps the 64 px of its field's
row, so what's typed shows.

At its top, the sidebar has its title, **Rotate** and **✕**, then one
search field, focused, and under it, scrolling, what was typed is:

- **A chord** (`C`, `Am7`, `F#m7b5`, `G/B`, `Cmaj9`, `C6/9`, `E5`): shown
  as it's typed, with its name, its notes spelled from the root (`C#  E#
  G#`, not F), its degrees (`1  b3  5  b7`) and its **voicings** on a
  guitar in standard tuning, as chord diagrams: the strings low E to
  high E, the nut (or the starting fret, "5fr") at the top, a dot per
  fretted string (the root notes in the primary colour), ○ for an open
  string, × for one not played, a bar for a barre, each string's note
  under it, and the frets written under the diagram (`x32010`). In the
  panel under the screen the same diagram **lies down**: the nut (or the
  starting fret, labelled under it) at the left, the frets going right,
  the high E at the top and the low E at the bottom, ○ and × before the
  nut and each string's note at its right end. The
  voicings are **found by itself**
  ([`voicings.dart`](../tabcam_app/lib/dictionary/voicings.dart)): every
  way to hold the chord's notes within four frets, up to the twelfth
  position, that a hand can play (four fingers at most, a barre
  counting as one, no string skipped between played ones), with the
  root as the lowest note (or the slash chord's bass: `G/B` has B in
  the bass); the fifth of a seventh chord, and the ninth of an
  eleventh or thirteenth, may be left out. The best eight are shown, up
  the neck, at most two starting at the same fret: easy and full
  shapes first (low on the neck, few fingers, many strings, no barre or
  stretch that isn't needed), so `C` shows `x32010` first and `A`
  `x02220` before `x02225`. A power chord (`5`) is two or three
  strings.
  **How a chord is written**: a root (`A`–`G`, or `Do Re Mi Fa Sol La
  Si`; `#`, `b`, `♯`, `♭`) and a quality: major (`C`, `Cmaj`, `C
  major`, `Do mayor`, `Dó maior`), minor (`m`, `min`, `minor`, `menor`,
  `-`), `5`, `dim` (`°`, `o`, `˚`), `aug` (`+`, `(#5)`, `augmented`,
  `aumentado`), `sus2`, `sus4` (`sus`), `6`, `m6`, `7`, `maj7` (`M7`,
  `7M`, `major 7`, `major seventh`, `séptima mayor`, `sétima maior`, and
  **the triangle**: `Δ`, `Δ7`, typed as `Δ`, `∆`, `△` or `^`), `m7`
  (`-7`), `m(maj7)` (`mΔ7`, `-Δ7`, `m7M`), `dim7` (`°7`, `diminished
  7`, `diminished seventh`), `m7b5` (**the cut circle**, half-diminished:
  `ø`, `ø7`, typed as `ø`, `Ø` or `∅`; `m7(b5)`, `-7b5`, `half
  diminished`, `half-diminished`, `half dim`, `semidisminuido`,
  `semidiminuto`, `meio-diminuto`), `7sus4`, `7sus2`, `aug7` (`+7`,
  `7#5`), `7b5`, `add9` (`add2`), `madd9`, `add11`, `6/9`, `9`, `maj9`
  (`Δ9`), `m9`, `7b9`, `7#9`, `11`, `m11`, `13`, `maj13`, `m13`; `/` and
  a bass note after it; spaces and case don't matter (`CM7` is major
  seventh, `Cm7` minor seventh), nor a trailing "chord"/"acorde". `C
  major` and `A minor` are chords; `C diminished` alone is the scale.
  **Other symbols**: under the degrees, a chord written with a symbol
  says its quality in words (half-diminished, major seventh, minor major
  seventh, diminished, diminished seventh, augmented) and **"Also
  written"** its other symbols, each of which reads back as the same
  chord: `Bm7b5` is "half-diminished · Also written Bø, Bø7, Bm7(b5),
  B-7b5", `Cmaj7` "major seventh · Also written CΔ7, CΔ, CM7, C7M"
  (with the bass after each, `CΔ7/E`).
- **A scale** (`A minor pentatonic`, `D dorian`, `C major scale`, `E
  blues`, `F# harmonic minor`, `Sol mixolidio`): its name (the type in
  the app's language), its notes and degrees as for a chord, and the
  **fretboard** up to the twelfth fret, every note of the scale on it
  with its name (the roots in the primary colour), the open strings past
  the nut, the fret numbers beside it and markers at 3, 5, 7, 9 and 12.
  In a sidebar narrower than 480 px it **stands up**, as a chord diagram
  does (low E on the left, the frets going down, numbered on the left,
  at most 300 px wide); dragged wider, it **lies across**, seen from
  above, the high E at the top. In the panel under the screen it always
  lies across, the nut at the left, however narrow the panel (a phone
  held up), and no taller than the panel shows (but 130 px at least, to
  stay readable; scrolled then). The types: major
  (ionian), minor (natural minor, aeolian), harmonic minor, melodic
  minor, major pentatonic (`pentatonic` alone), minor pentatonic, blues,
  major blues, dorian, phrygian, lydian, mixolydian, locrian, phrygian
  dominant, lydian dominant, harmonic major, double harmonic, whole
  tone, diminished (whole-half), dominant diminished (half-whole) and
  chromatic; named in English, Spanish or Portuguese, with or without
  "scale"/"mode"/"escala"/"modo". `C major scale`, `A minor scale`,
  `A natural minor` and `A aeolian` are scales (`C major` alone is the
  chord).
- **Anything else** is a song (or whatever it is): the sidebar says
  it's not a chord or a scale and offers **Search YouTube**, a button
  that opens YouTube's search for it outside the app (a new tab, or the
  browser or YouTube app), as any link opens
  ([event screen](event-screen.md)). Under it, once typing stops for
  **two seconds** ("Searching YouTube…" and a progress bar meanwhile),
  come **YouTube's results**, right there in the sidebar: three videos,
  each with its thumbnail, title (two lines at most) and channel, and
  an open-in-new mark; a tap opens the video on YouTube outside the app,
  in a new tab on the web ("Open on YouTube" as its tooltip). Enter (the
  keyboard's search key) searches at once, without the wait. If the
  search fails (offline, the quota spent), it says it couldn't load
  YouTube's results; if YouTube finds nothing, it says so; the button
  stays either way. A search typed again (on this screen or the next)
  shows its results at once: the device keeps the last 50 searches'
  results until the app closes, and asks YouTube once for each.
  **How**: the device asks the YouTube Data API v3 (`search.list`,
  videos only, title, channel and the medium thumbnail) itself
  ([`youtube_search.dart`](../tabcam_app/lib/dictionary/youtube_search.dart)),
  with the build's **API key**, `TABCAM_YOUTUBE_API_KEY` (a dart-define
  from `.env`, or the GitHub variable of the same name in the Release,
  Deploy and Deploy RC workflows). It's public, as it's in the app: a
  Google Cloud key restricted to the YouTube Data API v3 only. The API
  is free, so misuse can only spend its quota: 10,000 units a day, 100
  a search, so about 100 searches a day for all users until Google
  grants more (the YouTube API Services audit and quota form). No
  tabs.cam server is involved. A build without the key shows the button
  only, and Enter opens YouTube's search as the button does.
  **Under YouTube's, Cifra Club's results** ("Tabs on Cifra Club"):
  three songs it has a tab or chords of, each with the artist's picture
  (where it has one), the song's title (two lines at most) and artist,
  and an open-in-new mark; a tap opens the song's page on Cifra Club
  outside the app ("Open on Cifra Club"). They're searched with
  YouTube's (the same two seconds, and Enter at once) and told on their
  own: "Searching Cifra Club…" with a progress bar, "Couldn't load Cifra
  Club's results." when the search fails, "Cifra Club found no tabs."
  when it finds nothing; the device keeps the last 50 searches' results
  as it does YouTube's. **How**: the device asks Cifra Club's own search
  index (`solr.sscdn.co/cc/h2/`, the site's Solr, which answers any
  origin, so the browser asks it too), for ten results, of which the
  songs (not the artists among them) are kept, the first three shown;
  no key, no quota, no tabs.cam server
  ([`cifraclub_search.dart`](../tabcam_app/lib/dictionary/cifraclub_search.dart)).
  A build without the YouTube key still searches Cifra Club.

<a id="writing-in-the-text"></a>**Writing it in the text (+)**: beside the event screen's
[Text view](tab-recognition.md#text-view), a chord's and a scale's
results have a **+** (a circled plus in the primary colour) that writes
them into the text tab as tab: under each chord diagram (its tooltip
"Write x32010 in the text") and beside a scale's name ("Write A minor
pentatonic in the text"). Anywhere else (Home, a file, Cam, the locked
preview, a capture shared read only) there's no text to write in, and no
+. What's written:

- **A chord**: that voicing, as one column across the six strings, its
  frets on the strings it plays and dashes on the others, the high E on
  the phrase's first line (`x32010` is `0 1 0 2 3 -`, top to bottom),
  then a dash.
- **A scale**: one position on the neck, its notes going up one at a
  time, a column each, from the root on the low E string: five frets
  from the fret under that root (the open strings and the first four
  frets for a root on the open string), each note on the highest string
  that reaches it there, up to the last note the high E reaches; so `A
  minor pentatonic` is the box at the fifth fret, `5 8` on every string
  but `5 7` on the A, D and G
  ([`scalePosition`](../tabcam_app/lib/dictionary/voicings.dart)).

Each column is as wide as its widest fret (`10`), with a dash after it.
**Where**: with the text's cursor on a six-line phrase (it stays where
it was while the dictionary's field is typed in), at the cursor's
column across the phrase, pushing the rest of every line right so the
columns stay lined up (a line too short to reach it is lengthened with
dashes before its closing bar, and nothing goes into a line's name or
opening bar). Anywhere else (a line of words, a phrase of other than six
lines, no cursor yet), in a **new phrase** like the editing tools' New
phrase, at least 80 characters wide, under the cursor's line or phrase
(at the end without a cursor), its lines `e|-`, what's written, dashes,
`|`. Either way the cursor ends just after what was written, so the next
+ follows it: tapping chord after chord writes a progression on one
phrase. It's an edit as any other (saved a second later, and the text the
user's). While Rescan reads or Fix's review shows, it says "The text
can't be changed right now" and writes nothing
([`writeColumns`](../tabcam_app/lib/screens/tab_editing.dart)).

Nothing typed, the sidebar explains itself and offers pills to tap: **the
capture's title first**, on a capture's screens (the capture, a file, Cam;
Home has none), so a song's tabs and videos are a tap away, then the
examples (`C`, `Am7`, `F#m7b5`, `G/B`, `Bø`, `GΔ7`, `Cadd9`, `Am11`, `A
minor pentatonic`, `E blues`, `D dorian`; `Bø` and `GΔ7` show the
half-diminished and major seventh symbols, `Cadd9` an added ninth and
`Am11` a ninth and an eleventh). A long title is cut to the sidebar's width.
Under them, a **Chord symbols** key, for the symbols a chart writes
instead of letters: **ø** half-diminished (`Bø7 = Bm7b5 = Bm7(b5)`),
**Δ** major seventh (`CΔ = Cmaj7 = CM7 = C7M = C^7`), **°** diminished
(`Bdim = Bo`), **°7** diminished seventh (`Bdim7 = Bo7`) and **+**
augmented (`Caug = C(#5)`), each row with its name and an example
(`Bø`, `CΔ7`, `B°`, `B°7`, `C+`) that a tap looks up; then how to type
them: on a phone, hold o for ø and º; on a Mac, ⌥O types ø, ⌥J ∆ and ⌥0
º; or write the letters (`m7b5`, `maj7` or `^7`, `dim` or `o`, `aug`)
or the name (half diminished).
In English, Spanish and Portuguese (the chord names and qualities are
the same in every language).
