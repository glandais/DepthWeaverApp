# Plan : Calcul du stéréogramme sur GPU (Metal)

## Contexte

Aujourd'hui `Services/StereogramGenerator.swift` fait tout en CPU. Il est parallélisé
par ligne (`DispatchQueue.concurrentPerform(iterations: height)`), mais à
l'intérieur de chaque ligne il y a une boucle séquentielle de longueur
`vwidth = width × oversam` (typiquement 6 000–10 000) qui fait :

1. Le **linking pass** (TIW + élimination de surfaces cachées de Steer) — RMW sur
   deux tableaux `lookL`/`lookR`, dépendance portée par la boucle.
2. L'**application du motif centre→droite** puis **centre→gauche** — copie
   `colour[x] = colour[lookL[x]]`, dépendance portée.
3. Le **remplissage des trous** par dégradé OKLab (`fillEmptyRunsOKLab`).
4. Le **downsample** virtuel→réel par moyenne OKLab (`averageOKLab`).

À 1920×1080 oversam=4, ça fait ~80 millions d'itérations séquentielles à exécuter
sur 6–10 cœurs CPU, ce qui rend l'aperçu live laggy quand on bouge un slider.
Sur Apple GPU on peut exécuter une ligne par thread avec quelques milliers de
threads en vol simultanément — l'algorithme reste le même mais l'occupation
hardware change d'ordre de grandeur. Le downsample OKLab (étape 4) devient en
plus *complètement* data-parallèle (un thread par pixel de sortie).

L'objectif : un nouveau service `MetalStereogramGenerator` qui produit la même
`UIImage` que `StereogramGenerator`, en utilisant deux kernels Metal compute.

## Conception

### Découpage en kernels

Deux kernels Metal compute dans `DepthWeaver/Resources/Shaders/Stereogram.metal` :

**Kernel 1 — `link_and_paint`** (un thread par ligne)

Reproduit lignes 75–150 de `StereogramGenerator.swift` à l'identique :
linking pass + application centre-vers-extérieur + remplissage des trous OKLab.
Toutes ces étapes ont une dépendance portée par x au sein d'une même ligne, donc
on garde la boucle séquentielle dans le kernel ; on parallélise uniquement sur y.

- Grid: `(1, height, 1)`, threadgroup `(1, 64, 1)`.
- Lit : `depthTex` (R32Float), `patternTex` (RGBA8Unorm, sampler `repeat`).
- Écrit : `vColourBuf` (uchar4, taille `vwidth × height`).
- Buffers temporaires `lookLBuf`, `lookRBuf`, `vEmptyBuf` également de taille
  `vwidth × height` — alloués globalement plutôt qu'en threadgroup memory parce
  que `vwidth × (8 + 4 + 1) = ~100 KB` par ligne dépasse la threadgroup memory
  Apple GPU (~32 KB).

**Kernel 2 — `downsample_oklab`** (un thread par pixel de sortie)

Lignes 152–170 du CPU : moyenne OKLab de `oversam` pixels virtuels consécutifs.

- Grid: `(width, height, 1)`, threadgroup `(8, 8, 1)`.
- Lit : `vColourBuf`.
- Écrit : `outputTex` (RGBA8Unorm, taille `width × height`).

### Buffers et textures

| Ressource    | Type                   | Taille                          | Mode storage    |
|--------------|------------------------|---------------------------------|-----------------|
| depthTex     | MTLTexture R32Float    | `width × height`                | shared (upload) |
| patternTex   | MTLTexture RGBA8Unorm  | `patWidth × patHeight`          | shared (upload) |
| lookLBuf     | MTLBuffer Int32        | `vwidth × height × 4 B` (~48 MB)| private         |
| lookRBuf     | MTLBuffer Int32        | idem                            | private         |
| vColourBuf   | MTLBuffer uchar4       | `vwidth × height × 4 B`         | private         |
| vEmptyBuf    | MTLBuffer uchar        | `vwidth × height × 1 B`         | private         |
| outputTex    | MTLTexture RGBA8Unorm  | `width × height`                | shared (readback)|

