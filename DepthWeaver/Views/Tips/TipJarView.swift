import StoreKit
import SwiftUI

/// The tip screen. On iOS it is pushed from the About sheet ("Support
/// DepthWeaver"); on macOS it fills the "Leave a Tip" window opened from the
/// Help menu.
///
/// Three consumables that unlock nothing. Names and prices come from the store,
/// in the buyer's language and currency: the catalog carries none of them.
struct TipJarView: View {
    let tipJar: TipJar

    @Environment(\.purchase) private var purchase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DWSpace.l) {
                Text("tip.header")
                    .font(DWFont.body)
                    .foregroundStyle(DWColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                tips
                status
            }
            .padding(DWSpace.l)
        }
        .background(DWColor.ground)
        .navigationTitle(Text("tip.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await tipJar.load() }
    }

    @ViewBuilder
    private var tips: some View {
        if tipJar.isLoading && tipJar.products.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(DWSpace.l)
                .dwGlass(radius: DWRadius.xl)
        } else if tipJar.isUnavailable {
            VStack(alignment: .leading, spacing: DWSpace.s) {
                Text("tip.unavailable")
                    .font(DWFont.body)
                    .foregroundStyle(DWColor.textSecondary)
                Button("tip.retry") {
                    Task { await tipJar.load() }
                }
                .font(DWFont.label)
                .foregroundStyle(DWColor.cyan)
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DWSpace.l)
            .dwGlass(radius: DWRadius.xl)
        } else {
            DWGroupedList {
                ForEach(tipJar.products) { product in
                    if product.id != tipJar.products.first?.id {
                        DWSeparator(leadingInset: 60)
                    }
                    row(product)
                }
            }
        }
    }

    private func row(_ product: Product) -> some View {
        Button {
            Task { await tipJar.buy(product, with: purchase) }
        } label: {
            HStack(spacing: DWSpace.m) {
                DWIconTile(systemImage: "cup.and.saucer", size: 32)
                Text(verbatim: product.displayName)
                    .font(DWFont.label)
                    .foregroundStyle(DWColor.text)
                Spacer(minLength: DWSpace.s)
                if tipJar.state == .purchasing(product.id) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(verbatim: product.displayPrice)
                        .font(DWFont.valueMono)
                        .foregroundStyle(DWColor.cyan)
                }
            }
            .padding(.horizontal, DWSpace.l)
            .padding(.vertical, DWSpace.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }

    @ViewBuilder
    private var status: some View {
        switch tipJar.state {
        case .thanked:
            Label {
                Text("tip.thanks")
            } icon: {
                Image(systemName: "heart.fill")
            }
            .font(DWFont.label)
            .foregroundStyle(DWColor.periwinkle)
        case .pending:
            note("tip.pending")
        case .failed:
            note("tip.failed")
        case .idle, .purchasing:
            EmptyView()
        }
    }

    private func note(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(DWFont.caption)
            .foregroundStyle(DWColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var isPurchasing: Bool {
        if case .purchasing = tipJar.state { true } else { false }
    }
}
