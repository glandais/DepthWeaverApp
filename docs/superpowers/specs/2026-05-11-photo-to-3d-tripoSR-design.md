# Photo-to-3D feature (TripoSR, on-device) — Design

**Status**: design validated, not yet implemented
**Date**: 2026-05-11

## Goal

Add a standalone "Generate 3D from photo" capture mode to DepthWeaver. A user picks a single photo; the app produces a `.usdz` mesh and stores it in `CapturedModelLibrary` (the same library used by Object Capture scans). The mesh is then viewable, exportable, and re-usable as a `model3D` depth source for stereogram generation.

This is a sibling to the existing iOS Object Capture (`GuidedCapture`) flow, but driven by a single AI-generated mesh instead of multi-photo photogrammetry.

## Scope

In scope:
- iOS and macOS.
- On-device CoreML inference (no network, no backend).
- TripoSR (Stability AI + Tripo AI, MIT) as the model.
- Geometry-only mesh (no texture, no vertex colors — explicitly omitted; the stereogram pipeline and basic shape preview do not need them).
- Adaptive grid resolution by device class.
- Bundling model weights directly in the app (~140MB added after 4-bit palettization).
- Integration via the existing `AppState.pendingCapture` pipeline; reuse of the existing `NameCaptureSheet` + `CapturedModelLibrary` save flow.
- Cross-platform refactor of `CapturedModelLibrary` (currently iOS-only).
- Localized in en + fr per the existing pattern.

Out of scope for v1:
- Texture / vertex colors.
- Mesh simplification or decimation.
- Projected-photo texture as a "view from front looks photographic" feature.
- Multi-image or few-shot reconstruction.
- watchOS / visionOS / tvOS / Mac Catalyst.
- On-demand download / Apple ODR (revisit if install size becomes a real complaint).

## Architecture

Parallel to the existing `Features/GuidedCapture/` module.

```
DepthWeaver/
  Features/
    PhotoTo3D/
      PhotoTo3DRootView.swift          ← top-level screen
      PhotoTo3DViewModel.swift         ← state machine
      PhotoTo3DPreviewView.swift       ← SceneKit orbit preview
  Services/
    TripoSRService.swift               ← CoreML inference orchestration
    TripoSRPostProcessor.swift         ← Metal marching cubes
    USDZExporter.swift                 ← MDLAsset → .usdz
  Resources/
    TripoSREncoder.mlpackage           ← bundled
    TripoSRDecoder.mlpackage           ← bundled
    TripoSRDensity.mlpackage           ← bundled
```

Wiring:

- New `NavigationDestination.photoTo3DCapture` on iOS, pushed from `GenerationView` next to the "Scan object" entry.
- On macOS: new button in `InspectorPanel`'s 3D-model source section, opens `PhotoTo3DRootView` as a sheet (mirrors `SceneCaptureSheet`).
- On success the view model writes a temp `.usdz`, sets `appState.pendingCapture = PendingCapture(url:)`, and the existing pipeline (`NameCaptureSheet` → `CapturedModelLibrary.save` → handoff to `Model3DCaptureView` / `SceneCaptureSheet`) takes over.
- `CapturedModelLibrary` becomes cross-platform (small refactor: remove `#if os(iOS)`, make it build under macOS).

Reuse:
- iOS photo picker: `PhotosPicker`.
- macOS photo picker: `NSOpenPanel` (matches `SceneCaptureSheet`).
- Mesh viewing + depth extraction: existing `Model3DCaptureView` / `SceneCaptureSheet` / `Model3DDepthRenderer`. Zero new code on that side.

## UI flow

iOS — pushed onto the existing `NavigationStack`:

```
GenerationView
  └─ "Generate 3D from photo" button
       └─ NavigationDestination.photoTo3DCapture
             └─ PhotoTo3DRootView
                  ├─ .idle           → PhotosPicker
                  ├─ .inferring      → determinate progress with sub-stage label
                  │                    ("Encoding image", "Reconstructing shape",
                  │                     "Extracting mesh")
                  ├─ .preview        → SceneKit orbit preview, [Save] / [Discard]
                  └─ .saving         → set appState.pendingCapture, pop
                                       (existing NameCaptureSheet takes over)
```

macOS — sheet from `InspectorPanel` 3D-model source section. Same state machine; uses `NSOpenPanel` for picking the source photo. On save, writes USDZ into the (now cross-platform) `CapturedModelLibrary` and dismisses.

A `[Cancel]` button is present at every state. Tasks check `Task.isCancelled` between sub-stages.

Error states:
- Inference fails (OOM on older device) → "Try a smaller image" + retry-with-downscaled-input.
- Mesh extraction empty → "Couldn't reconstruct from this photo" + retry.

