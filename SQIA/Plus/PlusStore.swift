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
        await loadProduct()
    }

    /// Again from the paywall, if launch found no network: the price is
    /// what the Subscribe button stands on.
    func loadProduct() async {
        guard product == nil else { return }
        product = try? await Product.products(for: Self.productIDs).first
    }

    enum Outcome: Equatable {
        case subscribed
        /// Ask to Buy, or a bank that wants a second look. It arrives
        /// through `Transaction.updates` if and when it goes through.
        case pending
        case cancelled
        case failed(String)
    }

    func purchase() async -> Outcome {
        await loadProduct()
        guard let product else {
            return .failed("The App Store did not answer. Try again in a moment.")
        }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await handle(verification)
                return access.hasPlus
                    ? .subscribed : .failed("The purchase could not be verified.")
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            log.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    /// Guideline 3.1.1 wants a way to restore. `AppStore.sync` asks the
    /// App Store for everything this Apple ID owns, which is also what
    /// brings a subscription over to a new phone.
    func restore() async -> Outcome {
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            log.error("Restore failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
        await refresh()
        return access.hasPlus
            ? .subscribed : .failed("There is no SQIA Plus on this Apple Account to restore.")
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
