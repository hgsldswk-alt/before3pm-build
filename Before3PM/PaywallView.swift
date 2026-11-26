import SwiftUI

@MainActor
struct PaywallView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var purchases: Purchases
    @Environment(\.dismiss) private var dismiss
    var close = false

    var body: some View {
        Page {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("paywall.title")).font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("paywall.title")
                    Text(L.t("paywall.once")).font(.subheadline).foregroundStyle(Theme.muted)
                }
                Spacer()
                if close {
                    Button { dismiss() } label: {
                        Text(L.t("common.close")).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                        .accessibilityIdentifier("paywall.close")
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(stateTitle).font(.headline).accessibilityIdentifier("paywall.state")
                Text(L.t("paywall.basic")).font(.subheadline).foregroundStyle(Theme.muted)
            }.panel(tinted: true)
            VStack(alignment: .leading, spacing: 12) {
                Text(L.t("paywall.unlock")).font(.headline)
                ForEach(["paywall.tasks", "paywall.templates", "paywall.history"], id: \.self) { key in
                    Label(L.t(key), systemImage: "checkmark").font(.subheadline)
                }
                if purchases.entitlement?.purchasedPro != true {
                    buyButton
                }
            }.panel()
            if purchases.entitlement?.trialClaimedAt == nil && purchases.entitlement?.purchasedPro != true {
                ActionButton(title: L.t("paywall.trial"), id: "paywall.trial") {
                    Task { await purchases.buy(purchases.trial) }
                }.disabled(purchases.busy)
                Text(L.t("paywall.trialDetails")).font(.footnote).foregroundStyle(Theme.muted)
            }
            ActionButton(title: L.t("paywall.restore"), id: "paywall.restore") {
                Task { await purchases.restore() }
            }.disabled(purchases.busy)
            if purchases.busy { ProgressView() }
            if let message = purchases.message {
                Text(message).font(.footnote).foregroundStyle(Theme.muted).accessibilityIdentifier("paywall.message")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await purchases.loadProducts() }
    }

    private var stateTitle: String {
        guard let entitlement = purchases.entitlement else { return L.t("paywall.freeCore") }
        if entitlement.purchasedPro { return L.t("paywall.owned") }
        if entitlement.hasPro(at: model.now, free: false) {
            let date = entitlement.trialEnd.formatted(.dateTime.year().month(.abbreviated).day())
            return L.f("paywall.until", date)
        }
        return L.t("paywall.expired")
    }

    private var buyButton: some View {
        let price = purchases.pro?.displayPrice ?? (Launch.isUITesting ? "US$2.99" : nil)
        return ActionButton(title: price.map { L.f("paywall.buy", $0) } ?? L.t("paywall.price"),
                            id: "paywall.buy", primary: true) {
            Task { await purchases.buy(purchases.pro) }
        }.disabled(purchases.busy)
    }
}
