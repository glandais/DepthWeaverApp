# Migration DepthWeaver iOS → Flutter (cross-platform)

## Contexte

DepthWeaver est aujourd'hui une app iOS SwiftUI (iOS 17+, ~9 000 LOC Swift sur 65 fichiers) qui génère des autostéréogrammes à partir de depth maps. Elle s'appuie massivement sur des frameworks Apple-only : ARKit/LiDAR, CoreML (DepthAnythingV2 48 Mo), SceneKit + Metal (rendu 3D + extraction depth), Core Image (denoising), RealityKit `ObjectCaptureSession` (scan photogrammétrique guidé).

L'objectif validé est une **migration cross-platform iOS + Android sous Flutter**, avec :
- Une inférence depth disponible des deux côtés (CoreML iOS + TFLite Android, abstraction Dart commune)
- Le rendu 3D via plugins natifs et PlatformViews (SceneKit iOS, Filament/SceneView Android)
- Les fonctions intrinsèquement Apple (LiDAR, ObjectCapture) maintenues côté iOS et conditionnellement masquées sur Android (ou remplacées en v1.1)

Ce plan formalise l'architecture cible, la liste des plugins natifs à écrire, le phasage et les pièges techniques. Il propose un **MVP cross-platform de 9–16 semaines** couvrant ~85% de l'usage actuel, en différant LiDAR / ObjectCapture / Android-3D à une v1.1.

## Architecture cible

### Monorepo Melos

```
depthweaver/
  app/                              # Flutter app shell (main, routing, l10n)
  packages/
    depth_core/                     # Pure Dart : DepthMap, DepthAdjustment,
                                    #   DepthDenoising, StereogramSettings,
                                    #   PatternSource, presets, types
    stereogram_engine/              # Pure Dart : StereogramGenerator (isolates),
                                    #   OKLab, fillEmptyRuns, downsample
    procedural_patterns/            # Pure Dart : Perlin, Worley, Voronoi,
                                    #   ReactionDiffusion, Stars, RandomDot
    depth_denoiser/                 # Pure Dart : pipeline median + bilateral
                                    #   + morphology + blend
    ui_kit/                         # Widgets partagés, theming, l10n ARB
  plugins/
    depthanything_plugin/           # Federated : iOS CoreML / Android TFLite
    depth_capture_plugin/           # iOS LiDAR (ARKit) ; Android stub
    model3d_viewer_plugin/          # PlatformView SceneKit / Filament
    object_capture_plugin/          # iOS-only ; Android stub `unsupported`
```

Justification : le pur Dart (CPU bound, testable hors device, isolates 3.x) doit rester séparé des plugins natifs fédérés. Cela permet des stubs par plateforme propres (pas de `#if os(iOS)` partout) et une CI rapide sur les packages logiques.

### State management — Riverpod

`flutter_riverpod` 2.x + `riverpod_generator` + `freezed`. Le flux actuel est un **graphe de dérivations** (`depthMap × settings → stereogram`, debounce inclus), pas un flux event-sourced — Riverpod est plus naturel que BLoC, et offre `family` + autodispose granulaire que Provider n'a pas.

Mapping :
- `@StateObject StereogramViewModel` → `AsyncNotifierProvider<StereogramNotifier, Uint8List?>`
- `@Published currentDepthMap` → `StateProvider<DepthMap?>`
- `onChange(of: depthMap?.adjustment) → triggerGeneration()` → simple `ref.watch` côté `stereogramProvider`
- Debounce 1 s → helper `ref.debounce(...)` ou `Future.delayed` + `ref.onDispose`

### SwiftUI → Flutter

| SwiftUI | Flutter |
|---|---|
| `NavigationStack` + `NavigationDestination` | `go_router` 14.x avec routes typées |
| `@StateObject` / `@Published` / `@Binding` | `Notifier`/`AsyncNotifier` Riverpod |
| `.sheet(isPresented:)` | `showModalBottomSheet` ou route `pushSheet` |
| `UIViewRepresentable` (SceneKit, ARKit) | `UiKitView` (iOS) + `AndroidView` (Filament), encapsulés dans plugin |
| `PhotosPicker`, `.fileImporter` | `image_picker`, `file_picker` |
| `Localizable.xcstrings` | ARB + `flutter_localizations` + `intl_utils` |
| `Task.detached` / `concurrentPerform` | `Isolate.run` + `TransferableTypedData` (zero-copy) |

