import os
import PhotosUI
import SwiftUI

private let logger = Logger(subsystem: "com.glandais.DepthWeaver", category: "GenerationView")

struct GenerationView: View {
    @Binding var depthMap: DepthMap?
    @Binding var path: NavigationPath
    @Binding var selectedPhoto: PhotosPickerItem?
    let lidarAvailable: Bool

    @State private var settings = StereogramSettings()
    @State private var showHelp = false
    @State private var showDepthMapPresets = false
    @State private var selectedPatternPhoto: PhotosPickerItem?
    @State private var selectedDepthMapPhoto: PhotosPickerItem?
    @StateObject private var stereogramVM = StereogramViewModel()
    @StateObject private var patternPreviewVM = PatternPreviewViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Depth source section
                depthSourceSection

                // Pattern picker
                GroupBox(String(localized: "pattern.textures_section", comment: "Section header")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(StereogramPattern.allCases) { pattern in
                                let source = PatternSource.asset(pattern)
                                Button {
                                    settings.patternSource = source
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(uiImage: pattern.loadImage())
                                            .resizable()
                                            .interpolation(.none)
                                            .frame(width: 60, height: 60)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(settings.patternSource == source ? Color.blue : Color.clear, lineWidth: 3)
                                                    .animation(.snappy(duration: 0.2), value: settings.patternSource)
                                            )

                                        Text(pattern.displayName)
                                            .font(.caption2)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(pattern.displayName)
                                .accessibilityAddTraits(settings.patternSource == source ? .isSelected : [])
                            }

                            // Import pattern from photo
                            PhotosPicker(selection: $selectedPatternPhoto, matching: .images) {
                                VStack(spacing: 4) {
                                    ZStack {
                                        if case .imported(let image) = settings.patternSource {
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFill()
                                        } else {
                                            Image(systemName: "photo.badge.plus")
                                                .font(.title2)
                                                .foregroundStyle(.secondary)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                .background(.quaternary)
                                        }
                                    }
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(settings.patternSource.id == "imported" ? Color.blue : Color.clear, lineWidth: 3)
                                            .animation(.snappy(duration: 0.2), value: settings.patternSource)
                                    )

                                    Text("pattern.import", comment: "Pattern name")
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "pattern.import_accessibility", comment: "Accessibility label"))
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Generated patterns
                GroupBox(String(localized: "pattern.generated_section", comment: "Section header")) {
                    VStack(spacing: 12) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(ProceduralPatternType.allCases) { type in
                                    let isSelected = isProceduralSelected(type)
                                    Button {
                                        selectProceduralType(type)
                                    } label: {
                                        VStack(spacing: 4) {
                                            ZStack {
                                                if let preview = patternPreviewVM.previewImage,
                                                   isSelected {
                                                    Image(uiImage: preview)
                                                        .resizable()
                                                        .interpolation(.none)
                                                } else {
                                                    Image(systemName: type.iconSystemName)
                                                        .font(.title2)
                                                        .foregroundStyle(.secondary)
                                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                        .background(.quaternary)
                                                }
                                            }
                                            .frame(width: 60, height: 60)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                                                    .animation(.snappy(duration: 0.2), value: settings.patternSource)
                                            )

                                            Text(type.displayName)
                                                .font(.caption2)
                                                .lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(type.displayName)
                                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        if case .procedural(let type, let config) = settings.patternSource {
                            ProceduralParamsView(
                                type: type,
                                config: Binding(
                                    get: { config },
                                    set: { settings.patternSource = .procedural(type, $0) }
                                ),
                                previewImage: patternPreviewVM.previewImage,
                                isGenerating: patternPreviewVM.isGenerating
                            )
                        }
                    }
                }

                // Settings
                GroupBox(String(localized: "generation.settings")) {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading) {
                            Text("generation.dpi_label \(settings.dpi)")
                                .font(.subheadline)
                            Slider(
                                value: Binding(
                                    get: { Double(settings.dpi) },
                                    set: { settings.dpi = Int($0) }
                                ),
                                in: 60...150,
                                step: 1
                            )
                            .accessibilityLabel("generation.dpi_accessibility")
                            .accessibilityValue("\(settings.dpi)")
                        }

                        VStack(alignment: .leading) {
                            Text("generation.depth_strength_label \(settings.depthStrength, specifier: "%.2f")")
                                .font(.subheadline)
                            Slider(
                                value: Binding(
                                    get: { Double(settings.depthStrength) },
                                    set: { settings.depthStrength = Float($0) }
                                ),
                                in: 0.5...2.0,
                                step: 0.05
                            )
                            .accessibilityLabel("generation.depth_strength_accessibility")
                            .accessibilityValue("\(settings.depthStrength, specifier: "%.2f")")
                        }

                        VStack(alignment: .leading) {
                            Text("generation.depth_range_label \(settings.sepFactor, specifier: "%.2f")")
                                .font(.subheadline)
                            Slider(
                                value: Binding(
                                    get: { Double(settings.sepFactor) },
                                    set: { settings.sepFactor = Float($0) }
                                ),
                                in: 0.40...0.70,
                                step: 0.01
                            )
                            .accessibilityLabel("generation.depth_range_accessibility")
                            .accessibilityValue("\(settings.sepFactor, specifier: "%.2f")")
                        }

                        VStack(alignment: .leading) {
                            Text("generation.smoothness_label \(settings.oversampling)")
                                .font(.subheadline)
                            Slider(
                                value: Binding(
                                    get: { Double(settings.oversampling) },
                                    set: { settings.oversampling = Int($0) }
                                ),
                                in: 1...6,
                                step: 1
                            )
                            .accessibilityLabel("generation.smoothness_accessibility")
                            .accessibilityValue("\(settings.oversampling)")
                        }

                        Toggle("generation.invert_depth", isOn: $settings.invert)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }

