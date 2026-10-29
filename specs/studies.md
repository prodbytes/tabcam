# Studies

A **study** groups related captures ("Jazz chords", "Recital pieces"). It's
rarely used, so it stays out of the way: nothing shows for it until the
user sets one.

## The study of a capture

- A capture (`CaptureEvent.study`) is in one study or none (empty). It's
  a name the user types, trimmed; captures with the same name are in the
  same study. There's no list of studies kept apart: the studies are the
  names the user's own captures have (`Library.studies`, sorted, case
  and accents aside), so a study with no captures left is gone.
- It's saved in the capture's `event.json` as `study` (left out when
  empty) and syncs with it, like the artist ([cloud sync](cloud-sync.md)).
  A [clone](library.md#events) keeps it.
- It's the owner's. On a capture shared with the user, the study is
  neither shown nor asked for, and it doesn't count among the user's
  studies.

## Setting it

From the open capture ([event screen](event-screen.md)): tapping the
title, or **Rename** (the pencil), opens the rename dialog, which on the
user's own captures has, under **Name**, an optional **Study** field (a
folder icon; "Optional: groups related captures"). As the user types it
suggests their studies that contain what's typed (case and accents
aside); picking one fills it in. Save sets it; emptied, the capture is in
no study. The same dialog opens from a card's Rename on Home.

Once set, the open capture shows it under its title (and artist), muted,
with a folder icon.

## On Home

Once any of the user's captures is in a study, a row of chips, one per
study (a folder icon), shows under [Home](library.md)'s search field,
scrolling sideways when they don't fit. Choosing one shows only the
user's captures in that study (with the search, if any, on top); choosing
it again shows all of them. A new capture clears the choice, as it clears
the search, so it shows. Search also finds a capture by its study.
