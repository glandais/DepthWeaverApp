#if os(macOS)
import SwiftUI

struct InspectorPanel: View {
    @Binding var settings: StereogramSettings
    @Binding var depthMap: DepthMap?
    @ObservedObject var patternPreview: PatternPreviewViewModel
    let onPickPhoto: () -> Void
    let onPick3DModel: () -> Void
    let onPickPattern: () -> Void

    @AppStorage("inspector.source.expanded")    private var sourceExpanded   = true
    @AppStorage("inspector.pattern.expanded")   private var patternExpanded  = true
    @AppStorage("inspector.depth.expanded")     private var depthExpanded    = false
    @AppStorage("inspector.settings.expanded")  private var settingsExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DisclosureGroup(isExpanded: $sourceExpanded) {
                    DepthSourceSection(
                        depthMap: $depthMap,
                        onPickPhoto: onPickPhoto,
                        onPick3DModel: onPick3DModel
                    )
                    .padding(.top, 6)
                } label: {
                    sectionLabel("inspector.section.source", systemImage: "photo.on.rectangle")
                }

                Divider()

                DisclosureGroup(isExpanded: $patternExpanded) {
                    PatternSection(
                        settings: $settings,
                        patternPreview: patternPreview,
                        onPickPattern: onPickPattern
                    )
                    .padding(.top, 6)
                } label: {
                    sectionLabel("inspector.section.pattern", systemImage: "square.grid.3x3")
                }

                Divider()

                DisclosureGroup(isExpanded: $depthExpanded) {
                    DepthAdjustmentSection(depthMap: $depthMap)
                        .padding(.top, 6)
                } label: {
                    sectionLabel("inspector.section.depth", systemImage: "slider.horizontal.below.rectangle")
                }

                Divider()

                DisclosureGroup(isExpanded: $settingsExpanded) {
                    StereogramSettingsSection(settings: $settings)
                        .padding(.top, 6)
                } label: {
                    sectionLabel("inspector.section.settings", systemImage: "slider.horizontal.3")
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func sectionLabel(_ key: LocalizedStringKey, systemImage: String) -> some View {
        Label(key, systemImage: systemImage)
            .font(.headline)
    }
}

// MARK: - Source

struct DepthSourceSection: View {
    @Binding var depthMap: DepthMap?
    let onPickPhoto: () -> Void
    let onPick3DModel: () -> Void

