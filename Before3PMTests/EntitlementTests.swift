import Foundation
import XCTest

final class EntitlementTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_781_532_480)

    func testPaidTrialStartsAtFirstOpenAndEndsAtThirtyDays() {
        let value = Entitlement(firstOpen: now)
        XCTAssertFalse(Launch.freePeriod)
        XCTAssertTrue(value.hasPro(at: now, free: false))
        XCTAssertTrue(value.hasPro(at: now.addingTimeInterval(29 * 86400), free: false))
        XCTAssertTrue(value.hasPro(at: now.addingTimeInterval(30 * 86400 - 1), free: false))
        XCTAssertFalse(value.hasPro(at: now.addingTimeInterval(30 * 86400), free: false))
        XCTAssertFalse(value.hasPro(at: now.addingTimeInterval(31 * 86400), free: false))
    }

    func testFreeVersionUpgradeStartsPaidTrialOnce() {
        var value = Entitlement(firstOpen: now.addingTimeInterval(-90 * 86400))
        value.beginPaidPeriod(at: now.addingTimeInterval(-60 * 86400), free: true)
        XCTAssertNil(value.proStartedAt)
        XCTAssertTrue(value.hasPro(at: now, free: true))
        value.beginPaidPeriod(at: now, free: false)
        value.beginPaidPeriod(at: now.addingTimeInterval(86400), free: false)
        XCTAssertEqual(value.proStartedAt, now)
        XCTAssertTrue(value.hasPro(at: now, free: false))
    }

    func testReceiptRestorationUsesEarliestVerifiedStart() {
        var value = Entitlement(firstOpen: now, proStartedAt: now)
        let original = now.addingTimeInterval(-35 * 86400)
        value.recordTrial(at: now.addingTimeInterval(86400))
        XCTAssertEqual(value.trialStart, now)
        value.recordTrial(at: original)
        value.recordTrial(at: now)
        XCTAssertEqual(value.trialStart, original)
        XCTAssertFalse(value.hasPro(at: now, free: false))
    }

    func testLifetimeAndRevocationAfterTrial() throws {
        let old = now.addingTimeInterval(-40 * 86400)
        var value = Entitlement(firstOpen: old, proStartedAt: old)
        value.recordPro(purchasedAt: now, revoked: false)
        value = try JSONDecoder().decode(Entitlement.self, from: JSONEncoder().encode(value))
        XCTAssertTrue(value.hasPro(at: now, free: false))
        value.recordPro(purchasedAt: now, revoked: true)
        value.recordPro(purchasedAt: now, revoked: false)
        XCTAssertFalse(value.hasPro(at: now, free: false))
        value.recordPro(purchasedAt: now.addingTimeInterval(1), revoked: false)
        XCTAssertTrue(value.hasPro(at: now.addingTimeInterval(1), free: false))
    }
}
