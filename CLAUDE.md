# DepthWeaver

## Project overview

iOS app (SwiftUI, iOS 17+) that generates autostereograms (Magic Eye images) from depth maps. Localized in English and French.

## Architecture

MVVM with a single `NavigationStack`. Shared state lives in `AppState` (`ContentView.swift`); the current `DepthMap` is a `@Published` property so navigation destinations stay in sync after edits. The whole app is built around one main screen (`GenerationView`) that pushes specialized capture / adjustment views on demand.

```
ContentView (NavigationStack + AppState)
  └── GenerationView                  ← main screen: depth source + pattern + settings + live preview
        ├── DepthAdjustmentView       ← input/output range remap + denoising
        ├── LiDARCaptureView          ← live LiDAR depth capture
        ├── Model3DCaptureView        ← USDZ/USD/OBJ/SCN loader + orbit camera + depth capture
        └── StereogramResultView      ← full-screen result + share
```

`NavigationDestination` (in `ContentView.swift`) enumerates the four pushable destinations.

## Key components

### Models
- **DepthMap** (`Models/DepthMap.swift`): wraps `[Float]` depth values with source dims, original (display) dims, an `adjustment` (input/output remap) and a `denoising` config. Exposes `workingDepth` and `adjustedDepthValues(width:height:)` consumed by the generator. `Source` is `lidar | depthAnything | imported | model3D`. Denoising only runs on `.imported` depths (8-bit imports are the noisy ones).
- **DepthAdjustment** / **DepthDenoising** (`Models/`): value types stored on `DepthMap`. Editing them re-triggers stereogram generation via `onChange` in `GenerationView`.
- **DepthMapPreset** (`Models/DepthMapPreset.swift`): bundled height maps in `Resources/HeightMaps/`.
- **Model3DPreset** (`Models/Model3DPreset.swift`): bundled `.usdz` files in `Resources/Models3D/`.
- **PatternSource** (`Models/PatternSource.swift`): `.asset(StereogramPattern) | .procedural(ProceduralPatternType, ProceduralConfig) | .imported(UIImage)`.
- **ProceduralPatternType** (`Models/ProceduralPatternType.swift`): `randomDot | stars | perlinNoise | worleyNoise | voronoi | reactionDiffusion`, each with its own `*Config` struct and SF Symbol icon.
- **StereogramSettings** (`Models/StereogramSettings.swift`): `dpi`, `depthStrength`, `sepFactor`, `oversampling`, `invert`, `patternSource`.

### Services
- **DepthAnythingService** (`Services/DepthAnythingService.swift`): CoreML inference with `DepthAnythingV2SmallF16.mlpackage`. Input: 518×392, output: Float16. Buffers are copied to avoid CoreML reuse.
- **LiDARDepthService** (`Services/LiDARDepthService.swift`): owns an `ARSession` directly (not via ARSCNView), publishes the camera feed as `UIImage`, rotates the depth buffer for portrait.
- **Model3DLoader** / **Model3DDepthRenderer** (`Services/`): SceneKit-based loader + Metal depth-buffer extractor. `captureDepthMap(from:outputSize:)` writes view-space distances; cleared pixels become `Float.nan` so the auto-range computation in `DepthMap.initialAdjustment` ignores them.
- **DepthMapDenoiser** (`Services/DepthMapDenoiser.swift`): Core Image pipeline (normalize → median → background mask → bilateral → blend) in a half-float working space. Lifts 8-bit imports out of their quantization grid.
- **StereogramGenerator** (`Services/StereogramGenerator.swift`): W.A. Steer's extension of the Thimbleby–Inglis–Witten algorithm — link-based hidden-surface removal, bitmapped patterns, oversampling, centre-outwards application. Parallelized per row via `concurrentPerform`. Upscales output so min dimension ≥ 960.
- **Generators/** (`Services/Generators/`): one `PatternGenerator` per `ProceduralPatternType` (`RandomDotGenerator`, `StarsGenerator`, `PerlinNoiseGenerator`, `WorleyNoiseGenerator`, `VoronoiGenerator`, `ReactionDiffusionGenerator`).

### ViewModels
- **PhotoDepthViewModel**, **LiDARCaptureViewModel**, **Model3DCaptureViewModel** drive the three capture flows.
- **StereogramViewModel** debounces calls to `StereogramGenerator` (`generateDebounced`) to keep the live preview responsive.
- **PatternPreviewViewModel** generates a thumbnail for the selected procedural pattern.

### Views
`Views/GenerationView.swift` is the hub: depth-source section (with `DepthPointCloudView` 3D preview), pattern picker (assets + photo import + procedural with `ProceduralParamsView`), settings sliders, and live stereogram preview. The help sheet (`HowToUseSheet`) is defined in the same file.

## Resources

- `Resources/Patterns/` — built-in textures (PNG)
- `Resources/HeightMaps/` — depth-map presets (PNG, grayscale)
- `Resources/Models3D/` — bundled `.usdz` samples
- `Resources/DepthAnythingV2SmallF16.mlpackage` — CoreML model (~48 MB)
- `Resources/Localizable.xcstrings` — String Catalog (en, fr)

## Build

Open `DepthWeaver.xcodeproj` in Xcode, set your Development Team in Signing & Capabilities, then build and run.

## App Store metadata

Use the `asc` CLI to sync app metadata (descriptions, keywords, what's new, screenshots, localizations) with App Store Connect. Canonical metadata lives under `./metadata/`. App Store Connect app ID: `6764146054` (bundle `io.github.glandais.depthweaver`).

## Known constraints

- LiDAR depth is 256×192 (always landscape from ARKit), rotated for portrait
- Depth Anything model is bundled (~48 MB)
- `smoothedSceneDepth` is not available; using `sceneDepth` fallback
- Depth maps flow through `AppState.currentDepthMap` (not `@State`) so `navigationDestination` re-renders see edits made in pushed views
- Denoising only applies to `.imported` depth maps (it targets 8-bit quantization and would smooth away real LiDAR / AI signal)
- `StereogramGenerator` requires `vmaxsep < vwidth`; pathological settings return an empty image