    @State private var showPresets = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let dm = depthMap {
                DepthPointCloudView(depthMap: dm, adjustment: dm.adjustment)
                    .aspectRatio(CGFloat(dm.width) / CGFloat(dm.height), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    let (label, icon): (String, String) = {
                        switch dm.source {
                        case .lidar: ("LiDAR", "camera.metering.matrix")
                        case .imported: (String(localized: "depth.source_imported"), "square.and.arrow.down")
                        case .model3D: (String(localized: "depth.source_3d_model"), "cube")
                        case .depthAnything: (String(localized: "depth.source_ai"), "photo.on.rectangle")
                        }
                    }()
                    Label(label, systemImage: icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: "\(dm.width) × \(dm.height)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Button {
                        showPresets = true
                    } label: {
                        Label("depth.presets", systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onPickPhoto()
                    } label: {
                        Label("depth.from_photo", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                GridRow {
                    Button {
                        onPick3DModel()
                    } label: {
                        Label("depth.from_3d_model", systemImage: "cube")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .gridCellColumns(2)
                }
            }
        }
        .sheet(isPresented: $showPresets) {
            HeightMapPresetSheet { preset in
                depthMap = preset.toDepthMap()
                showPresets = false
            }
            .frame(minWidth: 520, minHeight: 480)
        }
    }
}

struct HeightMapPresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (DepthMapPreset) -> Void

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("depth.presets_title")
                    .font(.headline)
                Spacer()
                Button("general.done") { dismiss() }
            }
            .padding()
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(DepthMapPreset.allCases) { preset in
                        Button {
                            onSelect(preset)
                        } label: {
                            VStack(spacing: 4) {
                                Image(platformImage: preset.loadImage())
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(preset.displayName)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - Pattern

struct PatternSection: View {
    @Binding var settings: StereogramSettings
    @ObservedObject var patternPreview: PatternPreviewViewModel
    let onPickPattern: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("inspector.pattern.kind", selection: bindingPatternKind) {
                Text("inspector.pattern.kind.asset").tag(PatternKind.asset)
                Text("inspector.pattern.kind.procedural").tag(PatternKind.procedural)
                Text("inspector.pattern.kind.imported").tag(PatternKind.imported)
            }
            .pickerStyle(.segmented)

            switch settings.patternSource {
            case .asset(let pattern):
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(StereogramPattern.allCases) { p in
                            Button {
                                settings.patternSource = .asset(p)
                            } label: {
                                Image(platformImage: p.loadImage())
                                    .resizable()
                                    .interpolation(.none)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(p == pattern ? Color.accentColor : .clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(Text(p.displayName))
                        }
                    }
                    .padding(.vertical, 4)
                }

            case .procedural(let type, let config):
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ProceduralPatternType.allCases) { t in
                            Button {
                                if t == type {
                                    settings.patternSource = .procedural(t, config)
                                } else {
                                    settings.patternSource = .procedural(t, t.defaultConfig())
                                }
                            } label: {
                                Image(systemName: t.iconSystemName)
                                    .font(.title3)
                                    .frame(width: 56, height: 56)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(t == type ? Color.accentColor : .clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(Text(t.displayName))
                        }
                    }
                    .padding(.vertical, 4)
                }

                ProceduralParamsView(
                    type: type,
                    config: Binding(
                        get: { config },
                        set: { settings.patternSource = .procedural(type, $0) }
                    ),
                    previewImage: patternPreview.previewImage,
                    isGenerating: patternPreview.isGenerating
                )

            case .imported:
                Button {
                    onPickPattern()
                } label: {
                    Label("pattern.import", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private enum PatternKind: Hashable {
        case asset, procedural, imported
    }

    private var bindingPatternKind: Binding<PatternKind> {
        Binding(
            get: {
                switch settings.patternSource {
                case .asset: .asset
                case .procedural: .procedural
                case .imported: .imported
                }
            },
            set: { newKind in
                switch newKind {
                case .asset:
                    settings.patternSource = .asset(.giraffe)
                case .procedural:
                    let t = ProceduralPatternType.randomDot
                    settings.patternSource = .procedural(t, t.defaultConfig())
                case .imported:
                    onPickPattern()
                }
            }
        )
    }
}

// MARK: - Depth adjustment

struct DepthAdjustmentSection: View {
    @Binding var depthMap: DepthMap?

    var body: some View {
        if let dm = depthMap {
            let adj = dm.adjustment
            let range = dm.rawDepthRange
            VStack(alignment: .leading, spacing: 12) {
                LabeledSlider(
                    title: String(format: "Min %.3f", adj.min),
                    value: floatBinding(\.min),
                    range: Double(range.lowerBound)...Double(range.upperBound)
                )
                LabeledSlider(
                    title: String(format: "Max %.3f", adj.max),
                    value: floatBinding(\.max),
                    range: Double(range.lowerBound)...Double(range.upperBound)
                )

                Divider()

                LabeledSlider(
                    title: String(format: "Start %.2f", adj.start),
                    value: floatBinding(\.end),
                    range: 0...1
                )
                LabeledSlider(
                    title: String(format: "End %.2f", adj.end),
                    value: floatBinding(\.start),
                    range: 0...1
                )

                Button("depth_adjustment.reset") {
                    var current = dm
                    current.adjustment = DepthMap.initialAdjustment(rawDepth: current.originalDepth)
                    depthMap = current
                }
                .buttonStyle(.bordered)
            }
        } else {
            Text("depth.acquire_prompt")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func floatBinding(_ keyPath: WritableKeyPath<DepthAdjustment, Float>) -> Binding<Double> {
        Binding(
            get: { Double(depthMap?.adjustment[keyPath: keyPath] ?? 0) },
            set: { newValue in
                guard var dm = depthMap else { return }
                dm.adjustment[keyPath: keyPath] = Float(newValue)
                depthMap = dm
            }
        )
    }
}

// MARK: - Stereogram settings

struct StereogramSettingsSection: View {
    @Binding var settings: StereogramSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledSlider(
                title: "DPI \(settings.dpi)",
                value: Binding(
                    get: { Double(settings.dpi) },
                    set: { settings.dpi = Int($0) }
                ),
                range: 60...150
            )
            LabeledSlider(
                title: String(format: "Depth strength %.2f", settings.depthStrength),
                value: Binding(
                    get: { Double(settings.depthStrength) },
                    set: { settings.depthStrength = Float($0) }
                ),
                range: 0.5...2.0
            )
            LabeledSlider(
                title: String(format: "Depth range %.2f", settings.sepFactor),
                value: Binding(
                    get: { Double(settings.sepFactor) },
                    set: { settings.sepFactor = Float($0) }
                ),
                range: 0.40...0.70
            )
            LabeledSlider(
                title: "Smoothness \(settings.oversampling)",
                value: Binding(
                    get: { Double(settings.oversampling) },
                    set: { settings.oversampling = Int($0) }
                ),
                range: 1...6
            )
            Toggle("generation.invert_depth", isOn: $settings.invert)
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $value, in: range)
        }
    }
}

// MARK: - Help sheet (macOS-friendly)

struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("help.how_to_use_title")
                    .font(.headline)
                Spacer()
                Button("general.done") { dismiss() }
            }
            .padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("help.step_acquire_full")
                    Text("help.step_adjust_depth")
                    Text("help.step_choose_pattern")
                    Text("help.step_adjust_settings")
                    Text("help.step_share")
                    Divider()
                    Text("help.viewing_3d").font(.headline)
                    Text("help.view_step_hold")
                    Text("help.view_step_relax")
                    Text("help.view_step_overlap")
                    Text("help.tip_device_close_alt")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
#endif
