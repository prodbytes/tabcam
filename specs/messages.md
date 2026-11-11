# Messages

The app's short messages ("Link copied", "Saved "Riff one" (1 link)"
with **Open**, "Couldn't take the picture", ...) show at the **top** of
the screen, from every screen (Home, the event screen, a file, Cam, the
Text view, a dialog's), on the web, Android and iOS
([lib/screens/messages.dart](../tabcam_app/lib/screens/messages.dart)).

- **Where**: a banner just under the app bar: its top is the status
  bar's height (the safe area's top) plus the app bar's (56 px) plus
  8 px, on every screen, with an app bar or not. It is 12 px in from the
  safe area's sides, centred, as wide as its text needs and 560 px at
  most. It floats over the page, above every screen and dialog: it moves
  and resizes nothing (the app bar, the bottom navigation bar, floating
  buttons and the page stay where they are) and covers neither the app
  bar (its back button and actions work while it shows) nor the bottom
  navigation bar. A tap on the banner itself
  dismisses it; taps elsewhere reach the page.
- **Look**: the theme's inverse surface, **42% transparent** (alpha
  0.58), what's behind showing through, slightly blurred so that the
  text stays readable; rounded (12 px), no shadow. The text (the inverse
  surface's text color) and the action (the inverse primary) are fully
  opaque, in the light and the dark theme.
- **In and out**: it slides down and fades in (250 ms), and slides up
  and fades out the same way.
- **How long**: each goes by itself, 4 seconds after it's in by default
  ("Saved … (Open)" after a capture: 6 seconds, Open included); at once
  on a tap on it, or swiped up. Its action (**Open**, **Upgrade**) runs
  and hides it. The one exception is the Text view's Premium offer
  (Fix's "… part of TabCam Premium." with **Upgrade**): it stays until
  it's tapped, swiped away, acted on or replaced, as it did as a
  SnackBar ([auto-correct](autocorrect.md)); messages after it wait.
- **One at a time**: a message waits for the one showing to go; where
  the new one replaces it (Home's, the Text view's, Share's "Link
  copied", Clone's "Cloned as"), the one showing goes at once (slides out)
  and the new one shows.
- **No leftovers**: a message shown before a page opens stays over the
  new page until its time is up; nothing is left once it has gone or the
  app closes.

How it works: `TopMessages`, around the app's navigator (MaterialApp's
`builder`), holds an overlay over every route; `showMessage` /
`replaceMessage` (or `Messenger.maybeOf(context)`, taken before an
`await`) put the message there, one overlay entry at a time; `persist:
true` keeps it until dismissed. A widget outside the app (in a test)
gets them on its root overlay instead.
Flutter's `SnackBar`s aren't used: they show at the bottom, over the
navigation bar, and push floating buttons up.
