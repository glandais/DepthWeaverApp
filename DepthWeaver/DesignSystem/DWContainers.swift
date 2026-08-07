import SwiftUI

// MARK: - Card

/// Glass container used for the drawer sections and the depth-source cards.
struct DWGlassCard<Content: View>: View {
    var radius: CGFloat = DWRadius.xl
    var padding: CGFloat = DWSpace.l
    var raised: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dwGlass(radius: radius, raised: raised)
    }
}

// MARK: - Icon tile

struct DWIconTile: View {
    let systemImage: String
    var tint: Color = DWColor.cyan
    var size: CGFloat = DWMetric.iconTile

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(tint.opacity(0.16))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(tint)
            }
    }
}

// MARK: - Grouped list

/// Rows share one glass container with hairlines between them, inset past the
/// leading icon tile.
struct DWGroupedList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .dwGlass(radius: DWRadius.xl)
    }
}

struct DWListRow: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let systemImage: String
    var tint: Color = DWColor.cyan
    var showsChevron: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DWSpace.m) {
                DWIconTile(systemImage: systemImage, tint: tint, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DWFont.label)
                        .foregroundStyle(DWColor.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(DWFont.ui(10.5))
                            .foregroundStyle(DWColor.textSecondary)
                    }
                }
                Spacer(minLength: DWSpace.s)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DWColor.textTertiary)
                }
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, DWSpace.l)
            .padding(.vertical, DWSpace.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Labels

/// Mono all-caps section header, with an optional trailing slot for tags such
/// as `PRO · LiDAR`.
struct DWSectionLabel<Trailing: View>: View {
    let title: LocalizedStringKey
    var showsRule: Bool = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: DWSpace.s) {
            Text(title).dwMicroLabel()
            if showsRule {
                Rectangle()
                    .fill(DWColor.hairline)
                    .frame(height: 1)
            } else {
                Spacer(minLength: 0)
            }
            trailing
        }
    }
}

extension DWSectionLabel where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, showsRule: Bool = false) {
        self.init(title: title, showsRule: showsRule) { EmptyView() }
    }
}

struct DWBadge: View {
    let text: String
    var tint: Color = DWColor.periwinkle

    var body: some View {
        Text(text)
            .dwBadgeLabel(color: tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Floating pill over the canvas: a swatch, a title and a mono subtitle.
struct DWPillLabel<Leading: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 9) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DWFont.ui(12, .medium))
                    .foregroundStyle(DWColor.text)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(DWFont.mono(9.5))
                        .foregroundStyle(DWColor.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 13)
        .padding(.vertical, 7)
        .dwGlassCapsule()
    }
}

/// Small centred hint pill ("TAP TO VIEW FULL SCREEN").
struct DWHintPill: View {
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: DWSpace.s) {
            Circle()
                .fill(DWColor.cyan)
                .frame(width: 6, height: 6)
            Text(text).dwMicroLabel(color: DWColor.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, DWSpace.s)
        .dwGlassCapsule()
    }
}

// MARK: - Progress arc

/// Cyan progress ring wrapping the trainer's circular stereogram.
struct DWCircularProgressArc: View {
    let progress: Double
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle()
                .stroke(DWColor.hairline, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress.clamped(to: 0...1))
                .stroke(DWColor.cyan, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: DWSpace.xl) {
            DWSectionLabel("start here")
            DWGlassCard {
                VStack(alignment: .leading, spacing: DWSpace.m) {
                    DWBadge(text: "estimated in 1.2s")
                    Text("From a photo").font(DWFont.cardTitle).foregroundStyle(DWColor.text)
                }
            }
            DWSectionLabel(title: "capture it yourself", showsRule: true) {
                DWBadge(text: "pro · lidar", tint: DWColor.cyan)
            }
            DWGroupedList {
                DWListRow(title: "Scan the room", subtitle: "Point and hold — live depth", systemImage: "camera.metering.matrix") {}
                DWSeparator(leadingInset: 60)
                DWListRow(title: "Open a 3D model", subtitle: "USDZ, OBJ or SCN", systemImage: "cube") {}
            }
            HStack {
                DWPillLabel(title: "Sphere study", subtitle: "depth · 500×500") {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(LinearGradient(colors: [DWColor.periwinkle, DWColor.cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 26, height: 26)
                }
                Spacer()
            }
            DWHintPill(text: "tap to view full screen")
            DWCircularProgressArc(progress: 0.5).frame(width: 120, height: 120)
        }
        .padding()
    }
    .background(DWColor.ground)
}
