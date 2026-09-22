#if os(iOS)
import SwiftUI

/// Discreet "About" sheet, opened from the ⓘ button on the canvas: version,
/// the tip screen, plus links to the website, support, privacy policy, source
/// code, a review prompt and the developer's other apps. Every link row opens
/// outside the app; the tip row stays inside it.
///
/// The Mac app exposes the same links, and the tip window, from its Help menu
/// instead (`DepthWeaverApp.commands`).
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TipJar.self) private var tipJar
    @State private var showsTips = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DWSpace.xl) {
                    header

                    // Tips go through in-app purchase and stay in the app
                    // (guideline 3.1.1): a pushed screen, not an outbound link.
                    VStack(alignment: .leading, spacing: DWSpace.s) {
                        DWSectionLabel("about.section_support")
                        DWGroupedList {
                            DWListRow(title: "about.tip", systemImage: "cup.and.saucer") {
                                showsTips = true
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: DWSpace.s) {
                        DWSectionLabel("about.section_info")
                        DWGroupedList {
                            AboutLinkRow(title: "about.website", systemImage: "globe", url: AppLinks.website)
                            DWSeparator(leadingInset: 60)
                            AboutLinkRow(title: "about.support", systemImage: "lifepreserver", url: AppLinks.support)
                            DWSeparator(leadingInset: 60)
                            AboutLinkRow(title: "about.privacy", systemImage: "hand.raised", url: AppLinks.privacy)
                            DWSeparator(leadingInset: 60)
                            AboutLinkRow(
                                title: "about.source_code",
                                systemImage: "chevron.left.forwardslash.chevron.right",
                                url: AppLinks.sourceCode
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: DWSpace.s) {
                        DWSectionLabel("about.section_app_store")
                        DWGroupedList {
                            AboutLinkRow(
                                title: "about.rate",
                                systemImage: "star",
                                tint: DWColor.periwinkle,
                                url: AppLinks.writeReview
                            )
                            DWSeparator(leadingInset: 60)
                            AboutLinkRow(
                                title: "about.more_apps",
                                systemImage: "square.grid.2x2",
                                tint: DWColor.periwinkle,
                                url: AppLinks.developerApps
                            )
                        }
                    }
                }
                .padding(.horizontal, DWSpace.l)
                .padding(.bottom, DWSpace.section)
            }
            .background(DWColor.ground)
            .navigationDestination(isPresented: $showsTips) {
                TipJarView(tipJar: tipJar)
            }
            .navigationTitle(Text("about.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("general.done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DWSpace.xs) {
            Text(verbatim: "DepthWeaver")
                .font(DWFont.heroTitle)
                .foregroundStyle(DWColor.text)
            Text("about.version \(Self.version) \(Self.build)")
                .font(DWFont.valueMono)
                .foregroundStyle(DWColor.textSecondary)
        }
        .padding(.top, DWSpace.l)
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

/// Same look as ``DWListRow``, but a `Link` with an "opens elsewhere" arrow.
private struct AboutLinkRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    var tint: Color = DWColor.cyan
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: DWSpace.m) {
                DWIconTile(systemImage: systemImage, tint: tint, size: 32)
                Text(title)
                    .font(DWFont.label)
                    .foregroundStyle(DWColor.text)
                Spacer(minLength: DWSpace.s)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DWColor.textTertiary)
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, DWSpace.l)
            .padding(.vertical, DWSpace.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("about.opens_externally")
    }
}
#endif
