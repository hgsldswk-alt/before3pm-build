import Combine
import SwiftUI
import StoreKit
import UIKit
import UniformTypeIdentifiers

private enum Destination: String, Identifiable {
    case settings, edit, importPreset, shortTask, gapCard, milestoneCard, paywall
    var id: String { rawValue }
}

@MainActor
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var purchases: Purchases
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @State private var destination: Destination?
    @State private var showsPresetFiles = false
    @State private var readsPresetFile = false
    @State private var importedPreset: PresetCode?
    @State private var showsInvalidPreset = false
    @State private var candidate: TaskPreset?
    @State private var proposal = TaskFit.skip
    @State private var didLoad = false
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize = 64.0

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Page {
            if !model.ready { loading }
            else {
                HStack(alignment: .top, spacing: 4) {
                    Heading(title: L.t("app.name"), buttonTitle: L.t("settings.title"), buttonID: "home.settings") {
                        destination = .settings
                    }
                    Button {
                        #if DEBUG
                        if Launch.isUITesting, Launch.value("-import-file-fixture") != nil,
                           let code = try? PresetCode(prepMin: 20, travelMin: 25, taskID: nil).encode() {
                            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Before3PM-Preset.txt")
                            try? code.write(to: url, atomically: true, encoding: .utf8)
                            readsPresetFile = true
                            Task { await importPresetFile(.success(url)) }
                            return
                        }
                        #endif
                        showsPresetFiles = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel(L.t("import.title"))
                    .accessibilityIdentifier("home.importPreset")
                }
                if let error = model.error { Text(error).font(.footnote).foregroundStyle(Theme.muted) }
                if let plan = model.plan { appointment(plan) }
                else if let last = model.data.lastAppointment { arrived(last) }
                else { AppointmentForm(existing: nil) {} }
            }
        }
        .disabled(readsPresetFile)
        .sheet(item: $destination) { item in
            switch item {
            case .settings:
                SettingsView()
            case .edit:
                Page {
                    Heading(title: L.t("appointment.edit"), buttonTitle: L.t("common.close"), buttonID: "appointment.close") {
                        destination = nil
                    }
                    AppointmentForm(existing: model.data.appointment, isEditing: true) { destination = nil }
                }
                .presentationDragIndicator(.visible)
            case .importPreset:
                if let importedPreset { presetConfirmation(importedPreset) }
            case .shortTask:
                if let candidate { shortTask(candidate) }
            case .gapCard:
                SharePreview(days: nil)
            case .milestoneCard:
                SharePreview(days: model.data.completedDays)
            case .paywall:
                PaywallView(close: true)
            }
        }
        .fileImporter(isPresented: $showsPresetFiles, allowedContentTypes: [.plainText]) { result in
            readsPresetFile = true
            Task { await importPresetFile(result) }
        }
        .alert(L.t("import.invalid"), isPresented: $showsInvalidPreset) {
            Button(L.t("common.close"), role: .cancel) {}
        }
        #if DEBUG
        .modifier(PresetFileExportFixture())
        #endif
        .task {
            guard !didLoad else { return }
            didLoad = true
            let clock = model.clock
            if Launch.isUITesting && Launch.arguments.contains("-paywall") { destination = .paywall }
            async let loadData: Void = model.load()
            async let loadEntitlement: Void = purchases.load(at: clock, expired: Launch.arguments.contains("-expired"))
            _ = await (loadData, loadEntitlement)
        }
        .onReceive(tick) { _ in
            if scenePhase == .active { model.refresh(); reviewIfReady() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            if scenePhase == .active { model.refresh(reconcile: true) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refresh(reconcile: true)
                Task { await purchases.refreshReceipts() }
            }
            if phase == .background { model.flushOnBackground() }
        }
    }

    @ViewBuilder private var loading: some View {
        if let error = model.error {
            Text(error)
            ActionButton(title: L.t("common.retry"), id: "app.retry", primary: true) {
                Task { await model.load() }
            }
        } else { ProgressView().frame(maxWidth: .infinity, minHeight: 120) }
    }

    private func appointment(_ plan: TimePlan) -> some View {
        let phase = plan.phase(at: model.now)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    if !plan.appointment.title.isEmpty { Text(plan.appointment.title).font(.headline) }
                    Text(DisplayTime.dateTime(plan.appointment.at, now: model.now))
                        .font(.subheadline).foregroundStyle(Theme.muted)
                        .accessibilityIdentifier("home.appointmentTime")
                }
                Spacer()
                Button(L.t("appointment.edit")) { destination = .edit }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 6)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("home.edit")
            }
            if let run = model.data.run { running(run, plan: plan) }
            else { TimeDeck(plan: plan, phase: phase, now: model.now) }
            if phase == .gap && model.data.run == nil { taskList }
            reminderRow
            if phase == .gap && model.data.run == nil { shareRow }
        }
    }

    private func importPresetFile(_ result: Result<URL, Error>) async {
        defer { readsPresetFile = false }
        do {
            let input = try await readPresetFile(result.get())
            importedPreset = try PresetCode.decode(input)
            destination = .importPreset
        } catch let error as CocoaError where error.code == .userCancelled {
            return
        } catch {
            showsInvalidPreset = true
        }
    }

    private func presetConfirmation(_ preset: PresetCode) -> some View {
        Page {
            Heading(title: L.t("import.title"), buttonTitle: L.t("common.close"), buttonID: "import.close") {
                destination = nil
            }
            VStack(alignment: .leading, spacing: 8) {
                presetDetails(preset)
                ActionButton(title: L.t("import.use"), id: "import.use", primary: true) {
                    model.change { $0.apply(preset) }
                    destination = nil
                }
            }.panel()
        }
        .presentationDragIndicator(.visible)
    }

    private func arrived(_ last: Appointment) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t(last.travel == 0 ? "phase.join" : "phase.appointment"))
                    .font(.title.weight(.bold)).accessibilityIdentifier("phase.arrived")
                Text(DisplayTime.dateTime(last.at, now: model.now)).foregroundStyle(Theme.muted)
            }.panel(tinted: true)
            AppointmentForm(existing: nil) {}
            shareRow
        }
    }

    private var taskList: some View {
        let tasks = model.data.visibleTasks(hasPro: purchases.hasPro(at: model.now))
        return VStack(alignment: .leading, spacing: 4) {
            Text(L.t("task.pick")).font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(tasks) { task in
                let fit = model.fit(task)
                RowButton(title: task.title,
                          detail: fit == .full ? DisplayTime.duration(Double(task.minutes) * 60)
                              : L.f("task.tooLongRow", DisplayTime.duration(Double(task.minutes) * 60)),
                          id: "task." + task.id,
                          symbol: fit == .full ? "play.circle" : "clock") {
                    pick(task)
                }
                if task.id != tasks.last?.id {
                    Divider()
                }
            }
        }.panel(inset: 13)
    }

    private func running(_ run: TaskRun, plan: TimePlan) -> some View {
        let left = max(0, run.endsAt.timeIntervalSince(model.now))
        let total = max(1, run.endsAt.timeIntervalSince(run.startedAt))
        return VStack(alignment: .leading, spacing: 11) {
            Text(L.t("run.title")).font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
            Text(run.preset.title).font(.title3.weight(.bold))
            Text(DisplayTime.timer(left))
                .font(.system(size: timerSize, weight: .bold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel(DisplayTime.duration(left))
                .accessibilityIdentifier("run.timer")
            ProgressView(value: min(left / total, 1))
                .accessibilityLabel(L.t("run.progress"))
            TimeMarkers(plan: plan, phase: .gap, now: model.now)
            ViewThatFits(in: .horizontal) {
                HStack { finishButtons }
                VStack { finishButtons }
            }
        }.panel(tinted: true)
    }

    @ViewBuilder private var finishButtons: some View {
        ActionButton(title: L.t("run.done"), id: "run.done", primary: true) { model.finish(.done) }
        ActionButton(title: L.t("run.stop"), id: "run.stop") { model.finish(.stopped) }
    }

    private var reminderRow: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(L.t("reminder." + model.reminderStatus.rawValue),
                  systemImage: model.reminderStatus == .on ? "bell.badge" : "bell")
                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                .accessibilityIdentifier("reminder.status")
            if model.reminderStatus == .denied {
                RowButton(title: L.t("reminder.settings"), id: "reminder.settings") { openNotificationSettings() }
            } else if model.reminderStatus != .on {
                RowButton(title: L.t("reminder.action"), id: "reminder.enable") {
                    Task { await model.enableReminders() }
                }.disabled(model.requestingPermission)
            }
        }.panel(inset: 12)
    }

    private var shareRow: some View {
        let milestone = model.data.completedDays >= 3
        return RowButton(title: L.t(milestone ? "share.milestone" : "share.gap"), id: "home.share",
                         symbol: "square.and.arrow.up") {
            destination = milestone ? .milestoneCard : .gapCard
        }.panel(inset: 12)
    }

    private func pick(_ task: TaskPreset) {
        model.refresh()
        guard model.data.run == nil, model.plan?.phase(at: model.now) == .gap else { return }
        let fit = model.fit(task)
        if fit == .full, model.start(task, minutes: task.minutes) { return }
        guard model.data.run == nil else { return }
        candidate = task
        proposal = model.fit(task)
        destination = .shortTask
    }

    private func shortTask(_ candidate: TaskPreset) -> some View {
        let remaining = model.plan?.gap(at: model.now) ?? 0
        let minutes: Int? = switch proposal {
        case .full: candidate.minutes
        case .shorter(let value): value
        case .skip: nil
        }
        return Page {
            Heading(title: candidate.title, buttonTitle: L.t("common.close"), buttonID: "short.close") {
                destination = nil
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L.t(proposal == .full ? "short.fits" : "short.title"))
                    .font(.headline).accessibilityIdentifier("short.title")
                Text(DisplayTime.duration(remaining))
                    .font(.largeTitle.weight(.bold)).monospacedDigit().foregroundStyle(Theme.accent)
                Text(L.f("short.planned", DisplayTime.duration(Double(candidate.minutes) * 60)))
                    .font(.footnote).foregroundStyle(Theme.muted)
            }.panel(tinted: true)
            if remaining >= 60, let minutes {
                Text(L.t("short.once")).font(.subheadline).foregroundStyle(Theme.muted)
                ActionButton(title: L.f("short.start", DisplayTime.duration(Double(minutes) * 60)),
                             id: "short.start", primary: true) {
                    if model.start(candidate, minutes: minutes) { destination = nil }
                    else { proposal = model.data.run == nil ? model.fit(candidate) : .skip }
                }
            }
            ActionButton(title: L.t("short.skip"), id: "short.skip") { destination = nil }
        }
        .presentationDragIndicator(.visible)
    }

    private func reviewIfReady() {
        let recentlyArrived = model.data.lastAppointment.map { model.now.timeIntervalSince($0.at) < 900 } ?? false
        let hasRoom = model.plan.map { $0.gap(at: model.now) >= 300 } ?? !recentlyArrived
        guard model.ready, !Launch.isUITesting, destination == nil,
              !showsPresetFiles, !readsPresetFile, !showsInvalidPreset, !model.requestingPermission, !purchases.busy,
              model.reminderStatus != .denied, model.reminderStatus != .failed,
              model.data.canRequestReview(at: model.now, hasRoom: hasRoom) else { return }
        model.change { $0.lastReviewRequest = model.now }
        requestReview()
    }
}

@MainActor
func openNotificationSettings() {
    guard !Launch.isUITesting, let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
    UIApplication.shared.open(url)
}
