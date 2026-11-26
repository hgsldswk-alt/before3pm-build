import SwiftUI

@MainActor
struct AppointmentForm: View {
    @EnvironmentObject private var model: AppModel
    @State private var date: Date?
    @State private var prep = ""
    @State private var travel = ""
    @State private var title = ""
    @State private var showsDate = false
    @State private var validation: String?
    @State private var initialized = false
    @FocusState private var focus: Field?

    enum Field { case title, prep, travel }

    let existing: Appointment?
    var isEditing = false
    let onSaved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isEditing {
                Text(L.t("appointment.new")).font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
            }
            RowButton(title: L.t("appointment.date"),
                      detail: date.map { DisplayTime.dateTime($0, now: model.now) } ?? L.t("appointment.chooseDate"),
                      id: "appointment.date", symbol: "calendar") {
                focus = nil
                if date == nil { date = defaultDate }
                showsDate.toggle()
                validation = nil
            }
            if showsDate {
                DatePicker(L.t("appointment.date"), selection: Binding(
                    get: { date ?? defaultDate }, set: { date = $0; validation = nil }
                ), displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .accessibilityIdentifier("appointment.picker")
                if let date {
                    Text(DisplayTime.offset(date)).font(.footnote).foregroundStyle(Theme.muted)
                    if let alternate = Timing.alternateWallTime(for: date), alternate > model.now {
                        RowButton(title: L.f("appointment.otherOffset", DisplayTime.offset(alternate)),
                                  id: "appointment.otherOffset") { self.date = alternate }
                    }
                }
            }
            Divider()
            MinuteField(title: L.t("appointment.prep"), id: "appointment.prep", value: $prep)
                .focused($focus, equals: .prep)
            MinuteField(title: L.t("appointment.travel"), id: "appointment.travel", value: $travel)
                .focused($focus, equals: .travel)
            Divider()
            TextField(L.t("appointment.optionalTitle"), text: $title)
                .textInputAutocapitalization(.sentences)
                .focused($focus, equals: .title)
                .frame(minHeight: 44)
                .accessibilityIdentifier("appointment.name")
            if let validation {
                Text(validation).font(.footnote).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("appointment.validation")
            }
            ActionButton(title: L.t(isEditing ? "appointment.save" : "appointment.set"),
                         id: "appointment.save", primary: true, action: save)
            if isEditing {
                ActionButton(title: L.t("appointment.cancel"), id: "appointment.cancel") {
                    model.cancelAppointment()
                    onSaved()
                }
            }
        }
        .panel()
        .onAppear {
            guard !initialized else { return }
            initialized = true
            date = existing?.at ?? (isEditing ? defaultDate : nil)
            showsDate = isEditing
            prep = String(existing?.prep ?? model.data.settings.defaultPrep)
            travel = String(existing?.travel ?? model.data.settings.defaultTravel)
            title = existing?.title ?? ""
        }
        .onChange(of: model.data.settings.defaultPrep) { _, value in
            if !isEditing && focus != .prep { prep = String(value) }
        }
        .onChange(of: model.data.settings.defaultTravel) { _, value in
            if !isEditing && focus != .travel { travel = String(value) }
        }
    }

    private var defaultDate: Date {
        Date(timeIntervalSince1970: ceil(model.clock.timeIntervalSince1970 / 60) * 60 + 3600)
    }

    private func save() {
        focus = nil
        guard let date, date > model.clock else {
            validation = L.t("appointment.future")
            return
        }
        guard let prep = MinuteField.number(prep), let travel = MinuteField.number(travel),
              TimePlan.validMinutes(prep), TimePlan.validMinutes(travel) else {
            validation = L.t("appointment.range")
            return
        }
        let originalZone = existing.flatMap { $0.at == date ? $0.timeZoneID : nil }
        let result = Appointment(at: date, prep: prep, travel: travel,
                                 title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)),
                                 timeZoneID: originalZone ?? TimeZone.autoupdatingCurrent.identifier)
        if model.saveAppointment(result) {
            validation = nil
            showsDate = false
            onSaved()
        } else {
            validation = L.t("appointment.future")
        }
    }
}

