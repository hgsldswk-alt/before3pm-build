import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var purchases: Purchases
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var showsFiles = false
    @State private var importStatus: String?
    @State private var prep = ""
    @State private var travel = ""
    @State private var defaultsStatus: String?
    @FocusState private var focusesCode: Bool

    private var preview: PresetCode? { try? PresetCode.decode(code) }

    var body: some View {
        NavigationStack {
            Page {
                Heading(title: L.t("settings.title"), buttonTitle: L.t("common.done"), buttonID: "settings.done") {
                    dismiss()
                }
                navigationRows
                importSection
                defaults
                notifications
            }
            .navigationBarHidden(true)
        }
        .presentationDragIndicator(.visible)
        .fileImporter(isPresented: $showsFiles, allowedContentTypes: [.plainText]) { result in
            Task { await readFile(result) }
        }
        .onAppear { copyDefaults() }
    }

    private var navigationRows: some View {
        VStack(spacing: 0) {
            navigation("settings.history", id: "settings.history") { HistoryView() }
            Divider()
            navigation("settings.tasks", id: "settings.tasks") { TaskSettings() }
            Divider()
            navigation("settings.templates", id: "settings.templates") { TemplateSettings() }
            if !Launch.isFree {
                Divider()
                navigation("paywall.title", id: "settings.pro") {
                    PaywallView().toolbar(.visible, for: .navigationBar)
                }
            }
        }.panel(inset: 12)
    }

    private func navigation<Content: View>(_ key: String, id: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationLink(destination: content()) {
            HStack {
                Text(L.t(key)).font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("import.title")).font(.headline).accessibilityAddTraits(.isHeader)
            TextField(L.t("import.field"), text: Binding(get: { code }, set: setCode), axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusesCode)
                .lineLimit(1...3)
                .frame(minHeight: 44)
                .accessibilityIdentifier("import.code")
            ViewThatFits(in: .horizontal) {
                HStack { importActions }
                VStack { importActions }
            }
            if let preview {
                presetDetails(preview)
                ActionButton(title: L.t("import.use"), id: "import.use", primary: true) {
                    focusesCode = false
                    model.change { $0.apply(preview) }
                    copyDefaults()
                    importStatus = L.t("import.applied")
                }
                if purchases.hasPro(at: model.now) {
                    ActionButton(title: L.t("import.template"), id: "import.template") {
                        focusesCode = false
                        model.refresh()
                        guard purchases.hasPro(at: model.now) else { return }
                        let template = TravelTemplate(name: L.t("import.templateName"),
                                                      prep: preview.prepMin, travel: preview.travelMin)
                        model.change { $0.settings.templates = ($0.settings.templates ?? []) + [template] }
                        importStatus = L.t("import.templateSaved")
                    }
                }
            }
            if let message = importStatus ?? (!code.isEmpty && preview == nil ? L.t("import.invalid") : nil) {
                Text(message).font(.footnote).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("import.status")
            }
        }.panel()
    }

    @ViewBuilder private var importActions: some View {
        if Launch.isUITesting {
            ActionButton(title: L.t("import.paste"), id: "import.paste") {
                setCode(ProcessInfo.processInfo.environment["UITEST_PRESET_CODE"] ?? "")
            }
        } else {
            PasteButton(payloadType: String.self) { items in
                if let value = items.first { setCode(value) }
            }
            .labelStyle(.titleAndIcon)
            .frame(minHeight: 48)
            .accessibilityLabel(L.t("import.paste"))
            .accessibilityIdentifier("import.paste")
        }
        ActionButton(title: L.t("import.file"), id: "import.file") { showsFiles = true }
    }

    private var defaults: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L.t("settings.defaults")).font(.headline).accessibilityAddTraits(.isHeader)
            MinuteField(title: L.t("appointment.prep"), id: "defaults.prep", value: $prep)
            MinuteField(title: L.t("appointment.travel"), id: "defaults.travel", value: $travel)
            ActionButton(title: L.t("common.save"), id: "defaults.save") {
                guard let p = MinuteField.number(prep), let t = MinuteField.number(travel),
                      TimePlan.validMinutes(p), TimePlan.validMinutes(t) else {
                    defaultsStatus = L.t("appointment.range")
                    return
                }
                model.change { $0.settings.defaultPrep = p; $0.settings.defaultTravel = t }
                defaultsStatus = L.t("settings.defaultsSaved")
            }
            if let defaultsStatus { Text(defaultsStatus).font(.footnote).foregroundStyle(Theme.muted) }
        }.panel()
    }

    private var notifications: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L.t("settings.reminders")).font(.headline).accessibilityAddTraits(.isHeader)
            Text(L.t("reminder." + model.reminderStatus.rawValue)).font(.footnote).foregroundStyle(Theme.muted)
            if model.reminderStatus == .denied {
                ActionButton(title: L.t("reminder.settings"), id: "settings.notificationSettings") {
                    openNotificationSettings()
                }
            } else if model.reminderStatus != .on {
                ActionButton(title: L.t("reminder.action"), id: "settings.enableReminders") {
                    Task { await model.enableReminders() }
                }.disabled(model.requestingPermission)
            }
            if model.data.settings.reminders {
                ActionButton(title: L.t("reminder.disable"), id: "settings.disableReminders") {
                    model.disableReminders()
                }
            }
        }.panel()
    }

    private func copyDefaults() {
        prep = String(model.data.settings.defaultPrep)
        travel = String(model.data.settings.defaultTravel)
    }

    private func setCode(_ value: String) {
        code = value
        importStatus = nil
    }

    private func readFile(_ result: Result<URL, Error>) async {
        do {
            let input = try await readPresetFile(result.get())
            _ = try PresetCode.decode(input)
            setCode(input)
        } catch let error as CocoaError where error.code == .userCancelled {
            return
        } catch {
            code = ""
            importStatus = L.t("import.invalid")
        }
    }
}

