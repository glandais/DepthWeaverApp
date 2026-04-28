# DepthWeaver

An iOS app that generates autostereograms (Magic Eye images) from depth maps.

## Features

- **Multiple depth sources**
  - **LiDAR Scan** — capture real-world 3D depth (iPhone Pro / iPad Pro)
  - **Photo (AI)** — estimate depth from any image with [Depth Anything V2](https://huggingface.co/apple/coreml-depth-anything-v2-small)
  - **3D Model** — load USDZ / USD / OBJ / SCN files (or built-in samples), orbit the camera, capture depth from the framed view
  - **Depth Map Presets** — bundled height maps (dog, dolphin, atomium, …)
  - **Import Depth Map** — bring your own grayscale image (white = close, black = far)
- **Depth refinement** — interactive 3D point-cloud preview, input/output range remapping, and Core Image-based denoising for noisy 8-bit imports
- **Patterns** — built-in textures, photo import, or procedural generators: random dot, stars, Perlin noise, Worley noise, Voronoi, reaction-diffusion
- **Stereogram engine** — W.A. Steer's extension of the Thimbleby–Inglis–Witten algorithm with link-based hidden-surface removal, bitmapped patterns, oversampling, and centre-outwards application; parallelized per row
- **Tunable rendering** — DPI, depth strength, depth range, smoothness (oversampling), and depth inversion
- **Localization** — English and French (String Catalogs)
- **Share & Save** — export to Photos or share via any app

## Requirements

- iOS 17.0+
- Xcode 16+
- LiDAR scanning requires iPhone 12 Pro or later / iPad Pro with LiDAR

## Getting Started

1. Clone the repository
2. Open `DepthWeaver.xcodeproj` in Xcode
3. Set your Development Team in Signing & Capabilities
4. Build and run from Xcode

The Depth Anything V2 CoreML model (~48 MB) and the bundled depth-map / 3D-model samples are included in the repository.

## How to View Stereograms

1. Hold the image at arm's length
2. Relax your eyes and look "through" the screen
3. The repeating pattern will start to overlap — keep your gaze relaxed until a 3D shape emerges
4. Slowly adjust distance to sharpen the image

## Tech Stack

- **SwiftUI** — UI framework
- **ARKit** — LiDAR depth capture
- **CoreML** — Depth Anything V2 inference
- **SceneKit + Metal** — 3D model loading and depth-buffer capture
- **Core Image** — depth denoising, image processing, and format conversion

## License

MIT