Les buffers temporaires (`lookL/R`, `vColour`, `vEmpty`) sont conservés sur le
generator pour être réutilisés entre invocations s'ils sont assez grands ; sinon
on réalloue. Pour 1920×1080 oversam=4 ça fait ~150 MB de buffers privés — OK
sur iPhone moderne, à surveiller. Si ça pose problème, on peut packer `lookL/R`
en Int16 (vwidth borné par les paramètres réalistes) pour passer à ~75 MB.

### Uniformes

Une struct `StereogramUniforms` partagée Swift/Metal contient tous les scalaires
(`width`, `height`, `vwidth`, `oversam`, `vmaxsep`, `s`, `poffset`, `maxdepthF`,
`depthRange`, `veyeSepF`, `obsDistF`, `invert`, `patWidth`, `patHeight`,
`yShift`). Passée en `setBytes` aux deux kernels.

### OKLab sur GPU

Les LUT 256-entrées et 4096-entrées du CPU (lignes 276–286) deviennent des
fonctions inline Metal (`pow`, `cbrt` sont natifs et rapides). Les coefficients
de la matrice OKLab (lignes 295–323) restent identiques.

### Lecture du résultat

`outputTex.getBytes(...)` dans un `[UInt8]`, puis on réutilise le helper
`createImage(from:width:height:)` existant. Pas de besoin de zero-copy via
`CVPixelBuffer` au départ.

### Repli CPU

Si `MTLCreateSystemDefaultDevice()` échoue ou qu'un pipeline ne se compile pas,
on délègue à `StereogramGenerator().generate(depthMap:settings:)` (le code CPU
existant reste intact).

## Étapes d'implémentation

1. **Refactoriser les helpers partagés** dans `Services/StereogramGenerator.swift` :
   - Sortir `preparePattern(_:targetWidth:)` et `createImage(from:width:height:)`
     en fonctions internes (`internal` ou `fileprivate static`) accessibles
     depuis le nouveau fichier. Pas de changement de comportement.
   - Pas toucher au reste de l'algorithme CPU — il reste le fallback.

2. **Créer `DepthWeaver/Resources/Shaders/Stereogram.metal`** avec :
   - Struct `StereogramUniforms` matchant le layout Swift (`packed_int4` /
     `packed_float4` selon le besoin, ou simplement champs alignés).
   - Helpers OKLab inline : `srgb_to_linear`, `linear_to_srgb`,
     `srgb_byte_to_oklab(uchar3)`, `oklab_to_srgb_byte(float3)`.
   - `kernel void link_and_paint(...)` portant lignes 64–150 de
     `StereogramGenerator.swift`. Les boucles internes sont identiques (Swift
     `for` → Metal `for`). Indexation des buffers globaux : `y * vwidth + x`.
   - `kernel void downsample_oklab(...)` portant lignes 152–170.

3. **Ajouter le `.metal` au build phase Xcode** :
   - Dans `DepthWeaver.xcodeproj/project.pbxproj`, ajouter `Stereogram.metal` à
     la "Compile Sources" build phase de la cible DepthWeaver. Xcode produira
     automatiquement `default.metallib` ; pas besoin d'ajouter Metal.framework
     à "Link Binary With Libraries" (auto-link).

