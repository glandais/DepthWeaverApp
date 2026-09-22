import Observation
import StoreKit
import SwiftUI // PurchaseAction

/// Tips: three consumable in-app purchases that unlock nothing.
///
/// Copied from the reference file shared by the developer's apps (the
/// `donations` repository). The `<bundle>.tip.small|medium|large` products live
/// in App Store Connect; `Tips.storekit`, at the repository root, mirrors them
/// for local testing from Xcode.
///
/// There is nothing to deliver or restore: a verified purchase is finished at
/// once and the app says thank you. No server, no stored data.
@MainActor
@Observable
final class TipJar {
    enum State: Equatable {
        case idle
        case purchasing(Product.ID)
        /// Ask to Buy: a parent has to approve; the purchase arrives later
        /// through `Transaction.updates`.
        case pending
        case thanked
        case failed
    }

    /// Derived from the bundle, so this file copies across apps unchanged.
    static let productIDs: [Product.ID] = {
        let bundle = Bundle.main.bundleIdentifier ?? ""
        return ["small", "medium", "large"].map { "\(bundle).tip.\($0)" }
    }()

    /// Sorted by ascending price.
    private(set) var products: [Product] = []
    private(set) var isLoading = false
    /// True when the store returned nothing (offline, products not yet approved…).
    private(set) var isUnavailable = false
    var state: State = .idle

    private var updates: Task<Void, Never>?

    /// Call at app launch, not when the screen opens: StoreKit replays
    /// transactions left open there (an interrupted purchase, Ask to Buy
    /// approved later), and they must be finished.
    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                guard let self, Self.productIDs.contains(transaction.productID),
                      transaction.revocationDate == nil else { continue }
                self.state = .thanked
            }
        }
    }

    func load() async {
        guard products.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: Self.productIDs)
                .sorted { $0.price < $1.price }
        } catch {
            products = []
        }
        isUnavailable = products.isEmpty
    }

    /// `purchase` comes from `@Environment(\.purchase)`, which tells StoreKit
    /// which scene or window presents the payment sheet.
    func buy(_ product: Product, with purchase: PurchaseAction) async {
        state = .purchasing(product.id)
        do {
            switch try await purchase(product) {
            case .success(.verified(let transaction)):
                await transaction.finish()
                state = .thanked
            case .success(.unverified):
                // Unverified: neither finished nor thanked; StoreKit replays it.
                state = .failed
            case .pending:
                state = .pending
            case .userCancelled:
                state = .idle
            @unknown default:
                state = .idle
            }
        } catch {
            state = .failed
        }
    }
}
