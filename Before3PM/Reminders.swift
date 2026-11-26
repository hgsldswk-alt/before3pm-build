import Foundation
import UserNotifications

enum ReminderStatus: String {
    case off, enable, denied, on, failed
}

actor ReminderScheduler {
    private struct Request {
        var reminders: [Reminder]
        var enabled: Bool
    }

    private let center = UNUserNotificationCenter.current()
    private var latest: Request?
    private var running = false
    private var waiters: [CheckedContinuation<ReminderStatus, Never>] = []

    func authorization() async -> ReminderStatus {
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral: return .on
        case .denied: return .denied
        default: return .enable
        }
    }

    func requestPermission() async -> ReminderStatus {
        let status = await authorization()
        guard status == .enable else { return status }
        do {
            return try await center.requestAuthorization(options: [.alert, .sound]) ? .on : .denied
        } catch {
            return .failed
        }
    }

    func reconcile(_ reminders: [Reminder], enabled: Bool) async -> ReminderStatus {
        await withCheckedContinuation { continuation in
            latest = Request(reminders: reminders, enabled: enabled)
            waiters.append(continuation)
            guard !running else { return }
            running = true
            Task { await drain() }
        }
    }

    private func drain() async {
        var status = ReminderStatus.off
        while let request = latest {
            latest = nil
            status = await apply(request)
        }
        running = false
        for waiter in waiters { waiter.resume(returning: status) }
        waiters.removeAll()
    }

    private func apply(_ request: Request) async -> ReminderStatus {
        let permission = await authorization()
        let desired = request.enabled && permission == .on ? request.reminders : []
        let pending = await center.pendingNotificationRequests()
        let owned = pending.filter { $0.identifier.hasPrefix("before3pm.") }
        let ids = Set(desired.map(\.id))
        let obsolete = owned.filter { !ids.contains($0.identifier) }.map(\.identifier)
        if !obsolete.isEmpty { center.removePendingNotificationRequests(withIdentifiers: obsolete) }

        var status: ReminderStatus = request.enabled || permission != .on ? permission : .off
        for reminder in desired {
            let fire = Date(timeIntervalSince1970: ceil(reminder.at.timeIntervalSince1970))
            guard fire > Date() else { continue }
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(secondsFromGMT: 0)!
            var components = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
            components.calendar = utc
            components.timeZone = utc.timeZone
            let content = UNMutableNotificationContent()
            content.title = L.t("notification." + reminder.phase.rawValue)
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
            } catch {
                status = .failed
            }
        }
        return status
    }
}