func readPresetFile(_ url: URL) async throws -> String {
    try await Task.detached(priority: .userInitiated) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: PresetCode.maxBytes + 1) ?? Data()
        guard data.count <= PresetCode.maxBytes, let value = String(data: data, encoding: .utf8) else {
            throw PresetCode.CodeError.invalid
        }
        return value
    }.value
}

@ViewBuilder
func presetDetails(_ preset: PresetCode) -> some View {
    Text(presetSummary(preset.prepMin, preset.travelMin))
        .font(.subheadline.weight(.semibold))
        .accessibilityIdentifier("import.preview")
    if let task = TaskPreset.builtIns.first(where: { $0.id == preset.taskID }) {
        Text(task.title).font(.footnote).foregroundStyle(Theme.muted)
    }
}

func presetSummary(_ prep: Int, _ travel: Int) -> String {
    L.f("import.summary", DisplayTime.duration(Double(prep) * 60), DisplayTime.duration(Double(travel) * 60))
}

@MainActor
struct TaskSettings: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var purchases: Purchases
    @State private var editing: TaskPreset?
    @State private var showsPro = false

    private var hasPro: Bool { purchases.hasPro(at: model.now) }
    private var canAdd: Bool { hasPro || model.data.tasks.count < 3 }

    var body: some View {
        Page {
            if !hasPro && model.data.tasks.count >= 3 {
                Text(L.t("tasks.limit")).font(.footnote).foregroundStyle(Theme.muted)
            }
            ActionButton(title: L.t("tasks.add"), id: "tasks.add", primary: true) {
                if canAdd { editing = TaskPreset(name: "", minutes: 5) }
                else { showsPro = true }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(TaskPreset.builtIns) { task in
                    HStack {
                        Text(task.title)
                        Spacer()
                        Text(DisplayTime.duration(Double(task.minutes) * 60)).foregroundStyle(Theme.muted)
                    }.font(.subheadline).frame(minHeight: 44)
                }
            }.panel(inset: 12)

            ForEach(model.data.tasks) { task in
                VStack(alignment: .leading, spacing: 0) {
                    RowButton(title: task.title, detail: DisplayTime.duration(Double(task.minutes) * 60),
                              id: "tasks.edit." + task.id) { editing = task }
                    if !hasPro && model.data.tasks.count > 3 {
                        let selected = picked.contains(task.id)
                        Toggle(L.t("tasks.onHome"), isOn: Binding(get: { selected }, set: { choose(task, on: $0) }))
                            .disabled(!selected && picked.count >= 3)
                            .accessibilityIdentifier("tasks.pick." + task.id)
                    }
                }.panel(inset: 12)
            }
        }
        .navigationTitle(L.t("settings.tasks"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $editing) { TaskEditor(task: $0) }
        .sheet(isPresented: $showsPro) { PaywallView(close: true) }
    }

    private var picked: [String] {
        model.data.visibleTasks(hasPro: false).filter { task in
            model.data.tasks.contains { $0.id == task.id }
        }.map(\.id)
    }

    private func choose(_ task: TaskPreset, on: Bool) {
        var next = picked.filter { $0 != task.id }
        if on && next.count < 3 { next.append(task.id) }
        model.change { $0.settings.pickedTaskIDs = next }
    }
}

