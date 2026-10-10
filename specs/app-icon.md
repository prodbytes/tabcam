# App icon

A scanned tab: a cream page (`#FBF7EF`) with a title stub and a six-line
tab staff, three amber fret numbers (3, 5, 7, rising across the strings)
breaking the lines the way typeset tab does, framed by four amber
(`#E0A030`) scanner corner brackets, on a dark warm background
(`#1E1A15`).

- **Masters**: `tabscan_app/assets/icon/icon.svg` (the full icon) and
  `icon_foreground.svg` (Android's adaptive foreground: transparent, shrunk
  to 60% so it stays inside the safe zone), rendered to 1024 px PNGs.
- **Platform icons** are generated from the PNGs by
  `dart run flutter_launcher_icons` (settings in `pubspec.yaml`): Android
  `launcher_icon` (adaptive on Android 8+, over `#1E1A15`), iOS `AppIcon`
  (no alpha), and the web favicon, PWA and maskable icons (theme color
  `#E0A030`).
- The generator also rewrites an unrelated Xcode setting
  (`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` to
  `AppIcon`); revert that change in `project.pbxproj` after running it.
