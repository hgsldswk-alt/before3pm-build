import Foundation
import SwiftUI
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var data = LocalState()
    @Published private(set) var now = Date()
    @Published private(set) var ready = false
    @Published private(set) var error: String?
    @Published private(set) var reminderStatus = ReminderStatus.off
    @Published private(set) var requestingPermission = false

    private let storage = LocalStorage(isTesting: Launch.isUITesting)
    private let reminders = ReminderScheduler()
    private let departureActivity = DepartureActivity()
    private var saving = false
    private var needsSave = false
    private var loading = false

    var clock: Date { Fixture.clock ?? Date() }
    var plan: TimePlan? { data.appointment.map { TimePlan(appointment: $0) } }

    func load() async {
        guard !ready, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let reset = Launch.isUITesting && Launch.arguments.contains("-reset")
            data = try await storage.load(reset: reset)
            if reset, let fixture = Fixture.state { data = fixture }
            ready = true
            error = nil
            refresh(reconcile: true)
        } catch {
            self.error = L.t("app.loadError")
        }
    }

    func refresh(reconcile: Bool = false) {
        guard ready else { return }
        let previous = now
        now = clock
        var updated = data
        updated.advance(at: now)
        if updated != data {
            change { $0 = updated }
            return
        }
        if reconcile { enqueueSave() }
        if reconcile || plan.map({ previous < $0.leaveAt && now >= $0.leaveAt }) == true {
            reconcileDepartureActivity()
        }
    }

    func change(startDepartureActivity: Bool = false, _ transform: (inout LocalState) -> Void) {
        guard ready else { return }
        var updated = data
        transform(&updated)
        guard updated != data else { return }
        let countdownChanged = updated.appointment != data.appointment || updated.run != data.run
        data = updated
        enqueueSave()
        if countdownChanged { reconcileDepartureActivity(allowStart: startDepartureActivity) }
    }

    private func reconcileDepartureActivity(allowStart: Bool = false) {
        guard !Launch.isUITesting else { return }
        departureActivity.reconcile(plan: plan, run: data.run, allowStart: allowStart)
    }

    func saveAppointment(_ appointment: Appointment) -> Bool {
        refresh()
        guard TimePlan(appointment: appointment).isValid(at: now) else { return false }
        change { $0.setAppointment(appointment, at: now) }
        return true
    }

    func cancelAppointment() {
        refresh()
        change { $0.cancel(at: now) }
    }

    func fit(_ task: TaskPreset) -> TaskFit {
        Timing.fit(task, gap: plan?.gap(at: now) ?? 0)
    }

    func start(_ task: TaskPreset, minutes: Int) -> Bool {
        refresh()
        guard let plan, data.run == nil,
              let run = Timing.start(task, confirmedMinutes: minutes, plan: plan, at: now) else { return false }
        change(startDepartureActivity: true) { $0.run = run }
        return true
    }

    func finish(_ outcome: RunOutcome) {
        refresh()
        change { $0.finish(outcome, at: now) }
    }

    func enableReminders() async {
        guard !requestingPermission else { return }
        requestingPermission = true
        defer { requestingPermission = false }
        let status = Launch.isUITesting
            ? (Fixture.reminderStatus == .denied ? ReminderStatus.denied : .on)
            : await reminders.requestPermission()
        reminderStatus = status
        guard status != .failed else { return }
        change { $0.settings.reminders = true }
        if status == .on { refresh(reconcile: true) }
    }

    func disableReminders() { change { $0.settings.reminders = false } }

    func flushOnBackground() {
        guard !Launch.isUITesting, saving || needsSave, backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save appointment") { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
    }

    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func enqueueSave() {
        needsSave = true
        guard !saving else { return }
        saving = true
        Task { await saveLatest() }
    }

    private func saveLatest() async {
        defer {
            saving = false
            endBackgroundTask()
        }
        while needsSave {
            needsSave = false
            let snapshot = data
            do {
                try await storage.save(snapshot)
                error = nil
            } catch {
                self.error = L.t("app.saveError")
                if needsSave { continue }
                return
            }
            guard !needsSave else { continue }
            let schedule = snapshot.appointment.map {
                TimePlan(appointment: $0).reminders(run: snapshot.run, after: clock)
            } ?? []
            if Launch.isUITesting {
                reminderStatus = Fixture.reminderStatus ?? (snapshot.settings.reminders ? .on : .enable)
            } else {
                let status = await reminders.reconcile(schedule, enabled: snapshot.settings.reminders)
                if !needsSave { reminderStatus = status }
            }
        }
    }
}