Progress UX detail: inference is the long part (10s-2min on iPhone). Show a determinate bar — image encoding is one step (~15%), triplane decoding is one step (~20%), density-grid sampling is the bulk (~50%, reportable by chunk), marching cubes is fast (~15%). No opaque spinners.

## CoreML inference pipeline

TripoSR is split into three `.mlpackage`s because the density MLP is called millions of times per generation and benefits from a tight, batched form, while the encoder/decoder run once each.

```
Resources/
  TripoSREncoder.mlpackage   ~340MB FP16 → ~90MB after 4-bit palettization
                             Image (512×512 RGB) → patch tokens
  TripoSRDecoder.mlpackage   ~160MB FP16 → ~45MB after 4-bit palettization
                             Patch tokens → triplane features
  TripoSRDensity.mlpackage   ~5MB
                             Batched (N×3 point coords + triplane) → N density
                             Called repeatedly on chunks of grid points.
                             (Geometry-only: no RGB output.)
```

Orchestration in `TripoSRService`:

```
input: PlatformImage
  ↓ resize + center-crop to 512×512, normalize per DINO stats
  ↓
encoder.predict(image) → tokens                            [progress 0% → 15%]
decoder.predict(tokens) → triplane (kept in memory)        [progress 15% → 35%]

# Density grid sampling
gridResolution = adaptive: 128 (iPhone) | 192 (Pro/M-series) | 256 (Mac Pro/Max)
for each chunk of ~64K grid points (memory cap):
    density.predict(chunk, triplane) → density             [progress 35% → 85%, by chunk]
  ↓
marching cubes on Metal (Section: Mesh post-processing)    [progress 85% → 100%]
  ↓
output: MDLMesh with positions + normals + indices (no colors)
```

Triplane stays in CPU/GPU memory as an `MLMultiArray` between density chunks — no per-call upload.

Adaptive resolution by device class (`ProcessInfo.processInfo.physicalMemory`):
- iPhone with < 8GB RAM → 128³
- iPhone with ≥ 8GB RAM, Apple Silicon Mac with M1/M2/M3 base → 192³
- Apple Silicon Mac with Pro/Max/Ultra chip → 256³

Memory budget:
- Triplane: ~40MB FP16.
- Density grid (128³ FP32): ~8MB; (256³ FP32): ~67MB.
- Peak during density chunk inference: a few hundred MB. Stays under 1.5GB total to keep 4GB iPhones safe.
- `MLModel` instances released after generation completes.

Conversion risk (see Risk register): the Phase 0 Python work is the go/no-go gate. The encoder (DINOv1 ViT) is well-trodden. The triplane decoder is medium-risk (custom positional encoding may need tweaks). The density MLP uses `torch.nn.functional.grid_sample` on three planes — supported in recent `coremltools` versions but worth proving early.

## Mesh post-processing & USDZ export

All native Swift / Metal — no ML.

`TripoSRPostProcessor.swift` — Metal marching cubes:
- One compute pass over the density grid; one thread per voxel; standard lookup table.
- Surface threshold from TripoSR reference (`density > 25.0` post-activation), configurable.
- Output: vertex positions in normalized `[-1, 1]` cube space.
- Second compute pass deduplicates vertices on a hashed grid for compactness.
- No mesh simplification in v1 — 128³ grids produce ~30-80K triangles which `Model3DDepthRenderer` handles fine.

`USDZExporter.swift`:
- Positions buffer → `MDLMeshBufferData`.
- Normals: `MDLMesh.addNormals(withAttributeNamed:creaseThreshold:)`.
- Indices → `MDLSubmesh`.
- Assemble `MDLMesh` → `MDLAsset` → `asset.export(to: tempURL.usdz)`.
- Scale by `0.1` so the mesh shows as a ~20cm object in Quick Look (matches Object Capture scale).
- Validate handedness on first preview; flip if SceneKit / `Model3DDepthRenderer` rendering is inverted.

Validation gate (in-process before handing the URL off):
- After `USDZExporter` writes the file, load it through the existing `Model3DLoader`.
- If it can't load, surface an error to the UI; do not save a broken file to the library.

Memory cleanup:
- Release the density grid + triplane after marching cubes (tens of MB).
- Release CoreML models from memory after each generation. First inference of a session pays the load cost; subsequent ones are warm.

## Model distribution

Bundle the three `.mlpackage`s directly in the app. Total ML payload grows from ~48MB (`DepthAnythingV2SmallF16`) to ~190MB — comparable to a mid-size game and well under the 4GB App Store binary cap.

Pros: zero first-run friction, fully offline, matches the existing `DepthAnythingV2SmallF16` pattern.
Cons: bigger install + OTA update size. Acceptable for v1; revisit on-demand download only if install size becomes a real complaint.

