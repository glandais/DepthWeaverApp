# DepthWeaver

A native iOS and macOS app that generates autostereograms (Magic Eye images) from depth maps.

[App Store](https://apps.apple.com/app/id6764146054) · [Website](https://glandais.github.io/DepthWeaver/) · [Support](https://glandais.github.io/DepthWeaver/support/) · [Privacy](https://glandais.github.io/DepthWeaver/privacy/) · [Website source](https://github.com/glandais/DepthWeaver) · [Other apps](https://apps.apple.com/developer/id1891310404) · [Buy me a coffee](https://ko-fi.com/gabylandais)

## Features

- **Multiple depth sources**
  - **LiDAR Scan** — capture real-world 3D depth (iPhone Pro / iPad Pro, iOS only)
  - **Photo (AI)** — estimate depth from any image with [Depth Anything V2](https://huggingface.co/apple/coreml-depth-anything-v2-small)
  - **3D Model** — load USDZ / USD / OBJ / SCN files (or built-in samples), orbit the camera, capture depth from the framed view
  - **Object Capture scan** — scan a real object into a `.usdz` with photogrammetry and reuse it as a depth source (iOS Pro devices only)
  - **Depth Map Presets** — bundled height maps (dog, dolphin, atomium, …)
  - **Import Depth Map** — bring your own grayscale image (white = close, black = far)
- **Depth refinement** — interactive 3D point-cloud preview, input/output range remapping, and Core Image-based denoising for noisy 8-bit imports
- **Patterns** — built-in textures, photo import, or procedural generators: random dot, stars, Perlin noise, Worley noise, Voronoi, reaction-diffusion
- **Stereogram engine** — W.A. Steer's extension of the Thimbleby–Inglis–Witten algorithm with link-based hidden-surface removal, bitmapped patterns, oversampling, and centre-outwards application. The full pipeline runs as a Metal compute kernel (one thread per row) with an OKLab gap-fill / oversampling downscale, and a CPU fallback when Metal is unavailable.
- **Tunable rendering** — DPI, depth strength, depth range, smoothness (oversampling), and depth inversion
- **Native on iOS and macOS** — the same code base ships an iPhone / iPad app and a Mac app with HSplitView + collapsible inspector, standard menus, and `.fileExporter`-based PNG save
- **About** — links to the website, support, privacy policy, source code and the App Store (ⓘ button on the iPhone canvas; *Help* menu on Mac)
- **Localization** — English and French (String Catalogs)
- **Share & Save** — export to Photos / Files, copy to the pasteboard, or share via any app

## Requirements

- iOS 18.0+ / iPadOS 18.0+, macOS 15.0+ on Apple silicon (the Mac app excludes Intel: it relies on `Float16`)
- Xcode 26 or later (the app icon is an Icon Composer `.icon`), [XcodeGen](https://github.com/yonaskolb/XcodeGen) and [Git LFS](https://git-lfs.com)
- LiDAR scanning and Object Capture scans require an iPhone 12 Pro or later / iPad Pro with LiDAR (iOS only)

## Getting Started

The bundled 3D models, videos and binary model weights are stored with Git LFS, and the Xcode project is generated from `project.yml` (it is not in the repository):

```bash
brew install xcodegen git-lfs
git lfs install
git clone https://github.com/glandais/DepthWeaverApp.git   # or `git lfs pull` in an existing clone
cd DepthWeaverApp
./scripts/xcb.sh gen        # generate DepthWeaver.xcodeproj
./scripts/xcb.sh build      # iOS simulator build (Debug)
./scripts/xcb.sh run        # build, install and launch on the simulator
./scripts/xcb.sh test       # unit tests on the simulator
./scripts/xcb.sh mac        # macOS build (Apple silicon)
```

`scripts/xcb.sh` pins the simulator declared in `scripts/sim-config.sh` and builds into `.build/DerivedData`; `./scripts/xcb.sh --help` lists every command. To run from Xcode instead, open the generated `DepthWeaver.xcodeproj` and set your Development Team in Signing & Capabilities.

The Depth Anything V2 CoreML model (~48 MB, its weights through Git LFS) and the bundled depth-map / 3D-model samples are included in the repository.

## How to View Stereograms

1. Hold the image at arm's length
2. Relax your eyes and look "through" the screen
3. The repeating pattern will start to overlap — keep your gaze relaxed until a 3D shape emerges
4. Slowly adjust distance to sharpen the image

## Tech Stack

- **SwiftUI** — UI framework (shared on iOS and macOS, with platform-specific entry points)
- **Metal** — GPU stereogram compute kernel (`StereogramKernels.metal` + `MetalStereogramRenderer`)
- **ARKit** — LiDAR depth capture (iOS)
- **CoreML** — Depth Anything V2 inference
- **SceneKit + Metal** — 3D model loading and depth-buffer capture
- **Object Capture / RealityKit** — photogrammetry-based real-object scans (iOS)
- **Core Image** — depth denoising, image processing, and format conversion
- **Swift Testing** — unit tests in `DepthWeaverTests/`

## Support

If you enjoy DepthWeaver, you can [buy me a coffee on Ko-fi](https://ko-fi.com/gabylandais).

## License

MIT
