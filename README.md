# iStereogram

An iOS app that generates autostereograms (Magic Eye images) from depth maps.

## Features

- **LiDAR Depth Capture** -- Use your device's LiDAR sensor to capture 3D depth of real-world scenes (iPhone Pro / iPad Pro)
- **AI Depth Estimation** -- Generate depth maps from any photo using [Depth Anything V2](https://huggingface.co/apple/coreml-depth-anything-v2-small) (works on all devices)
- **Autostereogram Generation** -- Transform depth maps into random-dot stereograms using the Thimbleby-Inglis-Witten algorithm
- **Adjustable Parameters** -- Tune strip width and eye separation for optimal viewing
- **Share & Save** -- Export generated stereograms to Photos or share via any app

## Requirements

- iOS 17.0+
- Xcode 16+
- LiDAR scanning requires iPhone 12 Pro or later / iPad Pro with LiDAR

## Getting Started

1. Clone the repository
2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you don't have it:
   ```bash
   brew install xcodegen
   ```
3. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```
4. Open `iStereogram.xcodeproj` in Xcode
5. Set your Development Team in Signing & Capabilities
6. Build and run

The Depth Anything V2 CoreML model (~48MB) is included in the repository.

## How to View Stereograms

1. Hold the image at arm's length
2. Relax your eyes and look "through" the screen
3. The repeating pattern will start to overlap -- keep your gaze relaxed until a 3D shape emerges
4. Slowly adjust distance to sharpen the image

## Tech Stack

- **SwiftUI** -- UI framework
- **ARKit** -- LiDAR depth capture
- **CoreML** -- Depth Anything V2 inference
- **Core Image** -- Image processing and format conversion

## License

MIT
