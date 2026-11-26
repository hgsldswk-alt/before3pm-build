import Foundation

struct Entitlement: Codable, Equatable {
    static let trialLength: TimeInterval = 30 * 24 * 60 * 60
    var firstOpen: Date
    var proStartedAt: Date? = nil
    var trialClaimedAt: Date? = nil
    var purchasedPro = false
    var proPurchasedAt: Date? = nil

    var trialStart: Date {
        let localStart = proStartedAt ?? firstOpen
        return min(localStart, trialClaimedAt ?? localStart)
    }

    var trialEnd: Date { trialStart.addingTimeInterval(Self.trialLength) }

    func hasPro(at now: Date, free: Bool = Launch.isFree) -> Bool {
        free || purchasedPro || (now >= trialStart && now < trialEnd)
    }

    mutating func beginPaidPeriod(at now: Date, free: Bool) {
        if !free && proStartedAt == nil { proStartedAt = now }
    }

    mutating func recordTrial(at originalPurchaseDate: Date) {
        trialClaimedAt = min(trialClaimedAt ?? originalPurchaseDate, originalPurchaseDate)
    }

    mutating func recordPro(purchasedAt: Date, revoked: Bool) {
        if let existing = proPurchasedAt {
            guard purchasedAt > existing || (purchasedAt == existing && revoked) else { return }
        }
        proPurchasedAt = purchasedAt
        purchasedPro = !revoked
    }
}
