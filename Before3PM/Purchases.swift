import Combine
import Foundation
import StoreKit

@MainActor
final class Purchases: ObservableObject {
    @Published private(set) var entitlement: Entitlement?
    @Published private(set) var products: [Product] = []
    @Published private(set) var busy = false
    @Published private(set) var message: String?

    private let storage = EntitlementStorage()
    private var updates: Task<Void, Never>?
    private var didLoad = false
    private var lastSaved: Entitlement?

    var pro: Product? { products.first { $0.id == Launch.proProduct } }
    var trial: Product? { products.first { $0.id == Launch.trialProduct } }

    func hasPro(at now: Date) -> Bool {
        Launch.isFree || (entitlement?.hasPro(at: now, free: false) ?? false)
    }

    func load(at now: Date, expired: Bool) async {
        guard !didLoad else { return }
        didLoad = true
        if Launch.isUITesting {
            let start = expired ? now.addingTimeInterval(-31 * 86400) : now
            entitlement = Entitlement(firstOpen: start, proStartedAt: start)
            return
        }

        do {
            let existing = try await storage.load()
            var current = existing ?? Entitlement(firstOpen: now)
            current.beginPaidPeriod(at: now, free: Launch.isFree)
            if existing != current { try await storage.save(current) }
            entitlement = current
            lastSaved = current
        } catch {
            self.message = L.t("store.localError")
        }

        guard !Launch.isFree else { return }
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self, case .verified(let transaction) = result else { continue }
                if await self.apply(transaction) { await transaction.finish() }
            }
        }
        Task { await refreshReceipts() }
    }

    func loadProducts() async {
        guard !Launch.isFree, !Launch.isUITesting, !busy else { return }
        do {
            products = try await Product.products(for: [Launch.proProduct, Launch.trialProduct])
                .filter { $0.type == .nonConsumable }
            message = pro == nil || trial == nil ? L.t("store.unavailable") : nil
        } catch {
            self.message = L.t("store.unavailable")
        }
    }

    func buy(_ product: Product?) async {
        guard !busy, !Launch.isUITesting else { return }
        guard let product else { await loadProducts(); return }
        busy = true
        defer { busy = false }
        message = nil
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    message = L.t("store.unverified")
                    return
                }
                if await apply(transaction) {
                    await transaction.finish()
                    message = L.t("store.recorded")
                }
            case .pending: message = L.t("store.pending")
            case .userCancelled: break
            @unknown default: message = L.t("store.unavailable")
            }
        } catch {
            self.message = L.t("store.unavailable")
        }
    }

    func restore() async {
        guard !busy, !Launch.isUITesting else { return }
        busy = true
        defer { busy = false }
        message = nil
        do {
            try await AppStore.sync()
            let found = await refreshReceipts()
            if message == nil { message = L.t(found ? "store.restored" : "store.nothing") }
        } catch {
            self.message = L.t("store.unavailable")
        }
    }

    @discardableResult
    func refreshReceipts() async -> Bool {
        guard !Launch.isFree, !Launch.isUITesting else { return false }
        var found = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if await apply(transaction), transaction.revocationDate == nil { found = true }
        }
        if let result = await StoreKit.Transaction.latest(for: Launch.proProduct),
           case .verified(let latest) = result {
            if latest.revocationDate != nil { _ = await apply(latest) }
        }
        return found
    }

    private func apply(_ transaction: StoreKit.Transaction) async -> Bool {
        let now = Date()
        var updated = entitlement ?? Entitlement(firstOpen: now, proStartedAt: now)
        switch transaction.productID {
        case Launch.proProduct:
            updated.recordPro(purchasedAt: transaction.purchaseDate, revoked: transaction.revocationDate != nil)
        case Launch.trialProduct:
            updated.recordTrial(at: transaction.originalPurchaseDate)
        default:
            return false
        }
        guard updated != lastSaved || updated != entitlement else { return true }
        return await persist(updated)
    }

    private func persist(_ updated: Entitlement) async -> Bool {
        entitlement = updated
        do {
            try await storage.save(updated)
            if entitlement == updated { lastSaved = updated }
            return true
        } catch {
            self.message = L.t("store.localError")
            return false
        }
    }
}
