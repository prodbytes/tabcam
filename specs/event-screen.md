# Event screen

One event, opened from the [library](library.md). If its text tab is
marked correct ([tab recognition](tab-recognition.md#text-tab-editor)),
the text tab editor opens over it, and Back shows the pages; otherwise it
opens on the pages.

- **App bar**: the title (and the artist under it, if set); tapping it, or
  **Rename** (pencil), renames the event (see
  [library](library.md#events)). **Text tab** (once read) opens the text tab editor
  ([tab recognition](tab-recognition.md)). **Clone** copies the event
  and opens the copy ([library](library.md#events)). **Share** opens the
  [share sheet](sharing.md). **Share with people** (the user's own
  events, signed in, in a build with sharing) shares it by email
  ([shared captures](shared-captures.md)).
- **Shared with the user**: a line under the app bar, "Shared by <email>
  · Can edit" or "· Read only". Read only, Rename, Add, Filter, Rotate,
  Read tab, Delete and editing the text tab are off.
- **Pages**: swiped left and right. Images are pinch-zoomable (up to 5×)
  and shown with their [filter](page-filters.md). Videos show a play
  button; tapped, they play in place, looping, with a scrubbable progress
  bar, and a tap pauses and resumes. A video that can't play says so.
  Links show as a card with a link icon, the title (or the address's
  host), the address (selectable), **Open** (in the browser, or the app
  that handles it, such as YouTube; a link that can't open says so) and
  **Copy** (to the clipboard). Under the pages, "2 / 5".
- **Tools** along the bottom, for the page shown:
  - **Add**: more pages, [scanned or picked](scanning.md#adding-to-an-event):
    Scan pages, Photos & videos, Files, or a **Link**.
  - **Filter**: toggles an image between Tab and Original; its icon and
    label say which it is. Off on videos and links.
  - **Rotate**: turns an image a quarter turn clockwise (stored as a new
    page in its place; see [library](library.md#events)). Off on videos
    and links.
  - **Read tab**: reads every image page of the event
    ([tab recognition](tab-recognition.md)); videos and links are
    skipped, and an event without images says there's nothing to read.
  - **Delete**: deletes the page; the last page can't be deleted (the
    message says to delete the event instead).
- While a tool works, a progress bar shows under the app bar and the tools
  are off. Failures show as a message at the bottom.
