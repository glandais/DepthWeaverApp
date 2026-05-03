# Mapped Texture Stereograms (MTS)

Investigation notes for adding an MTS pattern mode to DepthWeaver.

## Source

- https://www.hidden-3d.com/stereogram_lab_mts.php — Stereogram Lab MTS 1.0 (Windows, free), the desktop app credited as the first to render MTS automatically. Used by 3dimka and Gary W. Priester. The site itself has no algorithm details.
- Algorithm description below comes from a community forum explanation (paraphrased), not from the website.

## What MTS is

A stereogram where the encoded image is **colored** — chains inherit the seed pixel's color from a registered color image, so duplicates look like colored silhouettes of the scene rather than a tiled abstract pattern. This is the "3dimka look": crisp edges, sparse painterly fills, recognizable colors preserved across repeats.

Two inputs:
- 2D color image (the "color map")
- Registered depth map (Z-buffer) — same dimensions, pixel-aligned

## Algorithm (per seed)

Given seed pixel `(sx, sy)` with color `C = colorImage(sx, sy)`:

1. Compute parallax `sep` from `depth(sx, sy)` using the standard eye-geometry formula:
   `sep = eyeSep · featureZ / (featureZ + obsDist)`
2. Plot `C` at `xL = sx − sep/2` and `xR = sx + sep/2` on row `sy`.
3. **Extend left:** cast a ray from the right eye through screen-plane point `xL`. March the heightfield (= depth map as 1D per row). First hit `H` → project `H` through the left eye onto the screen plane → next `xL`. Plot `C`. Repeat until off-screen or the ray misses the heightfield (no hit ⇒ chain terminates, producing a silhouette edge).
4. **Extend right:** mirror, swap the eyes.

Per-row independent (same horizontal-baseline assumption as the existing TIW/Steer code).

### Why edges are crisp

A chain dies the moment a ray fails to hit the heightfield. There is no "fade" or "wrap" at the silhouette — the next-pixel's chain simply stops. That's structurally different from pattern-tile stereograms, where every output pixel is filled.

### Why colors are preserved

All points on a chain wear the **seed's** color, not the color sampled at each ray-hit. Every duplicate is therefore a colored copy of the same seed point. Across many seeds, the original image is reconstructed N times across the canvas, once per stereogram repeat.

## How it differs from the current generator

`StereogramGenerator.swift` (Steer / Thimbleby–Inglis–Witten) is a **dense per-row link scan**:
- Every output pixel gets a color
- Pattern is unrelated to the depth map (tiled bitmap or procedural)
- Hidden-surface removal via the `lookL` / `lookR` link tables

MTS is a **sparse seed-and-chain splatter**:
- Output starts blank; only seed-driven chains get plotted
- Pattern *is* the registered color image
- Hidden surfaces handled implicitly via heightfield ray-marching (no hit ⇒ stop)

The two cannot share `linkingPass`. MTS needs its own generator.

## Integration plan for DepthWeaver

### Models
- `PatternSource.swift`: add `.mappedTexture(UIImage)` — the registered color image, same dims as the depth map (or resampled to match). Gate availability on depth sources that have a paired RGB: `.lidar`, `.depthAnything`, `.model3D`. Hide for `.imported` (no associated photo).

### Services
- New `Services/MTSStereogramGenerator.swift`. Same public shape as `StereogramGenerator.generate(depthMap:settings:)`. Per-row `concurrentPerform`. Components:
  - **Seed sampler** — picks `(sx, sy)` positions
  - **Heightfield ray-marcher** — per-row ray vs. depth profile
  - **Chain plotter** — writes seeded color into output buffer

### ViewModel routing
- `StereogramViewModel`: route `.mappedTexture` to `MTSStereogramGenerator`; all other `PatternSource` cases continue through `StereogramGenerator`.

## Open design questions

### Seed strategy

The desktop app is interactive (user paints seeds). DepthWeaver has no painting UI, so seeds must be generated automatically. Three options:

| Strategy | Aesthetic | Effort |
|---|---|---|
| Uniform random / Poisson-disc | Even dot cloud, like the canonical screenshot | Lowest |
| Edge-weighted (Sobel on depth) | Sharp silhouettes, sparse interiors — the 3dimka signature | Medium |
| Dense grid (every pixel) | Fully filled image-as-pattern; closer to traditional MTS textbook output | Easy but loses the painterly quality |

Recommended first cut: uniform random with a `seedDensity` slider. Add edge-weighted as a follow-up — that's where the visual payoff is.

### Geometry consistency

The forum description talks about true 3D raycasting from two eye positions. The existing per-row 1D parallax model (`sep = eyeSep · z / (z + obsDist)`) is an approximation that's accurate enough because the eye baseline is horizontal. Sticking to the 1D per-row model keeps MTS consistent with the rest of the pipeline and keeps row-parallelism trivial. Worth flagging as a deliberate simplification.

### Background

MTS output has empty space where no chain reaches. Decide:
- Pure black (matches the canonical screenshot)
- Background color from `colorImage` outside the foreground mask
- A faint procedural fill so pure-flat regions still have viewable depth cues

### Depth/seed coupling

Seeds at NaN-depth pixels (cleared regions in `Model3DDepthRenderer`) must be skipped — they have no valid `featureZ`.

## Pointers in current code

- `Services/StereogramGenerator.swift:218–272` — `linkingPass`, the per-row HSR scan that MTS replaces with chain extension
- `Services/StereogramGenerator.swift:43` — eye-geometry constants (`eyeSep`, `obsDist`, `vmaxsep`, `oversam`) — reuse the same formulas in MTS
- `Models/DepthMap.swift` — `adjustedDepthValues(width:height:)` is the canonical normalized depth array; MTS reads from the same source
- `Models/PatternSource.swift:3` — extension point for the new `.mappedTexture` case