## Testing strategy

`PhotoTo3DTests` suite (Swift Testing, in `DepthWeaverTests/`):

1. **End-to-end shape test** — bundle a small reference image. Run the full pipeline. Assert: non-empty `.usdz`; mesh has 1,000–200,000 triangles; bounding box roughly `[-1, 1]³` × scale; `Model3DLoader` can load the produced file (closes the loop).
2. **Cancellation test** — start a generation, cancel mid-way through density-grid sampling. Assert: task exits cleanly, no temp files leaked, models can be re-invoked without state corruption.
3. **Adaptive-resolution smoke test** — for each grid resolution (128 / 192 / 256), run a quick generation and confirm a valid mesh comes out. Conditioned on `ProcessInfo.processInfo.physicalMemory`.

CoreML conversion parity test lives in the *Python conversion repo* (not the Swift test suite): given the same input image, the `.mlpackage`'s triplane output must match the PyTorch reference within `1e-3`. This is the go/no-go gate before merging model updates.

Explicitly not automated:
- Pixel-level visual quality of the mesh (subjective, brittle).
- Reference-mesh regression (high maintenance cost; rely on smoke tests + manual checks instead).
- Inference timing (varies by hardware; tracked as a manual benchmark, not a CI assertion).
- UI flow snapshot testing (not part of the existing test infrastructure; this isn't the moment to introduce it).

Manual release checklist (documented here, not automated):
- Generate from a real photo on iPhone (non-Pro) — under 2 min, mesh loads in `Model3DCaptureView`, stereogram generates from it.
- Generate from same photo on Apple Silicon Mac — under 30s.
- Cancel mid-generation; verify no leaked temp file in `NSTemporaryDirectory()`.
- Generate from a low-quality photo (blurry, off-center subject); verify graceful degradation, not a crash.

## Phasing

- **Phase 0 — Python conversion proof** (separate Python repo, no Swift code yet).
  Convert DINOv1 encoder, triplane decoder, density MLP to `.mlpackage`. Verify per-stage numerical parity with PyTorch reference (`<1e-3`). **GO/NO-GO gate** — if any stage can't be converted and can't be worked around, the feature stops here before we've touched the iOS codebase.
- **Phase 1 — Swift inference scaffolding**. `TripoSRService` (encoder + decoder + chunked density calls), `TripoSRPostProcessor` (Metal marching cubes), `USDZExporter`. Smoke test: produce a non-empty `.usdz` from a hardcoded test image, with `Model3DLoader` round-trip succeeding. No UI yet.
- **Phase 2 — iOS UI**. `PhotoTo3DRootView` + `PhotoTo3DViewModel` state machine, `NavigationDestination.photoTo3DCapture`, photo picker, progress, preview, cancel. Plug into `AppState.pendingCapture`.
- **Phase 3 — macOS parity**. Make `CapturedModelLibrary` cross-platform. Add the sheet flow from `InspectorPanel`. `NSOpenPanel`-based picker.
- **Phase 4 — Polish + ship**. Adaptive grid resolution by device class, OOM recovery, en+fr localization, manual release checklist.

## Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| TripoSR ops unsupported in coremltools | Medium | Phase 0 gate. Fallbacks: re-implement density MLP in Swift/Metal directly; pivot to Hunyuan3D Mini; or pivot to MLX Swift on Apple Silicon only. |
| Inference > 3 min on non-Pro iPhone | Medium | Drop grid to 96³ (blockier mesh, still usable). Floor: 6GB-RAM device gate. |
| OOM on 4GB iPhones | Medium | Smaller chunk size for density sampling. If still OOM, gate to 6GB+ devices (iPhone 12 Pro and newer). |
| Install size complaints (+140MB) | Low | Monitor. Revisit on-demand download if real. |
| TripoSR quality poor on non-object photos (people, landscapes) | High | TripoSR is trained on Objaverse synthetic objects. Scope the feature in UI copy: "works best with photos of a single object on a clean background." Fundamental property of all single-image-to-3D models, not a fixable bug. |
| App Store review skepticism | Low | Privacy disclosures clarify on-device, no network. Lower risk than the existing AI features in the app. |

## References

- TripoSR paper + code: https://github.com/VAST-AI-Research/TripoSR (MIT).
- Modly (image-to-3D desktop app, Python/Electron): inspiration for this feature; their stack is not portable to iOS but their pipeline shape (image → encoder → triplane → marching cubes → mesh export) is what we mirror in native code.
- DepthWeaver `CLAUDE.md`: architecture context for `AppState`, `CapturedModelLibrary`, `GuidedCapture`, `Model3DDepthRenderer`.
