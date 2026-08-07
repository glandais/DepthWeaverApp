#if os(iOS)
import SwiftUI

/// Drawer tab showing the current depth map and the two things you can do to
/// it: swap it, or reshape it.
struct DepthToolView: View {
    @Binding var depthMap: DepthMap?
    @Binding var path: NavigationPath

    var body: some View {
        VStack(alignment: .leading, spacing: DWSpace.m) {
            if let depthMap {
                DepthPointCloudView(depthMap: depthMap, adjustment: depthMap.adjustment)
                    .aspectRatio(CGFloat(depthMap.width) / CGFloat(depthMap.height), contentMode: .fit)
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: DWRadius.lg, style: .continuous))
                    .onTapGesture {
                        path.append(NavigationDestination.depthAdjustment)
                    }
                    .accessibilityHint("depth.tap_to_adjust")

                HStack(spacing: DWSpace.s) {
                    Text(sourceTitle)
                        .font(DWFont.label)
                        .foregroundStyle(DWColor.textSecondary)
                    Spacer(minLength: 0)
                    Text(verbatim: "\(depthMap.width) × \(depthMap.height)")
                        .font(DWFont.valueMono)
                        .foregroundStyle(DWColor.textTertiary)
                }
            } else {
                VStack(spacing: DWSpace.m) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 36))
                        .foregroundStyle(DWColor.textTertiary)
                    Text("depth.acquire_prompt")
                        .font(DWFont.body)
                        .foregroundStyle(DWColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DWSpace.xl)
            }

            DWGroupedList {
                DWListRow(
                    title: "canvas.change_depth_source",
                    subtitle: "canvas.change_depth_source_subtitle",
                    systemImage: "square.3.layers.3d"
                ) {
                    path.append(NavigationDestination.depthSource)
                }

                if depthMap != nil {
                    DWSeparator(leadingInset: 60)
                    DWListRow(
                        title: "depth.adjust_depth",
                        subtitle: "canvas.adjust_depth_subtitle",
                        systemImage: "slider.horizontal.below.square.and.square.filled",
                        tint: DWColor.periwinkle
                    ) {
                        path.append(NavigationDestination.depthAdjustment)
                    }
                }
            }
        }
    }

    private var sourceTitle: String {
        guard let depthMap else { return "" }
        return switch depthMap.source {
        case .lidar: "LiDAR"
        case .imported: String(localized: "depth.source_imported")
        case .model3D: String(localized: "depth.source_3d_model")
        case .depthAnything: String(localized: "depth.source_ai")
        }
    }
}
#endif
