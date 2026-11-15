# App icon and logo

**The icon** is a camera lens reading a line of tab: a thick gold
(`#E0A030`, the brand's gold) ring round a cream disc (`#FBF7EF`) that
shows a six-line tab staff (dark lines) with three gold fret numbers, 3,
5 and 7, rising across the strings and breaking the lines as typeset tab
does, and a red rec dot (`#E5533B`, ringed in the background colour) on
the ring at its top right, for the takes Cam records; on a dark warm
background (`#1E1A15`). At favicon size it reads as a gold ring round a
light lens with the red dot.

**The logo** is the lens (on a dark disc, so it reads on any background)
followed by the wordmark **tabs.cam**: "tabs" in cream and ".cam" in
gold, Roboto Medium (the app's font) turned into paths. It's made for
dark backgrounds (the brand's `#1E1A15`); Play's feature graphic uses it.

- **Masters**: `tabcam_app/assets/icon/icon.svg` (the full icon, opaque),
  `icon_foreground.svg` (Android's adaptive foreground: the lens alone,
  transparent, at 75% so the ring and the dot stay inside the safe zone)
  and `logo.svg`, written by
  [`scripts/app_icon.py`](../scripts/app_icon.py) (the digits are drawn
  strokes, the wordmark Roboto's glyphs as paths, so none needs a font),
  rendered to `icon.png` and `icon_foreground.png` (1024 px) and
  `logo.png` (480 px high) by headless Chrome.
- **Platform icons** are generated from the PNGs by
  `flutter_launcher_icons` (settings in `pubspec.yaml`): Android
  `launcher_icon` (adaptive on Android 8+, over `#1E1A15`), iOS `AppIcon`
  (no alpha), and the web favicon, PWA and maskable icons (theme color
  `#E0A030`).
- **Store graphics**: Play's 512 px icon and its feature graphic (the
  logo, what the app does and a page of a made-up riff) are drawn by
  the store graphics test ([app stores](app-stores.md#store-graphics)).
- **One command** makes all of it: `bash scripts/app-icon.sh` (in
  devbox, on a Mac with Google Chrome): the SVGs (fontTools in a
  throwaway venv), the PNGs, the platform icons, Play's icon and feature
  graphic, and the store check. The generator also rewrites an unrelated
  Xcode setting (`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`
  to `AppIcon`); the script puts it back.
