# Google Play images

Laid out as `fastlane supply` reads them, rendered by
`bash scripts/store-screenshots.sh` from the real app with made-up
captures ([app stores](../../../../specs/app-stores.md#store-graphics)).
They show **made-up riffs only**, never tabs of published songs, and no
real people's email addresses (only `example.com` ones).

| File | Size | Shows |
|---|---|---|
| `icon.png` | 512 x 512 px, 32-bit PNG with alpha | The [app icon](../../../../specs/app-icon.md) |
| `featureGraphic.png` | 1024 x 500 px, 24-bit PNG (no alpha) | The icon, the name, what it does, a page of tab |
| `phoneScreenshots/1.png` … `6.png` | 1080 x 1920 px, 24-bit PNG | The Text view, a page with the Tab filter, Home, Capture, Cam, Share with people |

Tablet screenshots (`sevenInchScreenshots/`, `tenInchScreenshots/`) are
optional and not made.