@MainActor
struct TaskEditor: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var purchases: Purchases
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var minutes = ""
    @State private var shorten = true
    @State private var message: String?
    @State private var delete = false
    let task: TaskPreset

    var body: some View {
        Page {
            Heading(title: L.t("tasks.edit"), buttonTitle: L.t("common.close"), buttonID: "taskEditor.close") { dismiss() }
            VStack(alignment: .leading, spacing: 10) {
                TextField(L.t("common.name"), text: $name)
                    .frame(minHeight: 44).accessibilityIdentifier("taskEditor.name")
                MinuteField(title: L.t("tasks.duration"), id: "taskEditor.minutes", value: $minutes)
                Toggle(L.t("tasks.shorten"), isOn: $shorten)
                    .frame(minHeight: 44).accessibilityIdentifier("taskEditor.shorten")
                if let message { Text(message).font(.footnote).foregroundStyle(Theme.muted) }
                ActionButton(title: L.t("common.save"), id: "taskEditor.save", primary: true, action: save)
                if model.data.tasks.contains(where: { $0.id == task.id }) {
                    ActionButton(title: L.t("common.delete"), id: "taskEditor.delete") { delete = true }
                }
            }.panel()
        }
        .onAppear { name = task.name; minutes = String(task.minutes); shorten = task.canShorten }
        .confirmationDialog(L.t("tasks.delete"), isPresented: $delete, titleVisibility: .visible) {
            Button(L.t("common.delete"), role: .destructive) {
                model.change {
                    $0.tasks.removeAll { $0.id == task.id }
                    $0.settings.pickedTaskIDs?.removeAll { $0 == task.id }
                }
                dismiss()
            }
        }
    }

    private func save() {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let number = MinuteField.number(minutes), (1...240).contains(number) else {
            message = L.t("tasks.invalid")
            return
        }
        model.refresh()
        let existing = model.data.tasks.firstIndex { $0.id == task.id }
        guard existing != nil || purchases.hasPro(at: model.now) || model.data.tasks.count < 3 else {
            message = L.t("tasks.limit")
            return
        }
        let updated = TaskPreset(id: task.id, name: String(name.prefix(80)), minutes: number, canShorten: shorten)
        model.change {
            if let existing { $0.tasks[existing] = updated }
            else {
                let wasPicked = $0.settings.pickedTaskIDs
                $0.tasks.append(updated)
                if let wasPicked, wasPicked.count < 3 { $0.settings.pickedTaskIDs = wasPicked + [updated.id] }
            }
        }
        dismiss()
    }
}

