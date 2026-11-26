import SwiftUI

@MainActor
struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var purchases: Purchases
    @StateObject private var delivery = ShareDelivery()
    @State private var choice: RunOutcome?
    @State private var range = HistoryRange.all
    @State private var showsPro = false

    private enum HistoryRange: String, CaseIterable {
        case all, week, month

        func includes(_ date: Date, now: Date, calendar: Calendar = .current) -> Bool {
            guard self != .all else { return true }
            let days = self == .week ? -6 : -29
            guard let start = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))
            else { return true }
            return date >= start
        }
    }

    private var hasPro: Bool { purchases.hasPro(at: model.now) }

    private var records: [CompletionRecord] {
        guard hasPro else { return model.data.history }
        return model.data.history.filter {
            (choice == nil || $0.outcome == choice) && range.includes($0.endedAt, now: model.now)
        }
    }

    var body: some View {
        Page {
            ActionButton(title: L.t("history.export"), id: "history.export", primary: true, action: export)
                .disabled(delivery.preparing)
            delivery.status
            if hasPro {
                VStack(alignment: .leading, spacing: 4) {
                    Picker(L.t("history.dateRange"), selection: $range) {
                        ForEach(HistoryRange.allCases, id: \.self) { value in
                            Text(L.t("history.range." + value.rawValue)).tag(value)
                        }
                    }.accessibilityIdentifier("history.range")
                    Picker(L.t("history.filter"), selection: $choice) {
                        Text(L.t("history.all")).tag(nil as RunOutcome?)
                        ForEach(RunOutcome.allCases, id: \.self) { item in
                            Text(L.t("outcome." + item.rawValue)).tag(Optional(item))
                        }
                    }.accessibilityIdentifier("history.filter")
                }.panel(inset: 10)
            }
            if records.isEmpty {
                Text(L.t("history.empty")).font(.subheadline).foregroundStyle(Theme.muted).panel()
            }
            ForEach(records) { record in
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.run.preset.title).font(.headline)
                    Text(record.endedAt.formatted(.dateTime.year().month(.abbreviated).day().hour().minute()))
                        .font(.subheadline)
                    Text(L.t("outcome." + record.outcome.rawValue)).font(.footnote).foregroundStyle(Theme.muted)
                }.panel()
            }
        }
        .navigationTitle(L.t("settings.history"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .modifier(ShareSheet(delivery: delivery))
        .sheet(isPresented: $showsPro) { PaywallView(close: true) }
    }

    private func export() {
        model.refresh()
        guard hasPro else { showsPro = true; return }
        let snapshot = records
        delivery.send(filename: "Before3PM.csv", data: {
            Data(HistoryCSV.make(snapshot).utf8)
        }, complete: { model.change { $0.sharedOrExported = true } })
    }
}
