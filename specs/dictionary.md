# Dictionary

A **Dictionary** button (a book icon, first in the app bar) at the top of
every file viewer and of Cam: the [event screen](event-screen.md) in all
its views (Files, Text, and the locked previews), the
[file screen](event-screen.md#file-screen) for any file, Cam
([cam.md](cam.md)) with or without Premium, and a capture opened by its
link. It's free for everyone, and takes nothing from TabCam's servers:
the chords and scales are worked out on the device
([`lib/dictionary/`](../tabcam_app/lib/dictionary/)); only a YouTube
search leaves it, from the device straight to YouTube.

It shows and hides the **Dictionary sidebar** on the right of the
screen, as the play-along player's sidebar opens
([Cam](cam.md#playing-along-with-a-file)): the viewer stays beside it,
on the left, and goes on working (the camera, the tab, what plays
along). Where both show, the dictionary is the one at the right edge.
The button is in the primary colour while the sidebar shows. The
sidebar is **app-wide**: open on one screen, it's open on the next (the
capture, a file, Cam) with the same search, until the button or the
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

At its top, the sidebar has its title and **✕**, then one search field,
focused, and under it, scrolling, what was typed is:

- **A chord** (`C`, `Am7`, `F#m7b5`, `G/B`, `Cmaj9`, `C6/9`, `E5`): shown
  as it's typed, with its name, its notes spelled from the root (`C#  E#
  G#`, not F), its degrees (`1  b3  5  b7`) and its **voicings** on a
  guitar in standard tuning, as chord diagrams: the strings low E to
  high E, the nut (or the starting fret, "5fr") at the top, a dot per
  fretted string (the root notes in the primary colour), ○ for an open
  string, × for one not played, a bar for a barre, each string's note
  under it, and the frets written under the diagram (`x32010`). The
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
  `-`), `5`, `dim` (`°`, `o`), `aug` (`+`), `sus2`, `sus4` (`sus`), `6`,
  `m6`, `7`, `maj7` (`M7`, `Δ7`), `m7` (`-7`), `m(maj7)`, `dim7` (`°7`),
  `m7b5` (`ø`, `ø7`), `7sus4`, `7sus2`, `aug7` (`7#5`), `7b5`, `add9`
  (`add2`), `madd9`, `add11`, `6/9`, `9`, `maj9`, `m9`, `7b9`, `7#9`,
  `11`, `m11`, `13`, `maj13`, `m13`; `/` and a bass note after it;
  spaces and case don't matter (`CM7` is major seventh, `Cm7` minor
  seventh), nor a trailing "chord"/"acorde". `C major` and `A minor` are
  chords.
- **A scale** (`A minor pentatonic`, `D dorian`, `C major scale`, `E
  blues`, `F# harmonic minor`, `Sol mixolidio`): its name (the type in
  the app's language), its notes and degrees as for a chord, and the
  **fretboard** up to the twelfth fret, every note of the scale on it
  with its name (the roots in the primary colour), the open strings past
  the nut, the fret numbers beside it and markers at 3, 5, 7, 9 and 12.
  In a sidebar narrower than 480 px it **stands up**, as a chord diagram
  does (low E on the left, the frets going down, numbered on the left,
  at most 300 px wide); dragged wider, it **lies across**, seen from
  above, the high E at the top. The types: major
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
  come **YouTube's results**, right there in the sidebar: eight videos,
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
  TabCam server is involved. A build without the key shows the button
  only, and Enter opens YouTube's search as the button does.

Nothing typed, the sidebar explains itself and offers examples to tap (`C`,
`Am7`, `F#m7b5`, `G/B`, `A minor pentatonic`, `E blues`, `D dorian`).
In English, Spanish and Portuguese (the chord names and qualities are
the same in every language).
