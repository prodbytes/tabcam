# Event screen

One event (a capture), opened from the [library](library.md): the list of
its files, each opening alone on the [file screen](#file-screen). It
always opens on the list (quick to show), a text tab marked correct
([tab recognition](tab-recognition.md#text-view)) included: **Text**
shows the tab, and a reload puts the user back on the view they were on
([navigation](navigation.md#coming-back-where-the-user-was)). **Text and Cam are TabCam Premium's**
([cloud OCR](cloud-ocr.md#in-the-app)): in a build with Premium set up, a
user without it sees both tools with a lock on the icon, and each opens
its screen as a greyed-out preview that takes nothing, under the Premium
card (what the feature is, the offer, **Not now**). When the capture has
recordings, videos, links or PDFs, the Text view has the play-along
sidebar beside it, open (on a screen narrower than 600 px it starts
closed, leaving the text and its tools the width, and opening it loads
the first file to play), and **Play along** (♫) in the app bar (in its
More menu on a phone), as in
[Cam](cam.md#playing-along-with-a-file), its PDFs listed to
[follow](cam.md#following-a-pdf) beside the text, with a quick sheet of tab
notation at its bottom ([tab recognition](tab-recognition.md#text-view));
the Files view has neither, and going to it, or to Cam, pauses what
plays along.

- **App bar**: the title (and the artist under it, if set, and the
  [study](studies.md), muted, with a folder icon); tapping it, or
  **Rename** (pencil), renames the event and, on the user's own, sets its
  study (see [library](library.md#events) and [studies](studies.md)). **Clone** copies the event and opens the
  copy ([library](library.md#events)). There's no Reorder button: the
  [files list](#reordering) reorders in place.
  **Download all** (a download arrow) saves the whole capture as
  `<title>.zip`: every file listed (named as in the list; the images
  left out when [hidden](hidden-images.md)), the text tab as
  `<title> tab.txt` and the links, one a line, as `links.txt` (names
  that repeat get " (2)"…); files still coming down
  ([sync](cloud-sync.md#listed-first-files-after)) are waited for.
  **Share** (a link icon) copies the capture's link, the one way to share
  it ([sharing](sharing.md)). There's no Hide images
  button (captures already [hidden](hidden-images.md) stay hidden).
  First of all of them, in every view (the locked previews too),
  **Dictionary** (a book icon) shows and hides the chord and scale
  [dictionary](dictionary.md) in a resizable sidebar on the right (or,
  turned by its Rotate button, a panel under the screen), and
  **Metronome** (a stopwatch icon) right after it the
  [metronome](metronome.md)'s.
  In the Text view, with its tab shown, the Text view's **Copy**,
  **Rescan** and **Verified** (and Fix, in a build that shows it) come
  first, right of the title ([tab recognition](tab-recognition.md#text-view)).
  On a screen narrower than 600 px they're icons, and Dictionary and
  Metronome (showing or hiding their sidebars), Play along, Rename, Clone, Download all and
  Share go in a **More** menu (⋮) after them, so the title keeps its room.
- **Shared with the user**: a line under the app bar, "Shared by <email>
  · Can edit" or "· Can view and add". Shared to read, Rename, reordering,
  Rotate, Delete and editing the text tab are off for the owner's files
  (the view still changes what shows, without saving it); Add, dragging
  files and Cam add to the user's own [contribution](contributions.md).
- **Contributions**, below the files ([contributions](contributions.md)):
  on the owner's capture, each reader's files under "From <email>", each
  with **Publish** (or Published, to take it back); on a reader's, their
  own under "Your files", each with Delete.
- **Files**: the list of the event's files, in their order, newest last
  (so a page just scanned or added is at the end, and the list scrolls to
  it after Add). Each row has a preview (80 px square, in a row with
  10 px of padding above and below) and a name. Previews are made on
  the device, from the file itself (nothing is fetched from the
  internet); one that can't be made shows its kind's generic badge:
  - **Images** (photos and scans): the image itself, as its filter shows
    it; "Page 1", "Page 2"…
  - **Videos**: the video's first frame (paused, silent) with a play mark
    over it, else a play badge; "Video 1"… The frames are loaded one
    after another (each is a player), so the list shows at once and they
    fill in.
  - **PDFs**: the PDF's first page (PDFium, as the file screen draws it),
    else a PDF badge; "PDF 1"…
  - **Recordings** (audio): a music note; "Recording 1"…
  - **Links**: a link badge (a video badge for a YouTube video: its
    picture would come from YouTube, and nothing loads from there before
    **Play**); the title (or the address's host), the address under it.

  **Playing from the list**: a video's or recording's row has a **play /
  pause** button (before the rename pencil); it plays the file right
  there ([`ListPlayer`](../tabcam_app/lib/screens/mini_player.dart),
  `video_player`), a video in its thumbnail's place, with a scrubbable
  progress bar and the time ("0:12 / 3:04") under its name. One plays at
  a time: playing another stops the first; opening a file (its own
  screen has its own player) and leaving the capture stop it too. At the
  end, play starts it over. One that can't play says so under its name
  ("This video can't be played here", or the recording's message).
  **Every row has a play button** (▶), in the same place, contributions
  included; the files that don't play in the list do what a tap on the
  row does. A **link**'s ("Play in a new tab") opens it outside the app
  (a new tab on the web; the browser, or the app the system hands it to
  such as YouTube, on Android and iOS). An **image**'s or a **PDF**'s
  ("Open to play along") opens its view on the
  [file screen](#file-screen), with the play-along sidebar beside it
  when the capture has something to play along with.

  Numbers count the files of that kind. A file the user named shows its
  name instead, whatever it is; files, PDFs, recordings and videos added
  are named after their file name (without the extension; photos aren't,
  pickers name them at random). **Rename file** (a pencil on each row, or
  a long press) asks for the name, prefilled; saving it empty goes back
  to the default name. The name is the page's `title`, synced with the
  event. **Download** (a download arrow, after the pencil) saves the
  file under its name in the list, with its extension (a scanned page,
  kept as `img`, downloads as `.jpg`): a download in the browser, the
  system's "save as" on Android and iOS (`file_picker` `saveFile`); a
  link has none. Downloading is offered read only too. On a phone
  narrower than 600 px, Rename, Download and Delete are in a **More**
  menu (⋮) on each row instead of buttons, so the name keeps its room.
  **Delete file** (a bin on each row, after Download) asks
  "Delete "<name>"?" (Cancel, Delete, and **Don't ask again**: ticked, a
  file's delete no longer asks on this device, see
  [delete confirmations](delete-confirms.md)) and deletes the file (stopping it
  if it plays in the list); the last file can't be deleted (the message
  says to delete the event instead), and a failure shows "Couldn't
  delete". Rename and Delete aren't there read only. The play-along
  sidebar's Delete (beside the Text view, in Cam, on the file screen)
  is the same, from the same code, Don't ask again and all (one ticked
  in either place holds in both)
  ([Cam](cam.md#deleting-from-the-sidebar)): beside the Text view it
  also stops the file if it plays in the list, and shows in the
  screen's progress bar. A tap opens the file alone on the file screen, except a link's:
  a tap opens the link itself, outside the app, as the file screen's
  **Open** does (a new tab on the web; the browser, or the app for it
  such as YouTube, on Android and iOS). A link's chevron (**Details**)
  opens it on the file screen, for Copy and Delete. **Each file's name is
  a link** (`Link`, `url_launcher`): the file's own link, the capture's
  ([sharing](sharing.md)) with `&f=<file id>`, or a link file's address.
  On the web it's a real one, for a new tab: Cmd, Ctrl or Shift-click, a
  middle click, or the browser's menu (Open link in new tab, Copy link
  address); a plain click opens it here, as the row does. Contributions'
  files are links too. With the images [hidden](hidden-images.md), the list
  is the **text tab** first (its first line, or "No text tab yet"; a tap
  goes to the Text view), then the other files.
- <a id="reordering"></a>**Reordering**: in the user's own events or
  those shared to edit, with more than one file listed, each row ends in a
  **drag handle** (in place of the arrow, or after a link's Details,
  tooltip "Reorder"); dragging a
  row by it moves the file in the list itself (no separate sheet). Only
  the handle starts a drag, so a tap still opens the file, and the rename
  pencil and long press still rename it, on the web, desktop and phones.
  Each drop saves the new order at once (the event changes, so it syncs,
  and moved photos or PDFs are
  [read again](tab-recognition.md#reading-by-itself) in their new order).
  With the images [hidden](hidden-images.md), only the other files are
  listed and dragged, the images keep their places, and the text tab
  stays first. Shared to read, with a single file, or while a tool works,
  there are no handles. A failed save shows "Couldn't reorder".
- **Tools** along the bottom:
  - **Files**, first: the list (highlighted while it shows).
  - **Text**, second: the tab read from the files, in place of the list
    (highlighted while it shows): the
    [text view](tab-recognition.md#text-view), or why there's no text
    yet. There's no Read tab: every capture is read by itself
    ([tab recognition](tab-recognition.md#reading-by-itself)). Its icon
    says how the tab stands: a **spinner** in its place while the
    capture is read, on the device or in the cloud (tooltip "Reading the
    tab…"), and only then: once the text tab is there (read on the
    device, or come from the cloud with sync) the spinner stops, and a
    read that waits too long fails; the usual icon once there's a text
    tab; **greyed out** without one (no tab found, not read, the text
    deleted or blank, reading failed or not possible here). Greyed out,
    it still opens the Text view, which says why and offers Read again
    or Sign in. A tap opens the Text view; tapped on the Text view, it
    does nothing more: reading the tab again is the Text view's
    **Rescan**. **Locked** (no Premium): a lock on the icon, tooltip
    "Text: TabCam Premium"; it opens the view as a preview (the
    capture's text, or a sample tab) under the Premium card, with no
    sidebar or Play along ([cloud OCR](cloud-ocr.md#in-the-app)).
  - **Add**: more files, [scanned or picked](scanning.md#adding-to-an-event):
    Scan pages, Document, Photos & videos, Files, or a **Link**. The list
    then shows, scrolled to what was added.
  - **Cam**, last: the camera with the tab under it, one neckline at a
    time, to record the user playing along; takes are added as videos
    ([Cam](cam.md)), and back from it the list shows, scrolled to them.
    On a capture shared to read, takes are the user's own contribution's.
    Off on a capture opened by its link. **Locked** (no Premium): a lock
    on the icon, tooltip "Cam: TabCam Premium"; it opens Cam as a
    preview, no camera, under the Premium card
    ([cloud OCR](cloud-ocr.md#in-the-app)).
  - **Dragging files** onto the screen adds them too, as Files does
    (outlined with "Drop files to add" while they're over it; folders and
    files that aren't pages are left out, with the message saying how
    many); on a capture shared to read, to the user's own contribution.
    Not on a capture opened by its link, nor while a tool works; not on iOS (see [Capture](navigation.md#capture)).

  The Original / Scan view and Rotate are the file screen's, not this
  one's; Delete is on both.
- While a tool works, a progress bar shows under the app bar and the tools
  are off. Failures show as a message at the top ([messages](messages.md)).

## File screen

One file, opened from the list, on its own screen (the back button goes
to the list). The app bar has the file's name ("Page 2", a link's title,
or the name the user gave it); tapping it renames the file, as does the
**Rename** tool beside Delete. **Dictionary** (a book icon, first of
the app bar's buttons, for every kind of file) shows and hides the chord
and scale [dictionary](dictionary.md) in a resizable sidebar on the
right (or, turned by its Rotate button, a panel under the file), and
**Metronome** (a stopwatch icon) after it the
[metronome](metronome.md)'s.
The file is shown whole, as what it is:

- **Images** are pinch-zoomable (up to 5×), as the view says. When the
  capture has recordings, videos or links, the play-along sidebar is
  beside the image, open, with **Play along** (♫) in the app bar, as
  beside a PDF.
- **PDFs** show the document itself (`pdfrx`, PDFium; WASM on the web,
  loaded when a PDF is first shown), its pages scrolling down, zoomable:
  by pinching, or with **Zoom in** (+) and **Zoom out** (−) at its bottom
  right, one over the other, each going to the viewer's next zoom step.
  Every PDF view has them: this screen's, and the PDF pane beside Cam
  and the Text view.
  A PDF that can't be read says so. When the capture has recordings,
  videos or links, the play-along sidebar is beside it, open, with **Play
  along** (♫) in the app bar, as in [Cam](cam.md#playing-along-with-a-file).
  Beside an image or a PDF the sidebar lists what plays along (Cam's
  takes last, under **Takes**) and, when
  the capture has a text tab, the **Text tab** first, to
  [follow beside the file](cam.md#following-the-text) in a pane on its
  left (then ♫ is there even with nothing to play, the sidebar opened
  by it); no PDFs or pages to follow.
- **Videos** show a play button; tapped, they play in place, looping
  (as their [edit](video-edit.md) says: the kept part, its own sound and
  its song mixed, each at its volume, and a take's tab drawn over it,
  [layers](video-edit.md#layers), also with no edit; the title and the
  watermark are the editor's Download's only), with a bar at the bottom: a **play / pause**
  button and a scrubbable progress bar. A tap on the video also pauses and resumes. A video that
  can't play says so. **Edit** (below) trims it and mixes a song with
  its sound ([video edit](video-edit.md)).
- **Recordings** (audio) of the capture's own open in the play-along
  sidebar, as usual: it opens with the recording loaded in its player
  frame, paused, marked in its list (not the first file to play, as
  elsewhere), with the frame's controls, section and speed, and its
  keys once a tap gives the sidebar the keyboard (**0** back to the
  start of the file or section, the **space bar** to pause and play)
  ([Cam](cam.md#playing-along-with-a-file)); ♫ hides the sidebar and
  pauses it. The screen itself shows a card with a music note,
  "Recording" and "It plays in the sidebar. Pick a page or PDF there to
  follow along." Under the files to play along (Cam's takes aside),
  the sidebar lists the capture's **images and PDFs** under **Follow a page or PDF** (and,
  first in the list, the **Text tab**, when there is one,
  [followed the same way](cam.md#following-the-text)): a tap
  shows one in a pane on the left, as Cam
  [follows a PDF](cam.md#following-a-pdf) (an image pinch-zoomable, a
  PDF scrolling, with the separator to drag; **Hide the page** / **Hide
  the PDF** closes it; tapped again, or another tapped, it goes or is
  replaced). Cam's takes come after them, last in the list, under
  **Takes**, and play along as the other files do. A recording that
  can't play says so in the frame. A
  contribution's recording (not listed in the sidebar) still shows as a
  card with a **play** button; tapped, it loads and plays, with **play /
  pause**, a scrubbable progress bar and the time ("0:12 / 3:04"), and at
  the end play starts it over. They play through `video_player`, as
  videos do.
- **Links** show as a card with a link icon, the title (or the address's
  host), the address (selectable), **Open** and **Copy** (to the
  clipboard). **Open** opens the link outside the app: on the web in a
  new tab; on Android and iOS in the browser, or the app the system
  hands it to (such as YouTube) (`url_launcher`,
  `LaunchMode.externalApplication`, window `_blank`). Only `http` and
  `https` links open. A link that can't open says so.
- **YouTube videos**: a link to one (`youtube.com/watch?v=…`,
  `youtu.be/…`, `/shorts/…`, `/live/…`, `/embed/…`, on any YouTube
  host) shows the same card with a video icon. Nothing plays in the app:
  **Open** opens it like any link, where YouTube starts it at the
  link's own start time (`t=`), if it has one.

Its tools, along the bottom:

- **The view** (images only): a tap flips **Original ↔ Scan**, its icon
  and label saying which shows. **Original**: the photo as taken;
  **Scan**: processed (the Tab [filter](page-filters.md)). It sets that
  image's filter, saved (its thumbnail and the exports follow); a new
  page shows Scan.
- **Rotate** (images only): turns the image a quarter turn clockwise
  (stored as a new page in its place; see [library](library.md#events));
  the screen stays on it.
- **Edit** (scissors, videos only), before Rename: the
  [video edit](video-edit.md) screen over this one (the video's own
  player let go meanwhile, so only the preview plays): trim, two
  sound lanes mixed (the video's own and a song, each with its volume
  and Mute), and what's drawn over it (a take's tab, a title, the
  watermark, which only [Premium](cloud-ocr.md#in-the-app) removes:
  the event screen hands its Premium status on), kept with the video as
  it's made; back here, the video plays as edited.
- **Rename** (pencil), just before Delete: asks for the file's name,
  prefilled, as on the list (saving it empty goes back to the default
  name).
- **Delete**: deletes the file and goes back to the list. The last file
  can't be deleted (the message says to delete the event instead). The
  play-along sidebar beside a recording has no Delete on the recording's
  own row (it has on the other files,
  [as in Cam](cam.md#deleting-from-the-sidebar)).

Edit, Rename and Delete are off while a tool works and on a capture
shared read only. The tools share the bar equally, so all four (an
image's) fit a narrow phone.

A reload or a restart with a file open reopens it, over its event's list
([navigation](navigation.md#coming-back-where-the-user-was)).
