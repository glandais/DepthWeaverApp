# App Store screenshots

Three steps, all scripted:

```bash
./scripts/screenshots.sh                          # 1. capture  -> screenshots/flat/<device>/<locale>/
kou generate screenshots/koubou/iphone.yaml       # 2. framing  -> screenshots/koubou/out/iphone/<locale>/<frame>/
kou generate screenshots/koubou/ipad.yaml         #             -> screenshots/koubou/out/ipad/<locale>/<frame>/
./screenshots/assemble.sh                         # 3. assembly -> screenshots/IPHONE_65/ and IPAD_PRO_3GEN_129/
```

The Mac set is opt-in (it takes over the screen for a minute):

```bash
./scripts/screenshots.sh --mac                    # -> screenshots/flat/mac/<locale>/
kou generate screenshots/koubou/mac.yaml          # -> screenshots/koubou/out/mac/...
./screenshots/assemble.sh                         # -> screenshots/APP_DESKTOP/
```

The listing targets iPhone and iPad (`TARGETED_DEVICE_FAMILY: "1,2"`) plus the native Mac
app: one set per display type — `IPHONE_65` (1242×2688), `IPAD_PRO_3GEN_129` (2048×2732)
and `APP_DESKTOP` (2880×1800) — in `en-US` and `fr-FR`. Seven cards on iPhone and iPad,
three on the Mac.

## 1. Capture

`./scripts/screenshots.sh` produces the **raw captures**: seven screens × two languages ×
two devices, with no frame and no hand navigation, in `screenshots/flat/` (not versioned).

```bash
./scripts/screenshots.sh                  # iPhone and iPad, en-US and fr-FR
./scripts/screenshots.sh --iphone fr-FR   # one device, one language
./scripts/screenshots.sh --mac            # the Mac window, en-US and fr-FR
```

**One simulator at a time.** The iPhone is the repository's (`iPhone 17 Pro Max`, iOS 26.5,
`scripts/sim-config.sh`); the iPad, `iPad Pro 13-inch (M4)`, exists only for the captures
(`IPAD_DEVICE`, same file). Before booting a device the script shuts down every other
simulator; at the end — even on an error — it shuts the iPad down and boots the iPhone again
if it was up on arrival. The iPad is never brought back, even if it was up: that would make
two simulators.

**Nothing else may drive the simulator meanwhile**: `./scripts/xcb.sh run` would install the
Debug app over it, under the same bundle id, and the Debug app has no capture mode. The
script notices (two identical captures in a set) and fails.

### How it works

- The simulator plumbing — arguments, locales, one device at a time, system language and
  status bar, launching one screen and waiting for its marker — lives in
  `scripts/sim-capture.sh`, sourced by `screenshots.sh`.
- The app is built in the **`Screenshots`** configuration (`project.yml`), a Debug clone
  that defines the `SCREENSHOTS` condition, through the `DepthWeaver-Screenshots` scheme.
  Everything the capture mode needs — `DepthWeaver/Screenshots/ScreenshotMode.swift` and a
  few `#if SCREENSHOTS` hooks — is missing from the archived binary. To check:
  `xcodebuild -project DepthWeaver.xcodeproj -target DepthWeaver -configuration Release -showBuildSettings | grep SWIFT_ACTIVE_COMPILATION_CONDITIONS`
  must print nothing.
- Each capture is one launch:
  `simctl launch … -screenshotMode YES -screenshotScreen tune -AppleLanguages "(fr)" -AppleLocale fr_FR`.
  `-screenshotScreen` takes `hero`, `source`, `depth3d`, `model`, `pattern`, `adjust` or
  `tune`. No tap: nothing depends on a label that changes between languages.
- Every screen is deterministic: a bundled height map (a different one per card), a bundled
  or seeded pattern, fixed settings; the Tune card is on the Punchy preset. The first-launch
  trainer and the pinch hint are switched off through the argument domain (never saved).
- **LiDAR.** The simulator has none, so no card pretends to show a live scan. The source card
  lists the capture flows exactly as a LiDAR iPhone or iPad does, under the app's own
  "Pro · LiDAR" tag (`ScreenshotMode.showsCaptureHardware`, source screen only); the third
  card shows the Depth drawer's 3D point cloud of a bundled height map, and its subtitle
  names LiDAR as one source among others.
- The script does not wait a fixed delay: the app writes `tmp/screenshot-ready` in its
  container once the stereogram (or the point cloud, or the 3D model) is in place, plus
  1.2 s for SceneKit; the script then leaves 2 s more. On a loaded Mac the first launch after
  an install has taken minutes: the timeout is 600 s (`DEPTHWEAVER_READY_TIMEOUT`).
- The **status bar** is the system's, which `-AppleLanguages` does not reach: the script puts
  the simulator's system in each set's language (and restarts SpringBoard), then gives its
  own back. The time is forced to 9:41, the battery full. `simctl spawn` has been seen to
  hang for minutes on a loaded Mac, so each call is given up after 90 s
  (`DEPTHWEAVER_SPAWN_TIMEOUT`); only the iPad's status-bar date depends on it.
