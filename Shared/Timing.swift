import Foundation

enum Phase: String, Codable {
    case gap, prepare, leave, join, appointment
}

struct Appointment: Codable, Equatable, Identifiable {
    var id = UUID()
    var revision = 0
    var at: Date
    var prep: Int
    var travel: Int
    var title = ""
    var timeZoneID = TimeZone.current.identifier
}

struct TimePlan: Equatable {
    var appointment: Appointment
    var leaveAt: Date { appointment.at.addingTimeInterval(-Double(appointment.travel) * 60) }
    var prepareAt: Date { leaveAt.addingTimeInterval(-Double(appointment.prep) * 60) }

    func gap(at now: Date) -> TimeInterval { max(0, prepareAt.timeIntervalSince(now)) }

    func phase(at now: Date) -> Phase {
        if now >= appointment.at { return appointment.travel == 0 && appointment.prep == 0 ? .join : .appointment }
        if now >= leaveAt { return appointment.travel == 0 ? .join : .leave }
        if now >= prepareAt { return .prepare }
        return .gap
    }

    static func validMinutes(_ value: Int) -> Bool { (0...240).contains(value) }

    func isValid(at now: Date) -> Bool {
        appointment.at > now && Self.validMinutes(appointment.prep) && Self.validMinutes(appointment.travel)
    }

    func departureCountdown(run: TaskRun?, startedAt: Date, at now: Date) -> DepartureCountdown? {
        let departure = leaveAt
        guard now < departure else { return nil }

        var task: DepartureCountdown.RunningTask?
        if let run {
            let taskEnd = min(run.endsAt, prepareAt)
            if now < taskEnd {
                let title = String(decoding: run.preset.title.utf8.prefix(256), as: UTF8.self)
                task = .init(title: title, timerInterval: min(run.startedAt, now)...taskEnd)
            }
        }
        return DepartureCountdown(timerInterval: min(startedAt, now)...departure,
                                  isOnline: appointment.travel == 0, task: task)
    }
}

enum TaskFit: Equatable {
    case full, shorter(Int), skip
}

struct TaskPreset: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var minutes: Int
    var canShorten = true

    var title: String {
        switch id {
        case "break": return L.t("task.break")
        case "desk": return L.t("task.desk")
        case "read": return L.t("task.read")
        default: return name
        }
    }

    static let builtIns = [
        TaskPreset(id: "break", name: "", minutes: 5),
        TaskPreset(id: "desk", name: "", minutes: 10),
        TaskPreset(id: "read", name: "", minutes: 30)
    ]
}

enum RunOutcome: String, Codable, CaseIterable {
    case done, stopped, elapsed, interrupted
}

struct TaskRun: Codable, Equatable, Identifiable {
    var id = UUID()
    var preset: TaskPreset
    var startedAt: Date
    var endsAt: Date
}

struct CompletionRecord: Codable, Equatable, Identifiable {
    var run: TaskRun
    var endedAt: Date
    var outcome: RunOutcome
    var useDay: String?
    var id: UUID { run.id }
}

enum Timing {
    static func fit(_ task: TaskPreset, gap: TimeInterval) -> TaskFit {
        guard task.minutes > 0 else { return .skip }
        if Double(task.minutes) * 60 <= gap { return .full }
        let minutes = Int(max(0, gap) / 60)
        guard task.canShorten, minutes >= 1 else { return .skip }
        return .shorter(minutes >= 10 ? (minutes / 10) * 10 : minutes)
    }

    static func start(_ task: TaskPreset, confirmedMinutes: Int, plan: TimePlan, at now: Date) -> TaskRun? {
        let fit = fit(task, gap: plan.gap(at: now))
        guard (fit == .full && confirmedMinutes == task.minutes) || fit == .shorter(confirmedMinutes),
              (1...240).contains(confirmedMinutes) else { return nil }
        return TaskRun(preset: task, startedAt: now,
                       endsAt: min(now.addingTimeInterval(Double(confirmedMinutes) * 60), plan.prepareAt))
    }

    static func shorten(_ run: TaskRun, for plan: TimePlan) -> TaskRun {
        var shortened = run
        shortened.endsAt = min(run.endsAt, plan.prepareAt)
        return shortened
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = calendar.timeZone
        let parts = localCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func alternateWallTime(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        let wallTime = calendar.dateComponents([.hour, .minute], from: date)
        let beforeDay = calendar.startOfDay(for: date).addingTimeInterval(-1)
        guard let first = calendar.nextDate(after: beforeDay, matching: wallTime, matchingPolicy: .strict,
                                            repeatedTimePolicy: .first),
              let last = calendar.nextDate(after: beforeDay, matching: wallTime, matchingPolicy: .strict,
                                           repeatedTimePolicy: .last),
              first != last, calendar.isDate(first, inSameDayAs: date),
              calendar.isDate(last, inSameDayAs: date) else { return nil }
        return abs(first.timeIntervalSince(date)) < 60 ? last : first
    }
}

enum ReminderPhase: String {
    case prepare, leave, join, task
}

struct Reminder: Equatable {
    var id: String
    var phase: ReminderPhase
    var at: Date
}

extension TimePlan {
    func reminders(run: TaskRun?, after now: Date) -> [Reminder] {
        let prefix = "before3pm.\(appointment.id.uuidString).\(appointment.revision)."
        var schedule: [Reminder] = []
        func add(_ phase: ReminderPhase, _ date: Date, suffix: String = "") {
            guard date > now, !schedule.contains(where: {
                ceil($0.at.timeIntervalSince1970) == ceil(date.timeIntervalSince1970)
            }) else { return }
            schedule.append(Reminder(id: prefix + phase.rawValue + suffix, phase: phase, at: date))
        }
        add(appointment.travel == 0 ? .join : .leave, leaveAt)
        add(.prepare, prepareAt)
        if let run { add(.task, run.endsAt, suffix: "." + run.id.uuidString) }
        return schedule.sorted { $0.at < $1.at }
    }
}
