# Video edit

Basic edits of a video (a take from [Cam](cam.md), or a video added) on
one time axis. **The video opens as its only row**; a song added to it
(one of the capture's recordings, videos or takes, or a sound file), or
a take's own song lined up as it played, gets **a row of its own under
it**, and the two sound lanes are mixed: trim the video's start and
end, set its own sound's level, and place the song along it at a level
of its own, each lane with its **channels** (a take recorded on
the left only can play on both sides) and **balance**
([stereo](#a-lanes-channels-and-balance)), both through a **master**
volume (up to 200%); and,
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
on the take's row in the play-along sidebar: beside the Text view and
beside a recording it opens the same way, over the screen; in Cam it
opens in Cam's own view, in the camera's place ([in Cam](#in-cam),
[editing a take from the sidebar](cam.md#editing-a-take-from-the-sidebar)).
It also opens from a link to the file's edit view, and again after a
reload where it was open over its own file screen (not a take edited
from a sidebar) ([sharing](sharing.md),
[navigation](navigation.md#coming-back-where-the-user-was)); **Share**
in its app bar (a link icon, before About; on a phone in its More menu)
copies that link.

**The edit is kept, not applied.** It's saved with the video's page as
it's made (the page's `edit`, see [stored](#how-the-edit-is-stored);
synced with the capture as a rename is), and the video's file stays as
it is: no Save, and no waiting for the video to be made again. Players
play the video as its edit says, from the same
[render plan](#the-render-plan) Download renders
([`edited_playback.dart`](../tabcam_app/lib/screens/edited_playback.dart)):
the kept part only (the editor's own preview plays from wherever its
playhead is, [below](#the-edit-screen)), the two lanes mixed: the video's own sound at its
level (through the video's player), and the song's player along it, in
its clip (from where the plan says it is, paused outside it; checked
every tenth of a second, as the
[section](cam.md#playing-along-with-a-file) is). <a id="preview-in-step"></a>**The song is
kept in step with the video** at every check while both play: both
players are asked where they are at once, and the song's error against
where the plan has it is corrected. Within 8 ms (below what's heard as
two sounds) it plays at its speed; up to 250 ms off, its speed is nudged
by up to 5% either way (heard as the same song) to catch up over about
a second, then put back; further off (a seek, a stall), it's sought
again. Its start is sought a little ahead of the video, by as much as it
was found late the last times it started (its player's start-up, learnt
as it plays, 400 ms at most), so it starts in step instead of catching
up. Until 2026-11-18 it was only checked every 2 seconds and sought when
more than 150 ms off, which left a start-up lag of up to that, heard as
the song behind the take (the downloaded file is exact whatever the
preview does). A change that moves nothing (a level, Mute: a muted lane plays
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

<a id="the-edit-screen"></a>**The edit screen** ([`video_edit_screen.dart`](../tabcam_app/lib/screens/video_edit_screen.dart)),
with the file's name in its app bar, then **Reset** and **Download**
([below](#reset-and-download)), **Download settings** (a tune icon,
[below](#download-settings)), **Dictionary** and **Metronome** (their
sidebars, as on the file's screen: [dictionary](dictionary.md),
[metronome](metronome.md)), **Share**, the keyboard button
([keyboard shortcuts](keyboard-shortcuts.md)) and **ⓘ** (it says "Your
edit is kept as you make it and plays with the video; Download makes a
file of it."); on a screen under 600 points wide (a phone), Dictionary,
Metronome, Share and ⓘ are in a **More** menu (⋮) at the bar's end, so
the file's name keeps some room. It opens with the video's edit as it
was left. It's **a frame that doesn't scroll**, as a small video
editor's: **the viewer** on top, with the **Download settings** beside
it or under it; and docked at the bottom edge, the whole width, **the
transport** right over **the rows** (the ruler, the video's row, the
Song row once there's a song, and the cut's steps). The dock is as
high as its rows: 82 points for the video alone (the ruler, 32; the
row, 44; 6 under it), 128 with a Song row (another 44, 2 apart), so a
video alone leaves the viewer more room. The dictionary's and the
metronome's sidebars open at the right of it all, the body's whole
height, and stay usable during a download. The editor's body is laid out at least
360 points wide (or the screen's width, where that's narrower): on a
phone with the dictionary's or the metronome's sidebar open beside it,
it's cut at the sidebar's edge rather than squeezed. While the
on-screen keyboard is open (the title typed in), the transport and the
rows give their room to the viewer and the field, and come back as it
closes; in a window too short for them, the cut's steps go first, then
the rows, then the transport.

<a id="in-cam"></a>**In Cam** the editor is the same view: the editor
and [Cam](cam.md) are one widget, `StudioView`
([`video_edit_screen.dart`](../tabcam_app/lib/screens/video_edit_screen.dart),
Cam's parts in
[`video_edit_cam.dart`](../tabcam_app/lib/screens/video_edit_cam.dart)),
one frame whatever is in its **main row**: a page opened to edit, or, in
Cam, the camera. `VideoEditScreen` (the editor over the file screen) and
`PlayAlongScreen` (Cam) build it, the first with the page, the second
with the camera ([Cam's view](cam.md#cams-view)). A take's **Edit** in
Cam's play-along sidebar puts the take in the main row in place of the
camera, with no screen pushed over Cam: the viewer shows the take with
its layers, the dock has the transport, the take's rows (Take, then its
Song lined up) and the cut's steps, the Download settings are beside or
under the viewer as above, and the app bar is the editor's, with
**Back** at its start and **Play along** (♫) after Metronome (on a
phone, in the More menu). The play-along sidebar stays at the right,
the body's whole height, as the dictionary's and the metronome's do;
the take edited shows neither Edit nor Delete there. The keys are the
editor's: the space bar plays the preview and ← and → move it, while
Cam's keys and the play-along's own (/, ., 1, 0) do nothing ([keyboard
shortcuts](keyboard-shortcuts.md)). The camera stays open behind it,
hidden, its head gestures paused (no frame goes to them; Cam's
`CamSession.setAway`), and the metronome plays on. Another take's Edit
meanwhile takes this one's place, its edit kept first. **Back** (the
app bar's, the system's, the browser's) keeps the edit and puts the
camera back, with the song in the main row as it was; so does a file
tapped in the sidebar, which then plays in the main row. On a phone,
where the sidebar would leave the editor narrower than 360 points, or
on its side, too narrow for the Download settings beside the viewer
(560 points in a window under 480 high), the Edit hides the sidebar,
and it shows again when the camera is back (Play along shows it
meanwhile). During a download Back does nothing and the
sidebar takes no taps, as the rest of the editor. What's in the main
row changes in place (`_switchMain`): a change not yet kept is kept with
its page at once, the players are let go of, everything known of the
page is forgotten (`_forgetPage`), and the next opens as the editor
opens one. The edit is the page's, as anywhere: a take edited in Cam
opens as left on its file screen, and the other way round. A reload
while a take is edited in Cam opens Cam on the camera
([navigation](navigation.md#coming-back-where-the-user-was)).

<a id="download-settings"></a>**The Download settings**
([`download_settings.dart`](../tabcam_app/lib/screens/download_settings.dart)):
what Download puts in the file and how it sounds, in a sidebar with its
title ("Download settings") and ✕ at the top, then, scrolling, the
[**Master**](#master), [**On the video**](#on-the-video) (its chips,
the fields they open and the tab's style) and [the song's
details](#the-songs-details), or, with no song, **Add a song**. The app
bar's **Download settings** button (a tune icon, in the primary colour while they show, then "Hide the
download settings") shows and hides it, as the dictionary's and the
metronome's buttons do theirs; its ✕ hides it too.

- **Where**: beside the viewer, on its right, where the editor's room is
  **wide**: 840 points and more, or 560 in a window under 480 high (a
  phone on its side). The width is the editor's own room's, not the
  screen's: with the dictionary's or the metronome's sidebar beside the
  editor, a 900-point window has the settings under the viewer. The
  height is the window's, which the on-screen keyboard doesn't change:
  typing the title on a tablet in split view or a foldable's inner
  screen, the settings stay where they were. Beside it, its default
  width is 320 points (at most 40% of the room); its left edge is a
  separator to drag (`SplitHandle`, as the other sidebars') wider or
  narrower, from 224 points (40% of the narrowest wide room, where the
  Master's slider keeps some room at the largest text size; the other
  sidebars go down to 160) up to leaving the viewer 96, a double tap
  putting the default back, and the width is kept on the device with
  the other sidebars' ([`SidebarWidths`](../tabcam_app/lib/screens/sidebar_widths.dart),
  `downloadSettings`). Elsewhere (a phone) it's under the viewer, across
  it: the viewer as high as the picture needs, leaving the settings at
  least 160 points, their title included (a tall video takes the rest).
  Hidden, the viewer takes all the room, and the picture grows into it
  where it can.
- **Open the first time** in each session of the app; hidden, it stays
  hidden for the session, in this editor and the next, until it's shown
  again (app-wide, `DownloadSettingsState`, not kept on the device).
- **A tap on the picture that opens one of its fields shows it** where
  it's hidden, scrolled to that field: a tap on the title, a fade's
  badge, a long press on the tab's band on a phone, and, on a wide
  screen, a tap that picks the band (its style is in the settings).
  Hidden, the fields a chip opened in the chips' place (on a phone)
  close, as Done does.
- During a download it takes no taps, as the rest of the editor.

- **The viewer**, at the top: the video as large as its box allows, on
  black (a tap on the black plays or pauses it): the video
  (its taps are the [on-picture controls'](#on-the-picture): a tap on
  what's drawn picks it, elsewhere it plays or pauses; on a phone, a
  long press on the tab's band opens its style),
  with what Download draws over it (the [layers](#layers): a take's
  tab, the title, the watermark as this user's download would have
  it), drawn by the same code, so the preview is what the file will be
  (while the title's text is being edited, the title shows as it ends
  up, the whole kept part through, rather than as its cards fade in and
  out, so it's seen wherever the preview is). While it
  plays, the [fades](#fades) darken it from and to black and ramp both
  lanes with it; paused, the frame shows as it is (a trim's grip shows
  the frame it cuts at, not black). **It plays from where the playhead
  is**, anywhere in the video: in the kept part as the edit plays it
  (both lanes as set, the fades, what's drawn over it); in a cut part
  (dimmed on the lanes) the video as it is, its own sound at its lane's
  level, no song, nothing drawn over it and no black. Playing into the
  kept part from before it, the edit takes over there; reaching **the
  kept part's end** it stops and rests there, on its last frame, and
  Play then starts again from the kept part's start; started after the
  kept end, it plays on to the video's end. A click on the ruler or a
  lane while it plays keeps it playing from there. (The file screen's
  player plays the kept part only, as above.) A player that fails (a
  play the browser refused, a file it can't read on) says "This video
  can't be played here" with **Try again**, which opens it again with
  the edit as it was kept.
- <a id="on-the-picture"></a>**On the picture** (a video editor's
  on-screen controls, [`on_picture.dart`](../tabcam_app/lib/screens/on_picture.dart)):
  **while the preview is paused**, each layer drawn at that frame has a
  thin white outline: the take's band showing then, the title while one
  of its cards is on (all through it, though it fades in and out) and
  the watermark. Nothing of it shows
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
  opens the fades' sliders (on a phone, in place of the chips), showing
  the [Download settings](#download-settings) where they're hidden.
- **The transport**, one row 48 points high right over the lanes: at
  its left **the current time** (`0:12.3`, to the tenth of a second)
  over the part kept (`Keep 0:02.5–0:41.0`, in the primary colour once
  trimmed; both shrink to fit at large text sizes); in the middle **To
  the start** (⏮), **Play** / **Pause** (filled, larger) and **To the
  end** (⏭); at its right **Start here** (|◀) and **End here** (▶|),
  which set either end where the preview is (icons with tooltips,
  named from 720 points wide). **To the start** goes to the kept
  part's start, or, there already, the video's, playing on if it
  played; **To the end** pauses and goes to the kept part's end, or,
  there already, the video's. Play / Pause's tooltip names the space
  bar: **the space bar** plays and pauses the preview too, as a tap on
  it does, wherever the editor is clicked. **Home** and **End** are To
  the start and To the end, and **←** / **→** move the preview a tenth
  of a second (with Shift, a second; held, a seek at most every
  150 ms). **H** lists these keys ([keyboard
  shortcuts](keyboard-shortcuts.md), also the app bar's keyboard
  button). No key does while the title is typed in, nor with Ctrl, Alt
  or ⌘ held; Home, End and the arrows only while nothing in the editor
  has the keyboard (a slider's arrows are its own; a click on an empty
  spot gives it back). During a download the row says "Making the
  file…" instead. The kept part is at least half a second long. **A cut's or the song's
  time** (the part kept, the cut's ends under the lanes, where the song
  starts, how far it was moved, the part of it used) is shown to the
  tenth of a second when it's on one, else **to the hundredth**
  (`0:02.55`, `0:01.26`), so every step of ‹ and › shows, and a cut on
  one of the song's marks reads as it is.
- <a id="waveforms"></a>**Each lane draws its sound**: a waveform over
  its bar, the Take lane's from the video's own sound, the Song lane's
  from the song's file where the song plays along the video (each clip
  of one lined up in clips, the part used of one placed by hand), each
  point's loudest mirrored about the bar's middle, in the text's colour,
  brighter in the part kept and dim outside it, scaled so the loudest of
  each is the bar's height (a quiet take shows as well as a loud song).
  The sound is read once, as the editor opens or a song is picked, on
  the device with the same readers as [the song's line-up](#a-takes-song-lined-up)
  ([`SoundReader`](../tabcam_app/lib/capture/sound_reader.dart): Web
  Audio in the browser, `MediaCodec` on Android, `AVAssetReader` on
  iOS), at 4000 samples a second and kept as its loudest every 5 ms
  ([`waveform.dart`](../tabcam_app/lib/capture/waveform.dart); at most
  30 minutes), so it stays fine zoomed in all the way ([zoom](#zoom)).
  Until it's read, and where it can't be (no reader on a desktop build,
  no sound in the file, a format not decoded), the bar shows without
  it, as before; it never holds anything back, and nothing is sent
  anywhere.
- <a id="zoom"></a>**The timeline zooms**: **Zoom out** and **Zoom in**
  (magnifiers) sit in the corner left of the ruler, over the rows'
  headers, with the zoom between them once it isn't the whole video
  (`4×`, in the primary colour). Zoom goes 1×, 2×, 4×, 8×, 16× and 32×
  (at 32×, a 3-minute take's rows show under 6 s at once), each a step;
  Ctrl / ⌘ + the mouse wheel, and a trackpad's pinch, zoom too while
  zoomed in. Zoomed in, the ruler, the rows' bars and the playhead
  are as many times wider, on their one time axis, and scroll sideways
  together (a scrollbar under them; the wheel or a trackpad's sideways
  swipe), the rows' headers staying put at their left. Zooming keeps
  the playhead where it was on screen. While the preview plays, the
  timeline scrolls to keep the playhead in view (a quarter in from the
  left once it would leave it). Everything on the rows works as at 1×,
  at the zoom's precision: a tap or a drag on the ruler or a row is
  where it is in time, a grip or the song dragged moves as many times
  less time per point, and **a grip snaps to the song's marks within a
  hundredth of the part in view** (no less than a twentieth of a second
  at 1×, down to a millisecond at 32×) rather than of the whole video.
  The zoom isn't kept: the editor opens on the whole video.
- **The timeline**, docked at the bottom: a **ruler** 32 points high
  (the video's times, m:ss, a tick as
  often as there's room for its time, down to a tenth of a second
  zoomed in, "0:01.5"; its times stay small at large
  text sizes; on a take with its song lined up, a small flag in the
  primary colour at each of [the song's marks](#the-songs-marks), where
  it starts and stops), right over **the rows**, 2 points apart, on
  **one time axis** (`_rows` in the editor, keys `video-edit-take-row`
  and `video-edit-song-row`): first the video's own, its only row, then
  the [Song row](#the-song-row) once there's a song. Each row is one of
  the edit's two sound lanes; its bar spans the whole video, lined up
  under the ruler, after the row's **header** at its left: its name
  (small, two lines at most on a phone, 72 points; one line, 136
  points, on a wide screen; 16 of them are room for the ⋮ of a name
  that opens a menu, so the ⋮ doesn't cut the name short: on a phone,
  "Sonido del video" stays whole on two lines, as does "Video sound"
  at the largest text, checked in Roboto in
  `test/video_edit_frame_test.dart`), then its **volume**. **The playhead**,
  where the preview is, is a line across the ruler and the rows with a
  small handle on the ruler; it and the time move at once on a click, before
  the player gets there. Tapped or dragged, the ruler takes the preview
  anywhere in the video (while dragged, a seek at most every 150 ms;
  exactly where it's let go); **a click or tap on a row's bar does
  too** (the Take row's or the Song row's), exactly where it's
  clicked, while a drag on them still trims or moves as below. Playing,
  it plays on from there; paused, it stays paused, and Play starts from
  exactly there. Neither moves anything while the video's length isn't
  known.
  This holds for a take the browser recorded too, whose player can't say
  how long it is (MediaRecorder writes no length: the browser calls it
  endless): the player is told the length the editor finds as it opens
  (on the web, every player of a capture's file is, as it opens), since
  until it knows it, every seek went to the start, Play stuck there and
  the time read a huge negative number. The rows are labelled
  **Take** and **Song** for one of Cam's takes, **Video sound** and
  **Track** for any other video.
  - **The Take row** (the video's own sound's lane): the whole video,
    the kept part bright and the rest dimmed. Its name is in its
    header; while it's the only row, the name has a ⋮ and opens **Add a
    song** (**Add a track**) (keys `video-edit-take-menu` and
    `video-edit-take-add-track`), as the [Download
    settings](#download-settings) do; with a Song row it's just its
    name. **Its two grips trim it**, and both
    sounds with it: what's outside the kept part is dimmed in both
    rows, and **the song stays where it is along the video** (a
    trimmed start cuts the song's start with it). While paused, the
    preview follows the grip dragged (a seek at most every 150 ms,
    exactly the end it moved when let go). On a take with its song
    lined up, [the song's marks](#the-songs-marks) are thin lines down
    the bar, and **a grip dragged near one is on it** (it snaps: the
    cut is then exactly where the song starts or stops).
    <a id="the-cuts-steps"></a>**Under the rows, the cut's two ends,
    each stepped by ‹ and ›**: at the left **Start 0:02.5**, at the
    right **End 0:41.0**, each between **‹** and **›**, which move that
    end **0.05 s** (a twentieth of a second) earlier or later ("Start
    0.05 s earlier", "End 0.05 s later"…), from wherever it is (a cut on
    a mark at 0:01.26 steps to 0:01.31), within the video and no nearer
    the other end than half a second (greyed where there's no further
    to go). The song stays where it is along the video, and the
    preview, while paused, shows the frame cut at, as with a grip. Keys
    `video-edit-start-earlier`, `-later`, `-at`, `video-edit-end-…`.
    They're a row 40 points high under the rows, as wide as the bars;
    a window too short for them (a phone on its side, with a Song row)
    leaves them out and keeps the rows; under the video alone, a phone
    on its side has room for them. On a phone they fit at the largest
    text size (the times shrink).
    Checked (`test/video_edit_test.dart`): each end stepped earlier and
    later, the times shown, the edit kept, the song where it was, the
    preview sought to the end moved, and no step past the video's ends. This replaces
    the Trim section's range and the preview's scrub bar. The [fades](#fades)
    are drawn on the kept part as ramps at its ends (shaded above a
    line from its corner across the fade's length), as long as they
    play.
  - <a id="the-song-row"></a>**The Song row** (the song's lane) is
    there only once there's a song. A take recorded while a song played
    along (one Cam noted in its [log](cam.md#what-a-take-keeps), still in
    the capture) opens with that song in it, **lined up by itself** as
    it played while recording ([lined up](#a-takes-song-lined-up)), with
    no edit kept for it: nothing to sync by hand. A song the edit has
    (a take's lined up, or one placed) has its row from the moment the
    editor shows, empty until the song's player opens, so the viewer
    doesn't shrink as it comes; Reset keeps a take's the same way while
    it's put back. Otherwise **the video is its only row**, with no
    empty lane beside it: **Add a song** (**Add a track**), in the menu
    the Take row's name opens and in the Download settings' song
    section (an outlined button, key `video-edit-song-add`), opens a
    sheet, **Pick a song** (**Pick a track**), of the
    capture's **recordings**, **videos**
    and **takes** (not the video edited) and **a sound file** from the
    device (**a sound file picked is added to the capture's files** as
    a recording, named after its file, so the edit can name it and it
    syncs with the rest). Picked, the song is placed by hand
    (`song: manual`) **at the timeline's end**: one shorter than the
    kept part ends where it ends (silence before it), one as long or
    longer starts with the kept part (none of its start cut), as does
    one whose length can't be told; heard at the lane's
    level; its row comes under the video's, the dock growing by it, and
    its bar shows its used part (its name on it) where it plays
    along the video, what falls outside the kept part dimmed (it's cut
    off). **Dragged, the song moves** along the video; **dragged by
    either end, it's trimmed** (a grip at each end; the start moves
    with what's cut, so the rest stays put; at least half a second
    stays). **Its name in the row's header**, with a ⋮, opens
    **Change** (the sheet again) and **Remove** (its row goes and the
    video is its only row again, the edit keeping `song: off`, so a
    song a later version would add by default isn't put back; Reset
    stays on, and clears it). Checked (`test/video_edit_test.dart`, the
    rows; `test/video_edit_frame_test.dart`): a video opens as its only
    row, the dock 82 high; Add a track from its name and from the
    Download settings, the Song row then under it; a take with its song
    opens Take, then Song, from the first frame; Remove takes the row
    away and Reset puts it back; a phone on its side keeps the cut's
    steps under a video alone and leaves them out with a song.
    A song whose length can't be told shows its name alone, unplaced,
    and holds back Download while it's heard; muted, it's left out of
    the download, which goes ahead (as an older app's edit with a track
    picked but the video's own sound chosen).
  - **Each row's volume**: a speaker over its level (`80%`, in the
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
    bars are 44 points high, a touch target's. The preview plays each lane at it at once.
    A lane goes **up to 100%**; louder is the master's (below). Both
    lanes default to 100%. With echo cancellation off while recording
    ([Cam](cam.md)), a take's own sound has the song from the speaker in
    it too: the levels and Mute are the remedy (headphones while
    recording give a clean mix). Under the slider, the lane's
    [channels and balance](#a-lanes-channels-and-balance); the level and
    speaker are in the primary colour too once either is changed.
  - <a id="a-lanes-channels-and-balance"></a>**A lane's channels and
    balance** (in its volume's popup, under the slider; `LaneStereo` in
    [`page_edit.dart`](../tabcam_app/lib/library/page_edit.dart)):
    - **Channels**, four segments, each with its tooltip: **Stereo** ("As
      recorded", the default), **Left** ("The left channel on both
      sides"), **Right** ("The right channel on both sides") and **Mono**
      ("Both channels mixed, on both sides", each at half). Asked for a
      take recorded on the left only (a guitar into one input of an
      interface): Left puts it on both sides. A one-channel sound plays
      on both sides whatever is picked.
    - **Balance**: a slider from left 100% through **Centre** to right
      100%, in steps of 5%, its value beside it ("L 30", "Centre", "R
      30"): the side it leans away from is turned down in a straight line
      (R 30: the left at 70%), the other stays as it is; after the
      channels (Left, then R 50: the left at 50%, the right at 100%).
    - Once either isn't the default, a note under them: "Download has the
      channels and balance; the preview plays the sound as recorded." The
      players (video_player, the browser's media element) can't pan, so
      the preview and the file screen's player play the sound as it is;
      Download's file has them. Kept as every change (a moment later),
      reopened as left, and Reset puts both lanes back as recorded. A
      song taken out of the lane, or another one picked, starts as
      recorded.
    - Keys `video-edit-<lane>-channels` (the segments
      `video-edit-<lane>-stereo`, `-left`, `-right`, `-mono`),
      `-balance`, `-balance-level` and `-stereo-note`. The segments
      shrink to fit the popup at large text sizes.
- <a id="master"></a>**Master**: both lanes go through it, after their own levels
  ("Master · Both sounds together, up to 200%"): **Mute** (a speaker,
  "Mute (Master)"; muted, nothing is heard and the level is kept, as a
  lane's) and a slider from **0% to 200%** in steps of 5% (sliding
  unmutes it), its level beside it (in the primary colour when it's not
  100% or it's muted, struck through while muted). It's in the
  [Download settings](#download-settings), **right above the fades'
  sliders**: beside the viewer, under **On the video**'s chips, between
  the title's fields and the fades; under the viewer (a phone), at the
  top, above **On the video** (whose Fades chip opens the sliders in its
  place, so it's above them too). Keys `video-edit-master`, `-mute`, `-slider`,
  `-level`. 100% by default; Reset puts it back. **Past 100% only the
  download is louder**: the players can't play a file louder than it
  is (video_player's volume and the browser's media element stop at
  1), so the preview plays a lane at its level times the master's, at
  most 100%; Download's file has the full level, each renderer clipping
  what goes past full scale rather than wrapping it
  (**How it's rendered**, under [fades](#fades)).
- <a id="on-the-video"></a>**On the video**, in the [Download
  settings](#download-settings): what's drawn over the video, as chips
  (beside the viewer, where the editor is wide, the title's fields, the
  master, the fades' sliders and the tab's style are under its chips;
  under it, on a phone, each opens in the chips' place):
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
    **White on black** (the default), **Gold on black**, tabs.cam's
    gold, and the app theme's primary and secondary colours on black,
    **Amber on black** and **Sand on black**; black on white and black
    on gold were offered once and taken
    away: an edit kept with either draws white on black now; the one
    picked ringed in the
    primary colour with a check; each a button with its name as its
    tooltip and for screen readers, saying whether it's picked),
    **Alignment** (three buttons, each an icon with its name as its
    tooltip: **Left**, the default, **Centre** and **Right**: where the
    tab's text sits across its band, past the band's padding on the
    left or right; bands were centred before it could be picked, and an
    edit kept then now draws its tab to the left; kept as `align` in
    the `tabStyle`, only when it isn't left),
    **Default style** (on once it's anything but the default: back to
    100%, 70%, white on black, to the left) and, on a phone, **Done**. The preview
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
    text: on a phone in place of the chips ("Title · Top left · the
    first and last 15 s"), with **First line** and **Second line** (80
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
- <a id="the-songs-details"></a>**Under them, the song's details**
  (when there's one; with none, **Add a song** (**Add a track**), which
  opens the sheet the Take row's menu does): its lane
  and name ("Song · Recording 1", on one line: in a narrow sidebar at a
  large text size, the lane's word takes at most half of it, and each is
  cut short with "…"), **‹** and **›**, which nudge it
  **0.05 s** (a twentieth of a second, the cut's step too; "0.05 s
  earlier", "0.05 s later") earlier or later, with where it starts in words
  between them ("The song starts 0:01.5 after the video": silence
  first; "… 0:01.5 before the video": that much more of its start is
  cut; counted from the kept part's start; for a song lined up in
  clips, its first), and, once trimmed, "Using
  0:01.0–0:42.5 of the song" (not for one lined up in clips).
  <a id="the-songs-delay"></a>Under ‹ and ›, **the song's delay, to the
  millisecond** ("Delay · To correct a Bluetooth speaker's or
  headphones' delay, a millisecond at a time."): its value, signed
  (`+120 ms`: the song that much later; `−35 ms`: earlier; `0 ms`), in
  the primary colour when it isn't 0, between **−10** and **−1** on its
  left and **+1** and **+10** on its right ("10 ms earlier", "1 ms
  later"…), a millisecond being about the smallest difference heard
  between two sounds. Tapped, the value opens **Song delay**, a field
  to type it in milliseconds ("Milliseconds: + later, − earlier"; Set,
  Cancel), at most 10 s either way. For a song lined up by itself it's
  how far it's been moved from that line-up (0 as lined up); for one
  placed by hand, where it starts against the kept part. It moves the
  song as ‹ and › do (the first clip's offset, the whole line-up with
  it), is kept with the edit, and Reset clears it. It shrinks to fit a
  narrow panel. Under it, for a take whose log says what its song
  played through ([`out`](cam.md#what-the-song-played-through)), a
  line says so: "Played through Bluetooth" (the speaker, wired
  headphones, a USB device, AirPlay, another output), with "; the
  device reported 160 ms" where the platform gave a latency (iOS, the
  web: a hint, never applied by itself) and "; the output changed
  during the take" when it did. **Remembered per output**: for a song
  lined up by itself and not found in the take's sound, through
  headphones (wired, Bluetooth, USB) that didn't change during the
  take, **Remember +170 ms for this Bluetooth device** ("these
  headphones", "this USB device") keeps the delay shown on this device
  for that output (its route and the fingerprint of its name, the
  device meta [`outdelays`](library.md#device-settings), −500 to 2500
  ms); once kept, "Kept for this Bluetooth device: its takes open with
  it"; at 0 ms with one kept, **Forget the delay for this Bluetooth
  device**. <a id="seeded-delay"></a>A take through that output (its
  log's `out` the same route and fingerprint, headphones, not changed)
  whose song is lined up by itself and wasn't found in its sound (not
  measured, or measured and not found), its Song lane still where the
  log has it (none kept, or kept unmoved: `LoggedSong.shiftOf` none),
  **opens with the delay kept**: the song moved by it as the delay
  control moves it, and the edit kept so (Download, the file screen and
  other devices play it there). A lane at that delay hasn't been moved
  by hand: when the song is then found in the take's sound (a take not
  measured yet, measured as the editor opens), it follows to where it
  was found, the delay dropped, since a found line-up has the output's
  delay in it already. Reset puts the take back as noted (no delay);
  the kept delay applies again the next time it opens, until Forget.
  The speaker and AirPlay are said, not remembered (a speaker's delay
  is found in the take's sound). A song
  lined up by itself says so under them: "Lined up by its sound in the
  take" when it was [found there](#a-takes-song-lined-up), else "Lined
  up as it played while you recorded", or, once nudged or dragged,
  "Lined up as recorded, moved 0:00.2 later" (or "earlier"); and under
  that, **Cut to the song** (scissors; "Keep the take from where the
  song starts to where it stops"), which keeps the take from the
  song's first start to its last stop ([the song's
  marks](#the-songs-marks)), greyed once that's the part kept.
  <a id="auto-align"></a>Beside it, for any song in the Song lane (lined
  up by itself, placed by hand, or a track on another video),
  **Auto-align** (a wand; "Find where the song lines up with the take,
  by their sounds, or by the rhythm with headphones"; on another video
  "Find where the track lines up with the video, by their sounds, or by
  the rhythm") moves the song to where the take's sound has it
  ([how](#a-takes-song-lined-up)). While it listens it's greyed, a
  spinner in place of its wand, and under it "Listening… 1 of 4" (the
  parts read, of how many); then it says what it did: "Lined up by the
  sound: moved 300 ms later" (or "earlier"), "Lined up by the sound:
  it was there already", "Lined up by the sound, roughly: moved 120 ms
  later; its parts disagree by 60 ms" (the song's parts found more
  than 30 ms apart), "Lined up by the rhythm: moved 180 ms later (it
  could be a beat off)" (headphones), "Found by its sound in the take,
  and lined up there" (a take not measured yet, measured first), "The
  song wasn't found in the take's sound, nor by the rhythm: zoom in and
  drag it under the take, or nudge it by ear" (on another video "The
  track wasn't found in the video's sound…"), or "The sounds couldn't
  be read here" (a file this device can't decode). It isn't offered
  where no sound can be read (the desktop builds). The move is the
  delay control's: kept with the edit, a song lined up by itself
  staying lined up, Reset undoing it; what it said goes when the song
  is changed or Reset. They
  name it as its lane does: "song" on
  a take, "track" ("The track starts…", "… of the track") on any other
  video. A song shorter than the kept part leaves
  silence after. They're at the end of the [Download
  settings](#download-settings).
- <a id="reset-and-download"></a>**In the app bar**: **Reset** (on once the edit is anything but the
  defaults: the whole video, its own sound at 100%, no song said (so a
  song Removed, `song: off`, keeps it on), a take's tab on, the title
  on with the capture's name, the watermark on, and fades of 3 s in and
  out, and a take's song lined up as it played while recording, where
  it has one; Reset goes back to them, any other song taken out, its
  row going (a take's own put back, lined up, its row staying), and the
  edit is
  none: none means the defaults, a take's tab, the title, the watermark,
  the fades and its song lined up included, not the file as it is) and
  **Download**, a split button: named from 840 points wide, icons with
  their names as tooltips under it (⟲ and ⤓), both shrinking to fit
  rather than crowd out the file's name, at the largest text sizes too. Pressed, it downloads **the video** as edited, both lanes
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
  video is in the list followed by the time it's downloaded,
  `_YYYYMMDD-HHMMSS` in the device's time (so each render of an edit
  is a file of its own, never overwriting or clashing with the last; a
  long name is cut, never the time), with the made format's extension
  (`.mp4`, `.m4a`; `.webm`, `.wav` where those are made), e.g.
  `Made-up riff_20261117-180509.mp4`; a video the edit
  doesn't change and with nothing drawn over it (the watermark off, so
  for a Premium user, or in a build without the service, and no title)
  and no fades downloads as it is when it's already MPEG-4 (an
  `.mp4` or `.m4v`, on every platform: in Firefox too, which would make
  it again only as a WebM) or already in the format made here (a
  `.webm` where the browser records WebM), and is made again otherwise
  (a WebM take in Chrome, a MOV), so the video is an MP4 wherever MP4
  is made (the plan is a [passthrough](#the-render-plan)). A progress
  bar shows meanwhile under the app bar, saying how far along it is (the
  browser's as the video plays; the phones' as Media3 or AVFoundation
  report it, every quarter of a second), with "Making the file…" in the
  transport's place; a
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
  default), `masterMuted`, `ownChannels` and `songChannels` (a lane's
  [channels](#a-lanes-channels-and-balance): `left`, `right` or `mono`;
  absent, or one this version doesn't know, `stereo`), `ownBalance` and
  `songBalance` (-1, the left only, to 1, the right only, to the
  hundredth; absent or not a number, 0), and
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
  `gold`, `primary`, `secondary`; `light` and `brand`, black on white
  and black on gold, were taken away and read as the default), e.g.
  `{"size": 1.5, "colors": "gold"}`.
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
- **Found in the take's sound, it's lined up there**: that line-up is
  what Cam noted (the player's word and the lag), a tenth of a second
  or so off at worst. The take's microphone heard the song from the
  speaker, so where it really is gets measured from the take's own
  sound, to the millisecond, and kept with the log
  ([`sync`](cam.md#the-song-found-in-the-takes-sound)): each clip is
  then that much later (or earlier) in the file, each segment measured
  by its own shift, the others by the song's, one found before the
  file's start cut there (`LoggedSong.measured`). So the song in the
  Song lane lies exactly over the song heard in the take: no echo
  between the two when both are heard, and a cut on the song's edge is
  on it in both. Cam has a take measured once it's saved; the editor
  has one that wasn't (a take from before, or from a device that
  couldn't read its files) measured as it opens, and the Song lane
  follows when what's found arrives, a moment later. Not found
  (headphones while recording, or the song too quiet in the take), or
  not measured yet, it stays as noted, moved by the delay control
  for what the headphones added (and, through headphones it was kept
  for, by the [delay kept for that output](#seeded-delay)). **An edit kept before it was
  found** follows too, when it had the song where the log alone had it
  (not moved: `LoggedSong.shiftOf` none); one moved by hand stays
  exactly where it was put. The file screen's player and Download line
  it up the same way, from the same log.
- <a id="the-songs-marks"></a>**The song's marks, to cut by**: where
  the lined-up song starts and stops in the take, clip by clip
  (`LoggedSong.marksIn`: the clips' edges as the edit has them, moved
  with the song, none past the video's end or the song's), are drawn on
  the timeline: a flag on the ruler and a thin line down the Take lane,
  in the primary colour. **A Take grip dragged to within a hundredth of
  the part in view of a mark** (the whole video at 1×; a few points of
  the lane; at least a twentieth of a second at 1×, a millisecond at
  32×, [zoomed](#zoom)) **is on the mark** (the nearest), so the take
  is cut exactly where the song starts or stops, to the millisecond;
  further away it's where it's dragged. **Cut to the song**, under the
  song's details, does both ends at once: the first mark to the last.
  Start here and End here don't snap (they cut where the preview is).
  A song placed by hand, or none, has no marks.
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
  speaker's delay is in the measured line-up; headphones' is the delay
  control's). **Trimmed** by its grips (one clip
  only: a song in clips has none, its bar spanning them all, dimmed
  between them), or another song picked, it's placed by hand
  (`manual`, its one clip as its track keys say). **Remove** keeps it
  out (`song: off`); **Reset** puts it back.
- <a id="auto-align-how"></a>**Auto-align** ([the button](#auto-align),
  `SongSync.align`, [`song_sync.dart`](../tabcam_app/lib/capture/song_sync.dart)):
  for a song nudged off, one placed by eye, or a take whose song
  wasn't found. A take not measured yet is measured first, as when the
  editor opens it (it writes the log's `sync`); found, the Song lane
  goes where it was found (any nudge undone), and that's all. Otherwise
  it listens **around where the Song lane has the song now** (each clip
  of a song lined up by itself as the edit moved it, else its one
  placed part, cut to the video), the way the song is
  [found in a take's sound](cam.md#the-song-found-in-the-takes-sound)
  (each clip of 3 s or more, the six longest, up to four 8 s windows
  along each, the correlations added up, the drift taken out) but
  **2 s either way** (the measure looks 0.6 s), a match counting at 16
  times the others' spread (14 for the measure, which looks at fewer
  places) and 1.3 times the next best: the middle clip's shift is the
  move. Its parts (the clips, and the windows clear on their own within
  0.25 s of it) more than 30 ms apart, it says so ("roughly"); where
  the windows are clear on their own but their sum isn't (they disagree
  a little), their middle one is taken. **Not in the take's sound**
  (headphones): **by the rhythm**, the guitar's onsets against the
  song's (`SongSync.onsets`: each hundredth of a second, how much
  louder it gets, less its mean over the second around, scaled to unit
  length; `onsetAlign`: their correlation added up over the windows,
  lags of up to 2 s, its peak taken weighted by a Gaussian 0.7 s wide
  around the lane's place, so a match a beat apart about as good goes
  to the nearer). It counts when the onsets correlate at 0.13 or more
  a window on average and stand 4 spreads above the rest; it could be
  a beat off, and says so. The move goes through the delay control's
  path (a song lined up by itself stays lined up; kept with the edit);
  **Auto-align never writes the log's `sync`** (a take measured keeps
  what was measured). On the device, from the files: nothing is
  uploaded; the sounds are read with one reader for the run (the web
  decodes each file once for it).
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
  nothing played; a song found in the take's sound lined up there, each
  clip by its own shift, an edit kept where the log had it following
  and one moved by hand staying, the marks (trimmed, moved, cut to the
  video and the song); the editor showing "Lined up by its sound in the
  take" and the marks on the Take lane where they are, Cut to the song
  keeping the first mark to the last, a grip dragged near a mark on it
  and one away from them where it's dragged, Download's clips after;
  and a take not measured yet measured as the editor opens, the Song
  lane following with nothing kept, one moved by hand staying where it
  was put; Auto-align (`test/video_edit_test.dart`, group
  `Auto-align`; `test/song_sync_test.dart`, group `align`): a measured
  take's song moved 300 ms off put back where its sound is (still lined
  up, the edit none again, Download's clip there, the log's `sync`
  unchanged) and "already there" the second time, a headphones take
  lined up by the rhythm within 25 ms of 180 ms, a take not measured
  yet measured first, a track placed by hand on another video moved
  283 ms, hiss not found and files unread said so (the song unmoved),
  greyed with its progress while it listens, and not offered without
  a reader; and on made-up riffs, a song found 83 ms, 1.5 s and −1.3 s
  off and not by the sound 2.5 s off, a long clip's four windows and
  two clips' each, halves 60 ms apart said rough, the rhythm 180 and
  ±420 ms off found (not a beat off), guitars in other tempos and hiss
  not, the onsets and their alignment. How the song is found is checked with
  [Cam's log](cam.md#the-song-found-in-the-takes-sound). **Not yet on a
  phone**: how close the line-up is there once measured (in Chrome, a
  song played into a video recorded as a take is was found about a
  tenth of a second from where it was noted, and lined up there), and
  with headphones, where nothing can be measured: whether a Bluetooth
  take's residual on Android is tens of ms (ExoPlayer's position allows
  for the headset's own delay report) or the whole latency (then the
  delay kept for it carries it), and how far iOS's reported latency is
  from the truth. Also checked (`test/video_edit_test.dart`): what the
  song played through said under the delay (the device's figure, an
  output that changed), Remember keeping the delay for a Bluetooth
  output in `outdelays`, Kept, Forget, and none offered for the
  speaker; a take through it opening with the kept delay, kept with the
  edit and in Download's clips, and not one found in its sound, moved
  by hand, through an output that changed, other headphones or none
  noted; and a headphones take not measured yet opening with it, then
  following its song found in its sound to the millisecond, the delay
  dropped.
  Not yet on a phone either: how long Auto-align takes on a phone (8 reads of 12 s and 8 s
  of sound for a long take), its thresholds on real speaker takes 2 s
  off, and the rhythm's on real headphones takes (a full song's onsets
  against a guitar's, and how often it's a beat off).

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
  2), and its channels and balance (`stereo`), or none (it or the master
  muted, or at 0%);
- the **song** lane: the song's page and file, its level through the
  master's (`songLevel`, as the own lane's), its channels and balance,
  and its
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
  100% and as recorded (its channels and balance), no song, nothing drawn over it, no fades, and the input already in the
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
reached over a `fadeIn` from its start and left over a `fadeOut` to its
end, straight lines; 0 outside its time) and where:
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
top left fading in and out, the watermark at the bottom right. (Android's
`PlanLayer.alphaAt` and iOS's opacity animations, a rise, a hold and a
fall, take the `fadeOutMs` the channel gives each layer; an older app's
renderer has none.)

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
**colours**: white on black, tabs.cam's gold (`#E0A030`) on black, or
the app theme's primary (`#F2BE6E`, a pale amber) or secondary
(`#DCC3A1`, sand) on black: the colours of its dark scheme
(`ColorScheme.fromSeed` of the gold), the one made for dark backgrounds,
fixed in `TabLayout` so a video looks the same whatever the device's
theme (a test keeps them equal to the theme's). The
text is drawn at its size, never
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
at most 80 characters, empty ones left out, at most two. At the **top
left**, 3.5% of the short side in, as **two cards** (`titleLayers`,
two layers `title`, `TitleLayout`): **at the start**, fading in from
nothing to full over the kept part's first 6 seconds, held 3 s, then
fading out over 6 s (gone 15 s in); and **at the end**, fading in over
6 s from 15 s before the end and held to it (under the video's fade to
black). Between them, none. On a kept part shorter than 40 s (no room
for both cards apart) it's one layer instead, fading in over its first
6 s (at most half of it) and staying to its end. The fades are twice
the 3 s the title faded in over before, and the video's own fades are
unchanged. It looks: white, with a soft shadow, on a 35% black
rounded box; the first line in Roboto Medium at 5% of the short side,
the second in Roboto Regular at 80% of that (each line 1.25 times its
text high); a line too long for the frame ends in "…". The box's height
is worked out in Dart from the line count alone (`TitleLayout`), so the
plan knows it without drawing.

**The watermark**: "tabs.cam", the same on a take and on any other
video, in every language (`watermarkText`; no "Recorded by", no
address); one layer, `mark`, at the **bottom right**, 3% of the short
side in, the whole video through, one line of Roboto Mono (fixed width,
as the tabs are) at 2.2% of the short side,
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
**the sound**, both lanes mixed, is multiplied by it. The title's cards
still fade in and out on their own ([layers](#layers)), under the
black. The sound only (M4A) and the video without sound get
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
the app's own text) for the title, and Roboto Mono (`monoFont`, the
tabs' font) for the watermark, so both are drawn the same in the
preview and the file on every platform, and the web never fetches them
from a CDN. They're drawn for a frame whose short side is
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
carries it out; the times are all worked out in Dart. **A lane's
channels and balance** reach every renderer as one 2×2 matrix, `mix`
in the lane's channel arguments (`LaneStereo.matrix`: `[ll, lr, rl,
rr]`, each side of the output from the sound's left and right; left out
when it's as recorded), worked out in Dart, so the three apply the
same thing.

- **Android**: Media3 Transformer
  ([`VideoEdit.kt`](../tabcam_app/android/app/src/main/kotlin/com/nu01/tabcam/VideoEdit.kt),
  method channel `tabcam/video_edit`, method `render`, the plan's
  `toChannel`: `input`, `output`, `video`, `startMs`, `endMs`, `own`
  `{volume, mix}` and `song` `{path, volume, mix, clips: [{atMs, fromMs,
  toMs, speed}]}`, and a `job`). A lane's `mix` is a Media3
  `ChannelMixingAudioProcessor` first in its effects, with a matrix for
  a stereo sound and one for a one-channel sound (its channel as both),
  each into two channels (`StereoMix.matrices`). With the picture: a
  composition whose primary sequence is the video clipped to the kept
  part, its audio removed unless the own lane keeps it (through a gain
  at its volume,
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
  levels that aren't 1, one input per audio track. A lane's `mix` is an
  `MTAudioProcessingTap` on its tracks' inputs (`stereoTap`), giving each
  side of a two-channel track's float samples what the matrix says of
  them (`applyStereo`); a one-channel track is left as it is, on both
  sides in the middle (its balance isn't applied on iOS). With layers, an
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
  over 1: the mix is float, and the WAV writer clips it; a lane's `mix`
  before it, `_stereo`: a gain node made two channels (`explicit`,
  `speakers`, so a one-channel sound is on both), a channel splitter,
  a gain per matrix entry and a channel merger; the mix is then in
  stereo, and an own sound streamed as it plays goes through it too), at 44.1 kHz
  (22.05 kHz for a kept part over 8 minutes). **Each sound at its times
  in its file**: a WebM's sound may start after the file does (a take
  the browser recorded often has its first sound some tens of ms in);
  a player plays it from there, but `decodeAudioData` gives it from its
  first sample, so the decoded sound is placed that much later
  ([`webm_times.dart`](../tabcam_app/lib/capture/webm_times.dart),
  `webmSoundStart`: the sound track's first block's time, read from the
  file), and both lanes are in the mix where their players play them:
  the own sound in step with the picture, and a song lined up by its
  sound exactly over it. `decodeAudioData` decodes
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
