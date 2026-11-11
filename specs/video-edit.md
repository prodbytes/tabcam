# Video edit

Basic edits of a video (a take from [Cam](cam.md), or a video added):
trim its start and end, and keep, remove or replace its sound (a new
track at a volume of its own). Opened
with **Edit** (scissors, before Rename) on a video's
[file screen](event-screen.md#file-screen), in the user's own captures
and those shared to edit (not read only, nor a contribution's file, nor
while a tool works).

**The edit is kept, not applied.** It's saved with the video's page as
it's made (the page's `edit`: the part kept, the sound, the track's page
ID, the part of the track used, where it starts and its volume; synced
with the capture as a rename is), and the video's file stays as it is: no Save,
and no waiting for the video to be made again. Players play the video as
its edit says
([`edited_playback.dart`](../tabcam_app/lib/screens/edited_playback.dart)):
the kept part only, with its own sound, silent, or muted with the new
track playing along it at its volume, started where it comes in
(checked every tenth of a second, as the [section](cam.md#playing-along-with-a-file) is). The
[file screen](event-screen.md#file-screen)'s player does, looping the
kept part; elsewhere (the file list's play buttons, Cam's play along,
the list's Download and Download all) the video's file is used as it
is. A cloned capture's video keeps its edit, naming the copy's track.
**Download** makes a file of the edit, on the device
([`video_edit.dart`](../tabcam_app/lib/capture/video_edit.dart)): nothing
is uploaded to make it, and no server is involved.

**The edit screen** ([`video_edit_screen.dart`](../tabcam_app/lib/screens/video_edit_screen.dart)),
with the file's name in its app bar, opening with the video's edit as it
was left:

- **The preview**, at the top, at most a third of the screen: the video
  (a tap on it plays or pauses), and **under it**, on one row, **Play** /
  **Pause**, a scrubbable progress bar and, at the right, **the current
  time** (`0:12.3`, to the tenth of a second: the trims are set by it);
  nothing over the frame. It plays the **kept part** only, from its start
  when outside it, paused back at its start at its end, with the sound as
  chosen: the video's own, silent, or silent with the new track along
  it, as the edit is played everywhere.
- **Trim**: a range over the whole video whose two ends set the part
  kept, its times under it (`Keep 0:02.5–0:41.0`, to the tenth of a
  second, in the primary colour once trimmed), with **Start here** (|◀)
  and **End here** (▶|) setting either end where the preview is. The
  kept part is at least half a second long; the preview seeks to the end
  moved while paused.
- **Sound**, three choices: **Original** (the video's own), **None**
  (taken out) or **New track**, which replaces it with one of the
  capture's **recordings** or **a sound file** from the device (the
  choice opens a sheet of them; picked, **Change** picks another). **A
  sound file picked is added to the capture's files** as a recording
  (named after its file), so the edit can name it and it syncs with the
  rest. Under the track's name, on one row, **the track's volume** at
  the left and **the track bar** filling the rest. The volume: a speaker
  over its level (`80%`, in the primary colour when it's not 100%; the
  speaker low under 50%, crossed out at 0%); tapped, it opens a slider
  from **0% to 100%** in steps of 5%, its level beside it, and **Mute**
  (Unmute puts back the level it had). 100%, the track as it is, is the
  default. The preview plays the track at it at once (a change of volume
  doesn't stop or re-seek the track), as the file screen and Download
  do. **100% is the most**: the players can't play a file louder than
  it is (video_player's volume, the browser's media element and iOS's
  audio mix all stop at 1), so a boost could only reach the download and
  would sound different from the preview; none is offered. The volume is
  the track's: Original keeps the video's own sound as it is, with no
  control. Kept in the edit as `trackVolume` (0 to 1, to the hundredth)
  only when it's not 100%; an older edit has none and plays the track as
  it is, and a value that isn't a number does too, one out of range is
  brought within it. The track bar: a bar as long as the
  kept part, with the track (its name on it) drawn over it where it
  plays, what falls outside the kept part cut off. **Dragged, the track
  moves** along the video; **dragged by either end, it's trimmed** (a
  grip at each end on the bar; the start moves with what's cut, so the
  rest stays put; at least half a second stays). Under the bar, **‹** and
  **›** nudge it a tenth of a second earlier or later, with where it
  starts in words between them ("The track starts 0:01.5 after the
  video": silence first; "… 0:01.5 before the video": that much more of
  its start is cut), and, once trimmed, "Using 0:01.0–0:42.5 of the
  track". A track shorter than the kept part leaves silence after.
- **At the bottom**: "Your edit is kept as you make it and plays with the
  video; Download makes a file of it.", **Reset** (on once the edit
  changes something: the whole video again, with its own sound; the
  track stays picked, from its start, at 100%) and **Download**, a split button. Pressed, it
  downloads **the video** as edited; its arrow opens a menu of **The
  video**, **The video without sound** and **The sound only** (off when
  the sound is None). A change is kept a moment after it's made (a drag
  makes many), and on leaving; an edit that changes nothing is none.
  Download makes the file on the device and saves it (the browser's
  download, or the system's "save as" on Android and iOS), named as the
  video is in the list; a video the edit doesn't change downloads as it
  is. A progress bar shows meanwhile (the browser's says how far along a
  video is; the phones' is indeterminate), with "Making the file…"; a
  failure says "Couldn't make the file" and why. A track whose length
  can't be told can't be downloaded with the video.

**How it's applied**, on the device
([platforms](platforms.md)):

- **Android**: Media3 Transformer
  ([`VideoEdit.kt`](../tabcam_app/android/app/src/main/kotlin/com/nu01/tabcam/VideoEdit.kt),
  method channel `tabcam/video_edit`, method `edit`): a composition
  whose primary sequence is the video clipped to the kept part, its
  audio removed unless kept; a new track is a second sequence, a gap
  (silence) for as long as it starts after the video, then the part of
  it that fits (`gapMs`, `fromMs`, `toMs`, worked out by the app), at its
  volume (`trackVolume`: a `GainProcessor` effect on it, when not 1), the
  composition forcing an audio track since the primary has none. H.264
  and AAC in MP4. The sound only (`video: false`) is one sequence, the
  kept part of the video's sound or the track's gap and part (at its
  volume), AAC in M4A; it ends where the sound does.
- **iOS**: AVFoundation
  ([`AppDelegate.swift`](../tabcam_app/ios/Runner/AppDelegate.swift), the
  same channel): an `AVMutableComposition` with the kept part of the
  video track (its orientation kept as the composition track's
  transform), its own audio tracks cut the same unless removed, or the
  track's sound inserted at its shift, at its volume (an
  `AVMutableAudioMix` whose input parameters set the track's volume,
  when not 1); exported as MP4 (highest quality).
  The sound only (`video: false`) leaves the video track out and exports
  M4A (`AVAssetExportPresetAppleM4A`); it ends where the sound does.
- **The web**
  ([`web_video_editor.dart`](../tabcam_app/lib/capture/web_video_editor.dart)):
  the kept part plays, hidden, into a canvas (its frames, at 30 a
  second) and a Web Audio graph (the video's own sound, or the track's,
  started where it comes in, through a gain node at its volume), and the browser's MediaRecorder records
  both: WebM (VP9 or VP8, Opus), or MP4 where only that records
  (Safari). It takes as long as the kept part is to play, and the
  progress bar says how far along it is. The file's format is the
  recorder's (an `.mp4` downloads as `.webm` where WebM records). **The
  sound only** is rendered offline, faster than it plays: the video's or
  the track's sound decoded (Web Audio's `decodeAudioData`) and mixed in
  an `OfflineAudioContext` as long as the kept part (the track after its
  gap, through a gain node at its volume), written as a 16-bit WAV (`wavBytes`).
- **Elsewhere** (desktop builds): Download says videos can't be edited
  here.

The math of fitting a track into the kept part is one function, the
app's (`trackSpan`, `VideoEdit.trackPart`): of the track, the part used
(its trims), starting at its shift from the kept part's start; the
silence before it, then the track from its first moment that falls in
the kept part to its last. The platforms get the result (`gapMs`,
`fromMs`, `toMs`; nothing when none of it falls in), and the track's
volume (`trackVolume`, 0 to 1), and only insert it.