@MainActor
struct TemplateSettings: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var purchases: Purchases
    @State private var editing: TravelTemplate?
    @State private var showsPro = false
    @State private var applied = false

    private var hasPro: Bool { purchases.hasPro(at: model.now) }

    var body: some View {
        Page {
            ActionButton(title: L.t("templates.add"), id: "templates.add", primary: true) {
                if hasPro {
                    editing = TravelTemplate(name: "", prep: model.data.settings.defaultPrep,
                                             travel: model.data.settings.defaultTravel)
                } else { showsPro = true }
            }
            if let templates = model.data.settings.templates {
                ForEach(templates) { template in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(template.name).font(.headline)
                        Text(presetSummary(template.prep, template.travel)).font(.footnote).foregroundStyle(Theme.muted)
                        if hasPro {
                            ActionButton(title: L.t("templates.use"), id: "templates.use." + template.id.uuidString) {
                                model.refresh()
                                guard hasPro else { return }
                                model.change {
                                    $0.settings.defaultPrep = template.prep
                                    $0.settings.defaultTravel = template.travel
                                }
                                applied = true
                            }
                            ActionButton(title: L.t("common.edit"), id: "templates.edit." + template.id.uuidString) {
                                editing = template
                            }
                        }
                    }.panel()
                }
            }
            if applied { Text(L.t("settings.defaultsSaved")).font(.footnote) }
        }
        .navigationTitle(L.t("settings.templates"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $editing) { TemplateEditor(template: $0) }
        .sheet(isPresented: $showsPro) { PaywallView(close: true) }
    }
}

@MainActor
struct TemplateEditor: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var purchases: Purchases
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var prep = ""
    @State private var travel = ""
    @State private var message: String?
    @State private var delete = false
    let template: TravelTemplate

    var body: some View {
        Page {
            Heading(title: L.t("settings.templates"), buttonTitle: L.t("common.close"), buttonID: "templateEditor.close") {
                dismiss()
            }
            VStack(alignment: .leading, spacing: 8) {
                TextField(L.t("common.name"), text: $name)
                    .frame(minHeight: 44).accessibilityIdentifier("templateEditor.name")
                MinuteField(title: L.t("appointment.prep"), id: "templateEditor.prep", value: $prep)
                MinuteField(title: L.t("appointment.travel"), id: "templateEditor.travel", value: $travel)
                if let message { Text(message).font(.footnote).foregroundStyle(Theme.muted) }
                ActionButton(title: L.t("common.save"), id: "templateEditor.save", primary: true, action: save)
                if (model.data.settings.templates ?? []).contains(where: { $0.id == template.id }) {
                    ActionButton(title: L.t("common.delete"), id: "templateEditor.delete") { delete = true }
                }
            }.panel()
        }
        .onAppear { name = template.name; prep = String(template.prep); travel = String(template.travel) }
        .confirmationDialog(L.t("templates.delete"), isPresented: $delete, titleVisibility: .visible) {
            Button(L.t("common.delete"), role: .destructive) {
                model.refresh()
                guard purchases.hasPro(at: model.now) else { dismiss(); return }
                model.change { $0.settings.templates?.removeAll { $0.id == template.id } }
                dismiss()
            }
        }
    }

    private func save() {
        model.refresh()
        guard purchases.hasPro(at: model.now) else { dismiss(); return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { message = L.t("templates.name"); return }
        guard let prep = MinuteField.number(prep), let travel = MinuteField.number(travel),
              TimePlan.validMinutes(prep), TimePlan.validMinutes(travel) else {
            message = L.t("appointment.range")
            return
        }
        let item = TravelTemplate(id: template.id, name: String(name.prefix(80)), prep: prep, travel: travel)
        model.change {
            var templates = $0.settings.templates ?? []
            if let index = templates.firstIndex(where: { $0.id == item.id }) { templates[index] = item }
            else { templates.append(item) }
            $0.settings.templates = templates
        }
        dismiss()
    }
}
