#if os(iOS)
import PhotosUI
import SwiftUI

/// Depth-source picking, re-ranked.
///
/// The old screen offered six equal-weight buttons; here "From a photo" is the
/// hero because it is the only source every device can use, the two file-based
/// sources are secondary cards, and the capture flows are grouped under their
/// own heading since most of them only exist on Pro hardware.
struct DepthSourceScreen: View {
    @Binding var depthMap: DepthMap?
    @Binding var path: NavigationPath
    @ObservedObject var photoDepthVM: PhotoDepthViewModel
    let lidarAvailable: Bool
    let guidedCaptureSupported: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedDepthMapPhoto: PhotosPickerItem?
    @State private var showPresets = false

    private var hasCaptureHardware: Bool { lidarAvailable || guidedCaptureSupported }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DWSpace.xl) {
                header
                startHere
                fileSources
                captureSources
            }
            .padding(.horizontal, DWSpace.l)
            .padding(.bottom, DWSpace.section)
        }
        .background(DWColor.ground)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPresets) {
            DepthPresetGrid { preset in
                depthMap = preset.toDepthMap()
                showPresets = false
                dismiss()
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let item = newValue else { return }
            Task {
                await photoDepthVM.processPhoto(item: item)
                selectedPhoto = nil
                if let estimated = photoDepthVM.depthMap {
                    depthMap = estimated
                    dismiss()
                }
            }
        }
        .onChange(of: selectedDepthMapPhoto) { _, newValue in
            guard let item = newValue else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    selectedDepthMapPhoto = nil
                    return
                }
                // DepthMap(image:) runs the denoising pipeline synchronously
                // (~100-150ms); shift it off the main actor so the UI stays
                // responsive.
                let imported = await Task.detached(priority: .userInitiated) {
                    DepthMap(image: image)
                }.value
                depthMap = imported
                selectedDepthMapPhoto = nil
                dismiss()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DWSpace.m) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(DWCircleGlassButtonStyle(size: 34))
            .accessibilityLabel("general.back")

            Text("depth_source.title")
                .font(DWFont.screenTitle)
                .foregroundStyle(DWColor.text)
        }
        .padding(.top, DWSpace.s)
    }

    // MARK: - Hero

    private var startHere: some View {
        VStack(alignment: .leading, spacing: DWSpace.s) {
            DWSectionLabel("depth_source.start_here")

            VStack(spacing: 0) {
                heroPreview
                VStack(alignment: .leading, spacing: DWSpace.m) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("depth_source.hero_title")
                            .font(DWFont.cardTitle)
                            .foregroundStyle(DWColor.text)
                        Text("depth_source.hero_body")
                            .font(DWFont.ui(12))
                            .foregroundStyle(DWColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Text("depth_source.choose_photo")
                            .font(DWFont.ui(14, .semibold))
                            .foregroundStyle(DWColor.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                DWColor.cyan,
                                in: RoundedRectangle(cornerRadius: DWRadius.lg, style: .continuous)
                            )
                    }
                }
                .padding(DWSpace.l)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dwGlass(radius: DWRadius.xxl)
            .clipShape(RoundedRectangle(cornerRadius: DWRadius.xxl, style: .continuous))
        }
    }

    @ViewBuilder
    private var heroPreview: some View {
        ZStack(alignment: .bottomLeading) {
            if let depthMap {
                // Same interactive point cloud as the Depth drawer, so the
                // current depth map reads the same wherever it is shown.
                DepthPointCloudView(depthMap: depthMap, adjustment: depthMap.adjustment)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DWColor.surface)
            } else {
                DWColor.surface
                    .overlay {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 36))
                            .foregroundStyle(DWColor.textTertiary)
                    }
            }

            if let duration = photoDepthVM.lastEstimateDuration {
                Text("depth_source.badge_estimated \(duration, specifier: "%.1f")")
                    .dwBadgeLabel(color: DWColor.text)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(DWColor.scrim, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(DWSpace.m)
            }
        }
        .frame(height: 196)
        .clipped()
    }

    // MARK: - Secondary sources

    private var fileSources: some View {
        HStack(spacing: DWSpace.m) {
            Button { showPresets = true } label: {
                sourceCard(
                    icon: "square.grid.2x2",
                    tint: DWColor.periwinkle,
                    title: "depth_source.examples",
                    subtitle: "depth_source.examples_subtitle"
                )
            }
            .buttonStyle(.plain)

            PhotosPicker(selection: $selectedDepthMapPhoto, matching: .images) {
                sourceCard(
                    icon: "square.and.arrow.down",
                    tint: DWColor.text,
                    title: "depth_source.import_map",
                    subtitle: "depth_source.import_map_subtitle"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func sourceCard(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: DWSpace.s) {
            DWIconTile(systemImage: icon, tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(DWFont.label)
                    .foregroundStyle(DWColor.text)
                Text(subtitle)
                    .font(DWFont.ui(10.5))
                    .foregroundStyle(DWColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DWSpace.m)
        .dwGlass(radius: DWRadius.xl)
    }

    // MARK: - Capture

    private var captureSources: some View {
        VStack(alignment: .leading, spacing: DWSpace.s) {
            DWSectionLabel(title: "depth_source.capture_yourself", showsRule: true) {
                // Only meaningful when at least one hardware-gated row is shown.
                if hasCaptureHardware {
                    Text("depth_source.pro_lidar_tag").dwBadgeLabel(color: DWColor.cyan)
                }
            }

            DWGroupedList {
                if lidarAvailable {
                    DWListRow(
                        title: "depth_source.scan_room",
                        subtitle: "depth_source.scan_room_subtitle",
                        systemImage: "camera.metering.matrix"
                    ) {
                        path.append(NavigationDestination.lidarCapture)
                    }
                    DWSeparator(leadingInset: 60)
                }

                if guidedCaptureSupported {
                    DWListRow(
                        title: "depth_source.scan_object",
                        subtitle: "depth_source.scan_object_subtitle",
                        systemImage: "camera.viewfinder"
                    ) {
                        path.append(NavigationDestination.guidedCapture)
                    }
                    DWSeparator(leadingInset: 60)
                }

                DWListRow(
                    title: "depth_source.open_3d_model",
                    subtitle: "depth_source.open_3d_model_subtitle",
                    systemImage: "cube",
                    tint: DWColor.text
                ) {
                    path.append(NavigationDestination.model3DCapture)
                }
            }
        }
    }
}
#endif
