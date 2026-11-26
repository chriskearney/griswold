# Griswold

Snow, lights and the occasional sleigh, for your Mac. Free.

**Download:** <https://chonkbase.net/griswold/>

Griswold is a menu bar app that decorates your desktop:

- **Snow that settles.** Flakes fall in three depth layers, pile up along the top of your windows and on the ground, slide off when you drag a window, and drop when you close one. Distant snow falls behind your windows; near snow falls in front. Wave the pointer through it and it swirls.
- **Lights around every display.** Five bulb styles, eleven color sets, ten patterns, with speed, brightness, glow, size and spacing controls. Pick which edges, and whether the string hangs under the menu bar.
- **Surprises.** Santa's sleigh crossing every display, shooting stars, gusts that blow spindrift off the snow, presents that land on your windows, northern lights, a snowman, a snowball on the glass, fireworks at New Year, and the Griswold Moment.
- **Easy on the machine.** Drawn with Metal in one pass per display. 60 fps on power, 30 on battery or in Low Power Mode, slower when only steady lights are showing, and nothing at all when the display sleeps, the screen locks, or a full-screen app is in front.
- **No permissions.** It reads where windows are, never what is in them. No Screen Recording, no Accessibility, no account, no tracking. The only network request is an optional daily check of `version.json` on the website.

Requires macOS 13 or later. Universal (Apple silicon and Intel).

## Building

```sh
swift build                      # debug build
swift test                       # unit tests
swift run Griswold               # run from the terminal

scripts/build-app.sh 1.0.0 1 build            # universal Griswold.app in build/
MAC_SIGNING_IDENTITY=- scripts/sign-and-package.sh build/Griswold.app 1.0.0 build/out   # ad hoc DMG
```

There is no Xcode project. The package is plain SwiftPM, shaders are compiled from source at launch, and all art (sleigh, reindeer, presents, snowman, the app icon) is drawn in code, so the app bundle is one executable and an icon.

### Rendering pictures

The same simulation that runs on screen can render to a file. The images on the website come from this.

```sh
swift run -c release Griswold --snapshot out.png --seconds 120 --scale 2
swift run -c release Griswold --snapshot santa.png --surprise santa --lead 4
swift run -c release Griswold --snapshot icicles.png --preset wonderland
scripts/make-icon.sh             # regenerate Resources/AppIcon.icns
```

Options: `--width`, `--height`, `--scale`, `--seconds`, `--preset`, `--style`, `--palette`, `--pattern`, `--accumulation`, `--intensity`, `--surprise`, `--lead`, `--crop x,y,w,h`, `--no-snow`, `--no-lights`, `--no-windows`, `--light-windows`, `--transparent`.

## Layout

| Path | What it is |
| --- | --- |
| `Sources/Griswold` | The executable: starts the app, or the snapshot tool |
| `Sources/GriswoldKit/Snow` | Flakes, clumps, and the height-field piles |
| `Sources/GriswoldKit/Windows` | Window tracking and finding the visible top edges |
| `Sources/GriswoldKit/Lights` | String layout, palettes, patterns |
| `Sources/GriswoldKit/Surprises` | The director (scheduling, Santa, gusts, aurora) and sparks |
| `Sources/GriswoldKit/Overlay` | One transparent window and scene per display; pacing |
| `Sources/GriswoldKit/Render` | Metal renderer, shaders, drawn art, snapshots |
| `Sources/GriswoldKit/UI` | Menu bar popover and settings window (SwiftUI) |
| `site/` | The landing page served at chonkbase.net/griswold |
| `deploy/` | Container and Kubernetes manifests for the site |

## Releasing

Pushing a tag such as `v1.0.0` runs `.github/workflows/release.yml`: it builds the universal app, signs it with the Developer ID certificate, has Apple notarize and staple the disk image, and publishes a GitHub release. It needs these repository secrets: `MAC_CERTIFICATE_P12_BASE64`, `MAC_CERTIFICATE_PASSWORD`, `MAC_SIGNING_IDENTITY`, `APP_STORE_CONNECT_API_KEY_BASE64`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`.

Then publish the site with the new disk image:

```sh
deploy/deploy-site.sh 1.0.0
```
