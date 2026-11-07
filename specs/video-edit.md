# Video edit

Basic edits of a video (a take from [Cam](cam.md), or a video added):
trim its start and end, and keep, remove or replace its sound. Opened
with **Edit** (scissors, before Rename) on a video's
[file screen](event-screen.md#file-screen), in the user's own captures
and those shared to edit (not read only, nor a contribution's file, nor
while a tool works). The edit is applied on the device
([`video_edit.dart`](../tabcam_app/lib/capture/video_edit.dart)): nothing
is uploaded to make it, and no server is involved.

**The edit screen** ([`video_edit_screen.dart`](../tabcam_app/lib/screens/video_edit_screen.dart)),
with the file's name in its app bar:

- **The preview**, at the top, at most a third of the screen: the video,
  a tap on it (or **Play** / **Pause** under it) playing the **kept part**
  only, from its start when outside it, paused back at its start at its
  end; under it, on one row, **Play** / **Pause**, a scrubbable progress
  bar and, at the right, **the current time** (`0:12.3`, to the tenth of
  a second: the trims are set by it). It plays with the sound as chosen:
  the video's own, silent, or silent with the new track along it,
  started where it comes in (checked every tenth of a second, as the
  [section](cam.md#playing-along-with-a-file) is).
- **Trim**: a range over the whole video whose two ends set the part
  kept, its times under it (`Keep 0:02.5–0:41.0`, to the tenth of a
  second, in the primary colour once trimmed), with **Start here** (|◀)
  and **End here** (▶|) setting either end where the preview is. The
  kept part is at least half a second long; the preview seeks to the end
  moved while paused.
- **Sound**, three choices: **Original** (the video's own), **None**
  (taken out) or **New track**, which replaces it with one of the
  capture's **recordings** or **a sound file** from the device (the
  choice opens a sheet of them; picked, **Change** picks another). Under
  the track's name, **the track bar**: a bar as long as the kept part,
  with the track (its name on it) drawn over it where it plays, what
  falls outside the kept part cut off. **Dragged, the track moves** along
  the video; **dragged by either end, it's trimmed** (a grip at each end
  on the bar; the start moves with what's cut, so the rest stays put; at
  least half a second stays). Under the bar, **‹** and **›** nudge it a
  tenth of a second earlier or later, with where it starts in words
  between them ("The track starts 0:01.5 after the video": silence
  first; "… 0:01.5 before the video": that much more of its start is
  cut), and, once trimmed, "Using 0:01.0–0:42.5 of the track". A track
  shorter than the kept part leaves silence after. A track whose length
  can't be told has no bar, and can't be saved.
- **Cancel** leaves without a change. **Save** (on only once something
  changes; "Saving replaces the video." beside it) applies the edit and
  puts the result in the video's place: a **new page** with the video's
  name (a new ID, as [Rotate](event-screen.md#file-screen) makes, so it
  syncs as an added file and the old one is deleted); the file screen
  then shows it. A progress bar shows meanwhile (the browser's says how
  far along it is; the phones' is indeterminate), with "Saving the
  video…"; a failure says "Couldn't save the video" and why, and the
  video stays as it was. The original isn't kept: to keep it, **Clone**
  the capture first.

**How it's applied**, on the device
([platforms](platforms.md)):

- **Android**: Media3 Transformer
  ([`VideoEdit.kt`](../tabcam_app/android/app/src/main/kotlin/com/nu01/tabcam/VideoEdit.kt),
  method channel `tabcam/video_edit`, method `edit`): a composition
  whose primary sequence is the video clipped to the kept part, its
  audio removed unless kept; a new track is a second sequence, a gap
  (silence) for as long as it starts after the video, then the part of
  it that fits (`gapMs`, `fromMs`, `toMs`, worked out by the app), the
  composition forcing an audio track since the primary has none. H.264
  and AAC in MP4.
- **iOS**: AVFoundation
  ([`AppDelegate.swift`](../tabcam_app/ios/Runner/AppDelegate.swift), the
  same channel): an `AVMutableComposition` with the kept part of the
  video track (its orientation kept as the composition track's
  transform), its own audio tracks cut the same unless removed, or the
  track's sound inserted at its shift; exported as MP4 (highest quality).
- **The web**
  ([`web_video_editor.dart`](../tabcam_app/lib/capture/web_video_editor.dart)):
  the kept part plays, hidden, into a canvas (its frames, at 30 a
  second) and a Web Audio graph (the video's own sound, or the track's,
  started where it comes in), and the browser's MediaRecorder records
  both: WebM (VP9 or VP8, Opus), or MP4 where only that records
  (Safari). It takes as long as the kept part is to play, and the
  progress bar says how far along it is. The video's format changes to
  the recorder's (a take's `.webm` stays WebM; an `.mp4` becomes
  `.webm` where WebM records).
- **Elsewhere** (desktop builds): Save says videos can't be edited here.

The math of fitting a track into the kept part is one function, the
app's (`trackSpan`, `VideoEdit.trackPart`): of the track, the part used
(its trims), starting at its shift from the kept part's start; the
silence before it, then the track from its first moment that falls in
the kept part to its last. The platforms get the result (`gapMs`,
`fromMs`, `toMs`; nothing when none of it falls in) and only insert it.
