# DepthWeaver

## Project overview

Cross-platform Apple app (SwiftUI, iOS 18+ / macOS 15+ on Apple silicon) that generates autostereograms (Magic Eye images) from depth maps. Localized in English and French.

## Architecture

MVVM with shared state in `AppState` (`ContentView.swift`). The current `DepthMap`, last result image and other shared flags are `@Published` so views stay in sync after edits. `ContentView` branches by platform: iOS uses a `NavigationStack` of pushed destinations; macOS uses a single document-style window with an inspector pane.

```
ContentView (AppState)
  ├── iOS: IOSContentView (NavigationStack)
  │     └── GenerationView                  ← main screen: depth source + pattern + settings + live preview
  │           ├── DepthAdjustmentView       ← input/output range remap + denoising
  │           ├── LiDARCaptureView          ← live LiDAR depth capture
  │           ├── Model3DCaptureView        ← USDZ/USD/OBJ/SCN loader + orbit camera + depth capture
  │           ├── GuidedCaptureRootView     ← Object Capture scan of a real object → .usdz (Pro devices)
  │           └── StereogramResultView      ← full-screen result + share
  │
  └── macOS: MacGenerationView (HSplitView)
        ├── canvas (live stereogram preview)
        └── InspectorPanel                  ← collapsible source / pattern / depth / settings sections
              └── SceneCaptureSheet         ← .usdz/.usd/.obj/.scn loader + orbit + depth capture (modal)
```

iOS-only: `NavigationDestination` enumerates the five pushable destinations. `GuidedCapture` is a port of Apple's WWDC `ScanningObjectsUsingObjectCapture` sample (under `Features/GuidedCapture/`), gated on `ObjectCaptureSession.isSupported && PhotogrammetrySession.isSupported`. Its `onCompleted(URL)` callback hands the finished scan to `AppState.pendingCapture`, which presents `NameCaptureSheet` and stores the model via `CapturedModelLibrary` for later use as a `.model3D` depth source.

macOS-only: `DepthWeaverApp` adds standard menu commands (Open ⌘O, Save ⌘S, Copy ⌘⇧C, Toggle Inspector ⌘⌥I, plus a Help menu of outbound links) wired through `NotificationCenter` to `MacGenerationView`. LiDAR / live AR captures and the `GuidedCapture` Object-Capture flow are iOS-only and gated with `#if os(iOS)`; on macOS the user opens 3D models from disk via `SceneCaptureSheet`. Save uses a `FileDocument` (`StereogramPNGDocument`) through `.fileExporter`.

## Key components

