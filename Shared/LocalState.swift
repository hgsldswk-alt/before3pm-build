import Foundation

struct TravelTemplate: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var prep: Int
    var travel: Int
}

struct Settings: Codable, Equatable {
    var defaultPrep = 10
    var defaultTravel = 15
    var preferredTaskID: String? = nil
    var reminders = false
    var pickedTaskIDs: [String]? = nil
    var templates: [TravelTemplate]? = nil

    enum CodingKeys: String, CodingKey {
        case defaultPrep, defaultTravel, preferredTaskID, reminders, pickedTaskIDs, templates
    }

    init() {}

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        defaultPrep = try box.decodeIfPresent(Int.self, forKey: .defaultPrep) ?? 10
        defaultTravel = try box.decodeIfPresent(Int.self, forKey: .defaultTravel) ?? 15
        preferredTaskID = try box.decodeIfPresent(String.self, forKey: .preferredTaskID)
        reminders = try box.decodeIfPresent(Bool.self, forKey: .reminders) ?? false
        pickedTaskIDs = try box.decodeIfPresent([String].self, forKey: .pickedTaskIDs)
        templates = try box.decodeIfPresent([TravelTemplate].self, forKey: .templates)
    }
}

struct LocalState: Codable, Equatable {
    var appointment: Appointment?
    var lastAppointment: Appointment?
    var run: TaskRun?
    var tasks: [TaskPreset] = []
    var history: [CompletionRecord] = []
    var settings = Settings()
    var sharedOrExported = false
    var lastReviewRequest: Date? = nil

    enum CodingKeys: String, CodingKey {
        case appointment, lastAppointment, run, tasks, history, settings, sharedOrExported, lastReviewRequest
    }

    init() {}

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        appointment = try box.decodeIfPresent(Appointment.self, forKey: .appointment)
        lastAppointment = try box.decodeIfPresent(Appointment.self, forKey: .lastAppointment)
        run = try box.decodeIfPresent(TaskRun.self, forKey: .run)
        tasks = try box.decodeIfPresent([TaskPreset].self, forKey: .tasks) ?? []
        history = try box.decodeIfPresent([CompletionRecord].self, forKey: .history) ?? []
        settings = try box.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        sharedOrExported = try box.decodeIfPresent(Bool.self, forKey: .sharedOrExported) ?? false
        lastReviewRequest = try box.decodeIfPresent(Date.self, forKey: .lastReviewRequest)
    }

    var completedDays: Int { Set(history.compactMap(\.useDay)).count }

    func canRequestReview(at now: Date, hasRoom: Bool) -> Bool {
        hasRoom && run == nil && completedDays >= 3
            && (lastReviewRequest.map { now.timeIntervalSince($0) >= 120 * 86400 } ?? true)
    }

    func visibleTasks(hasPro: Bool) -> [TaskPreset] {
        let allowed = settings.pickedTaskIDs.map { ids in tasks.filter { ids.contains($0.id) } } ?? tasks
        var result = TaskPreset.builtIns + (hasPro ? tasks : Array(allowed.prefix(3)))
        if let index = result.firstIndex(where: { $0.id == settings.preferredTaskID }) {
            let preferred = result.remove(at: index)
            result.insert(preferred, at: 0)
        }
        return result
    }

    mutating func finish(_ outcome: RunOutcome, at now: Date, calendar: Calendar = .current) {
        guard let run else { return }
        self.run = nil
        guard !history.contains(where: { $0.id == run.id }) else { return }
        let beforePrepare = appointment.map { now < TimePlan(appointment: $0).prepareAt } ?? false
        let useDay = outcome == .done && beforePrepare ? Timing.dayKey(now, calendar: calendar) : nil
        history.insert(CompletionRecord(run: run, endedAt: max(run.startedAt, now), outcome: outcome, useDay: useDay), at: 0)
    }

    mutating func advance(at now: Date) {
        guard let appointment else {
            if run != nil { finish(.interrupted, at: now) }
            return
        }
        let plan = TimePlan(appointment: appointment)
        if let run, now >= run.endsAt || now >= plan.prepareAt {
            finish(.elapsed, at: min(run.endsAt, plan.prepareAt))
        }
        if now >= appointment.at {
            lastAppointment = appointment
            self.appointment = nil
        }
    }

    mutating func setAppointment(_ newValue: Appointment, at now: Date) {
        advance(at: now)
        var updated = newValue
        if let existing = appointment {
            updated.id = existing.id
            updated.revision = existing.revision + 1
        }
        appointment = updated
        lastAppointment = nil
        if let run {
            let shortened = Timing.shorten(run, for: TimePlan(appointment: updated))
            if shortened.endsAt <= now {
                finish(.interrupted, at: now)
            } else {
                self.run = shortened
            }
        }
    }

    mutating func cancel(at now: Date) {
        advance(at: now)
        finish(.interrupted, at: now)
        appointment = nil
        lastAppointment = nil
    }

    mutating func apply(_ preset: PresetCode) {
        settings.defaultPrep = preset.prepMin
        settings.defaultTravel = preset.travelMin
        settings.preferredTaskID = preset.taskID
    }
}

enum HistoryCSV {
    static func make(_ history: [CompletionRecord]) -> String {
        let formatter = ISO8601DateFormatter()
        let header = ["csv.task", "csv.start", "csv.finish", "csv.result"].map { quote(L.t($0)) }.joined(separator: ",")
        let rows = history.map { record in
            [safeCell(record.run.preset.title), formatter.string(from: record.run.startedAt),
             formatter.string(from: record.endedAt), L.t("outcome." + record.outcome.rawValue)]
                .map(quote).joined(separator: ",")
        }
        return "\u{FEFF}" + ([header] + rows).joined(separator: "\r\n") + "\r\n"
    }

    private static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func safeCell(_ value: String) -> String {
        guard let leading = value.drop(while: { $0.isWhitespace }).first,
              "=+-@".contains(leading) else { return value }
        return "'" + value
    }
}
