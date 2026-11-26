import Foundation
#if DEBUG
import SwiftUI
import UniformTypeIdentifiers
#endif

enum Fixture {
    static var name: String? { Launch.isUITesting ? Launch.value("-fixture") : nil }
    static let example = Date(timeIntervalSince1970: 1_781_532_480)
    static var clock: Date? { name == nil ? nil : example }

    static var reminderStatus: ReminderStatus? {
        switch name {
        case "denied": return .denied
        case "ready", "leave": return .on
        default: return nil
        }
    }

    static var state: LocalState? {
        guard let name else { return nil }
        var state = LocalState()
        guard name != "empty" else { return state }
        let offset: TimeInterval
        switch name {
        case "ready": offset = 20 * 60
        case "leave": offset = 10 * 60
        case "arrived", "online": offset = -60
        default: offset = 52 * 60
        }
        let online = name == "online"
        state.appointment = Appointment(at: example.addingTimeInterval(offset), prep: online ? 0 : 10,
                                        travel: online ? 0 : 15,
                                        timeZoneID: "Etc/UTC")
        state.settings.reminders = name == "ready" || name == "leave"
        if name == "milestone" || name == "expired" {
            let desk = TaskPreset.builtIns[1]
            state.history = (1...3).map { day in
                let start = example.addingTimeInterval(-Double(day) * 86400)
                let run = TaskRun(preset: desk, startedAt: start, endsAt: start.addingTimeInterval(600))
                return CompletionRecord(run: run, endedAt: run.endsAt, outcome: .done,
                                        useDay: Timing.dayKey(start))
            }
        }
        if name == "expired" {
            state.tasks = (1...4).map { TaskPreset(id: "fixture.\($0)", name: "Task \($0)", minutes: 5) }
            state.settings.templates = [TravelTemplate(name: "Train", prep: 15, travel: 20)]
        }
        return state
    }
}

#if DEBUG
struct PresetFileExportFixture: ViewModifier {
    @State private var showsExporter = false
    @State private var didPresent = false

    func body(content: Content) -> some View {
        if Launch.isUITesting, let name = Launch.value("-export-preset-fixture") {
            content.fileExporter(isPresented: $showsExporter, document: PresetFile(), contentType: .plainText,
                                 defaultFilename: name) { _ in }
                .onAppear {
                    guard !didPresent else { return }
                    didPresent = true
                    showsExporter = true
                }
        } else {
            content
        }
    }

    private struct PresetFile: FileDocument {
        static var readableContentTypes: [UTType] { [.plainText] }

        init() {}

        init(configuration: ReadConfiguration) throws { throw CocoaError(.fileReadUnknown) }

        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            let code = try PresetCode(prepMin: 20, travelMin: 25, taskID: nil).encode()
            return FileWrapper(regularFileWithContents: Data(code.utf8))
        }
    }
}
#endif
