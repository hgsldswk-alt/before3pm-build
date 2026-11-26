import Foundation
import ActivityKit

struct DepartureCountdown: Codable, Hashable {
    struct RunningTask: Codable, Hashable {
        let title: String
        let timerInterval: ClosedRange<Date>
    }

    let timerInterval: ClosedRange<Date>
    let isOnline: Bool
    let task: RunningTask?

    var leaveAt: Date { timerInterval.upperBound }
}

struct DepartureActivityAttributes: ActivityAttributes {
    typealias ContentState = DepartureCountdown

    let appointmentID: UUID
    let startedAt: Date
}
