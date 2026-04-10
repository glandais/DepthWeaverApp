# iStereogram

## Project overview

iOS app (SwiftUI, iOS 17+) that generates autostereograms (Magic Eye images) from depth maps.

## Architecture

MVVM with NavigationStack. Shared state via `AppState` ObservableObject.

```
HomeView (ContentView)
  ├── LiDAR Scan → LiDARCaptureView → DepthPreviewView → StereogramResultView
  └── From Photo → PhotosPicker → DepthPreviewView → StereogramResultView
```

## Key components

- **DepthMap** (`Models/DepthMap.swift`): CVPixelBuffer wrapper with normalization, bilinear resize, Float16/Float32/UInt8 format support. LiDAR values are inverted (meters → normalized).
- **DepthAnythingService** (`Services/DepthAnythingService.swift`): CoreML inference with `DepthAnythingV2SmallF16.mlpackage`. Input: 518x392, output: Float16 depth. Buffers are copied to avoid CoreML reuse.
- **LiDARDepthService** (`Services/LiDARDepthService.swift`): ARKit session with `.sceneDepth`. Owns the `ARSession` directly (not via ARSCNView). Renders camera feed to published `UIImage`. Rotates depth buffer for portrait.
- **StereogramGenerator** (`Services/StereogramGenerator.swift`): Thimbleby-Inglis-Witten algorithm, parallelized per row via `concurrentPerform`. Upscales to min dimension 960px.

## Build

```bash
# Generate Xcode project (requires xcodegen)
xcodegen generate

# Build
xcodebuild -project iStereogram.xcodeproj -scheme iStereogram -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Set your Development Team in Xcode Signing & Capabilities before running on device.

## Known constraints

- LiDAR depth is 256x192 (always landscape from ARKit), rotated for portrait
- Depth Anything model is bundled (~48MB)
- `smoothedSceneDepth` is not available; using `sceneDepth` fallback
- Navigation passes depth maps via `AppState` ObservableObject (not `@State`) due to SwiftUI `navigationDestination` timing
