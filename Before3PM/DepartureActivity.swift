import ActivityKit
import Foundation
import OSLog

@MainActor
final class DepartureActivity {
    private typealias LiveActivity = Activity<DepartureActivityAttributes>

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Before3PM", category: "LiveActivity")
    private var pending: (plan: TimePlan?, run: TaskRun?)?
    private var startID: UUID?
    private var reconciling = false

    func reconcile(plan: TimePlan?, run: TaskRun?, allowStart: Bool) {
        let appointmentID = plan?.appointment.id
        if allowStart { startID = appointmentID }
        if startID != appointmentID { startID = nil }
        pending = (plan, run)
        guard !reconciling else { return }

        reconciling = true
        Task {
            while let request = pending {
                pending = nil
                await apply(plan: request.plan, run: request.run)
            }
            reconciling = false
        }
    }

    private func apply(plan: TimePlan?, run: TaskRun?) async {
        let now = Date()
        let upcoming = plan.flatMap { $0.leaveAt > now ? $0 : nil }
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        var matching: LiveActivity?
        for activity in LiveActivity.activities {
            let state = activity.activityState
            guard state == .active || state == .stale else { continue }
            if enabled, activity.attributes.appointmentID == upcoming?.appointment.id, matching == nil {
                matching = activity
            } else {
                await activity.end(activity.content, dismissalPolicy: .immediate)
            }
        }

        guard pending == nil else { return }
        let mayStart = startID != nil && startID == upcoming?.appointment.id
        startID = nil
        guard enabled, let upcoming, matching != nil || mayStart else { return }

        let updatedAt = Date()
        let startedAt = matching?.attributes.startedAt ?? run?.startedAt ?? updatedAt
        guard let state = upcoming.departureCountdown(run: run, startedAt: startedAt, at: updatedAt) else {
            if let matching { await matching.end(matching.content, dismissalPolicy: .immediate) }
            return
        }
        let content = ActivityContent(state: state, staleDate: state.leaveAt)
        if let matching {
            if matching.content.state != state || matching.activityState == .stale {
                await matching.update(content)
            }
        } else {
            do {
                let attributes = DepartureActivityAttributes(appointmentID: upcoming.appointment.id, startedAt: startedAt)
                _ = try LiveActivity.request(attributes: attributes, content: content, pushType: nil)
            } catch {
                logger.error("Could not start Live Activity: \(error.localizedDescription)")
            }
        }
    }
}