struct MinuteField: View {
    let title: String
    let id: String
    @Binding var value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer(minLength: 6)
            TextField(title, text: $value)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
                .frame(minWidth: 60, minHeight: 44)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel(title)
                .accessibilityIdentifier(id)
            Text(L.t("duration.unit")).font(.footnote).foregroundStyle(Theme.muted)
        }
    }

    static func number(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 3, trimmed.allSatisfy({
            $0.wholeNumberValue.map { (0...9).contains($0) } ?? false
        }) else { return nil }
        return Int(trimmed.compactMap(\.wholeNumberValue).map { String($0) }.joined())
    }
}

struct TimeDeck: View {
    let plan: TimePlan
    let phase: Phase
    let now: Date
    @ScaledMetric(relativeTo: .largeTitle) private var digitSize = 75.0

    private var heading: String { L.t("phase." + phase.rawValue) }
    private var count: TimeInterval {
        switch phase {
        case .gap: return plan.gap(at: now)
        case .prepare: return plan.leaveAt.timeIntervalSince(now)
        case .leave: return plan.appointment.at.timeIntervalSince(now)
        case .join, .appointment: return 0
        }
    }

    private var unit: String {
        if count >= 3600 { return L.t("duration.unit") }
        return L.t(count >= 60 ? "duration.unit" : "duration.secondUnit")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading).font(.headline).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("phase." + phase.rawValue)
            if phase == .gap || phase == .prepare || phase == .leave {
                countdown
            }
            if phase == .gap { segments }
            TimeMarkers(plan: plan, phase: phase, now: now)
        }.panel(tinted: true)
    }

    private var countdown: some View {
        VStack(alignment: .leading, spacing: 4) {
            if count >= 3600 {
                Text(DisplayTime.duration(count))
                    .font(.system(size: min(digitSize * 0.59, 70), weight: .bold, design: .rounded))
                    .monospacedDigit()
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(Int(max(0, count) / (count >= 60 ? 60 : 1))))
                        .font(.system(size: digitSize, weight: .bold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
                    Text(unit).font(.headline)
                }
            }
            if phase != .gap {
                Text(L.t(phase == .leave ? "phase.untilAppointment" :
                         (plan.appointment.travel == 0 ? "phase.untilJoin" : "phase.untilLeave")))
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .foregroundStyle(Theme.accent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DisplayTime.duration(count))
        .accessibilityIdentifier("home.countdown")
    }

    private var segments: some View {
        let durations = [plan.gap(at: now), Double(plan.appointment.prep) * 60, Double(plan.appointment.travel) * 60]
        let total = max(durations.reduce(0, +), 1)
        let colors = [Theme.accent, Theme.prep, Theme.travel]
        return GeometryReader { proxy in
            let visible = durations.indices.filter { durations[$0] > 0 }
            let width = max(0, proxy.size.width - CGFloat(max(0, visible.count - 1)) * 4)
            HStack(spacing: 4) {
                ForEach(visible, id: \.self) { index in
                    Capsule().fill(colors[index]).frame(width: width * CGFloat(durations[index] / total))
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

struct TimeMarkers: View {
    @Environment(\.dynamicTypeSize) private var type
    let plan: TimePlan
    let phase: Phase
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if type.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { markers }
            } else {
                HStack(alignment: .top, spacing: 8) { markers }
            }
            if let zone = TimeZone(identifier: plan.appointment.timeZoneID),
               zone.identifier != TimeZone.autoupdatingCurrent.identifier {
                Text(L.f("appointment.originalZone",
                         zone.localizedName(for: .generic, locale: .current) ?? zone.identifier,
                         DisplayTime.offset(plan.appointment.at, in: zone)))
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
    }

    @ViewBuilder private var markers: some View {
        marker("marker.prepare", plan.prepareAt, active: phase == .prepare)
        marker(plan.appointment.travel == 0 ? "marker.join" : "marker.leave", plan.leaveAt,
               active: phase == .leave || phase == .join)
        marker("marker.appointment", plan.appointment.at, active: phase == .appointment)
    }

    private func marker(_ key: String, _ date: Date, active: Bool) -> some View {
        let sameDay = Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: now)
        return VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(active ? Theme.accent : Theme.line).frame(height: 3).accessibilityHidden(true)
            Text(L.t(key)).font(.caption.weight(.semibold)).foregroundStyle(active ? Theme.accent : Theme.muted)
            Text(sameDay ? DisplayTime.clock(date) : DisplayTime.dateTime(date, now: now))
                .font(.caption.weight(.bold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
