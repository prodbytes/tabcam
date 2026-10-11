# Event screen

One event, opened from the [library](library.md). If its text tab is
marked correct ([tab recognition](tab-recognition.md#text-view)), it
opens on the Text view (the Text tool goes back to the pages); otherwise
it opens on the pages.

- **App bar**: the title (and the artist under it, if set); tapping it, or
  **Rename** (pencil), renames the event (see
  [library](library.md#events)). **Clone** copies the event
  and opens the copy ([library](library.md#events)). **Share** opens the
  [share sheet](sharing.md). **Share with people** (the user's own
  events, signed in, in a build with sharing) shares it by email
  ([shared captures](shared-captures.md)). There's no Hide images button
  any more: switching between the pages and the text is the Text tool's
  job, at the bottom (captures already [hidden](hidden-images.md) stay
  hidden).
- **Shared with the user**: a line under the app bar, "Shared by <email>
  · Can edit" or "· Read only". Read only, Rename, Add, Rotate, Delete
  and editing the text tab are off; the view still changes what shows,
  without saving it.
- **Pages**: swiped left and right. Images are pinch-zoomable (up to 5×)
  and shown as the view says (Original or Scan, below). Videos show a play
  button; tapped, they play in place, looping, with a scrubbable progress
  bar, and a tap pauses and resumes. A video that can't play says so.
  Links show as a card with a link icon, the title (or the address's
  host), the address (selectable), **Open** (in the browser, or the app
  that handles it, such as YouTube; a link that can't open says so) and
  **Copy** (to the clipboard). Under the pages, "2 / 5". With the
  images [hidden](hidden-images.md), the pages are the text tab (its
  **Open** goes to the Text view), then the videos and links.
- **Tools** along the bottom:
  - **The view**, first: a tap flips **Original ↔ Scan**, its icon and
    label saying which shows. **Original**: the photos as taken;
    **Scan**: processed (the Tab [filter](page-filters.md)). Either sets
    the filter of every image page, saved (thumbnails and exports
    follow); a new event shows Scan. Off in the Text view.
  - **Text**, second: shows the tab read from the pages in place of them
    (no page count): the [text view](tab-recognition.md#text-view), or
    why there's no text yet. It then reads **Pages**, and a tap goes back
    to the pages, as the view showed them.
    There's no Read tab: every capture is read by itself
    ([tab recognition](tab-recognition.md#reading-by-itself)).
  - **Add**: more pages, [scanned or picked](scanning.md#adding-to-an-event):
    Scan pages, Photos & videos, Files, or a **Link**.
  - **Rotate**: turns an image a quarter turn clockwise (stored as a new
    page in its place; see [library](library.md#events)). Off on videos,
    links, and in the Text view.
  - **Delete**: deletes the page; the last page can't be deleted (the
    message says to delete the event instead). Off in the Text view.
- While a tool works, a progress bar shows under the app bar and the tools
  are off. Failures show as a message at the bottom.
