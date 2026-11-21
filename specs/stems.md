# Instruments (stem separation)

In the [video editor](video-edit.md), **each sound lane can be split into
its instruments** (stems): the Take row's (the video's own sound, "Video
sound" for a video Cam didn't record) and the Song row's ("Track"), each
on its own. Split, a lane has four instruments, each with a level and a
Mute of its own: **Vocals**, **Drums**, **Bass** and **Other** (the rest:
guitars, keys). Turning one down or muting it takes it out of the lane's
sound: a song without its vocals to sing over, without its guitar part to
play it, a take with the bass turned down.

**The split is rough for now**, done on the device by filters, not a
model that knows the instruments ([how it's split](#how-its-split)). It's
the place a better separation goes later (a model on the device, or in
the cloud for [Premium](cloud-ocr.md)): the edit keeps only each
instrument's level, whatever splits the sound, so edits made now keep
their meaning then.

## In the editor

In a lane's **volume** popup (its speaker, at the left of its row: [each
row's volume](video-edit.md#a-lanes-channels-and-balance)), under the
lane's slider, Channels and Balance:

- **Split into instruments**, a switch (key `video-edit-<lane>-stems`,
  `<lane>` being `take` or `song`), off by default; its label's tooltip
  says how it splits ("A rough split for now: the bass under 200 Hz, the
  drums over 4 kHz, the voice in the middle of the mix, the rest at its
  sides."). On, the lane is split with **every instrument at 100%**,
  which sounds as the lane does unsplit; off again, the lane is whole and
  its instruments' levels are forgotten.
- Split, **a row per instrument** under it, in the order Vocals, Drums,
  Bass, Other: its **Mute** (a speaker, "Mute (Vocals)" / "Unmute
  (Vocals)", key `video-edit-<lane>-<instrument>-mute`), its name, a
  **slider from 0% to 100%** in steps of 5% (key `…-slider`; sliding
  unmutes it) and its level (`50%`, key `…-level`; in the primary colour
  when it isn't 100%, struck through while muted). As a lane's: **muting
  keeps the level**, Unmute puts it back (at 100% if it was at 0%).
  Each row fits the popup's width (about 300 points), the name cut with
  an ellipsis at large text sizes.
- Once an instrument isn't at 100% (or is muted), a note under them:
  "Download has the instruments' levels; the preview plays the sound as
  recorded." (key `video-edit-<lane>-stems-note`): as with
  [channels and balance](video-edit.md#a-lanes-channels-and-balance),
  the players (video_player, the browser's media element) play the file
  as it is, so **the preview and the file screen's player play the lane
  unsplit**; Download's file has the instruments' levels, and so does
  [the kept download](video-edit.md#the-kept-download) once it's made,
  which the file screen and the file list then play.
- A split lane's speaker (the row's volume button) is in the primary
  colour, as a lane's changed level is.

Every change is kept with the edit at once, as a level is
([stored](#stored)), reopened as left; **Reset** puts both lanes back
whole. A song taken out of the lane (Remove), or another one picked in
its place (Change), starts whole.

## How it's split

[`StemSplit`](../tabcam_app/lib/capture/stem_split.dart): each channel
goes through a **three-band crossover**, Linkwitz-Riley (two Butterworth
biquads in a row, 24 dB an octave; the Audio EQ Cookbook's, Q 1/√2):

- **Bass**: under **200 Hz** (two low-passes), then an all-pass at
  4 kHz, so it turns as the rest does there;
- above 200 Hz (two high-passes), split again at **4 kHz**: under it,
  **the middle band** (two low-passes); over it, **Drums** (two
  high-passes);
- the middle band, by where it sits in the mix: **Vocals** its middle,
  what both channels have alike (`(L + R) / 2`, on both sides), **Other**
  its sides (`(L − R) / 2` on the left, its opposite on the right).

The four add back up to the sound as it was through two all-pass filters
(its phase turned at the crossovers, its level not), so a split lane at
100% throughout sounds as it did; it isn't processed at all then. A
one-channel sound has no sides: its middle band is all Vocals, and Other
is silent. The simpler split, the middle band as the sound minus its
lows and highs, was ruled out before it was built: the low band's phase
shift would leave most of a 60 Hz tone in the lane with Bass muted (about
−1.5 dB, worked out; this crossover takes it down about 40 dB).

Checked in `test/lane_stems_test.dart`: every instrument at 100% is as
loud as the sound at 50 Hz, 200 Hz, 1, 4 and 12 kHz (within 2%); Bass
muted leaves a 60 Hz tone under 2% (−34 dB or less) and a 1 kHz tone
whole; Drums muted, a 12 kHz tone under 3%; Vocals muted, a 1 kHz tone
in the middle under 2% and one at the sides whole; Other the other way
round; Vocals at 50%, half as loud; a one-channel 1 kHz tone all Vocals.

## Stored

The page's `edit` ([how the edit is stored](video-edit.md#how-the-edit-is-stored)):
`ownStems` (the Take row's) and `songStems` (the Song row's), written
only while the lane is split: a map of each instrument not at 100%, by
its name, with what isn't the default, e.g. `"songStems": {"vocals":
{"muted": true}, "bass": {"volume": 0.5}}`; `{}` is split, every
instrument at 100%. Volumes are read within 0–1, to the hundredth (not a
number: 1); an entry that isn't a map is left out. An instrument this
version doesn't know (a newer app's, e.g. `guitar`) is kept and written
back, and left out of the mix. Older apps keep both keys (as a newer
app's), and play and download the lanes whole.

## Download

The [render plan](video-edit.md#the-render-plan)'s lanes carry their
instruments (`OwnLane.stems`, `SongLane.stems`), and each renderer gets
them (the channel's `stems` in `own` and `song`: `{vocals, drums, bass,
other}`, each instrument's gain, 0 when muted, and the crossover's
`bassHz` and `drumsHz`, so the frequencies are set in one place) only
when they change the lane's sound; a lane split at 100% throughout, or
not split, has none and is rendered as before. They come after the
lane's channels and balance and before its volume. A video whose own
sound's instruments change is made again, never saved as it is
(`RenderPlan.passthrough`).

- **Web** ([`web_video_editor.dart`](../tabcam_app/lib/capture/web_video_editor.dart),
  `_stems`): in the offline mix (and the own sound streamed from a long
  video), the lane goes into a node that makes it two channels, then
  through Web Audio `IIRFilterNode`s with the coefficients `StemSplit`
  works out for the context's rate: Bass and Drums each through a gain
  at theirs, the middle band through a 2×2 matrix (its middle at the
  Vocals' gain, its sides at Other's: `[(v + o) / 2, (v − o) / 2, …]`).
  An instrument at 0 isn't made. The mix is in stereo then. Checked in
  Chrome (`test/web_lane_stems_test.dart`): each instrument muted takes
  its tone away, the rest kept, and a one-channel sound's middle band
  is Vocals.
- **Android** ([`Stems.kt`](../tabcam_app/android/app/src/main/kotlin/com/nu01/tabcam/Stems.kt)):
  a `StemsProcessor` (a Media3 `BaseAudioProcessor`, on 16-bit or float
  PCM) among the lane's effects, after its `ChannelMixingAudioProcessor`
  and before its gain; each channel's bands (`StemBands`, biquads in
  doubles) start afresh at every flush; samples are held within range.
  Compiled; to be checked by hand on a phone.
- **iOS** ([`AppDelegate.swift`](../tabcam_app/ios/Runner/AppDelegate.swift)):
  the lane's processing tap (`laneTap`, which also applies its channels
  and balance) runs `applyStems` on its float samples, interleaved or
  not, each channel's bands made in the tap's prepare at the track's
  rate. Run on a Mac against the same tones as the Dart tests (the same
  results), and in `RunnerTests` (`testReadsAndAppliesTheLanesInstruments`).
