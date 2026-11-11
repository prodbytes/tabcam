# Video edit

Basic edits of a video (a take from [Cam](cam.md), or a video added) on
one time axis, in **two sound lanes, mixed**: trim its start and end,
set its own sound's level, and add a song (one of the capture's
recordings, videos or takes, or a sound file) placed along it at a
level of its own. Opened
with **Edit** (scissors, before Rename) on a video's
[file screen](event-screen.md#file-screen), in the user's own captures
and those shared to edit (not read only, nor a contribution's file, nor
while a tool works).

**The edit is kept, not applied.** It's saved with the video's page as
it's made (the page's `edit`, see [stored](#how-the-edit-is-stored);
synced with the capture as a rename is), and the video's file stays as
it is: no Save, and no waiting for the video to be made again. Players
play the video as its edit says, from the same
[render plan](#the-render-plan) Download renders
([`edited_playback.dart`](../tabcam_app/lib/screens/edited_playback.dart)):
the kept part only, the two lanes mixed: the video's own sound at its
level (through the video's player), and the song's player along it, in
its clip (from where the plan says it is, paused outside it; checked
every tenth of a second, as the
[section](cam.md#playing-along-with-a-file) is). Every 2 seconds, while
both play, the song's place is compared with where the plan has it, and
it's sought again when it's more than 150 ms off, so a long video's song
doesn't drift on (the downloaded file is exact whatever the preview
does). A change that moves nothing (a level, or Mute: a muted lane plays
on at 0) doesn't stop or re-seek the song. The
[file screen](event-screen.md#file-screen)'s player does the same,
looping the kept part (a muted song isn't opened there); it finds the
song's length as the editor does (its player's, or, where the player
can't say, as for a take the browser recorded, the editor's), and when
neither can say, takes the end the edit keeps for it (none: the song
doesn't play); elsewhere (the file list's play buttons, Cam's play
along, the list's Download and Download all) the video's file is used
as it is. A cloned capture's video keeps its edit, naming the copy's
song. An edit's keys from a newer app (a newer editor's settings) are
kept with it and written back with every change made here, even a
Reset: the edit then stays, as the whole video with its own sound, which
plays and downloads as the video itself ([library](library.md#events)).
**Download** renders the edit's plan to a file, on the device
([`video_edit.dart`](../tabcam_app/lib/capture/video_edit.dart)): nothing
is uploaded to make it, and no server is involved.

**The edit screen** ([`video_edit_screen.dart`](../tabcam_app/lib/screens/video_edit_screen.dart)),
with the file's name in its app bar and **ⓘ** at its right (it says
"Your edit is kept as you make it and plays with the video; Download
makes a file of it."), opening with the video's edit as it was left:

- **The preview**, at the top, at most a third of the screen: the video
  (a tap on it plays or pauses); nothing over the frame. It plays the
  **kept part** only, from its start when outside it, paused back at its
  start at its end, with both lanes as set, as the edit is played
  everywhere.
- **Under it, on one row**: **Play** / **Pause**, **the current time**
  (`0:12.3`, to the tenth of a second: the trims are set by it), the
  part kept (`Keep 0:02.5–0:41.0`, in the primary colour once trimmed;
  it shrinks to fit at large text sizes), and **Start here** (|◀) and
  **End here** (▶|), which set either end where the preview is. The
  kept part is at least half a second long.
- **The timeline**: a **ruler** (the video's times, m:ss, a tick as
  often as there's room for its time; its times stay small at large
  text sizes), over two lanes, **one time axis**: each lane's bar spans
  the whole video, lined up under the ruler, with its **volume** at its
  left; **where the preview is** is a line across the ruler and both
  lanes. Tapped or dragged, the ruler takes the preview anywhere in the
  video (while dragged, a seek at most every 150 ms; exactly where it's
  let go); playback stays in the kept part. The lanes are labelled
  **Take** and **Song** for one of Cam's takes, **Video sound** and
  **Track** for any other video.
  - **The Take lane**: the whole video, the kept part bright (the lane's
    name on it) and the rest dimmed. **Its two grips trim it**, and both
    sounds with it: what's outside the kept part is dimmed in both
    lanes, and **the song stays where it is along the video** (a
    trimmed start cuts the song's start with it). While paused, the
    preview follows the grip dragged (a seek at most every 150 ms,
    exactly the end it moved when let go). This replaces the Trim
    section's range and the preview's scrub bar.
  - **The Song lane**: empty, a dashed **Add a song** (**Add a track**)
    row, which opens a sheet of the capture's **recordings**, **videos**
    and **takes** (not the video edited) and **a sound file** from the
    device (**a sound file picked is added to the capture's files** as
    a recording, named after its file, so the edit can name it and it
    syncs with the rest). Picked, the song is placed by hand
    (`song: manual`), from the kept part's start, heard at the lane's
    level; its bar shows its used part (its name on it) where it plays
    along the video, what falls outside the kept part dimmed (it's cut
    off). **Dragged, the song moves** along the video; **dragged by
    either end, it's trimmed** (a grip at each end; the start moves
    with what's cut, so the rest stays put; at least half a second
    stays). **⋮** at its right: **Change** (the sheet again) and
    **Remove** (the lane empty again, the edit keeping `song: off`).
    A song whose length can't be told shows its name alone, unplaced,
    and can't be downloaded with the video.
  - **Each lane's volume**: a speaker over its level (`80%`, in the
    primary colour when it's not 100% or it's muted; the speaker low
    under 50%, crossed out when the lane isn't heard, the level struck
    through while muted); tapped, it opens a slider from **0% to 100%**
    in steps of 5% (sliding unmutes the lane), its level beside it, and
    **Mute**. **Muting keeps the level**: Unmute puts it back, also
    after the edit is opened again; after a slide down to 0%, Unmute
    puts back the level before the slide (100% if it was opened at 0%,
    as an older app's Mute saved it). Each lane's controls have keys of
    their own (`video-edit-take-…`, `video-edit-song-…`). It fits its
    bar's height at any text size: the level stays on one line, and
    speaker and level shrink together when the text is too large; the
    bars are 44 points high. The preview plays each lane at it at once.
    **100% is the most**: the players can't play a file louder than it
    is (video_player's volume, the browser's media element and iOS's
    audio mix all stop at 1), so a boost could only reach the download
    and would sound different from the preview; none is offered. Both
    lanes default to 100%. With echo cancellation off while recording
    ([Cam](cam.md)), a take's own sound has the song from the speaker in
    it too: the levels and Mute are the remedy (headphones while
    recording give a clean mix).
- **Under the lanes, the song's details** (when there's one): its lane
  and name ("Song · Recording 1"), **‹** and **›**, which nudge it a
  tenth of a second earlier or later, with where it starts in words
  between them ("The track starts 0:01.5 after the video": silence
  first; "… 0:01.5 before the video": that much more of its start is
  cut; counted from the kept part's start), and, once trimmed, "Using
  0:01.0–0:42.5 of the track". A song shorter than the kept part leaves
  silence after. (Later steps put the layer chips here, the song's
  details then showing when its lane is selected.)
- **At the bottom**: **Reset** (on once the edit is anything but the
  defaults: the whole video, its own sound at 100%, and no song; Reset
  goes back to them, the song taken out, and the edit is none) and
  **Download**, a split button (both shrink to fit at the largest text
  sizes). Pressed, it downloads **the video** as edited, both lanes
  mixed; its arrow opens a menu of **The video (MP4)**, **The video
  without sound (MP4)** and **The sound only (M4A)** (both lanes mixed;
  off when neither lane is heard): **the whole video as an MP4** (H.264
  and AAC), **its sound alone as an M4A** (AAC, `audio/mp4`).
  Each item says the format it makes here (the editor's `formats()`):
  MP4 and M4A on Android, iOS and the browsers that make them (Chrome,
  Edge, Safari); in a browser that can't record MP4 the videos say
  **(WebM)**, and in one that can't make AAC the sound says **(WAV)**
  (Firefox, both), so the label is always what the file will be. (MP3
  was asked for; AAC was chosen instead, as no MP3 encoder is bundled
  and every platform here makes AAC.) A change is kept a moment after
  it's made (a drag makes many), and on leaving; an edit that's the
  defaults is none.
  Download makes the file on the device and saves it (the browser's
  download, or the system's "save as" on Android and iOS), named as the
  video is in the list with the made format's extension (`.mp4`,
  `.m4a`; `.webm`, `.wav` where those are made); a video the edit
  doesn't change downloads as it is when it's already MPEG-4 (an
  `.mp4` or `.m4v`, on every platform: in Firefox too, which would make
  it again only as a WebM) or already in the format made here (a
  `.webm` where the browser records WebM), and is made again otherwise
  (a WebM take in Chrome, a MOV), so the video is an MP4 wherever MP4
  is made (the plan is a [passthrough](#the-render-plan)). A progress
  bar shows meanwhile, saying how far along it is (the browser's as the
  video plays; the phones' as Media3 or AVFoundation report it, every
  quarter of a second), with "Making the file…"; a
  failure says "Couldn't make the file" and why.

### How the edit is stored

The page's `edit` ([`page_edit.dart`](../tabcam_app/lib/library/page_edit.dart)),
version 2 (`v: 2`):

- `startMs`, `endMs`: the part kept.
- The song lane: `trackId` (the capture's page), `trackStartMs` /
  `trackEndMs` (the part of it used; none: its end), `offsetMs` (where
  it starts after the kept part's start; before it when negative) and
  `trackVolume` (its level, 0 to 1, to the hundredth). These keep the
  meaning they had before the two lanes, so older apps read them.
- New keys, each written only when it isn't the default: `ownVolume`
  (the own sound's level, 1 by default), `ownMuted`, `songMuted`, and
  `song`: `manual` (placed by hand), `off` (none; Remove) or `auto` (a
  later step lines a take's song up by itself; this version plays it
  as the one clip its track keys approximate, and a change made here
  makes it `manual`). Absent, the song lane is none.
- **`sound`, for older apps**, worked out from the lanes and always
  written: `track` when only the song is heard, `none` when neither is,
  `original` otherwise (with both heard, older apps play the video's
  own sound: a safe fallback).
- **An edit from before the two lanes** (no `v`) is read by its old
  `sound`: `original` keeps the own sound (a track picked stays, as a
  manual song lane, muted, so it and its settings survive); `none`
  mutes both lanes; `track` mutes the own sound and plays the track at
  `trackVolume`. Each plays and downloads as it did.
- **An edit an older app changed since**: on reading a `v: 2` edit, its
  `sound` is worked out again from the lanes; if the stored one
  differs, an app that only knows the old keys changed it, and its old
  meaning wins for the lanes (the song lane manual with the stored
  track keys, the lanes muted as `sound` says; an own sound to be
  heard at 0% comes back at 100%, as that app plays it), while the
  levels and the keys that app doesn't know are kept. The track keys
  are the manual lane itself, so a track an older app moved is simply
  where it put it.
- Muting keeps the level (`ownMuted`/`songMuted` beside the volumes),
  so an edit reopens muted at the level it had.
- Values that aren't numbers are read as the default; volumes out of
  range are brought within 0–1. `PageEdit` has one `copyWith`, and its
  `==`, `hashCode` and `toString` go by one list of its fields.

### The render plan

Download and the players work from one description of the edit, the
**render plan**
([`render_plan.dart`](../tabcam_app/lib/capture/render_plan.dart),
pure Dart, `RenderPlan.of`): derived from the page's edit each time,
never stored. It says:

- the **input** and the part of it **kept** (`start`–`end`); output
  times count from the kept part's start;
- the **format** made and whether the **picture** goes in (not for the
  sound only);
- the **own** lane: the video's own sound at its level, or none (muted,
  or at 0%);
- the **song** lane: the song's page and file, its level, and its
  **clips**, each from a time in the output (`at`) the song from
  `from` to `to` (at a `speed`, 1 for now), silent between them; none
  when there's no song, or it's muted or at 0%. The two lanes are
  **mixed**: both play, each at its level. A song placed by hand makes
  at most one clip: the part of it that fits the kept part, where its
  shift puts it (`trackSpan`: the silence before it, then the song
  from its first moment in the kept part to its last).
  Clips are cut to the output (`clampClips`): nothing is ever played
  before its start or past its end. Where the song is at a time in the
  output is one function, shared by the preview and the web's renderer
  (`songAt`, a binary search over the clips; none in a gap);
- whether it's a **passthrough**: the whole video, its own sound at
  100%, no song, and the input already in the format made (an MP4 or
  M4V anywhere; a WebM where WebM is made). Only then does Download save
  the file as it is; everything else is rendered.

Download's three items are three plans of the same edit: **the video**;
**the video without sound** (the same plan with neither lane: only the
sound is dropped); **the sound only** (no picture, both lanes mixed).
The preview's plan (`preview: true`) leaves the files out and keeps a
lane that isn't heard at level 0, so muting and unmuting only change a
level and move nothing (what moves sound, the plan's `timeline`: the
kept part, the song's page and clips, is what makes the preview seek
the song again). Layers drawn over the video (the tab, a title, a
watermark) and fades in and out (by default 3 s, set by the user: the
picture from and to black, both lanes' levels ramping with it) come in
later steps of the editor's redesign, as more of the plan; for now a
plan has none, and each lane's level is one level throughout.

**How it's rendered**, on the device
([platforms](platforms.md)): each platform gets the plan and only
carries it out; the times are all worked out in Dart.

- **Android**: Media3 Transformer
  ([`VideoEdit.kt`](../tabcam_app/android/app/src/main/kotlin/com/nu01/tabcam/VideoEdit.kt),
  method channel `tabcam/video_edit`, method `render`, the plan's
  `toChannel`: `input`, `output`, `video`, `startMs`, `endMs`, `own`
  `{volume}` and `song` `{path, volume, clips: [{atMs, fromMs, toMs,
  speed}]}`, and a `job`). With the picture: a composition whose
  primary sequence is the video clipped to the kept part, its audio
  removed unless the own lane keeps it (through a `GainProcessor` at its
  volume, when not 1); the song lane is a second sequence, a gap
  (silence) up to each clip, then the track clipped to it, at the lane's
  volume, the composition forcing an audio track when the primary has
  none; with both lanes, Transformer's audio graph mixes the two
  sequences (converting sample rates and channels; two real inputs
  mixed on a phone are still to be checked by hand). H.264 and AAC in
  MP4. The sound only has no picture: the own
  lane's sound clipped, and the song's sequence, AAC in M4A; it ends
  where the sound does. A clip at a speed other than 1 is refused (not
  yet). While it renders, `Transformer.getProgress` is read every quarter
  of a second and sent back to the app (`progress`, with the `job` and
  `done`, 0 to 1), which moves the progress bar.
- **iOS**: AVFoundation
  ([`AppDelegate.swift`](../tabcam_app/ios/Runner/AppDelegate.swift), the
  same channel and method): an `AVMutableComposition` with the kept part
  of the video track (its orientation kept as the composition track's
  transform), its own audio tracks cut the same when the own lane keeps
  them, and the song lane's clips inserted on one audio track, each where
  it starts, so both lanes are mixed; one `AVMutableAudioMix` sets the
  levels that aren't 1, one input per audio track.
  Exported as MP4 (highest quality); the sound only leaves the video
  track out and exports M4A (`AVAssetExportPresetAppleM4A`), and ends
  where the sound does. The track's asset is held until the export is
  done (a composition doesn't keep the assets its tracks came from; let
  go, the export failed). The export's `progress` is read every quarter
  of a second and sent back as on Android.
- **The web**
  ([`web_video_editor.dart`](../tabcam_app/lib/capture/web_video_editor.dart),
  the plan given directly): **the sound first, offline and exact**: the
  two lanes are decoded (Web Audio's `decodeAudioData`, each file once;
  a video whose sound can't be decoded, as one without any, adds none)
  and mixed in an `OfflineAudioContext` as long as the kept part (the
  own lane from the kept part's start, each of the song's clips where
  it starts, each through a gain node at its lane's level), at 44.1 kHz
  (22.05 kHz for a kept part over 8 minutes, so the decoded sound fits
  in memory). Then **the video follows the sound's clock**: the kept
  part plays, hidden and muted, into a canvas (its frames, at 30 a
  second), and the mix plays from a buffer into the recorded stream
  beside it (the `AudioContext` it plays in made and started at
  Download's tap, before the files are decoded), started as the video
  starts playing; at each frame, while the video is more than 40 ms
  ahead of or behind the mix, its `playbackRate` is nudged to 0.98 or
  1.02 (back to 1 within 10 ms). So the lanes are sample-accurate with
  each other, picture and sound stay within about a frame, and if a
  frame drops, the sound doesn't. The browser's MediaRecorder records
  both. **The video is MP4** where the browser records it: the first
  type it supports of `video/mp4;codecs=avc1.42E01E,mp4a.40.2`,
  `video/mp4;codecs=avc1,mp4a.40.2` and `video/mp4`
  ([`edit_formats.dart`](../tabcam_app/lib/capture/edit_formats.dart),
  `videoRecorderTypes`; Chrome and Edge record H.264 and AAC, raising
  the level for a larger frame, and Safari does); **WebM** (VP9 or VP8,
  Opus) only where none is (Firefox). The file is named by what was
  recorded (`edit.mp4`, `video/mp4`; `edit.webm` otherwise). The MP4
  Chrome writes is fragmented and says its length (a final fragment
  and index), so it seeks and plays in browsers, QuickTime and
  FFmpeg-based players; no fix-up is needed, unlike the WebM it records,
  which says it's endless until sought to its end. It takes as long as
  the kept part is to play, and the progress bar says how far along it
  is. **The sound only** is the same offline mix (at 44.1 kHz), made
  faster than it plays.
  Then, the first way the browser can ([`WebSoundWay`](../tabcam_app/lib/capture/edit_formats.dart)):
  - **WebCodecs' `AudioEncoder`** (`mp4a.40.2`, AAC-LC at 160 kbit/s,
    checked with `AudioEncoder.isConfigSupported`: Chrome and Edge on
    macOS, Windows and Android, Safari 26), fed the mix a second at a
    time, so it's still faster than it plays; its frames are written
    into an **M4A** here, by a small muxer in Dart
    ([`m4a.dart`](../tabcam_app/lib/capture/m4a.dart), `m4aBytes`: no
    library, nothing fetched): `ftyp` (`M4A `), then `moov` (one `mp4a`
    track, its `esds` holding the AudioSpecificConfig, the frames'
    sizes and one chunk's offset) before `mdat`, so it plays as it
    loads. The AudioSpecificConfig is the encoder's description as
    Chrome gives it (two bytes); Safari's encoder gives Apple's "magic
    cookie" instead, a whole MPEG-4 ES descriptor, from which it's taken
    (`audioSpecificConfig`; written as it was, it said no audio type and
    the file played nowhere). **An edit list cuts the encoder's delay
    and padding**, so the file is as long as the kept part, to the
    sample, and the track starts exactly where it should; and a `roll`
    sample group (each frame needs the one before, -1), as Apple's own
    MP4s have, without which Apple's decoders (Safari, AVFoundation)
    cut the usual delay themselves and the edit list's too, losing the
    sound's first 2,112 samples. The delay is measured once per channel
    count (a tone after 4,096 samples of silence, encoded, written and
    decoded, starts that much later; 2,112 samples under Apple's
    encoder, the one used where it can't be measured), except in Safari
    (its ES descriptor says it's Apple's encoder): 2,112. Checked with
    Chrome's and Safari's encoders: Chrome, Safari (WebKit) and
    Firefox's `decodeAudioData`, AVFoundation, `afconvert` and FFmpeg
    all start the sound where it is; Firefox's alone keeps the padding,
    up to about 46 ms more at the end (silence).
  - Else **MediaRecorder** as `audio/mp4;codecs=mp4a.40.2` (an older
    Safari, without the AudioEncoder): the mix played into it, so it
    takes as long as the kept part, the progress bar saying how far
    along; an M4A about as long (the recorder's start may cut a moment).
    The `AudioContext` it plays in is made and started first, at
    Download's tap (Safari starts one only then), before the file is
    read, decoded and mixed; if the browser still won't run it (or
    record), the sound downloads as a WAV instead (`sound.wav`) rather
    than failing.
  - Else (Firefox, Chrome on Linux: no AAC encoder) a 16-bit **WAV**
    (`wavBytes`), and the menu says (WAV).
- **Elsewhere** (desktop builds): Download says videos can't be edited
  here.

**Native smoke tests**: the renderers are also tested on their
platforms, with a 2 s made-up clip and a made-up tone as the song: an
XCTest in `ios/RunnerTests` (on the simulator: `xcodebuild test
-workspace ios/Runner.xcworkspace -scheme Runner -destination
'platform=iOS Simulator,name=…' -only-testing:RunnerTests`) and an
instrumented test in `android/app/src/androidTest` (on a phone on USB:
`./gradlew :app:connectedDebugAndroidTest` in `android/`), each
rendering a trimmed plan with its own sound and a song clip at half its
volume, the sound alone, and refusing a plan with neither picture nor
sound; and each reading the channel's arguments. (ML Kit's pods leave
the arm64 simulator out, so the XCTest needs a simulator that runs
x86_64.)