### Models
- **DepthMap** (`Models/DepthMap.swift`): wraps `[Float]` depth values with source dims, original (display) dims, an `adjustment` (input/output remap) and a `denoising` config. Exposes `workingDepth` and `adjustedDepthValues(width:height:)` consumed by the generator. `Source` is `lidar | depthAnything | imported | model3D` (Object Capture scans reuse `.model3D` since they're consumed via the same renderer). Denoising only runs on `.imported` depths (8-bit imports are the noisy ones).
- **DepthAdjustment** / **DepthDenoising** (`Models/`): value types stored on `DepthMap`. Editing them re-triggers stereogram generation via `onChange` in `GenerationView`.
- **DepthMapPreset** (`Models/DepthMapPreset.swift`): bundled height maps in `Resources/HeightMaps/`.
- **Model3DPreset** (`Models/Model3DPreset.swift`): bundled `.usdz` files in `Resources/Models3D/`.
- **PatternSource** (`Models/PatternSource.swift`): `.asset(StereogramPattern) | .procedural(ProceduralPatternType, ProceduralConfig) | .imported(UIImage)`.
- **ProceduralPatternType** (`Models/ProceduralPatternType.swift`): `randomDot | stars | perlinNoise | worleyNoise | voronoi | reactionDiffusion`, each with its own `*Config` struct and SF Symbol icon.
- **StereogramSettings** (`Models/StereogramSettings.swift`): `dpi`, `depthStrength`, `sepFactor`, `oversampling`, `invert`, `patternSource`.

### Services
- **DepthAnythingService** (`Services/DepthAnythingService.swift`): CoreML inference with `DepthAnythingV2SmallF16.mlpackage`. Input: 518×392, output: Float16. Buffers are copied to avoid CoreML reuse.
- **LiDARDepthService** (`Services/LiDARDepthService.swift`, iOS-only): owns an `ARSession` directly (not via ARSCNView), publishes the camera feed as `UIImage`, rotates the depth buffer for portrait.
- **Model3DLoader** / **Model3DDepthRenderer** (`Services/`): SceneKit-based loader + Metal depth-buffer extractor. `captureDepthMap(from:outputSize:)` writes view-space distances; cleared pixels become `Float.nan` so the auto-range computation in `DepthMap.initialAdjustment` ignores them.
- **DepthMapDenoiser** (`Services/DepthMapDenoiser.swift`): Core Image pipeline (normalize → median → background mask → bilateral → blend) in a half-float working space. Lifts 8-bit imports out of their quantization grid.
- **StereogramGenerator** (`Services/StereogramGenerator.swift`): W.A. Steer's extension of the Thimbleby–Inglis–Witten algorithm — link-based hidden-surface removal, bitmapped patterns, oversampling, centre-outwards application. Upscales output so min dimension ≥ 960. The default path runs the entire algorithm on the GPU via `MetalStereogramRenderer`; if the Metal library / pipeline can't be created, falls back to a CPU path parallelized per row via `DispatchQueue.concurrentPerform` with OKLab-based oversampling and gap-fill.
- **MetalStereogramRenderer** + **StereogramKernels.metal** (`Services/`): GPU implementation of the algorithm. One thread per output row dispatches the linking pass, both centre-outwards pattern fills, OKLab gap fill, and OKLab oversampling downscale; per-row scratch arrays are slices of large `storageModePrivate` buffers so threads never synchronize. `MetalStereogramRenderer.shared` is a lazy singleton — `nil` if Metal is unavailable, which transparently selects the CPU path.
- **Generators/** (`Services/Generators/`): one `PatternGenerator` per `ProceduralPatternType` (`RandomDotGenerator`, `StarsGenerator`, `PerlinNoiseGenerator`, `WorleyNoiseGenerator`, `VoronoiGenerator`, `ReactionDiffusionGenerator`).

### ViewModels
- **PhotoDepthViewModel**, **LiDARCaptureViewModel** (iOS-only), **Model3DCaptureViewModel** drive the capture flows. The Object Capture flow (iOS) is driven by `GuidedCaptureModel` (an `ObservableObject` ported from Apple's `AppDataModel`) inside `Features/GuidedCapture/`, with `CapturedModelLibrary` persisting finished scans to `Documents/CapturedModels/<uuid>.usdz`.
- **StereogramViewModel** debounces calls to `StereogramGenerator` (`generateDebounced`) to keep the live preview responsive.
- **PatternPreviewViewModel** generates a thumbnail for the selected procedural pattern.

### Views
- **iOS** — `Views/GenerationView.swift` is the hub: depth-source section (with `DepthPointCloudView` 3D preview), pattern picker (assets + photo import + procedural with `ProceduralParamsView`), settings sliders, and live stereogram preview. The help sheet (`HowToUseSheet`) is defined in the same file.
- **About / outbound links** — every external URL (website, support, privacy, GitHub source, App Store review, developer page) lives in `Models/AppLinks.swift`. iOS shows them in `Views/About/AboutView.swift` (sheet behind the ⓘ button on `CanvasScreen`); macOS puts them in the Help menu (`DepthWeaverApp`). They open via `Link` — the app itself still makes no network request. Never add a donation/tip link in the app (App Review 3.1.1); Ko-fi stays on the website and README.
- **Tips** — `Views/Tips/`: three consumable in-app purchases that unlock nothing. `TipJar` is copied from the reference shared by the developer's apps (the `donations` repo, outside this one) and started at launch in `DepthWeaverApp` (finishes Ask to Buy / interrupted transactions). iOS pushes `TipJarView` from the About sheet ("Support DepthWeaver"); macOS opens it in its own `Window` from Help → "Support DepthWeaver…". Names and prices come from the store (`displayName`, `displayPrice`), never the catalog. App Store Connect products: `io.github.glandais.depthweaver.tip.small` (€0.99, `6814831087`), `.medium` (€2.99, `6814830911`), `.large` (€4.99, `6814831029`), base territory France, 175 territories, en/fr names. The first in-app purchase ships **with an app version** (iOS 1.2.1). `Tips.storekit` (repo root) is the scheme's `storeKitConfiguration` and only applies when run from Xcode; installed through `simctl`, the app queries the real store and shows "unavailable" until the products are approved.
- **macOS** — `Views/Mac/` contains `MacGenerationView` (HSplitView with canvas + inspector), `InspectorPanel` (collapsible source/pattern/depth/settings sections persisted via `@AppStorage`), `SceneCaptureSheet` (modal for loading 3D models and capturing depth from an orbit camera), and `StereogramPNGDocument` (`FileDocument` for `.fileExporter`-based PNG save).

### Screenshot mode
`Screenshots/ScreenshotMode.swift` plus a few `#if SCREENSHOTS` hooks (in `ContentView`, `DepthWeaverApp`, `CanvasScreen`, `DepthSourceScreen`, `DepthAdjustmentView`, `Model3DCaptureView`, `MacGenerationView`) put the app on one App Store screen at launch, with no tap. It compiles only in the `Screenshots` build configuration (see Publishing → Screenshots); Release does not define `SCREENSHOTS`, so none of it reaches the archive.

### Cross-platform plumbing
- `Extensions/PlatformImage.swift` typealiases `PlatformImage = UIImage` on iOS and `PlatformImage = NSImage` on macOS, with parity helpers (`pngData()`, `jpegData(compressionQuality:)`, `cgImage`, `loadFromAssets`, `loadFromBundle`, `pixelSize`) and `Image.init(platformImage:)`. All code that used `UIImage` directly was migrated to `PlatformImage` so models, services, generators and tests are platform-agnostic.

### Tests
`DepthWeaverTests/DepthWeaverTests.swift` uses Swift Testing (`@Suite` / `@Test`). The current suite renders the bundled `dog` height map with default settings and asserts on output dimensions, render time, and pixel-statistics (mean / std-dev) to catch regressions that produce a uniform or empty image, and checks that the Metal and CPU paths agree. Run with `./scripts/xcb.sh test` (pinned simulator) and `./scripts/xcb.sh test-mac` (this Mac).

## Resources

- `Resources/Patterns/` — built-in textures (PNG)
- `Resources/HeightMaps/` — depth-map presets (PNG, grayscale)
- `Resources/Models3D/` — bundled `.usdz` samples
- `Resources/DepthAnythingV2SmallF16.mlpackage` — CoreML model (~48 MB)
- `Resources/Localizable.xcstrings` — String Catalog (en, fr)
- `Resources/InfoPlist.xcstrings` — localized `INFOPLIST_KEY_*` strings (display name, camera and add-only Photos prompts)
- `Resources/PrivacyInfo.xcprivacy` — privacy manifest (see Publishing → Privacy)

## Build

```bash
./scripts/xcb.sh gen              # (re)generate DepthWeaver.xcodeproj from project.yml
./scripts/xcb.sh build            # DepthWeaver scheme, Debug, iOS simulator
./scripts/xcb.sh run              # build, install and launch on the pinned simulator
./scripts/xcb.sh test             # DepthWeaverTests on the pinned simulator
./scripts/xcb.sh test-mac         # DepthWeaverTests on this Mac (arm64)
./scripts/xcb.sh mac              # DepthWeaver scheme, Debug, macOS (arm64)
./scripts/xcb.sh strings          # build iOS + macOS, then sync Localizable.xcstrings
./scripts/xcb.sh archive-ios      # Release archive + export → build/export-ios/*.ipa
./scripts/xcb.sh archive-mac      # strip quarantine, Release archive + export → build/export-mac/*.pkg
./scripts/xcb.sh -- <args...>     # raw xcodebuild, destination still pinned
```

Prerequisites: Xcode 26 or later (the app icon is an Icon Composer `AppIcon.icon`), `brew install xcodegen`, and Git LFS (`.usdz`, `.mp4`, the Core ML weights, the App Store cards under `screenshots/` and other binaries are LFS objects; without `git lfs pull` they are pointer files). The single `DepthWeaver` target ships both the iOS/iPadOS app and the native macOS app (no Mac Catalyst); macOS uses its own entitlements file (`DepthWeaver/DepthWeaver.macOS.entitlements`). Arguments after the subcommand go to `xcodebuild`. `DEPTHWEAVER_ALLOW_PROVISIONING_UPDATES=1` adds `-allowProvisioningUpdates` to archive and export.

### Simulator

`./scripts/xcb.sh` is the **only** way to run `xcodebuild` here. It pins `-destination` by UDID (iOS) or to `platform=macOS,arch=arm64`, and `-derivedDataPath` to `.build/DerivedData`. Never write a `-destination` by hand, never use `generic/platform=iOS Simulator` (it builds without booting anything, so the next command that needs a device picks one on its own), and never `simctl … booted`.

The device is **`iPhone 17 Pro Max` on iOS 26.5**, declared once in `scripts/sim-config.sh` (`sim_udid`, `sim_boot`, `sim_dest`). `sim_boot` shuts down every other booted simulator first: one simulator at a time. An `iPhone 18 Pro Max` (iOS 27.0) also exists on this Mac but runs badly (`simctl install` of the app hangs there): **do not use it**. `DEPTHWEAVER_SIM_DEVICE` / `DEPTHWEAVER_SIM_RUNTIME` switch device for a whole session (export them; a prefix on one command escapes the hook), `DEPTHWEAVER_DERIVED_DATA` moves the build folder. The `iPad Pro 13-inch (M4)` (`IPAD_DEVICE`, same file) exists only for App Store screenshots: only `scripts/screenshots.sh` boots it, and it shuts it down again.

`scripts/guard-simulator.py` is a `PreToolUse` hook on Bash, registered in `.claude/settings.json` (versioned; the rest of `.claude/` is ignored). It reads the device from `sim-config.sh` and blocks `xcodebuild` without `-destination`, `generic/platform=iOS Simulator`, any simulator other than the pinned iPhone or the screenshots iPad, and any `simctl … booted`. It lets through `xcb.sh`, archives to `generic/platform=iOS|macOS`, `-exportArchive`, read-only queries and heredoc bodies. Its cases live in `./scripts/test-guard-simulator.sh` — run it after touching the hook or `sim-config.sh`.

**Never run two `xcodebuild`s on the same `.build/DerivedData` at once**: the second fails with `build.db: database is locked`, which is not a code error.

`xcb.sh run` installs the **Debug** product by its explicit path (`Debug-iphonesimulator/DepthWeaver.app`), never a `find … | head -1` that could pick up a stale `Release-iphonesimulator/`.

### Project generation (XcodeGen)

`DepthWeaver.xcodeproj` is **generated** from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen) and is not versioned — treat `project.yml` as the source of truth. After adding/removing/moving files or changing build settings, run `./scripts/xcb.sh gen` (`xcb.sh` also generates on its own when the project is missing). A "cannot find X in scope" right after adding a file means the project is stale, not that the code is wrong.

Notes:
- The `DepthWeaver` app target sources the whole `DepthWeaver/` folder (files are auto-classified into Sources/Resources by extension), so **new files are picked up automatically** on regenerate — no manual project edits. `.DS_Store` and the stray root `DepthWeaver/SportsCar.usdz` duplicate are excluded.
- `DepthWeaverTests` is a **host-less logic test**: it re-lists the generation-core subset of app sources explicitly (no UI/capture) and bundles `dog.png` + `pattern-giraffe.png`. If a test starts needing another app source file, add it to that target's `sources` list in `project.yml`. Its deployment targets match the app's (iOS 18.0 / macOS 15.0).
- Both targets are multiplatform (`supportedDestinations: [iOS, macOS]`). The app has no `Info.plist` on disk — it uses `GENERATE_INFOPLIST_FILE=YES` with `INFOPLIST_KEY_*` settings in `project.yml`, translated in `Resources/InfoPlist.xcstrings`. Photos access is **add-only** (`NSPhotoLibraryAddUsageDescription`, for Save): picking goes through `PhotosPicker`, which needs no permission, so do not add `NSPhotoLibraryUsageDescription` back unless the code starts reading the library (`PHPhotoLibrary`, `PHAsset`…).
- macOS is Apple-Silicon-only (`EXCLUDED_ARCHS[sdk=macosx*] = x86_64`): the code uses `Float16`, which does not exist on x86_64.
- Build configurations: `Debug`, `Release`, and `Screenshots` (a Debug clone that adds `SCREENSHOTS` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS`). Schemes: `DepthWeaver` (archives in Release), `DepthWeaver-Screenshots` (only for `scripts/screenshots.sh`; never archive with it) and `DepthWeaverTests`.
- `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` are the only place a version is bumped.

## Translation

`i18n/translations.json` (versioned) is the **single source of translations**. It covers `Resources/Localizable.xcstrings`, `Resources/InfoPlist.xcstrings`, `screenshots/koubou/koubou-strings.xcstrings`, `metadata/app-info/<locale>.json` and `metadata/version/<latest version>/<locale>.json`, in English and French. The app catalogs use `en`/`fr`; the Koubou catalog and `metadata/` use `en-US`/`fr-FR` (`localeMap`).

```bash
./scripts/i18n.py export     # sources → JSON
./scripts/i18n.py import     # JSON → sources
./scripts/i18n.py check      # byte-exact round trip, Koubou variables, JSON in sync (needs PyYAML)
```

Cycle for a new key: write the code, `./scripts/xcb.sh strings`, `./scripts/i18n.py export`, fill in the `en` and `fr` units in the JSON (a bare string means `translated`; `{"value": …, "state": "new"}` otherwise), `./scripts/i18n.py import`, `./scripts/i18n.py check`. For a Koubou card: add the English sentence as a key of `tables.Koubou`, fill in `fr-FR`, import, then `kou generate`.

- **Never edit a generated file by hand** (catalog or metadata): the next `import` erases it; `check` reports it as `OUT OF SYNC` (run `export` if the edit is intentional).
- `import` is authoritative over the set of keys: a key removed from the JSON disappears from the catalog. That is how to drop a stale key — and how to destroy a live one by mistake.
- Run `export` after every `./scripts/xcb.sh strings` and every `asc metadata pull`, otherwise the next `import` cancels them; run `import` before `asc metadata validate/plan` reads a wording change.
- `i18n.py` keeps the catalog's `strings` table in the order it finds it; `xcstringstool sync` (so `xcb.sh strings`) writes it sorted. Each metadata file keeps its JSON formatting.
- `xcb.sh strings` syncs `Localizable.xcstrings` only, from the iOS **and** macOS stringsdata (a one-platform sync marks the other platform's keys stale). It puts back any key the sync drops while the code still uses it: the compiler extracts nothing from an `NSLocalizedString` whose `bundle:` is a variable (the Object Capture strings). `InfoPlist.xcstrings` is never synced (its keys come from `INFOPLIST_KEY_*`, not Swift; a sync would mark them all stale): edit it through the JSON.
- Only the **latest** `metadata/version/<x.y.z>` (numeric sort) is covered; older released versions stay on disk and `import` never touches them.
- In the Koubou yaml files, `align` (`left`/`center`) is also looked up in the catalog: `left` and `center` must stay catalog keys.
- Reports at the top of the JSON: `missingFrench`, `needsReview`, `stale`. Dotted keys and English-sentence keys live side by side; no convention is imposed.
- Out of scope: `metadata/review-notes.md` and `metadata/app-privacy.json`.

## Publishing

App Store Connect app **`6764146054`**, bundle `io.github.glandais.depthweaver`, team `7Q49262697`, primary language `en-US`, also `fr-FR`. One app record, two platforms: iOS (iPhone + iPad, `TARGETED_DEVICE_FAMILY: "1,2"`) and macOS, each with its own version train — iOS `1.2.0` (build 7) and macOS `1.1.0` (build 6) are live; `project.yml` is at `1.2.1` / `8`, released on **both** iOS and macOS with the same build number: it carries the first in-app purchases (the three tips) and brings the Mac from 1.1.0 to the current code. `metadata/version/1.2.1` serves both platforms (`--platform IOS`, then `MAC_OS`), so its What's New must stay true on both. Build numbers have so far run in one sequence across both platforms (5 iOS, 6 Mac, 7 iOS); `asc builds next-build-number --app 6764146054 --platform IOS` (or `MAC_OS`) gives the next one (a rejected upload still consumes its number). Name and subtitle fit in 30 characters each, keywords in 100.

### Metadata

Canonical metadata lives under `./metadata/` (`app-info/<locale>.json`, `version/<version>/<locale>.json`), generated from `i18n/translations.json` (see Translation). Never `apply` without reading the plan. Pass `--platform` (`IOS` or `MAC_OS`): the two platforms share version strings (`1.1.0` exists for both).

```bash
V=1.2.1   # the version being prepared
asc metadata pull     --app 6764146054 --version "$V" --platform IOS --dir ./metadata --force  # refuses to overwrite metadata/app-info/ without --force
./scripts/i18n.py export                     # the pull rewrote metadata/
asc metadata validate --dir ./metadata
asc metadata plan     --app 6764146054 --version "$V" --platform IOS --dir ./metadata
asc metadata approve  --review-dir .asc/metadata/review --all
asc metadata apply    --app 6764146054 --version "$V" --platform IOS --dir ./metadata \
                      --review-dir .asc/metadata/review --confirm
```

A version must exist in App Store Connect before it can be pulled (`asc versions create --app 6764146054 --version "$V" --platform IOS`). A released version (`READY_FOR_DISTRIBUTION`) can no longer be edited. `.asc/` keeps `asc`'s local state and is not versioned.

`asc metadata` does **not** manage review details: `metadata/review-notes.md` is the canonical App Review → Notes text, pushed by hand (its header has the exact commands):

```bash
asc review details-for-version --version-id "<VERSION_ID>"      # note the detail id
asc review details-update --id "<DETAIL_ID>" \
  --notes "$(sed -n '/^---$/,$p' metadata/review-notes.md | tail -n +2)"
```

Keep it true: a person reads it with the app open (how to test without LiDAR, why the camera and add-only Photos permissions, the tips, the Apple-silicon-only Mac app).

### Privacy

- `Resources/PrivacyInfo.xcprivacy`: no tracking, no tracking domains, no collected data, one required-reason API — `UserDefaults` `CA92.1` (the `@AppStorage` keys `trainer.completedRound`, `canvas.hintDismissed`, `trainer.hasSeen`, `inspector.*.expanded`). Without a manifest Apple returns ITMS-91053 on upload. **Re-read it whenever another required-reason API enters the code**: file timestamps (`creationDate`, `modificationDate`, `attributesOfItem`, `resourceValues`), boot time (`systemUptime`, `mach_absolute_time`), disk space (`volumeAvailableCapacity`), active keyboards. Directory listings pass `includingPropertiesForKeys: nil/[]` on purpose.
- `metadata/app-privacy.json` (a single `DATA_NOT_COLLECTED` entry: `asc web privacy plan` rejects an empty `dataUsages`) is the nutrition label, "Data Not Collected", consistent with the manifest (no network, no analytics, no third-party SDK; tips are handled by Apple). Push it with `asc web privacy plan --app 6764146054 --file metadata/app-privacy.json`, then `apply` and `publish --confirm` after reading the plan; `asc web` uses a web session that may ask for a 2FA code.
- The website's privacy page (separate `website` repository) must follow both: a new permission, stored datum or network access changes it too.

### Archive and upload

```bash
./scripts/xcb.sh test && ./scripts/xcb.sh test-mac
./scripts/xcb.sh archive-ios      # → build/export-ios/DepthWeaver.ipa
./scripts/xcb.sh archive-mac      # → build/export-mac/DepthWeaver.pkg
asc builds upload --app 6764146054 --ipa build/export-ios/DepthWeaver.ipa --wait
asc builds upload --app 6764146054 --pkg build/export-mac/DepthWeaver.pkg --version <x.y.z> --build-number <n> --wait  # a .pkg needs both; archive-mac prints them
```

Both archive with the `DepthWeaver` scheme in Release (`generic/platform=iOS|macOS`, which boots nothing) and export with `ExportOptions.plist` / `ExportOptions-macOS.plist` (`app-store-connect`). They never upload; they print the `asc builds upload` command. macOS pitfalls, both handled by `archive-mac` and the project:
- **Quarantine (ITMS-91109)**: Apple rejects a Mac bundle carrying `com.apple.quarantine`, which some downloaded resources keep. `archive-mac` runs `xattr -rd com.apple.quarantine DepthWeaver` and fails if any file still has it.
- **Apple silicon only**: x86_64 is excluded (`Float16`); the `.pkg` is arm64 only, and the listing must not promise Intel Macs.

### Screenshots

Three scripted steps, described in `screenshots/README.md`:

```bash
./scripts/screenshots.sh                     # raw captures, iPhone then iPad, en-US and fr-FR
kou generate screenshots/koubou/iphone.yaml  # Koubou cards (frame, headline)
kou generate screenshots/koubou/ipad.yaml
./screenshots/assemble.sh                    # → screenshots/IPHONE_65/, IPAD_PRO_3GEN_129/, APP_DESKTOP/
```

- `screenshots.sh` builds the **`Screenshots`** configuration (scheme `DepthWeaver-Screenshots`) and launches the app once per screen with `-screenshotMode YES -screenshotScreen <hero|source|depth3d|model|pattern|adjust|tune>`, no tap; a `tmp/screenshot-ready` marker says the screen is ready. It boots the iPad only after shutting every other simulator down, shuts it down at the end and boots the iPhone again. **Drive nothing else on the simulator meanwhile**: `xcb.sh run` would install the Debug app, which has no capture mode, over it.
- The Mac set is opt-in: `./scripts/screenshots.sh --mac` then `kou generate screenshots/koubou/mac.yaml`. It brings the window to the front and needs the Screen Recording permission for the terminal.
- `assemble.sh` checks sizes (`IPHONE_65` 1242×2688, `IPAD_PRO_3GEN_129` 2048×2732, `APP_DESKTOP` 2880×1800), alpha, weight (10 MB ceiling), runs `asc screenshots validate`, and removes stale files. Seven cards on iPhone and iPad, three on the Mac, in `en-US` and `fr-FR`.
- Card headlines are translated through `i18n/translations.json` (table `Koubou`). `crop.html` cards set `align` (`left` for Tune; `center` for the iPad `03-depth-3d`, no frame and no zoom so the labels are not cut).
- Upload with `asc screenshots upload --version-localization <ID> --path screenshots/IPHONE_65/en-US --device-type IPHONE_65` (IDs from `asc localizations list --version <VERSION_ID>`); `--replace --confirm` empties the set first, `--skip-existing` resumes after an error.

### Submitting (1.2.1, 2026-09-24)

iOS and macOS 1.2.1 (build 8) went to review on 2026-09-24 with the three tips: iOS submission `f5a775bd-83cc-4bb7-9b55-6106b70055e4` (the version + the three IAP versions), macOS `6eb589a3-e39f-46b8-8a6d-165238cb7d79` (the version only; the tips are app-wide and ride with iOS). What it took:

- **In-app purchases go in a review submission, version-scoped**: `asc review submissions-create --platform IOS`, `asc review items-add --item-type appStoreVersions --item-id <version>`, then `asc iap versions submit --version-id <iap version> --submission <id> --confirm` for each tip (IAP version ids from `asc iap versions list --iap-id`), then `asc review submissions-submit --id <id> --confirm`. The older `inAppPurchaseSubmissions` / `submitWithNextAppStoreVersion` route (skill `asc-iap-attach`) is refused with `FIRST_CONSUMABLE_MUST_BE_SUBMITTED_ON_VERSION`.
- **The IAP review note** (`reviewNote`) cannot be set with `asc iap`; it was written through the web session (`PATCH /iris/v2/inAppPurchases/<id>`). The web API reports the tips as `MISSING_METADATA` while the public API says `READY_TO_SUBMIT`; the submission went through anyway.
- `asc builds upload --pkg` needs `--version` and `--build-number` (`archive-mac` prints them).
- `asc web …` needs a web session with 2FA: `asc web auth login --apple-id <email>`, typed by the user.
- After the iOS `metadata apply`, the macOS plan drifts (the app info is shared): re-plan and re-approve before the macOS `apply`.

## Known gaps

- `metadata/version/1.2.1` (local only, not yet in App Store Connect) carries the corrected description (iOS 18+ / macOS 15+ on Apple silicon, iPhone, iPad and Mac, no "Magic Eye"), the 1.2.1 What's New (About, tips) and a second ASO pass on name, subtitle and keywords (no word repeated across the three fields, which Apple indexes together). `asc metadata pull` of the new version would bring back the store's old text ("iPhone, iOS 17+"): do not pull it over `metadata/`, or run `./scripts/i18n.py import` right after to restore the local text.
- The Mac app on sale (1.1.0, build 6) was built for macOS 14; the next Mac build requires macOS 15.
- The APP_DESKTOP cards come from 1440×900 (1×) Mac captures upscaled to 2880×1800.
- 87 Localizable keys have no French: the Object Capture strings ported from Apple's sample, and strings that only appear in `DesignSystem/` `#Preview`s ("Soft", "Tune", "Scan the room"…, never shown in the app); plus 2 InfoPlist keys (`CFBundleDisplayName`, `CFBundleName`). 33 Localizable keys are stale (see the reports in `i18n/translations.json`).

## Known constraints

- LiDAR depth is 256×192 (always landscape from ARKit), rotated for portrait
- Depth Anything model is bundled (~48 MB)
- `smoothedSceneDepth` is not available; using `sceneDepth` fallback
- LiDAR capture and the `GuidedCapture` Object-Capture flow are iOS-only and gated behind `#if os(iOS)`
- Depth maps flow through `AppState.currentDepthMap` (not `@State`) so navigation / inspector re-renders see edits made in pushed views or sheets
- Denoising only applies to `.imported` depth maps (it targets 8-bit quantization and would smooth away real LiDAR / AI signal)
- `StereogramGenerator` requires `vmaxsep < vwidth`; pathological settings return an empty image
- `MetalStereogramRenderer` returns `nil` and `StereogramGenerator` falls back to the CPU path when Metal is unavailable or the kernel can't be loaded; both paths must stay numerically aligned (notably OKLab gap fill + averaging)