## Plugins natifs

| Plugin | iOS | Android | Reco |
|---|---|---|---|
| `depthanything_plugin` | CoreML (.mlpackage existant) | TFLite (modèle reconverti depuis le checkpoint PyTorch d'origine) | **Critique** |
| `depth_capture_plugin` | ARKit `sceneDepth` (port `LiDARDepthService.swift`) | stub `unsupported` (ARCore Depth Play Services hors v1) | **Critique iOS** |
| `model3d_viewer_plugin` | `SCNView` + Metal (port `Model3DDepthRenderer.swift`) | Filament via `playx_3d_scene` ou wrapper custom | **Critique** |
| `object_capture_plugin` | RealityKit `ObjectCaptureSession` (wrapper du sample `GuidedCapture`) | stub `unsupported` | **iOS-only v1** |
| ~~`depth_denoiser_plugin`~~ | — | — | **À ne pas écrire** : pipeline reproductible en Dart pur (~400 LOC), perf cible 80–120 ms à 256×192 ; fallback FFI OpenCV si insuffisant |

Communication via `MethodChannel` ; pour les transferts d'image (518×392×4 ≈ 800 KiB par inférence), `Pigeon` + `dart:ffi` zero-copy si latence problématique.

## Fichiers iOS critiques à porter

- `Services/StereogramGenerator.swift` (415 LOC) — algorithme cœur, 50 % portable, parallélisme à passer en isolates
- `Services/DepthAnythingService.swift` (144 LOC) — port direct dans le plugin iOS
- `Services/LiDARDepthService.swift` (299 LOC) — port direct dans `depth_capture_plugin/ios`
- `Services/Model3DDepthRenderer.swift` (~289 LOC) + `Model3DLoader.swift` — port iOS dans `model3d_viewer_plugin`, équivalent Android via Filament
- `Services/DepthMapDenoiser.swift` (175 LOC) — **réécrire en Dart pur** dans `packages/depth_denoiser`
- `Services/Generators/*.swift` (730 LOC, 6 fichiers) — port Dart 1-pour-1 dans `procedural_patterns`
- `Models/DepthMap.swift` (282 LOC) — port Dart, math 100 % portable, `CVPixelBuffer` extraction → côté plugin
- `Views/GenerationView.swift` (615 LOC) — réécriture Flutter
- `Views/Model3DCaptureView.swift` (420 LOC), `ProceduralParamsView.swift` (396 LOC), `DepthAdjustmentView.swift` (185 LOC), `LiDARCaptureView.swift` (148 LOC), `StereogramResultView.swift` (188 LOC), `DepthPointCloudView.swift` (124 LOC) — réécriture Flutter ; `DepthPointCloud` et `Model3DScene` deviennent PlatformViews
- `Features/GuidedCapture/*` (3 354 LOC, 18 fichiers) — wrapper minimal côté `object_capture_plugin/ios` ; UI guidée réécrite en Flutter par-dessus
- `Resources/Localizable.xcstrings` (2 537 clés en+fr) — script Python `xcstrings → ARB` (1 j de script + 1 j de QA)
- `Resources/HeightMaps/`, `Resources/Patterns/` — réutilisés tels quels comme assets Flutter
- `Resources/Models3D/*.usdz` — conversion **batch USDZ → glTF/GLB** (Filament Android ne lit pas USDZ) ; conserver les deux formats, sélection runtime
- `Resources/DepthAnythingV2SmallF16.mlpackage` (48 Mo) — conservé iOS ; pour Android, repartir du checkpoint PyTorch (LiheYoung/depth-anything-v2-small) et exporter directement en TFLite via `ai-edge-torch` (évite les ennuis d'opérateurs `Resize`/`LayerNorm` du chemin coremltools→onnx→tflite)

## Phasage

| # | Phase | Optimiste | Pessimiste | MVP |
|---|---|---|---|---|
| 1 | Bootstrap Melos + logique pure (`depth_core`, `stereogram_engine`, `procedural_patterns`, `depth_denoiser`) avec **tests golden pixel-à-pixel** vs sortie Swift | 12 j | 20 j | ✅ |
| 2 | UI + navigation + l10n (`go_router`, theming, GenerationScreen, sliders, presets, import photo) | 12 j | 20 j | ✅ |
| 3 | Plugin DepthAnything (CoreML iOS + TFLite Android) | 10 j | 18 j | ✅ |
| 4 | Capture LiDAR iOS + UI ARKit overlay | 6 j | 10 j | ⏭ v1.1 |
| 5 | Rendu 3D : iOS SceneKit + extraction Metal ; Android Filament | 12 j | 20 j | ✅ iOS / ⏭ Android v1.1 |
| 6 | Object Capture (port wrapper Apple sample) | 10 j | 18 j | ⏭ v1.1, iOS-only |
| | **MVP cross-platform (1+2+3+5 iOS)** | **46 j** | **78 j** | |
| | **Full parity iOS + Android dégradé** | 62 j | 106 j | |

Inversion possible : si MVP Android prioritaire, faire la phase 3 dès J15 (avant l'UI complète) pour valider tôt l'inférence cross-platform.

## Pièges techniques (par ordre de douleur)

1. **Conversion CoreML → TFLite/ONNX**. Repartir du checkpoint PyTorch d'origine plutôt que `coremltools→onnx→tflite` (opérateurs `Resize` linéaire et `LayerNorm` divergent). Garder `.mlpackage` côté iOS.
2. **Isolates Dart vs `DispatchQueue.concurrentPerform`**. Bench attendu : 1.2–1.5× plus lent que Swift sur iOS, équivalent sur Android haut de gamme. Utiliser `Isolate.run` + `TransferableTypedData` zero-copy, découper en `Platform.numberOfProcessors` isolates.
3. **`.xcstrings` → ARB** (2 537 clés). Script Python parsant `localizations.fr.stringUnit.value`, émettant ARB ; placeholders `\(value)` → `{value}`, `varied(.plural)` → ICU MessageFormat.
4. **Bundle 97 Mo Android**. Play Asset Delivery (`install-time`) pour `Models3D/` et le modèle TFLite ; CoreML embarqué iOS uniquement. Cible APK base ~20 Mo + packs.
5. **USDZ → glTF Android obligatoire**. Conversion batch via `usdcat`/Reality Composer ; vérifier les matériaux PBR. Stocker les deux formats.
6. **Debounce slider Riverpod**. Sans debounce explicite entre `settingsProvider` et `stereogramProvider`, on déclenche 30+ régénérations/s sur drag — reproduire la stratégie actuelle.
7. **Filament + PlatformView Android**. Cycle de vie `Surface` complexe, prévoir 5 j de debug.

## Vérification

- **Tests unitaires golden** sur `stereogram_engine` et `procedural_patterns` : produire un fichier de sortie binaire pixel-à-pixel comparé à un dump Swift de référence (tolérance ±1 LSB en OKLab) sur ≥10 fixtures (heightmap × pattern × settings)
- **Tests d'intégration** Riverpod sur le flux `depthMap × settings → stereogram` (debounce, invalidation, autodispose)
- **Bench device-réel** : phase 3, mesurer latence DepthAnything sur iPhone 13 (cible ≤ 200 ms) et un Android milieu de gamme (cible ≤ 500 ms)
- **Test cross-platform manuel** : phase 5, charger les 6 USDZ/GLB sur iOS et Android, vérifier rendu point cloud + extraction depth identique (±2 % MSE)
- **QA visuelle l10n** : phase 2, vérifier en+fr sur tous les écrans après migration ARB
- **CI** : `flutter test` par package (Melos `melos run test`), `flutter build ios --release` et `flutter build appbundle --release`, taille de bundle vérifiée en CI (alerter si > 25 Mo base)
- **Validation MVP utilisateur** : tester le golden path photo → DepthAnything → preview stereogram → partage sur iPhone et un Android cible avant ouverture beta
