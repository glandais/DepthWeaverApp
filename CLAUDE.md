# DepthWeaver

## Project overview

Cross-platform Apple app (SwiftUI, iOS 17+ / macOS 14+) that generates autostereograms (Magic Eye images) from depth maps. Localized in English and French.

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

macOS-only: `DepthWeaverApp` adds standard menu commands (Open ⌘O, Save ⌘S, Copy ⌘⇧C, Toggle Inspector ⌘⌥I) wired through `NotificationCenter` to `MacGenerationView`. LiDAR / live AR captures and the `GuidedCapture` Object-Capture flow are iOS-only and gated with `#if os(iOS)`; on macOS the user opens 3D models from disk via `SceneCaptureSheet`. Save uses a `FileDocument` (`StereogramPNGDocument`) through `.fileExporter`.

## Key components

### Models
- **DepthMap** (`Models/DepthMap.swift`): wraps `[Float]` depth values with source dims, original (display) dims, an `adjustment` (input/output remap) and a `denoising` config. Exposes `workingDepth` and `adjustedDepthValues(width:height:)` consumed by the generator. `Source` is `lidar | depthAnything | imported | model3D` (Object Capture scans reuse `.model3D` since they're consumed via the same renderer). Denoising only runs on `.imported` depths (8-bit imports are the noisy ones).
- **DepthAdjustment** / **DepthDenoising** (`Models/`): value types stored on `DepthMap`. Editing them re-triggers stereogram generation via `onChange` in `GenerationView`.
- **DepthTransform** (`Models/DepthTransform.swift`): the pan/zoom framing of the depth map, also stored on `DepthMap` and applied while resampling (`scale` ≥ 1, offsets clamped so the window never leaves the map). Driven by the canvas' live mode; `.identity` for every capture path. `DepthTransform.source(_:inverseScale:offset:)` is the single formula both `DepthMap.adjustedDepthValues` and `StereogramKernels.metal` run — they must stay byte-identical, hence the shared reciprocal instead of a divide.
- **DepthMapPreset** (`Models/DepthMapPreset.swift`): bundled height maps in `Resources/HeightMaps/`.
- **Model3DPreset** (`Models/Model3DPreset.swift`): bundled `.usdz` files in `Resources/Models3D/`.
- **PatternSource** (`Models/PatternSource.swift`): `.asset(StereogramPattern) | .procedural(ProceduralPatternType, ProceduralConfig) | .imported(UIImage)`.
- **ProceduralPatternType** (`Models/ProceduralPatternType.swift`): `randomDot | stars | perlinNoise | worleyNoise | voronoi | reactionDiffusion`, each with its own `*Config` struct and SF Symbol icon.
- **StereogramSettings** (`Models/StereogramSettings.swift`): `dpi`, `depthStrength`, `sepFactor`, `oversampling`, `invert`, `patternSource`.

### Services
- **DepthAnythingService** (`Services/DepthAnythingService.swift`): CoreML inference with `DepthAnythingV2SmallF16.mlpackage`. Input: 518×392, output: Float16. Buffers are copied to avoid CoreML reuse.
- **LiDARDepthService** (`Services/LiDARDepthService.swift`, iOS-only): owns an `ARSession` directly (not via ARSCNView), publishes the camera feed as `UIImage`, rotates the depth buffer for portrait.
- **Model3DLoader** / **Model3DDepthRenderer** (`Services/`): SceneKit-based loader + Metal depth-buffer extractor. `captureDepthMap(from:outputSize:)` writes view-space distances; cleared pixels become `Float.nan` so the auto-range computation in `DepthMap.initialAdjustment` ignores them. The work lives in `Model3DDepthRenderer.Session`, a reusable pipeline that keeps its `SCNRenderer` and its four render targets between captures — live mode captures dozens of times a second and cannot reallocate them per frame. The static entry point builds a throwaway session.
- **OrbitCamera** (`Services/OrbitCamera.swift`): spherical framing (target / distance / azimuth / elevation) used by live mode, which has no viewport and so cannot lean on SceneKit's own camera controller. Everything is scaled by `extent`, the longest side of the *drawable* content's bounding box (camera nodes excluded), and `framing(scene:)` adopts the angle of the scene's existing camera so live mode picks up where the capture screen left off.
- **DepthMapDenoiser** (`Services/DepthMapDenoiser.swift`): Core Image pipeline (normalize → median → background mask → bilateral → blend) in a half-float working space. Lifts 8-bit imports out of their quantization grid.
- **StereogramQuality** (`Services/StereogramGeometry.swift`): `.preview` (min output dimension 480) vs `.full` (960). Live mode renders `.preview` while a finger is down and `.full` the moment it lifts.
- **StereogramGenerator** (`Services/StereogramGenerator.swift`): W.A. Steer's extension of the Thimbleby–Inglis–Witten algorithm — link-based hidden-surface removal, bitmapped patterns, oversampling, centre-outwards application. Upscales output so min dimension ≥ 960. The default path runs the entire algorithm on the GPU via `MetalStereogramRenderer`; if the Metal library / pipeline can't be created, falls back to a CPU path parallelized per row via `DispatchQueue.concurrentPerform` with OKLab-based oversampling and gap-fill.
- **MetalStereogramRenderer** + **StereogramKernels.metal** (`Services/`): GPU implementation of the algorithm. One thread per output row dispatches the linking pass, both centre-outwards pattern fills, OKLab gap fill, and OKLab oversampling downscale; per-row scratch arrays are slices of large `storageModePrivate` buffers so threads never synchronize. `MetalStereogramRenderer.shared` is a lazy singleton — `nil` if Metal is unavailable, which transparently selects the CPU path.
- **Generators/** (`Services/Generators/`): one `PatternGenerator` per `ProceduralPatternType` (`RandomDotGenerator`, `StarsGenerator`, `PerlinNoiseGenerator`, `WorleyNoiseGenerator`, `VoronoiGenerator`, `ReactionDiffusionGenerator`).

### ViewModels
- **PhotoDepthViewModel**, **LiDARCaptureViewModel** (iOS-only), **Model3DCaptureViewModel** drive the capture flows. The Object Capture flow (iOS) is driven by `GuidedCaptureModel` (an `ObservableObject` ported from Apple's `AppDataModel`) inside `Features/GuidedCapture/`, with `CapturedModelLibrary` persisting finished scans to `Documents/CapturedModels/<uuid>.usdz`.
- **StereogramViewModel** debounces calls to `StereogramGenerator` (`generateDebounced`) to keep the live preview responsive. `generateLive` is the gesture path instead: it *coalesces* rather than debounces (only the newest frame is kept, rendered as soon as the previous one lands, at `.preview` quality and without the spinner), and a render token makes sure a late coarse frame can never land on top of the full-quality one that replaced it.
- **LiveSceneViewModel** (iOS-only) owns live mode's 3D half: the `OrbitCamera`, the camera node it writes onto a scene that is never displayed, and the `Model3DDepthRenderer.Session` the gestures feed.
- **PatternPreviewViewModel** generates a thumbnail for the selected procedural pattern.

### Views
- **iOS** — `Views/GenerationView.swift` is the hub: depth-source section (with `DepthPointCloudView` 3D preview), pattern picker (assets + photo import + procedural with `ProceduralParamsView`), settings sliders, and live stereogram preview. The help sheet (`HowToUseSheet`) is defined in the same file.
- **macOS** — `Views/Mac/` contains `MacGenerationView` (HSplitView with canvas + inspector), `InspectorPanel` (collapsible source/pattern/depth/settings sections persisted via `@AppStorage`), `SceneCaptureSheet` (modal for loading 3D models and capturing depth from an orbit camera), and `StereogramPNGDocument` (`FileDocument` for `.fileExporter`-based PNG save).

### Canvas modes (iOS)

`CanvasScreen` answers a gesture in one of two ways, picked with the toggle in the top bar (`CanvasMode` in `Views/Canvas/CanvasScreenState.swift`):

- **`.view`** — the original behaviour: pinch/drag move the *rendered* image (`zoom` / `offset`, SwiftUI gestures).
- **`.live`** — gestures move the *source* and the stereogram is regenerated for each frame. A flat depth map pans and zooms through `DepthMap.transform`; a `.model3D` map whose scene is still loaded (`AppState.liveScene`, handed over by `Model3DCaptureView.onCapture`) is orbited instead — one finger turns, two fingers slide, pinch dollies — and re-captured through `LiveSceneViewModel`. Double-tap (or the reset button that appears once the framing moves) restores the starting framing.

`Views/Canvas/LiveGestureView.swift` is a `UIViewRepresentable` gesture host: SwiftUI cannot tell a one-finger drag from a two-finger one, which is exactly the distinction live 3D turns on, so live mode brings its own `UIPanGestureRecognizer`s (1-touch and 2-touch), a `UIPinchGestureRecognizer` and the two tap recognizers, and reports incremental deltas.

Mid-gesture 3D captures are additionally gated on `StereogramViewModel.hasPendingLiveFrame`, so the scene is re-rendered into a depth buffer at the generator's rate rather than the touch stream's.

### Cross-platform plumbing
- `Extensions/PlatformImage.swift` typealiases `PlatformImage = UIImage` on iOS and `PlatformImage = NSImage` on macOS, with parity helpers (`pngData()`, `jpegData(compressionQuality:)`, `cgImage`, `loadFromAssets`, `loadFromBundle`, `pixelSize`) and `Image.init(platformImage:)`. All code that used `UIImage` directly was migrated to `PlatformImage` so models, services, generators and tests are platform-agnostic.

### Tests
`DepthWeaverTests/DepthWeaverTests.swift` uses Swift Testing (`@Suite` / `@Test`). The current suite renders the bundled `dog` height map with default settings and asserts on output dimensions, render time, and pixel-statistics (mean / std-dev) to catch regressions that produce a uniform or empty image. Run via the `DepthWeaverTests` scheme.

## Resources

- `Resources/Patterns/` — built-in textures (PNG)
- `Resources/HeightMaps/` — depth-map presets (PNG, grayscale)
- `Resources/Models3D/` — bundled `.usdz` samples
- `Resources/DepthAnythingV2SmallF16.mlpackage` — CoreML model (~48 MB)
- `Resources/Localizable.xcstrings` — String Catalog (en, fr)

## Build

Open `DepthWeaver.xcodeproj` in Xcode, set your Development Team in Signing & Capabilities, then build and run. The single `DepthWeaver` target ships both the iOS and the native macOS app (no Mac Catalyst); run the `DepthWeaverTests` scheme for unit tests. macOS uses its own entitlements file (`DepthWeaver/DepthWeaver.macOS.entitlements`).

### Project generation (XcodeGen)

`DepthWeaver.xcodeproj` is **generated** from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen) — treat `project.yml` as the source of truth, not the `.pbxproj`. After adding/removing/moving files or changing build settings, regenerate with:

```bash
xcodegen generate      # reads project.yml, rewrites DepthWeaver.xcodeproj
```

Notes:
- The `DepthWeaver` app target sources the whole `DepthWeaver/` folder (files are auto-classified into Sources/Resources by extension), so **new files are picked up automatically** on regenerate — no manual project edits. `.DS_Store` and the stray root `DepthWeaver/SportsCar.usdz` duplicate are excluded.
- `DepthWeaverTests` is a **host-less logic test**: it re-lists the generation-core subset of app sources explicitly (no UI/capture) and bundles `dog.png` + `pattern-giraffe.png`. If a test starts needing another app source file, add it to that target's `sources` list in `project.yml`.
- Both targets are multiplatform (`supportedDestinations: [iOS, macOS]`). The app has no `Info.plist` on disk — it uses `GENERATE_INFOPLIST_FILE=YES` with `INFOPLIST_KEY_*` settings in `project.yml`. macOS is Apple-Silicon-only (`EXCLUDED_ARCHS[sdk=macosx*] = x86_64`).

## App Store metadata

Use the `asc` CLI to sync app metadata (descriptions, keywords, what's new, screenshots, localizations) with App Store Connect. Canonical metadata lives under `./metadata/`. App Store Connect app ID: `6764146054` (bundle `io.github.glandais.depthweaver`).

## Known constraints

- LiDAR depth is 256×192 (always landscape from ARKit), rotated for portrait
- Depth Anything model is bundled (~48 MB)
- `smoothedSceneDepth` is not available; using `sceneDepth` fallback
- LiDAR capture and the `GuidedCapture` Object-Capture flow are iOS-only and gated behind `#if os(iOS)`
- Depth maps flow through `AppState.currentDepthMap` (not `@State`) so navigation / inspector re-renders see edits made in pushed views or sheets
- Denoising only applies to `.imported` depth maps (it targets 8-bit quantization and would smooth away real LiDAR / AI signal)
- `StereogramGenerator` requires `vmaxsep < vwidth`; pathological settings return an empty image
- `MetalStereogramRenderer` returns `nil` and `StereogramGenerator` falls back to the CPU path when Metal is unavailable or the kernel can't be loaded; both paths must stay numerically aligned (notably OKLab gap fill + averaging, and the `DepthTransform` resample)
- Live mode is iOS-only; on macOS the canvas keeps the pan/zoom-the-image behaviour
- Live 3D needs the scene, not just the depth map: after a cold start, or when the depth came from a photo / LiDAR, live mode falls back to panning and zooming the flat depth map
