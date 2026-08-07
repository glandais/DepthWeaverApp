#if os(iOS)
import SwiftUI

/// The bundled height maps, as a grid of glass tiles.
struct DepthPresetGrid: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (DepthMapPreset) -> Void

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: DWSpace.m)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: DWSpace.l) {
                    ForEach(DepthMapPreset.allCases) { preset in
                        Button {
                            onSelect(preset)
                        } label: {
                            VStack(spacing: DWSpace.s) {
                                Image(uiImage: preset.loadImage())
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: DWRadius.sm, style: .continuous))

                                Text(preset.displayName)
                                    .font(DWFont.caption)
                                    .foregroundStyle(DWColor.textSecondary)
                                    .lineLimit(1)
                            }
                            .padding(DWSpace.s)
                            .dwGlass(radius: DWRadius.lg)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(DWSpace.l)
            }
            .background(DWColor.ground)
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
#endif
