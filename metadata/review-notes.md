# App Review notes

Canonical copy of the App Review Information → Notes field. `asc metadata` does
not manage review details: this file is the source, and it is pushed by hand.

```bash
asc review details-for-version --version-id "<VERSION_ID>"   # read it, and note the detail id
asc review details-update --id "<DETAIL_ID>" --notes "$(sed -n '/^---$/,$p' metadata/review-notes.md | tail -n +2)"
```

Keep it true: a person reads it with the app open. Every statement below was
checked against the code; re-check it when a feature, permission or product
changes.

---

DepthWeaver turns a depth map into an autostereogram (a "Magic Eye" image). Everything runs on the device: there is no account, no sign-in, no server, no analytics and no network request of any kind (the Mac app's sandbox does not even have the outgoing-network entitlement). The only outbound links are in About (the ⓘ button on the iPhone/iPad canvas, the Help menu on the Mac): website, support, privacy policy, source code, App Store rating page and developer page. They open in Safari or the App Store.

HOW TO TRY IT QUICKLY (ANY DEVICE, NO LIDAR NEEDED)
On first launch a short "Learn to see it" trainer opens; "Skip the trainer" closes it. The canvas already shows a stereogram built from a bundled example depth map. Tap the depth pill at the top left (or Depth → Change depth source) to open the Depth source screen:
- "Choose a photo" (From a photo): pick any picture in the system photo picker; the bundled Core ML model estimates its depth in a few seconds.
- "Examples": ready-made depth maps bundled with the app.
- "Import a map": any greyscale image used as a depth map.
- "Open a 3D model" → + → Presets: bundled USDZ models (or Open File… for your own USDZ, USD, OBJ or SCN). Orbit the model, then tap Capture Depth.
The Pattern and Tune tools at the bottom change the texture and the 3D settings; the result can be shared or saved to Photos.

LIDAR AND OBJECT CAPTURE (IPHONE PRO / IPAD PRO ONLY)
Two more sources appear under "Capture it yourself" only on devices with a LiDAR Scanner; they are hidden elsewhere, so their absence on a non-Pro device is expected.
- "Scan the room" streams live LiDAR depth from ARKit; "Capture depth" takes a snapshot.
- "Scan an object" uses Apple's Object Capture (RealityKit) to photograph an object from all sides and reconstruct a 3D model on the device. The model is saved in the app's own storage and can then be used as a 3D-model depth source.

PERMISSIONS
- Camera: requested only when one of the two LiDAR / Object Capture flows above is opened, on devices that have them.
- Photos: photos, patterns and depth maps are picked through the system photo picker, which needs no library permission. The only photo prompt is add-only, when the user taps Save to save a stereogram to Photos.
Nothing picked, captured or generated leaves the device unless the user shares it.

ON-DEVICE MACHINE LEARNING
Depth from a photo uses Depth Anything V2 Small, a Core ML model bundled in the app (about 48 MB) and run locally. No image is uploaded anywhere.

TIPS (IN-APP PURCHASE)
The app has no paid content or feature. Three optional consumable tips (io.github.glandais.depthweaver.tip.small, .medium, .large) are offered through In-App Purchase: on iPhone/iPad under ⓘ → Support DepthWeaver, on the Mac under Help → Support DepthWeaver…. A tip unlocks nothing; the app just says thank you. There is nothing to restore, and there is no external tip or donation link in the app.

MAC APP
The same app ships natively for macOS (Apple silicon only, no Intel build). It has no LiDAR or Object Capture; a photo, height map or 3D model is opened from disk (File → Open…, the toolbar, or drag and drop), and the stereogram is saved with File → Save Image… or copied.
