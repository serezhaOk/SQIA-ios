// Whether this Apple ID has SQIA Plus, straight from StoreKit.
//
// The subscription belongs to the Apple ID rather than to the SQIA account,
// the way every App Store subscription does: nothing about it is written to
// Supabase, and there is no server of ours to ask. StoreKit keeps the
// signed receipts on the phone and answers offline, so the answer is its
// word and nobody else's.
//
// The last answer is also kept in UserDefaults, only so a relaunch does not
// open with the second track silent for the moment StoreKit takes to
// reply. It is never the answer for longer than that: `refresh` replaces
// it on every launch, and whenever a transaction arrives.

import Foundation
import Observation
import OSLog
import SQIACore
import StoreKit

@MainActor
@Observable
final class PlusStore {
    /// One product for now. A yearly plan would join it in the same group,
    /// and the paywall would show both without being told.
    static let monthly = "com.serezhaok.sqia.plus.monthly"
    static let productIDs = [monthly]

    private(set) var access: Access
    /// For the profile's row, which says what it costs before anyone opens
    /// the paywall. Nil until StoreKit has answered, or if it cannot.
    private(set) var product: Product?

    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.serezhaok.sqia", category: "plus")
    private static let cacheKey = "sqia.plus"

    init() {
        access = Access(hasPlus: UserDefaults.standard.bool(forKey: Self.cacheKey))
    }

    /// Listen for transactions and read what is owned. Called once, at
    /// launch — a renewal, a refund or a purchase made on another device can
    /// arrive at any time after that, and only a listener hears it.
    func start() async {
        if updates == nil {
            updates = Task { [weak self] in
                for await result in Transaction.updates {
                    await self?.handle(result)
                }
            }
        }
        await refresh()
        product = try? await Product.products(for: Self.productIDs).first
    }

    /// Read the entitlements again. `currentEntitlements` already leaves out
    /// what has expired or been refunded, so anything verified in it for one
    /// of our products is a live subscription.
    func refresh() async {
        var hasPlus = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                log.error("Unverified entitlement: \(String(describing: result), privacy: .public)")
                continue
            }
            log.info("Entitlement \(transaction.productID, privacy: .public)")
            if Self.productIDs.contains(transaction.productID),
                transaction.revocationDate == nil
            {
                hasPlus = true
            }
        }
        log.info("Plus: \(hasPlus, privacy: .public)")
        set(hasPlus)
    }

    /// A purchase made on the paywall, or one that arrived by itself.
    /// Unverified transactions are never finished and never unlock anything;
    /// StoreKit will offer them again.
    func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            log.error("Unverified transaction: \(String(describing: result), privacy: .public)")
            return
        }
        await transaction.finish()
        await refresh()
    }

    private func set(_ hasPlus: Bool) {
        UserDefaults.standard.set(hasPlus, forKey: Self.cacheKey)
        guard hasPlus != access.hasPlus else { return }
        access = Access(hasPlus: hasPlus)
    }
}
