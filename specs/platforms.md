# Platforms

| | Android | iOS | Web |
|---|---|---|---|
| Minimum | 7.0 (API 24) | 15.5 | A current browser |
| Scan | System document scanner (ML Kit): edges, straightening, several pages | System document scanner (VisionKit) | One photo, uncropped |
| Import photos | Through the scanner | Through the scanner | Photo picker, several |
| Read tab | ✅ ML Kit on the device | ✅ ML Kit on the device | ❌ (says it needs the app) |
| Library | Files in the app's documents | Files in the app's documents | Memory, until the tab closes |
| Share | System share sheet | System share sheet | Web Share, or downloads |

App IDs: `com.nu01.tabscan` (Android application ID and iOS bundle ID).
The app is named **TabScan** everywhere.

The web build is deployed to https://tabscan.nu01.com/app/
([deploy](deploy.md)).
