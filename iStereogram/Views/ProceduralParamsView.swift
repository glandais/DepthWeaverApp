import SwiftUI

struct ProceduralParamsView: View {
    let type: ProceduralPatternType
    @Binding var config: ProceduralConfig
    let previewImage: UIImage?
    let isGenerating: Bool

    var body: some View {
        VStack(spacing: 12) {
            // Live preview
            ZStack {
                if let image = previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .aspectRatio(1, contentMode: .fit)
                }

                if isGenerating {
                    ProgressView()
                        .scaleEffect(1.2)
                }
            }
            .frame(height: 128)

            // Type-specific parameters
            parameterSliders

            // Randomize button
            Button {
                randomize()
            } label: {
                Label(String(localized: "Randomize", comment: "Button"), systemImage: "dice")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var parameterSliders: some View {
        switch config {
        case .randomDot(var c):
            randomDotParams(config: c) { c = $0; config = .randomDot(c) }
        case .perlin(var c):
            perlinParams(config: c) { c = $0; config = .perlin(c) }
        case .worley(var c):
            worleyParams(config: c) { c = $0; config = .worley(c) }
        case .voronoi(var c):
            voronoiParams(config: c) { c = $0; config = .voronoi(c) }
        case .reactionDiffusion(var c):
            reactionDiffusionParams(config: c) { c = $0; config = .reactionDiffusion(c) }
        }
    }

    // MARK: - Random Dot

    private func randomDotParams(config: RandomDotConfig, update: @escaping (RandomDotConfig) -> Void) -> some View {
        VStack(spacing: 8) {
            paramSlider(
                label: String(localized: "Density", comment: "Parameter"),
                value: config.density,
                range: 0.1...1.0,
                format: "%.2f"
            ) { var c = config; c.density = Float($0); update(c) }

            paramSlider(
                label: String(localized: "Dot Size", comment: "Parameter"),
                value: Float(config.dotSize),
                range: 1...5,
                step: 1,
                format: "%.0f"
            ) { var c = config; c.dotSize = Int($0); update(c) }

            enumPicker(
                label: String(localized: "Colors", comment: "Parameter"),
                selection: config.colorMode,
                displayName: \.displayName
            ) { var c = config; c.colorMode = $0; update(c) }
        }
    }

    // MARK: - Perlin Noise

    private func perlinParams(config: PerlinConfig, update: @escaping (PerlinConfig) -> Void) -> some View {
        VStack(spacing: 8) {
            paramSlider(
                label: String(localized: "Frequency", comment: "Parameter"),
                value: config.frequency,
                range: 0.001...0.05,
                format: "%.3f"
            ) { var c = config; c.frequency = Float($0); update(c) }

            paramSlider(
                label: String(localized: "Octaves", comment: "Parameter"),
                value: Float(config.octaves),
                range: 1...8,
                step: 1,
                format: "%.0f"
            ) { var c = config; c.octaves = Int($0); update(c) }

            paramSlider(
                label: String(localized: "Persistence", comment: "Parameter"),
                value: config.persistence,
                range: 0.1...1.0,
                format: "%.2f"
            ) { var c = config; c.persistence = Float($0); update(c) }

            enumPicker(
                label: String(localized: "Colors", comment: "Parameter"),
                selection: config.colorMode,
                displayName: \.displayName
            ) { var c = config; c.colorMode = $0; update(c) }

            if config.colorMode == .hue {
                paramSlider(
                    label: String(localized: "Hue", comment: "Parameter"),
                    value: config.hue,
                    range: 0...1,
                    format: "%.2f"
                ) { var c = config; c.hue = Float($0); update(c) }
            }
        }
    }

    // MARK: - Worley Noise

    private func worleyParams(config: WorleyConfig, update: @escaping (WorleyConfig) -> Void) -> some View {
        VStack(spacing: 8) {
            paramSlider(
                label: String(localized: "Cell Size", comment: "Parameter"),
                value: config.cellSize,
                range: 20...150,
                format: "%.0f px"
            ) { var c = config; c.cellSize = Float($0); update(c) }

            enumPicker(
                label: String(localized: "Distance", comment: "Parameter"),
                selection: config.distanceFunction,
                displayName: \.displayName
            ) { var c = config; c.distanceFunction = $0; update(c) }

            enumPicker(
                label: String(localized: "Mode", comment: "Parameter"),
                selection: config.combineMode,
                displayName: \.displayName
            ) { var c = config; c.combineMode = $0; update(c) }

            Toggle(String(localized: "Invert", comment: "Parameter"), isOn: Binding(
                get: { config.invertLuminance },
                set: { var c = config; c.invertLuminance = $0; update(c) }
            ))
            .font(.subheadline)
        }
    }

    // MARK: - Voronoi

    private func voronoiParams(config: VoronoiConfig, update: @escaping (VoronoiConfig) -> Void) -> some View {
        VStack(spacing: 8) {
            paramSlider(
                label: String(localized: "Cell Count", comment: "Parameter"),
                value: Float(config.cellCount),
                range: 4...40,
                step: 1,
                format: "%.0f"
            ) { var c = config; c.cellCount = Int($0); update(c) }

            paramSlider(
                label: String(localized: "Jitter", comment: "Parameter"),
                value: config.jitter,
                range: 0...1,
                format: "%.2f"
            ) { var c = config; c.jitter = Float($0); update(c) }

            paramSlider(
                label: String(localized: "Edge Width", comment: "Parameter"),
                value: config.edgeWidth,
                range: 0...5,
                format: "%.1f px"
            ) { var c = config; c.edgeWidth = Float($0); update(c) }

            enumPicker(
                label: String(localized: "Color Scheme", comment: "Parameter"),
                selection: config.colorScheme,
                displayName: \.displayName
            ) { var c = config; c.colorScheme = $0; update(c) }
        }
    }

    // MARK: - Reaction-Diffusion

    private func reactionDiffusionParams(config: ReactionDiffusionConfig, update: @escaping (ReactionDiffusionConfig) -> Void) -> some View {
        VStack(spacing: 8) {
            paramSlider(
                label: String(localized: "Feed Rate (F)", comment: "Parameter"),
                value: config.feedRate,
                range: 0.01...0.1,
                format: "%.3f"
            ) { var c = config; c.feedRate = Float($0); update(c) }

            paramSlider(
                label: String(localized: "Kill Rate (k)", comment: "Parameter"),
                value: config.killRate,
                range: 0.04...0.07,
                format: "%.3f"
            ) { var c = config; c.killRate = Float($0); update(c) }

            paramSlider(
                label: String(localized: "Iterations", comment: "Parameter"),
                value: Float(config.iterations),
                range: 500...5000,
                step: 100,
                format: "%.0f"
            ) { var c = config; c.iterations = Int($0); update(c) }

            HStack {
                Text(String(localized: "Color A", comment: "Parameter"))
                    .font(.subheadline)
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { config.colorA.color },
                    set: { var c = config; c.colorA = CodableColor(color: $0); update(c) }
                ))
                .labelsHidden()
            }

            HStack {
                Text(String(localized: "Color B", comment: "Parameter"))
                    .font(.subheadline)
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { config.colorB.color },
                    set: { var c = config; c.colorB = CodableColor(color: $0); update(c) }
                ))
                .labelsHidden()
            }
        }
    }

    // MARK: - Randomize

    private func randomize() {
        let newSeed = UInt64.random(in: 1...UInt64.max)
        switch config {
        case .randomDot(var c):
            c.seed = newSeed
            c.density = Float.random(in: 0.1...1.0)
            c.dotSize = Int.random(in: 1...5)
            c.colorMode = PatternColorMode.allCases.randomElement()!
            config = .randomDot(c)
        case .perlin(var c):
            c.seed = newSeed
            c.frequency = Float.random(in: 0.001...0.05)
            c.octaves = Int.random(in: 1...8)
            c.persistence = Float.random(in: 0.1...1.0)
            c.colorMode = PerlinColorMode.allCases.randomElement()!
            c.hue = Float.random(in: 0...1)
            config = .perlin(c)
        case .worley(var c):
            c.seed = newSeed
            c.cellSize = Float.random(in: 20...150)
            c.distanceFunction = DistanceFunction.allCases.randomElement()!
            c.combineMode = WorleyCombineMode.allCases.randomElement()!
            c.invertLuminance = Bool.random()
            config = .worley(c)
        case .voronoi(var c):
            c.seed = newSeed
            c.cellCount = Int.random(in: 4...40)
            c.jitter = Float.random(in: 0...1)
            c.edgeWidth = Float.random(in: 0...5)
            c.colorScheme = VoronoiColorScheme.allCases.randomElement()!
            config = .voronoi(c)
        case .reactionDiffusion(var c):
            c.seed = newSeed
            // Pick from known-good parameter regions
            let presets: [(Float, Float)] = [
                (0.035, 0.065),  // Spots
                (0.029, 0.057),  // Labyrinth
                (0.018, 0.051),  // Waves
                (0.055, 0.062),  // Mitosis
            ]
            let preset = presets.randomElement()!
            c.feedRate = preset.0 + Float.random(in: -0.003...0.003)
            c.killRate = preset.1 + Float.random(in: -0.002...0.002)
            c.iterations = Int.random(in: 1000...4000)
            config = .reactionDiffusion(c)
        }
    }

    // MARK: - Helpers

    private func paramSlider(
        label: String,
        value: Float,
        range: ClosedRange<Float>,
        step: Float? = nil,
        format: String,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label): \(String(format: format, value))")
                .font(.subheadline)
            if let step {
                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { onChange($0) }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: Double(step)
                )
            } else {
                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { onChange($0) }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound)
                )
            }
        }
    }

    private func enumPicker<E: CaseIterable & Hashable>(
        label: String,
        selection: E,
        displayName: KeyPath<E, String>,
        onChange: @escaping (E) -> Void
    ) -> some View where E.AllCases: RandomAccessCollection {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Picker(label, selection: Binding(
                get: { selection },
                set: { onChange($0) }
            )) {
                ForEach(Array(E.allCases), id: \.self) { item in
                    Text(item[keyPath: displayName]).tag(item)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}
