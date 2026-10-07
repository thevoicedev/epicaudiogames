// Store.kt's BillingClient calls, as StoreKit 2 answers them: products, buying, the purchases made, and new ones.

import Foundation
import StoreKit

/// A purchase as the store needs it: its product, whether it was refunded or revoked, and finishing it.
struct StorePurchase: Sendable {
    let product: String
    let revoked: Bool
    let finish: @Sendable () async -> Void
}

/// What buying came to.
enum PurchaseOutcome: Sendable {
    case bought(StorePurchase)
    /// Waiting for a parent's OK (Ask to Buy) or the bank: the purchase comes later, as an update.
    case pending
    /// Cancelled.
    case nothing
}

/// A purchase the App Store didn't sign: nothing is installed for it.
struct UnverifiedPurchase: Error, CustomStringConvertible {
    var description: String { "the App Store didn't sign the purchase" }
}

/// The App Store as Store uses it. The app's is StoreKit's; tests give a fake.
protocol AppStoreClient: Sendable {
    /// Each product's price, as the App Store shows it ("£1.99").
    func prices(_ products: Set<String>) async throws -> [String: String]
    /// Buys a product whose price was loaded; nil if it wasn't (Store.kt's missing ProductDetails).
    func purchase(_ product: String) async throws -> PurchaseOutcome?
    /// The purchases this account has (Play's queryPurchasesAsync).
    func entitlements() async -> [StorePurchase]
    /// The purchases not yet finished.
    func unfinished() async -> [StorePurchase]
    /// Purchases as they come from outside a purchase() call: another device, Ask to Buy, a refund.
    func updates() -> AsyncStream<StorePurchase>
    /// The App Store asked again for this account's purchases (it may ask the player to sign in; their saying no
    /// isn't an error).
    func sync() async throws
}

/// StoreKit 2. Nonisolated: StoreKit's sequences and results come from its own threads.
nonisolated final class StoreKitClient: AppStoreClient, @unchecked Sendable {
    private let lock = NSLock()
    private var products: [String: Product] = [:]

    func prices(_ ids: Set<String>) async throws -> [String: String] {
        let list = try await Product.products(for: ids)
        lock.withLock { for p in list { products[p.id] = p } }
        return Dictionary(list.map { ($0.id, $0.displayPrice) }, uniquingKeysWith: { a, _ in a })
    }

    func purchase(_ id: String) async throws -> PurchaseOutcome? {
        guard let product = lock.withLock({ products[id] }) else { return nil }
        switch try await product.purchase() {
        case .success(let result):
            guard let purchase = Self.purchase(result) else { throw UnverifiedPurchase() }
            return .bought(purchase)
        case .pending:
            return .pending
        case .userCancelled:
            return .nothing
        @unknown default:
            return .nothing
        }
    }

    func entitlements() async -> [StorePurchase] {
        var out: [StorePurchase] = []
        for await result in Transaction.currentEntitlements {
            if let p = Self.purchase(result) { out.append(p) }
        }
        return out
    }

    func unfinished() async -> [StorePurchase] {
        var out: [StorePurchase] = []
        for await result in Transaction.unfinished {
            if let p = Self.purchase(result) { out.append(p) }
        }
        return out
    }

    func updates() -> AsyncStream<StorePurchase> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    if let p = Self.purchase(result) { continuation.yield(p) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func sync() async throws {
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            // The player didn't sign in: the purchases on the phone are read all the same.
        }
    }

    /// A transaction the App Store signed; nil for one it didn't (nothing is installed for it).
    private static func purchase(_ result: VerificationResult<Transaction>) -> StorePurchase? {
        guard case .verified(let t) = result else { return nil }
        return StorePurchase(product: t.productID, revoked: t.revocationDate != nil, finish: { await t.finish() })
    }
}
