# Video edit

Basic edits of a video (a take from [Cam](cam.md), or a video added) on
one time axis, in **two sound lanes, mixed**: trim its start and end,
set its own sound's level, and add a song (one of the capture's
recordings, videos or takes, or a sound file) placed along it at a
level of its own, both through a **master** volume (up to 200%); and,
**on the video**, a take's tab drawn over it as
it showed while recording (its **size**, **background** and **colours**
the user's to change, [the tab's style](#layers)), a **title** (the capture's name, or text
typed) and a small **watermark** that only [Premium](cloud-ocr.md#in-the-app)
removes ([layers](#layers)); and **fades in and out**, 3 s each by
default and adjustable: the video from and to black, both sounds with
it ([fades](#fades)). Opened
with **Edit** (scissors, before Rename) on a video's
[file screen](event-screen.md#file-screen), in the user's own captures
(not one shared with them, which is read only, nor a contribution's
file, nor while a tool works); and, for Cam's takes, with the **Edit**
on the take's row in the play-along sidebar (in Cam, beside the Text
view and beside a recording), which opens it the same way
([editing a take from the sidebar](cam.md#editing-a-take-from-the-sidebar)).

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
does). A change that moves nothing (a level, Mute: a muted lane plays
on at 0, or a fade) doesn't stop or re-seek the song. The plan's
[layers](#layers) are drawn over the picture as it plays, and its
[fades](#fades) with them. The
[file screen](event-screen.md#file-screen)'s player does the same,
looping the kept part (a muted song isn't opened there), a take's tab
and the title over it also when it has no edit (both are on by
default), but not the watermark, which only the editor's preview and
its Download add (it's the downloader's, by their Premium), nor the
fades (it loops the video: a fade to black and silence at each turn
would get in the way of watching and playing along); it finds the
song's length as the editor does (its player's, or, where the player
can't say, as for a take the browser recorded, the editor's), and when
neither can say, takes the end the edit keeps for it (none: the song
doesn't play); elsewhere (the file list's play buttons, Cam's play
along, the list's Download and Download all) the video's file is used
as it is: for a take, without its tab, which [Cam](cam.md#the-tab-with-the-take)
keeps apart from its picture; the editor's Download makes the finished
video. A cloned capture's video keeps its edit, naming the copy's
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
  (its taps are the [on-picture controls'](#on-the-picture): a tap on
  what's drawn picks it, elsewhere it plays or pauses; on a phone, a
  long press on the tab's band opens its style),
  with what Download draws over it (the [layers](#layers): a take's
  tab, the title, the watermark as this user's download would have
  it), drawn by the same code, so the preview is what the file will be
  (while the title's text is being edited, the title shows as it ends
  up rather than fading in, so it's seen at the start too). While it
  plays, the [fades](#fades) darken it from and to black and ramp both
  lanes with it; paused, the frame shows as it is (a trim's grip shows
  the frame it cuts at, not black). It plays the
  **kept part** only, from its start when outside it, paused back at its
  start at its end, with both lanes as set, as the edit is played
  everywhere.
- <a id="on-the-picture"></a>**On the picture** (a video editor's
  on-screen controls, [`on_picture.dart`](../tabcam_app/lib/screens/on_picture.dart)):
  **while the preview is paused**, each layer drawn at that frame has a
  thin white outline: the take's band showing then, the title (from
  the start, though it fades in) and the watermark. Nothing of it shows
  while it plays. **A tap picks** what's drawn (the title also opens its
  text, as ✎ does, playing or not); paused, a tap on the one picked, or
  on the picture outside every layer, plays (outside, nothing is picked
  any more), and playing, a tap anywhere but the title pauses: so a tap
  on the band, a good part of the picture, picks it first, then plays
  and pauses. The one picked is outlined in the primary colour with a
  **toolbar** beside it, on the picture (above it where there's room,
  else under it, else over its top; across from its centre, and
  narrowed to fit the picture at any text size):
  - **The tab's band**: **Smaller tab** and **Larger tab** (a step of
    the Size slider, greyed at its ends), its four **colours** (small
    swatches, "3" in each one's colours, the one in use ringed), on a
    phone its whole **style** (the palette, as the chip's), and **Hide
    the tab** (the Tab chip off). A **handle** at the band's top right
    ("Drag up or down to resize the tab") resizes it: dragged up, the
    band grows by as much as it's dragged (half its height up: half as
    large again), down, it shrinks, on the Size slider's steps and
    within its range; each change drawn at once and kept a moment
    later, as the slider's.
  - **The title**: **Edit the title** (its text) and **Hide the title**
    (off, its text kept).
  - **The watermark**: **Hide the watermark** for a user with Premium;
    without it, Premium's button ("Premium removes the watermark"),
    which shows Premium's card, as the chip does.
  While a fade covers the frame shown, a **badge** at the picture's top
  right says so ("Fade in · 3.0 s", "Fade out · 3.0 s"); a tap on it
  opens the fades' sliders (on a phone, in place of the chips).
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
  let go); **a click or tap on either lane's bar does too** (the Take
  lane's, or the Song lane's once it has a song; the empty lane's Add
  a song opens its sheet), exactly where it's clicked, while a drag on
  them still trims or moves as below; playback stays in the kept part. The lanes are labelled
  **Take** and **Song** for one of Cam's takes, **Video sound** and
  **Track** for any other video.
  - **The Take lane**: the whole video, the kept part bright (the lane's
    name on it) and the rest dimmed. **Its two grips trim it**, and both
    sounds with it: what's outside the kept part is dimmed in both
    lanes, and **the song stays where it is along the video** (a
    trimmed start cuts the song's start with it). While paused, the
    preview follows the grip dragged (a seek at most every 150 ms,
    exactly the end it moved when let go). This replaces the Trim
    section's range and the preview's scrub bar. The [fades](#fades)
    are drawn on the kept part as ramps at its ends (shaded above a
    line from its corner across the fade's length), as long as they
    play.
  - **The Song lane**, on a take recorded while a song played along
    (one Cam noted in its [log](cam.md#what-a-take-keeps), still in the
    capture), opens with that song in it, **lined up by itself** as it
    played while recording ([lined up](#a-takes-song-lined-up)), with
    no edit kept for it: nothing to sync by hand. Otherwise it's
    empty, a dashed **Add a song** (**Add a track**)
    row, which opens a sheet, **Pick a song** (**Pick a track**), of the
    capture's **recordings**, **videos**
    and **takes** (not the video edited) and **a sound file** from the
    device (**a sound file picked is added to the capture's files** as
    a recording, named after its file, so the edit can name it and it
    syncs with the rest). Picked, the song is placed by hand
    (`song: manual`) **at the timeline's end**: one shorter than the
    kept part ends where it ends (silence before it), one as long or
    longer starts with the kept part (none of its start cut), as does
    one whose length can't be told; heard at the lane's
    level; its bar shows its used part (its name on it) where it plays
    along the video, what falls outside the kept part dimmed (it's cut
    off). **Dragged, the song moves** along the video; **dragged by
    either end, it's trimmed** (a grip at each end; the start moves
    with what's cut, so the rest stays put; at least half a second
    stays). **⋮** at its right: **Change** (the sheet again) and
    **Remove** (the lane empty again, the edit keeping `song: off`, so
    a song a later version would add by default isn't put back; Reset
    stays on, and clears it).
    A song whose length can't be told shows its name alone, unplaced,
    and holds back Download while it's heard; muted, it's left out of
    the download, which goes ahead (as an older app's edit with a track
    picked but the video's own sound chosen).
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
    A lane goes **up to 100%**; louder is the master's (below). Both
    lanes default to 100%. With echo cancellation off while recording
    ([Cam](cam.md)), a take's own sound has the song from the speaker in
    it too: the levels and Mute are the remedy (headphones while
    recording give a clean mix).
- **Master**: both lanes go through it, after their own levels
  ("Master · Both sounds together, up to 200%"): **Mute** (a speaker,
  "Mute (Master)"; muted, nothing is heard and the level is kept, as a
  lane's) and a slider from **0% to 200%** in steps of 5% (sliding
  unmutes it), its level beside it (in the primary colour when it's not
  100% or it's muted, struck through while muted). It's **right above
  the fades' sliders**: on a wide screen in the **On the video** panel,
  between the title's fields and the fades; on a phone above **On the
  video** (whose Fades chip opens the sliders in its place, so it's
  above them too). Keys `video-edit-master`, `-mute`, `-slider`,
  `-level`. 100% by default; Reset puts it back. **Past 100% only the
  download is louder**: the players can't play a file louder than it
  is (video_player's volume and the browser's media element stop at
  1), so the preview plays a lane at its level times the master's, at
  most 100%; Download's file has the full level, each renderer clipping
  what goes past full scale rather than wrapping it
  (**How it's rendered**, under [fades](#fades)).
- **Under the lanes, On the video**: what's drawn over the video, as
  chips (on a wide screen, 840 points and more, **On the video** is a
  panel of its own beside the rest, 320 points wide, the title's fields,
  the master, the fades' sliders and the tab's style under its chips):
  - **Tab** (on a take only; none on a take without a tab: its log has
    none, or, with no log, its capture's tab text has no necklines): on
    by default, for a take whose tab is kept apart from its picture (its
    [log](cam.md#what-a-take-keeps) has its tab, not burned in: every
    take Cam saves now); tapped, it's off (kept as `tab: false`; Reset
    turns it on again), and its bands leave the preview and the
    download. On a take whose tab is already in its picture (burned in
    as it was saved, by the versions that did, or saved before takes
    kept a log) the chip is off and can't be turned on, so the tab is
    never drawn twice, and its tooltip (shown on a tap, or on hover)
    says why: "This take has the tab in its picture" (burned in), or
    "This take is from an earlier version: its tab can't be drawn over
    it" (no log, in a capture with a tab). (A `Tooltip` around the
    chip: a disabled chip shows none of its own; no line of text, which
    would stay under every such take.)
    **The tab's style**: on a take whose tab can be drawn, the chip's
    **palette** button ("Change how the tab looks"), or, on a phone, a
    long press on the tab's band in the preview, opens it: on a phone in
    place of the chips ("Tab style · How the tab looks over the video");
    on a wide screen it's always under the fades' sliders ("How the tab
    looks over the video"), without the button or Done (and no long
    press on the band there). The band picked on the preview has its
    size and colours [on the picture](#on-the-picture) too. It
    has **Size** (the tab's usual size times 50% to 200%, in steps of
    5%, but only the sizes that change the band over this video: from
    the smallest that reads on its frame, 50% on a 16:9 landscape one,
    90% on a portrait or square one, to the largest at which any of the
    take's bands still grows, at least 100%, so a staff that fills 40%
    of the frame by 130% stops there; a size kept past either end shows
    and is drawn as that end) and **Background** (its opacity, 0% to
    100% in steps of 5%, 70% by default), each its name and its value
    ("100%") on a
    line over a slider as wide as the panel (so neither is cut at any
    text size), **Colours** (four swatches under it,
    each a bit of band, "3-5" in its text's colour on its background's:
    **White on black** (the default), **Black on white**, **Gold on black** and
    **Black on gold**, tabs.cam's gold; the one picked ringed in the
    primary colour with a check; each a button with its name as its
    tooltip and for screen readers, saying whether it's picked),
    **Default style** (on once it's anything but the default: back to
    100%, 70%, white on black) and, on a phone, **Done**. The preview
    draws each change at once, a slider's as it's dragged (a new
    picture of the band showing; nothing is sought or rendered), and
    it's kept a moment later, as every change. A change turns the tab on
    (as typing turns the title on). The title's fields, the fades'
    sliders and the tab's style take each other's place on a phone. It
    fits a 360-point phone at the largest text size (the swatches wrap;
    their sample text doesn't grow). Reset puts it back with the rest.
  - **Title** ✎ (every video): on by default, showing the capture's
    name ([the title](#layers)); with no name to show (the name the
    app gave the capture, "Tab 2026-11-11 10:00"), the chip says
    **+ Title** and a tap opens its text. Tapped, it's on or off (its
    text kept). **✎**, or a tap on the title in the preview, opens its
    text: on a phone in place of the chips ("Title · Top left · fades
    in over 3 s"), with **First line** and **Second line** (80
    characters each), **Use the capture's name** (the text typed goes:
    the capture's name again, and it follows a rename), **No title**
    (off, the text typed kept) and **Done**; on a wide screen the same
    fields are always under the chips, without Done. Typing shows in
    the preview at once, kept a moment after the last key (as every
    change), and never seeks the song again (nothing it plays by
    changed); typing turns the title on.
  - **Watermark** (every video): on by default, "tabs.cam" and nothing
    else, small at the bottom right. **Only Premium removes it**: for a
    user with Premium now
    ([as the service last said](cloud-ocr.md#in-the-app), a week at
    most offline), and in a build without the service, it's a plain
    toggle (off kept as `watermark: false`); for anyone else it's on
    with a lock (tooltip "Premium removes the watermark"), and a tap
    opens the [Premium card](cloud-ocr.md#in-the-app) in a sheet,
    starting with "Premium removes the watermark", the chip staying on.
    Premium's answer arriving late (the editor open before it) unlocks
    it where it is. An edit with the watermark off, from a Premium
    user, still has it for anyone without Premium who downloads it (a
    collaborator): the rule is the downloader's, at Download.
  - **Fades** (every video; tooltip "The video from and to black, both
    sounds with it"): on by default, 3 s in and 3 s out
    ([fades](#fades)). Tapped, off (both none, kept as `fadeInMs: 0`,
    `fadeOutMs: 0`) or on again, as they were before it was turned off
    (3 s each if they never were). Its **tune** button ("Change the
    fades") opens the sliders: on a phone in place of the chips ("Fades
    · The video from and to black, both sounds with it"), with **Fade
    in** and **Fade out** (each from 0 to 10 s in tenths of a second,
    its length beside it, "3.0 s"), **No fades** (both none; the chip
    then puts them back) and **Done**; on a wide screen the same sliders
    are always under the title's fields, without Done (and the chip has
    no button). A slider goes at most to half the kept part (a fade kept
    longer plays that long, and is back when the kept part is long
    enough again). The preview plays a change at once (it moves no
    sound: nothing is sought), and it's kept a moment later, as every
    change. The title's fields and the sliders take each other's place
    on a phone.
- **Under them, the song's details** (when there's one): its lane
  and name ("Song · Recording 1"), **‹** and **›**, which nudge it a
  tenth of a second earlier or later, with where it starts in words
  between them ("The song starts 0:01.5 after the video": silence
  first; "… 0:01.5 before the video": that much more of its start is
  cut; counted from the kept part's start; for a song lined up in
  clips, its first), and, once trimmed, "Using
  0:01.0–0:42.5 of the song" (not for one lined up in clips). A song
  lined up by itself says so under them: "Lined up as it played while
  you recorded", or, once nudged or dragged, "Lined up as recorded,
  moved 0:00.2 later" (or "earlier"). They name it as its lane does: "song" on
  a take, "track" ("The track starts…", "… of the track") on any other
  video. A song shorter than the kept part leaves
  silence after. On a wide screen they stay under the lanes, beside
  On the video. (On a phone the title's fields and the fades' sliders
  already take the chips' place while they're open; a later step may make the song's details
  part of that one context area too, shown when the Song lane is
  selected.)
- **At the bottom**: **Reset** (on once the edit is anything but the
  defaults: the whole video, its own sound at 100%, no song said (so a
  song Removed, `song: off`, keeps it on), a take's tab on, the title
  on with the capture's name, the watermark on, and fades of 3 s in and
  out, and a take's song lined up as it played while recording, where
  it has one; Reset goes back to them, any other song taken out (that
  one put back, lined up), and the edit is
  none: none means the defaults, a take's tab, the title, the watermark,
  the fades and its song lined up included, not the file as it is) and
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
  doesn't change and with nothing drawn over it (the watermark off, so
  for a Premium user, or in a build without the service, and no title)
  and no fades downloads as it is when it's already MPEG-4 (an
  `.mp4` or `.m4v`, on every platform: in Firefox too, which would make
  it again only as a WebM) or already in the format made here (a
  `.webm` where the browser records WebM), and is made again otherwise
  (a WebM take in Chrome, a MOV), so the video is an MP4 wherever MP4
  is made (the plan is a [passthrough](#the-render-plan)). A progress
  bar shows meanwhile, saying how far along it is (the browser's as the
  video plays; the phones' as Media3 or AVFoundation report it, every
  quarter of a second), with "Making the file…"; a
  failure says "Couldn't make the file" and why. With the watermark and
  the fades on by default, almost every Download now makes the file (on the web,
  as long as the kept part takes to play); the file list's Download and
  Download all stay instant, the file as it is.

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
  (the own sound's level, 1 by default), `ownMuted`, `songMuted`,
  `masterVolume` (the master's level, 0 to 2, to the hundredth; 1 by
  default), `masterMuted`, and
  `song`: `manual` (placed by hand), `off` (none; Remove) or, absent
  with a `trackId`, `auto`: a take's song [lined up by
  itself](#a-takes-song-lined-up) from its log, its track keys placing
  its first clip (what apps from before it play; without a log that
  noted that song, it plays that one clip here too). Absent without a
  `trackId`: the page's default (a take's song lined up, if its log
  has one, else none). `auto` is never written (`song: auto` read is
  the same), and written back, absent stays absent.
- **`sound`, for older apps**, worked out from the lanes and always
  written: `track` when only the song is heard, `none` when neither is
  (also when the master is muted or at 0%), `original` otherwise (with
  both heard, older apps play the video's own sound: a safe fallback).
  Older apps don't know the master: they keep its keys and play the
  lanes at their own levels.
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
  heard at 0% comes back at 100%, as that app plays it, and a lane to be
  heard unmutes the master, at 100% if it was at 0%), while the
  levels and the keys that app doesn't know are kept. The track keys
  are the manual lane itself, so a track an older app moved is simply
  where it put it.
- `tab`: `false` when the Tab chip is off (written only then; absent,
  the tab is drawn on a take that can have it).
- `tabStyle`: how the tab's bands look, written only when it isn't the
  default, with only what isn't: `size` (1 by default; 0.5 to 2, to the
  hundredth), `opacity` (the background's, 0.7 by default; 0 to 1, to
  the hundredth) and `colors` (`dark` by default, white on black;
  `light`, `gold`, `brand`), e.g. `{"size": 1.5, "colors": "gold"}`.
  Values out of range are brought within it, ones that aren't numbers
  (or a colour this version doesn't know) read as the default; absent,
  the default: an edit kept before it looks as it did.
- `title`: absent, the default: on, the capture's name as it is now (so
  renaming the capture changes it). Otherwise `{"on": false}` (off, with
  the capture's name), or with `lines`, the text typed (at most two,
  each trimmed and at most 80 characters, trailing empty ones left
  off; `[]` is typed empty), on or off (`{"on": false, "lines": [...]}`
  keeps the text while it's off).
- `watermark`: `false` when a Premium user (or a build without the
  service) turns it off, written only then; obeyed only for a downloader
  who has Premium now ([layers](#layers)).
- `fadeInMs`, `fadeOutMs`: the [fades](#fades)' lengths, written only
  when not the default 3000 (0: none); read within 0 and 10,000.
  Absent, 3 s: an edit kept before the fades has them too.
- Muting keeps the level (`ownMuted`/`songMuted`/`masterMuted` beside
  the volumes), so an edit reopens muted at the level it had.
- Values that aren't numbers are read as the default; volumes out of
  range are brought within 0–1 (the master's within 0–2). `PageEdit` has one `copyWith`, and its
  `==`, `hashCode` and `toString` go by one list of its fields.

### A take's song, lined up

Cam notes the song played along while a take records, in its
[log](cam.md#what-a-take-keeps) (`song`: segments on the take's clock,
the song's page, where in it, at what speed). From it the editor lines
the song up by itself (`LoggedSong`, [`render_plan.dart`](../tabcam_app/lib/capture/render_plan.dart)):

- **Which song**: the one that played longest in the take, at its own
  speed (one played at another speed is noted, but left out: no
  renderer plays a song at another speed yet), and only while it's
  still one of the capture's files.
- **Where**: each segment is a clip, at its time in the file (the
  take's clock plus the log's lag, `lagMs`), the song from where it was
  to where it got; one playing as the take started plays from the
  file's first frame (the lag before the clock started) too. Between
  clips the song is silent (it was paused, or moved on): a song paused,
  skipped, started over by Repeat or its section is several clips.
- **The default**: a take with such a song opens with it in the Song
  lane (`withLoggedSong`): with no edit, or an edit that says no song
  (none picked, nor taken out). It's what plays in the preview, the
  [file screen](event-screen.md#file-screen)'s player (looping, as any
  edit) and Download, and the edit stays none until something else
  changes; then it's written without `song`, its track keys placing the
  first clip, for older apps.
- **Moved, it all moves** (‹ ›, or dragging the bar, by as much as the
  first clip's `offsetMs` moves; a trim of the video leaves it where it
  is along it), and stays lined up, for what the lag didn't catch (a
  speaker's or headphones' delay). **Trimmed** by its grips (one clip
  only: a song in clips has none, its bar spanning them all, dimmed
  between them), or another song picked, it's placed by hand
  (`manual`, its one clip as its track keys say). **Remove** keeps it
  out (`song: off`); **Reset** puts it back.
- Checked (`test/take_log_test.dart`, `test/render_plan_test.dart`,
  `test/video_edit_test.dart`, `test/play_along_test.dart`): the notes'
  segments for a play and pause, jumps, another song, speed or a link,
  a fresh reading re-telling a start; the song played longest, its
  clips in the file, the lag, one playing as the take started; the
  default only where the edit says no song; the clips moved, trimmed
  and cut to a short song, and manual and another song as their keys;
  the editor opening a take with its song lined up and nothing kept,
  ‹ moving it all, Reset, Download's clips and Remove; Cam's takes
  noting the song Rec started and one already playing, and none with
  nothing played. **Not yet on a phone**: how close the line-up is on
  each platform (the player's start and the speaker's delay aren't
  measured).

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
- the **own** lane: the video's own sound at its level through the
  master's (`PageEdit.ownLevel`: the lane's times the master's, 0 to
  2), or none (it or the master muted, or at 0%);
- the **song** lane: the song's page and file, its level through the
  master's (`songLevel`, as the own lane's), and its
  **clips**, each from a time in the output (`at`) the song from
  `from` to `to` (at a `speed`, 1 for now), silent between them; none
  when there's no song, or it or the master is muted or at 0%. The two lanes are
  **mixed**: both play, each at its level. A song placed by hand makes
  at most one clip: the part of it that fits the kept part, where its
  shift puts it (`trackSpan`: the silence before it, then the song
  from its first moment in the kept part to its last).
  Clips are cut to the output (`clampClips`): nothing is ever played
  before its start or past its end. Where the song is at a time in the
  output is one function, shared by the preview and the web's renderer
  (`songAt`, a binary search over the clips; none in a gap);
- the **layers** drawn over the picture ([layers](#layers)): none for
  the sound only;
- the **fades** (`fadeIn`, `fadeOut`, [fades](#fades)): the edit's (3 s
  each by default), each at most half the kept part; the same in all
  three of Download's plans;
- whether it's a **passthrough**: the whole video, its own sound at
  100%, no song, nothing drawn over it, no fades, and the input already in the
  format made (an MP4 or M4V anywhere; a WebM where WebM is made). Only
  then does Download save the file as it is; everything else is
  rendered.

Download's three items are three plans of the same edit: **the video**;
**the video without sound** (the same plan with neither lane: only the
sound is dropped, the layers kept); **the sound only** (no picture,
both lanes mixed, no layers).
The preview's plan (`preview: true`) leaves the files out and keeps a
lane that isn't heard at level 0, so muting and unmuting only change a
level and move nothing (what moves sound, the plan's `timeline`: the
kept part, the song's page and clips, is what makes the preview seek
the song again). The title and the watermark are layers too, so a
change to them never seeks, and nor does a fade's.

### Layers

What's drawn over the picture is a list of **layers** in the plan
([`render_plan.dart`](../tabcam_app/lib/capture/render_plan.dart),
`PlanLayer`), each: what it shows (its *look*, drawn by the app), when
(`from`–`to` in the output, `to` none: to the end), how (an `opacity`,
reached over a `fadeIn` from its start; 0 outside its time) and where:
by an **anchor**, `topLeft` or `bottomRight` (a corner, `heightU` high,
`marginU` in from it, the bottom right's `liftU` higher, and `liftW`
higher still, a fraction of the frame's width; no layer is lifted
today, both 0) or
`bottomFull` (along the whole bottom, as wide as the frame, as high as
its image makes it). Sizes are **fractions of the frame's short side**,
so a layer is the same on a portrait and a landscape video, and no one
but the renderer needs the frame's size: each platform places it on
its own upright frame (`PlanLayer.rectIn` in Dart; the same layout in
Kotlin and Swift). Layers of one kind (`id`: `tab`, `mark`, `title`)
never overlap in time; they're drawn in that order (the list's), the
title last, over the watermark should they meet. Fades and anchors
are supported everywhere: the tab along the bottom, the title at the
top left fading in, the watermark at the bottom right.

**The tab** ([`edit_layers.dart`](../tabcam_app/lib/capture/edit_layers.dart)):
on a take whose [log](cam.md#what-a-take-keeps) has its tab and says
it isn't in the picture (`burned: false`), unless the edit turns it off
(`tab: false`), one layer per band: each neckline from when it showed
until the next turn (a turn back to the line showing carries its band
on), at its time in the file (the turn's time on the take's clock plus
the log's `lagMs`, the first from the file's start), then in the output
(less the kept part's start), cut to the kept part (a trimmed start cuts
the first band, a trimmed end the last). Its text is the log's own copy
of the neckline, so a later change to the capture's tab changes nothing.
By default it looks as the tab burned into older takes did: white
monospaced text on a 70% black strip along the bottom, as wide as the
video, its text 1/48 of the width high at most (smaller when a line
wouldn't fit), each line 1.2 times that, 1/64 of the width above and
below. **Its style** (the edit's `tabStyle`, `EditTabStyle`, laid out by
`TabLayout` in `render_plan.dart`) changes that, and it's all in the
band's look (`BandLook`: its line, its style, its bound and its width),
so the band's picture, the preview and every Download (the web, Android
and iOS, which get it as its image) draw it alike, with nothing new for
the platforms to do: **size** multiplies the text (and, under 100%, the
padding), never past what fits the width (a long staff stays as big as
fits) and, grown past 100%, never past **40% of the frame's height**
(nor below its usual size, whatever that is: a frame of unknown shape
taken as a landscape 16:9 one), nor smaller than reads on the frame
(`TabLayout.minSizeOf`: its text, against the frame's short side, no
smaller than at 50% on a 16:9 landscape frame; 90% on a portrait or
square one, 65% on a 4:3 one, to the nearest 5%; a size kept smaller is
drawn at that); the **background** is the colours' background at the
style's opacity, the text always opaque, and **outlined in the
background's colour as the background fades below 70%** (its default,
which always carried the text alone; `TabLayout.outlineOf`: a stroke
18% of the text's size, fully opaque from 50% down, so a faint
background never leaves the text washed out, and in proportion between
50% and 70%), so it reads on any picture with no background at all; the
**colours**: white on black, black (`#111`) on white, tabs.cam's gold
(`#E0A030`) on black, black on gold. The text is drawn at its size, never
a bitmap scaled up: the band is drawn **as wide as the video's frame**
(`frame` in `RenderPlan.of`, the player's size; 1280 to 4096 pixels,
1280 when not known), so a renderer only scales it down, if at all; the
preview draws the same picture, scaled. With the default style the
picture is what it always was. A take with its tab in its
picture (`burned: true`: saved by the versions that put it there, or no
log: saved before takes kept one) gets none. A build with
`--dart-define=TABCAM_TAB_OVER_BURNED=true` draws it over such burned
takes too, to check by eye that the drawn bands sit over the burned
ones at the same frames (the time base and the lag); never in a
release.

**The title**: on unless the edit turns it off, its text the edit's
(`title.lines`) or the capture's name (`captureTitleLines`): the
capture's title, a copy's " (copy)" left off, and its artist, two
lines; with no artist, a title like "Blue Riff by Made-up Band" (or
with " – " or " - ") split into the two; a title the app gave the
capture ("Tab 2026-11-11 10:00") is no title. Each line is trimmed and
at most 80 characters, empty ones left out, at most two. One layer,
`title`, at the **top left**, 3.5% of the short side in, **fading in
from nothing to full over the kept part's first 3 seconds**, then
staying to its end. It looks: white, with a soft shadow, on a 35% black
rounded box; the first line in Roboto Medium at 5% of the short side,
the second in Roboto Regular at 80% of that (each line 1.25 times its
text high); a line too long for the frame ends in "…". The box's height
is worked out in Dart from the line count alone (`TitleLayout`), so the
plan knows it without drawing.

**The watermark**: "tabs.cam", the same on a take and on any other
video, in every language (`watermarkText`; no "Recorded by", no
address); one layer, `mark`, at the **bottom right**, 3% of the short
side in, the whole video through, one line of Roboto at 2.2% of the short side,
white at 60% with a soft shadow. It stays in that corner with the tab
drawn too, whatever the tab's size: over the bands (drawn after them),
never lifted above them. It's left out only when the edit turns it off
(`watermark: false`) **and** the one downloading has Premium now
(`watermarkUnlocked`: the service's answer, or its last one for the
same account kept on the device, a week at most, offline; a build
without the service counts as Premium, as nothing is locked there).
So it stays when Premium isn't known (no answer, none kept), and for a
collaborator without Premium who downloads a Premium user's edit. The
watermark is branding, not protection: the file list still downloads
the raw file.

### Fades

**The video fades in from black at the kept part's start and out to
black at its end, both sounds with it**: 3 s each by default, each set
by the user from 0 (none) to 10 s (`PageEdit.fadeIn` / `fadeOut`), and
never played longer than half the kept part (`PageEdit.fadeWithin`: a
4 s kept part fades 2 s in and 2 s out, meeting in the middle; the
length kept stays as set). One function says how much comes through at
a time in the output (`Fades.levelAt`, in
[`render_plan.dart`](../tabcam_app/lib/capture/render_plan.dart)): 0 at
the start, rising in a straight line to 1 at the end of the fade in, 1
until the fade out, falling in a straight line to 0 at the end; before
the start as at the start and past the end as at the end, so a side
whose fade is off never turns black a frame drawn a little past it (the
web's last frame after `end`, the preview running ahead of its check);
the renderers in Kotlin and Swift do the same (iOS's keyframes hold
their ends, `fillMode = .both`). **The picture**, with what's
drawn over it (the tab, the title, the watermark), is covered by black
at 1 − that (so the fades are over everything, not the video alone);
**the sound**, both lanes mixed, is multiplied by it. The title still
fades in over the kept part's first 3 s on its own ([layers](#layers)),
under the black. The sound only (M4A) and the video without sound get
the same fades, each what it has of them.

**Edits kept before the fades get them too.** An edit without the keys
has 3 s fades, as a fresh video has: the fades were asked for by
default, nothing is made until Download (files downloaded before stay
as they were), and the watermark and title already changed what an
older edit downloads as. An edit written by this version with the fades
turned off keeps them off (`fadeInMs: 0`, `fadeOutMs: 0`); an older app
keeps those keys as a newer app's and writes them back
([stored](#how-the-edit-is-stored)).

**In the preview**, `EditLayers` paints the black over the picture and
its layers, from the same `Fades`, but only while it plays: paused, the
frame shows as it is, so a trim's grip shows the frame it cuts at, and
the editor doesn't open on a black frame. `EditedPlayback` ramps both
players' volumes (each lane's level, through the master's and at most
1, times the fades' level), set again
at each of its checks (every tenth of a second, when it's moved 1% or
more, or reached 0 or the lane's level), and set before Play starts
(from where it starts, so the first tenth of a second isn't loud);
paused, the players are at their levels. The file screen's player
leaves the fades out (`fades: false`), as it does the watermark.

**The fonts**: Roboto Regular and Medium ship with the app
(`assets/fonts`, Apache 2.0, as the family `TabCamRoboto`, apart from
the app's own text), so the title and the watermark are drawn the same
in the preview and the file on every platform, and the web never
fetches them from a CDN. They're drawn for a frame whose short side is
1,200 pixels (`layerShort`) and scaled by each renderer.

**One drawing for the preview and the file.** Each look is drawn once
as a picture (`LayerPicture`): painted, scaled, over the preview, and
made a PNG for Download (`layerImages`: one per look, however many
layers use it). Over the preview, `EditLayers` (a `CustomPaint` in the
video's box, letting taps through) follows the video: between the
player's reports (every tenth of a second) the frame clock carries its
place on while it plays (at most 0.4 s past the last report), so fades
and bands change smoothly; on a seek or a pause it's where the player
says, and nothing runs while it's paused. Only a new place (a report or
a seek) restarts the carry: the player's other notices (its volume, as
a lane's slider is dragged, its buffering) leave it running. The editor and the file
screen's player both draw them (the file screen's player all but the
watermark).

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
  removed unless the own lane keeps it (through a gain at its volume,
  when not 1: a `GainProcessor` below 1, and above it a `ClippingGain`
  of ours, as Media3's `GainProcessor` wraps 16-bit samples lifted past
  full scale into loud crackles instead of clipping them; the channel's
  volumes are read within 0–2); the song lane is a second sequence, a gap
  (silence) up to each clip, then the track clipped to it, at the lane's
  volume (the same gains), the composition forcing an audio track when the primary has
  none; with both lanes, Transformer's audio graph mixes the two
  sequences (converting sample rates and channels; two real inputs
  mixed on a phone are still to be checked by hand). The layers (the
  channel's `images`, PNGs, and `layers`, each naming its image) are an
  `OverlayEffect` on the video
  ([`EditLayers.kt`](../tabcam_app/android/app/src/main/kotlin/com/nu01/tabcam/EditLayers.kt)):
  one `LayersOverlay` per kind of layer, giving at each frame the
  layer showing then (found by a binary search; a transparent pixel in
  the gaps) with its `StaticOverlaySettings`: scaled from its pixels to
  its size, anchored in normalized device coordinates (the band's
  bottom middle on the frame's; a corner on the corner a margin in, the
  bottom right's lifted by `liftU` of the short side and `liftW` of the
  width),
  `setAlphaScale` for its fade, in 64 steps. Frames reach the effects
  upright, so the frame size it's given is the frame as shown. The
  first frame's time is taken as the output's 0, so it's right whether
  Media3 counts a clipped video's frames from its clip's start or from
  the file's (to check on a phone: the `TABCAM_TAB_OVER_BURNED` build).
  The PNGs are decoded off the main thread and let go when it's done.
  **The fades** (the channel's `fadeInMs` and `fadeOutMs`, left out when
  none): the picture's black is one more overlay over all the others
  (`FadeOverlay`: a small black bitmap scaled to the frame, its alpha
  how dark `Fades.levelAt` leaves it, in 64 steps, the same first-frame
  time base); the sound's is one `GainProcessor` on the composition
  (`Composition.Builder.setEffects`: Transformer's audio graph runs the
  composition's audio effects on the mix, after the lanes are mixed),
  its `DefaultGainProvider` fading in linearly over the start
  (`FADE_IN_LINEAR`) and out over the end (`FADE_OUT_LINEAR`), on the
  output's samples, the sound only too.
  H.264 and AAC in MP4. The sound only has no picture: the own
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
  it starts (with the picture, cut to the video track's kept part too:
  the editor's end can pass it by a few tens of ms, as the player's
  duration is the longest track's, and a composition longer than its
  video composition's instruction fails the export, -11841), so both
  lanes are mixed; one `AVMutableAudioMix` sets the
  levels that aren't 1, one input per audio track. With layers, an
  `AVMutableVideoComposition` turns the video upright (the render size
  and transform as the tab's burn had them) and
  `AVVideoCompositionCoreAnimationTool` draws one `CALayer` per layer
  (its PNG as contents, placed by its anchor on the upright frame), its
  opacity 0 but while it shows: a `CABasicAnimation` from 0 to its
  opacity over its fade, then one holding it to its end, from
  `AVCoreAnimationBeginTimeAtZero`. **The fades**: a black `CALayer`
  over the whole frame, over all the others, its opacity a linear
  `CAKeyframeAnimation` (1 at the start, 0 after the fade in, 0 until
  the fade out, 1 at the end: `fadeKeyframes`), so the video composition
  is made for fades alone too; and each audio track's input in the
  audio mix ramps (`setVolumeRamp`) from silence to its level over the
  fade in and back over the fade out (`fade`), every track the same, so
  the mix fades, the sound only too. An audio mix plays nothing louder
  than 1, so a lane louder than it is (the master past 100%) is inserted
  twice, each copy at half its volume (`copies`): they add up to it.
  Exported as MP4 (highest quality); the sound only leaves the video
  track out and exports M4A (`AVAssetExportPresetAppleM4A`), and ends
  where the sound does. The track's asset is held until the export is
  done (a composition doesn't keep the assets its tracks came from; let
  go, the export failed). The export's `progress` is read every quarter
  of a second and sent back as on Android.
- **The web**
  ([`web_video_editor.dart`](../tabcam_app/lib/capture/web_video_editor.dart),
  the plan given directly): **the sound first, offline and exact**: the
  two lanes are decoded (Web Audio's `decodeAudioData`, each file once)
  and mixed in an `OfflineAudioContext` as long as the kept part (the
  own lane from the kept part's start, each of the song's clips where
  it starts, each through a gain node at its lane's level, which may be
  over 1: the mix is float, and the WAV writer clips it), at 44.1 kHz
  (22.05 kHz for a kept part over 8 minutes). `decodeAudioData` decodes
  a whole file, whatever part of it is kept, so the rate a file is
  decoded at goes by its own length: over 8 minutes, 22.05 kHz (about
  176 KB a second in stereo rather than 384 KB at 48 kHz). **A video
  over 16 minutes**, or one whose sound won't decode (one without any),
  **has its own sound streamed** from the playing video instead
  (`createMediaElementSource`, through the lane's gain, into the
  recording beside the mixed song), so a long take trimmed short
  doesn't decode all of it (a video without sound then adds silence).
  The sound alone has no playing video to stream from: there, a video
  whose own sound won't decode fails the download, saying why, rather
  than leaving the lane out unsaid. Then **the video follows the
  sound's clock**: the kept
  part plays, hidden and muted (unless its own sound streams), into a
  canvas (its frames, at 30 a
  second), the layers drawn over each frame (each look's PNG made an
  `ImageBitmap` once; each layer showing then drawn where its anchor
  puts it on the video's own frame size, with `globalAlpha` its
  opacity then, put back to 1 after), then the fades' black over the
  whole frame (`fillRect`, `globalAlpha` its darkness then); the offline
  mix fades through one more gain node, after the lanes', ramped
  (`linearRampToValueAtTime`) from 0 to 1 over the fade in and back to
  0 over the fade out, to the sample (an own sound streamed as it plays
  has its gain set at each frame instead), the sound only too; and the mix plays from a buffer into the recorded stream
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
sound; a plan with a red band along the bottom for the kept part's first
half second and a red square at the top left (the band's pixels red
while it shows and not after, the square where its anchor puts it); a
plan fading in and out, its first frame black, the square too, and its
middle bright (and, on Android, its sound only made); and each reading
the channel's arguments, the layers' and the fades' too. The layers'
layout and timing, and the fades' levels, are also JVM tests
(`android/app/src/test`, `EditLayersTest`) and XCTests that need no
video (the fades' keyframes and volume ramps). (These native
render tests are compiled here, not yet run on a phone or a simulator
for the layers.) (ML Kit's pods leave
the arm64 simulator out, so the XCTest needs a simulator that runs
x86_64.)
