# tabscan_app

The TabScan Flutter app (Android, iOS and web). Build and run it from the
repo root with `make` and the `scripts/` (see the [README](../README.md));
what it does is specified in [specs/](../specs/README.md).

| Folder | Holds |
|---|---|
| [lib/capture/](lib/capture) | Getting pages: the system document scanner, or photos |
| [lib/library/](lib/library) | Scans and where they're kept |
| [lib/processing/](lib/processing) | Page filters (the black-and-white Tab look) and rotation |
| [lib/recognition/](lib/recognition) | Reading tabs: ML Kit OCR, staff-line detection, text layout |
| [lib/export/](lib/export) | PDF, text and image sharing |
| [lib/screens/](lib/screens) | The library, a scan, and the text tab editor |

`flutter analyze` and `flutter test` run here.