                // Stereogram preview
                stereogramPreview
            }
            .padding()
        }
        .navigationTitle("DepthWeaver")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("help.how_to_use_button")
            }
        }
        .sheet(isPresented: $showHelp) {
            HowToUseSheet()
        }
        .sheet(isPresented: $showDepthMapPresets) {
            DepthMapPresetSheet { preset in
                depthMap = preset.toDepthMap()
                showDepthMapPresets = false
            }
        }
        .onAppear {
            triggerGeneration()
        }
        .onChange(of: depthMap?.id) { _, _ in
            triggerGeneration()
        }
        .onChange(of: depthMap?.adjustment) { _, _ in
            triggerGeneration()
        }
        .onChange(of: settings) { _, _ in
            triggerGeneration()
            updatePatternPreview()
        }
        .onChange(of: selectedPatternPhoto) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    settings.patternSource = .imported(image)
                }
            }
        }
        .onChange(of: selectedDepthMapPhoto) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    depthMap = DepthMap(image: image)
                }
                selectedDepthMapPhoto = nil
            }
        }
    }

    private func triggerGeneration() {
        guard let depthMap else {
            stereogramVM.resultImage = nil
            return
        }
        stereogramVM.generateDebounced(depthMap: depthMap, settings: settings)
    }

    private func updatePatternPreview() {
        if case .procedural = settings.patternSource {
            patternPreviewVM.updatePreview(source: settings.patternSource)
        }
    }

    private func isProceduralSelected(_ type: ProceduralPatternType) -> Bool {
        if case .procedural(let selectedType, _) = settings.patternSource {
            return selectedType == type
        }
        return false
    }

    private func selectProceduralType(_ type: ProceduralPatternType) {
        if case .procedural(let currentType, let config) = settings.patternSource,
           currentType == type {
            // Already selected, keep current config
            settings.patternSource = .procedural(type, config)
        } else {
            settings.patternSource = .procedural(type, type.defaultConfig())
        }
    }

    // MARK: - Depth Source

    @ViewBuilder
    private var depthSourceSection: some View {
        if let depthMap {
            GroupBox {
                VStack(spacing: 12) {
                    DepthPointCloudView(depthMap: depthMap, adjustment: depthMap.adjustment)
                        .aspectRatio(CGFloat(depthMap.width) / CGFloat(depthMap.height), contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture {
                            path.append(NavigationDestination.depthAdjustment)
                        }
                        .accessibilityHint("depth.tap_to_adjust")

                    HStack {
                        Label(
                            depthMap.source == .lidar ? "LiDAR" : depthMap.source == .imported ? String(localized: "depth.source_imported", comment: "Depth map source label") : String(localized: "depth.source_ai"),
                            systemImage: depthMap.source == .lidar ? "camera.metering.matrix" : depthMap.source == .imported ? "square.and.arrow.down" : "photo.on.rectangle"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        Spacer()

                        Text(verbatim: "\(depthMap.width) × \(depthMap.height)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Button {
                            path.append(NavigationDestination.depthAdjustment)
                        } label: {
                            Label("depth.adjust_depth", systemImage: "slider.horizontal.below.square.and.square.filled")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }

                    Spacer().frame(height: 4)

                    depthAcquisitionButtons
                }
            } label: {
                Text("depth.section_title")
            }
        } else {
            GroupBox {
                VStack(spacing: 16) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    Text("depth.acquire_prompt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    depthAcquisitionButtons
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } label: {
                Text("depth.section_title")
            }
        }
    }

    @ViewBuilder
    private var depthAcquisitionButtons: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                if lidarAvailable {
                    Button {
                        path.append(NavigationDestination.lidarCapture)
                    } label: {
                        Label("depth.lidar_scan", systemImage: "camera.metering.matrix")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("depth.from_photo", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            GridRow {
                Button {
                    showDepthMapPresets = true
                } label: {
                    Label("depth.presets", systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                PhotosPicker(selection: $selectedDepthMapPhoto, matching: .images) {
                    Label("depth.import_depth_map", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            GridRow {
                Button {
                    path.append(NavigationDestination.model3DCapture)
                } label: {
                    Label("depth.from_3d_model", systemImage: "cube")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .gridCellColumns(2)
            }
        }
    }

    // MARK: - Stereogram Preview

    @ViewBuilder
    private var stereogramPreview: some View {
        if let image = stereogramVM.resultImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    if stereogramVM.isGenerating {
                        ProgressView()
                            .scaleEffect(1.5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.ultraThinMaterial.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .transition(.opacity)
                    }
                }
                .animation(.smooth(duration: 0.25), value: stereogramVM.isGenerating)
                .onTapGesture {
                    if !stereogramVM.isGenerating {
                        path.append(NavigationDestination.stereogramResult(image))
                    }
                }
                .accessibilityLabel("result.preview")
                .accessibilityHint("result.tap_fullscreen")
        } else if depthMap != nil {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .aspectRatio(CGFloat(depthMap!.width) / CGFloat(depthMap!.height), contentMode: .fit)
                .overlay {
                    ProgressView("generation.generating")
                }
        }
    }
}

struct HowToUseSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("help.how_to_use_title")
                        .font(.title2)
                        .fontWeight(.bold)

                    step(1, icon: "camera.metering.matrix",
                         text: "help.step_acquire_full")

                    step(2, icon: "slider.horizontal.below.square.and.square.filled",
                         text: "help.step_adjust_depth")

                    step(3, icon: "square.grid.3x3",
                         text: "help.step_choose_pattern")

                    step(4, icon: "slider.horizontal.3",
                         text: "help.step_adjust_settings")

                    step(5, icon: "eye",
                         text: "help.step_share")

                    Divider()

                    Text("help.viewing_3d")
                        .font(.title3)
                        .fontWeight(.semibold)

                    step(1, icon: "hand.raised",
                         text: "help.view_step_hold")

                    step(2, icon: "eye.slash",
                         text: "help.view_step_relax")

                    step(3, icon: "cube.transparent",
                         text: "help.view_step_overlap")

                    Text("help.tip_device_close_alt")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("general.done") { dismiss() }
                }
            }
        }
    }

    private func step(_ number: Int, icon: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.blue, in: Circle())

            Text(text)
                .font(.body)
        }
    }
}

struct DepthMapPresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (DepthMapPreset) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(DepthMapPreset.allCases) { preset in
                        Button {
                            onSelect(preset)
                        } label: {
                            VStack(spacing: 4) {
                                Image(uiImage: preset.loadImage())
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
            .navigationTitle(String(localized: "depth.presets_title", comment: "Sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("general.done") { dismiss() }
                }
            }
        }
    }
}