4. **Créer `DepthWeaver/Services/MetalStereogramGenerator.swift`** :
   - `final class MetalStereogramGenerator` exposant
     `func generate(depthMap: DepthMap, settings: StereogramSettings) -> UIImage`.
   - Init paresseuse de `MTLDevice`, `MTLCommandQueue`,
     `MTLComputePipelineState` x2 via `device.makeDefaultLibrary()`. Si ces
     init échouent, le service tient un flag `isAvailable = false` et délègue
     au CPU.
   - Cache des textures/buffers temporaires entre appels (réalloc seulement
     quand la taille change).
   - Calcule les mêmes scalaires que le CPU (lignes 9–62), construit
     `StereogramUniforms`, upload `depthTex` (à partir de
     `depthMap.adjustedDepthValues(width:height:)`) et `patternTex` (réutilise
     `preparePattern` extrait à l'étape 1).
   - Encode kernel 1 puis kernel 2 dans le même command buffer ; commit +
     waitUntilCompleted.
   - `outputTex.getBytes` → `[UInt8]` → `createImage(from:width:height:)`
     (helper extrait à l'étape 1).
   - Fallback CPU sur toute erreur (pipeline state nul, command buffer.error,
     etc.) avec `os.Logger`.

5. **Brancher le générateur GPU** dans `ViewModels/StereogramViewModel.swift` :
   remplacer l'instanciation actuelle de `StereogramGenerator()` par
   `MetalStereogramGenerator.shared`. Le service GPU contient déjà son propre
   fallback CPU, donc le ViewModel n'a aucune logique à changer.

## Fichiers à modifier / créer

- `DepthWeaver/Services/StereogramGenerator.swift` — extraire `preparePattern`
  et `createImage` (refactor sans changement comportemental).
- `DepthWeaver/Resources/Shaders/Stereogram.metal` (NEW).
- `DepthWeaver/Services/MetalStereogramGenerator.swift` (NEW).
- `DepthWeaver/ViewModels/StereogramViewModel.swift` — switch d'instanciation.
- `DepthWeaver.xcodeproj/project.pbxproj` — ajouter les nouvelles sources et la
  compilation du `.metal`.

## Précédents à réutiliser

- `Services/Model3DDepthRenderer.swift` (lignes 28–95, 119–148) : pattern
  d'init `MTLDevice`/`MTLCommandQueue`, allocation de textures avec
  storage modes, blit encoder, `cmdBuf.waitUntilCompleted()`. Précédent direct
  pour la nouvelle classe.
- `Models/DepthMap.swift` `adjustedDepthValues(width:height:)` (lignes
  161–188) : reste la source du depth uploadé en R32Float. (Une étape future
  pourrait porter ce resampling lui-même en kernel.)
- `Services/StereogramGenerator.swift` `preparePattern` (lignes 184–216) et
  `createImage` (lignes 391–414) : extraits et réutilisés tels quels.

## Vérification

End-to-end :

1. **Build** : ouvrir `DepthWeaver.xcodeproj`, build sur simulateur iOS et sur
   appareil physique. Vérifier que `Stereogram.metal` apparaît dans
   "Compile Sources" et que `default.metallib` est produit.
2. **Diff visuel CPU vs GPU** : ajouter un test ad-hoc (ou un toggle debug
   temporaire) qui génère le même stéréogramme via les deux paths pour un
   `DepthMap` fixe (e.g. la preset `Resources/HeightMaps/`) et un pattern
   asset, oversam=1 puis oversam=4. Diff pixel-à-pixel attendu : écart
   ≤ 2/255 par canal (différences de rounding cbrt vs LUT, et ordre de sommation
   en OKLab).
3. **Tests fonctionnels** dans l'app :
   - Live preview en faisant glisser `depthStrength`, `sepFactor`,
     `oversampling` — le preview doit suivre sans lag perceptible.
   - Tester chaque `PatternSource` : asset, chaque `ProceduralPatternType`,
     `imported` (sélection photo).
   - Tester chaque `Source` de depth : `lidar`, `depthAnything`, `imported`,
     `model3D` — y compris depth maps avec NaN (modèle 3D capturé) et
     petites depth maps LiDAR (256×192 upscalées vers 960).
   - Tester le invert flag.
   - Vérifier que `vmaxsep ≥ vwidth` (settings extrêmes) renvoie toujours une
     `UIImage` vide comme avant.
4. **Repli CPU** : forcer l'échec d'init Metal (e.g. en commentant la création
   du pipeline) et vérifier que l'app fonctionne toujours via le path CPU.
5. **Performance** : mesurer le wall-clock de `generate(...)` pour 1920×1080
   oversam=4 sur device — gain attendu 5–20× selon GPU.