- The app forces dark mode: the simulator's appearance changes nothing.
- **Mac.** The script runs the macOS `Screenshots` build directly, waits for the line
  `screenshot-ready <screen> <window number>` on its stdout (the marker file sits in the
  sandbox container, which app data protection keeps other processes from reading), and
  captures the window with `screencapture -o -l`. `ScreenshotMode.stageWindow()` gives the
  window a fixed 1440×900 frame. This Mac's display is 1x, so the capture is 1440×900 pixels;
  the Koubou card (2880×1800) draws it 1.26× larger. On a Retina display the same window
  would capture at 2880×1800. The terminal running the script needs the Screen Recording
  permission.

**No alpha channel.** App Store Connect refuses any capture that carries one
(`IMAGE_ALPHA_NOT_ALLOWED`), and the rounded corners of an iPhone capture (or a Mac window)
are transparent. The script flattens them on black, before Koubou. `asc screenshots validate`
does **not** see it — it only checks dimensions: `assemble.sh` does.

## 2. Framing

Koubou turns each capture into a **card**: device frame, headline, subtitle, background.
The sources are versioned in `screenshots/koubou/`: `iphone.yaml`, `ipad.yaml`, `mac.yaml`,
`templates/` (five compositions) and `koubou-strings.xcstrings` (the headlines, in English
and French). The renders are not.

The iPhone 17 Pro Max simulator's screen is 1320×2868, and its Koubou frame (Deep Blue) is
used. The iPad uses the iPad Pro 13 M4 frame (Space Gray). The
Mac cards have no device frame: the template draws the window itself.

One set of templates serves the iPhone and iPad canvases: the iPad's, almost square, is
caught by `@media (min-aspect-ratio: 3/5)` and gets its own sizes. The direction comes from
the app: the navy ground, cyan and periwinkle (`DesignSystem/DWTheme.swift`), Space Grotesk
loaded from `DepthWeaver/Resources/Fonts/`, and a small depth profile — a shape rising out of
flat ground — as the rule under each headline.

| Card | Screen | Template | What it says |
|---|---|---|---|
| `01-hero` | `hero` | `hero` | the hook: a finished stereogram, full bleed |
| `02-source` | `source` | `rise` | depth from a photo, a 3D model, or LiDAR on Pro devices |
| `03-depth-3d` | `depth3d` | `offset` | every depth map as a 3D point cloud |
| `04-model` | `model` | `hero` | frame any 3D model (Toy Biplane) |
| `05-pattern` | `pattern` | `rise` | textures or generated patterns (Stars) |
| `06-adjust` | `adjust` | `offset` | depth ranges and denoising |
| `07-tune` | `tune` | `crop` | one-tap presets, then every slider |

`07-tune` has no frame (`frame: false`): in a device its slider labels would no longer read;
the template shows the bottom of the capture, where the drawer is (`align: left`). On the
iPad, `03-depth-3d` uses the same frameless `crop` template (`align: center`): the drawer
keeps its point cloud small and low on the large screen, and inside a whole device it would
be a speck. It is shown at the window's full width, not enlarged: any zoom centred on the
point cloud cuts the drawer's row labels at the edges. Every card on `crop` sets `align`. Mac: `01-hero`,
`02-pattern`, `03-tune`, all on the `desk` template.

Text fits itself: each text block declares the share of the height it owns
(`data-fit-budget`, and `-ipad` for the other canvas); a short script shrinks the headline,
then the subtitle, until it fits. French runs longer than English; English does not move.

`kou generate` has no language option: to iterate on one, copy a configuration to
`screenshots/koubou/x.local.yaml` (not versioned) and reduce `localization.languages`, or
use `kou live screenshots/koubou/iphone.yaml`.

### The texts

**The catalog's keys are the English sentence itself** — that is how Koubou finds a
variable's translation. Changing a headline means changing its key in the `.yaml` files
*and* in `koubou-strings.xcstrings`. French puts a space before `:` `;` `?` `!`: make it a
no-break space (U+00A0) in the catalog, or the punctuation can wrap alone.

## 3. Assembly

Koubou writes `out/<device>/<locale>/<frame name>/NN-*.png`; App Store Connect wants
`screenshots/<type>/<locale>/NN-*.png`. `./screenshots/assemble.sh` flattens that level,
removes from the destination what the new render does not replace, and refuses a set the
upload would reject: exact dimensions, no alpha channel, not empty, not much lighter than the
same card in the other language, not heavier than 10 MB (a conservative ceiling). It ends with `asc screenshots validate` per locale, a local
check that sends nothing. `--keep-stale` skips the removal, `--no-validate` the validation.

`screenshots/IPHONE_65/`, `IPAD_PRO_3GEN_129/` and `APP_DESKTOP/` are versioned, numbered
because files go up in alphabetical order. They are Git LFS objects (`screenshots/**/*.png`
in `.gitattributes`): every regeneration would otherwise add about 56 MB to the history.

## Upload

Not done by any script here. By hand, per locale and per display type (App Store Connect
does not inherit screenshots from the primary language):

```bash
asc localizations list --version "VERSION_ID"

asc screenshots upload --version-localization "LOCALIZATION_ID" \
  --path "./screenshots/IPHONE_65/en-US" --device-type "IPHONE_65"
asc screenshots upload --version-localization "LOCALIZATION_ID" \
  --path "./screenshots/IPAD_PRO_3GEN_129/en-US" --device-type "IPAD_PRO_3GEN_129"
```

The Mac version has its own localizations (`APP_DESKTOP`). The set already on the store
used other file names (`01_hero_stereogram.png`…): delete those screenshots in App Store
Connect before uploading the new ones, or both sets will show.
