# Metronome

A metronome in a sidebar, as the [dictionary](dictionary.md) and the
play-along player are: to practice a tab in time. All on the device:
nothing leaves it, and no server is involved.

## Where

- **Metronome** (a stopwatch icon, `Icons.av_timer`) in the app bar of
  every capture ([event screen](event-screen.md), all its views), every
  file screen and [Cam](cam.md), right after **Dictionary**; in the
  primary colour while its sidebar shows. On a phone's Text view it's in
  the **More** menu (⋮), with Dictionary. The button shows and hides the
  sidebar.
- The sidebar opens on the right of the screen, beside the content; with
  the dictionary open too, the metronome's is the rightmost (and, the
  dictionary turned into its panel under the screen, at the right of the
  viewer and the panel, the screen's whole height). Its default
  width is 30% of the screen (260 to 340 px); dragging its left edge makes
  it wider or narrower, a double tap puts the default back, and the width
  is kept on the device with the other sidebars'
  ([`SidebarWidths`](../tabcam_app/lib/screens/sidebar_widths.dart),
  `metronome`).
- Open on one screen, it's open on the next (app-wide,
  `MetronomeState`), and keeps playing there. It **stops** when its
  sidebar is closed (its close button, or the app bar's button), and when
  the user leaves for a screen that has no metronome (Home, Profile).
- In Cam, closing it gives the keys back to the tab, as the dictionary
  does.

## The sidebar

From the top:

- **The tempo**, large: "80 BPM" by default. **−** and **+** take a BPM
  off or add one; a **slider** goes from **30 to 250 BPM** (while it's
  dragged the number follows, and a playing metronome takes the new tempo
  when it's let go).
- **Time signature**: chips for the most common, **2/4, 3/4, 4/4** (the
  default), **5/4, 6/8, 7/8, 9/8 and 12/8**. Each click is one of the
  signature's notes at the BPM: a quarter note in x/4, an eighth note in
  x/8 (the sidebar says so: "Each click is an eighth note; the first of
  each group is accented.").
- **The beats**: a light per beat of the bar, bigger for the accented
  ones, lit in turn as they click.
- **Start** / **Stop**. Changing the tempo or the time signature while it
  plays starts it over at the bar's first beat with the new ones. When
  the sound can't play here it says so, in the error colour ("The
  metronome can't play here: …").

The tempo and the time signature are kept on the device (the library's
`metronome` meta file), so it opens as it was left.

## The sound

Short clicks, as a metronome's: a 40 ms tone that dies away fast, higher
and louder for accents:

| Click | Pitch | Volume |
|---|---|---|
| The bar's first beat | 1760 Hz | full |
| A group's first beat (6/8: 3 + 3, 7/8: 2 + 2 + 3, 9/8: 3 + 3 + 3, 12/8: 3 + 3 + 3 + 3) | 1320 Hz | 80% |
| Any other beat | 880 Hz | 60% |

- **Web**: Web Audio. Each click is an oscillator scheduled on the audio
  clock, the next 100 ms at a time by a 25 ms timer, so clicks keep exact
  time while the page is busy. Start resumes the audio context (browsers
  allow sound only after the user does something).
- **Android, iOS and macOS**: no audio library is needed. The app writes
  whole bars of clicks as a WAV (16-bit mono, 22,050 Hz, at least 20
  seconds; [`clickTrackWav`](../tabcam_app/lib/metronome/click_track.dart))
  to the cache folder, once per tempo and signature, and the platform's
  media player (`video_player`) loops it, mixed with other sound (the
  play-along track). The clicks keep exact time within the file, and the
  loop starts over between bars.
- The lights follow a timer from the first click, so they track the sound
  closely but are not tied to it.

## Tests

`tabcam_app/test/metronome_test.dart`:
- **Accents:** the bar, then the groups in 6/8, 7/8 and 12/8.
- **Signatures:** the common ones and their labels.
- **The click track:** a WAV of whole bars, at least 20 seconds, with clicks on every beat, the bar's loudest, a group's next, and silence between.
- **The metronome's state:**
  - it starts at 80 BPM in 4/4, closed and silent;
  - the tempo stays between 30 and 250;
  - a new tempo or signature restarts it, and closing it stops it;
  - a dragged slider applies when it's let go;
  - stopped while starting, it stays silent;
  - it says so when it can't play;
  - the settings are kept on the device.
- **The sidebar:**
  - it opens on the right at 80 BPM in 4/4 with 4 lights;
  - − and + change the tempo, and 6/8 shows 6 lights and the eighth-note line;
  - Start plays and lights the beats in turn, and Stop stops it;
  - the close button stops it;
  - leaving the screens that have it stops it.
