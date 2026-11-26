import SwiftUI
import UIKit

@MainActor
struct SharePreview: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var delivery = ShareDelivery()
    @State private var image: UIImage?
    @State private var cardError = false
    @State private var copyStatus: String?
    let days: Int?

    private var downloadURL: URL {
        ShareCard.downloadURL(appStoreID: Bundle.main.infoDictionary?["APP_STORE_ID"] as? String)
    }

    var body: some View {
        Page {
            Heading(title: L.t(days == nil ? "share.gap" : "share.milestone"), subtitle: L.t("share.preview"),
                    buttonTitle: L.t("common.close"), buttonID: "share.close") { dismiss() }
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel(cardLabel)
                    .accessibilityIdentifier("share.card")
            } else if cardError {
                Text(L.t("share.failure")).font(.footnote).foregroundStyle(Theme.muted)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 220)
            }
            ActionButton(title: L.t("share.image"), id: "share.image", primary: true, action: send)
                .disabled(image == nil || delivery.preparing)
            ActionButton(title: L.t("share.copy"), id: "share.copy", action: copy)
            delivery.status
            if let copyStatus {
                Text(copyStatus).font(.footnote).accessibilityIdentifier("share.copied")
            }
        }
        .modifier(ShareSheet(delivery: delivery))
        .task {
            let count = days
            let url = downloadURL
            image = await Task.detached(priority: .userInitiated) { ShareCard.render(days: count, url: url) }.value
            cardError = image == nil
        }
    }

    private var cardLabel: String {
        [L.t("share.headline"), days.map { L.f("share.days", $0) }, L.t("share.caption"), L.t("share.hashtags")]
            .compactMap { $0 }.joined(separator: " ")
    }

    private func send() {
        guard let image else { return }
        delivery.send(filename: "Before3PM.png", extra: L.t("share.text"), data: {
            image.pngData()
        }, complete: { model.change { $0.sharedOrExported = true } })
    }

    private func copy() {
        let defaults = model.data.settings
        let code = PresetCode(prepMin: model.plan?.appointment.prep ?? defaults.defaultPrep,
                              travelMin: model.plan?.appointment.travel ?? defaults.defaultTravel,
                              taskID: defaults.preferredTaskID)
        do {
            let output = try code.encode()
            if !Launch.isUITesting { UIPasteboard.general.string = output }
            copyStatus = L.t("share.copied")
        } catch {
            copyStatus = L.t("share.failure")
        }
    }
}

@MainActor
final class ShareDelivery: ObservableObject {
    struct Payload: Identifiable {
        var id = UUID()
        var url: URL
        var extra: String?
        var complete: () -> Void
    }

    @Published var payload: Payload?
    @Published private(set) var preparing = false
    @Published private var requested = false
    @Published private var failed = false
    private var cleanupURL: URL?

    @ViewBuilder var status: some View {
        if requested {
            Text(L.t("share.requested")).font(.footnote).accessibilityIdentifier("share.requested")
        }
        if failed { Text(L.t("share.failure")).font(.footnote).foregroundStyle(Theme.muted) }
    }

    func send(filename: String, extra: String? = nil, data: @escaping @Sendable () -> Data?,
              complete: @escaping () -> Void) {
        guard !preparing, payload == nil else { return }
        requested = false
        failed = false
        preparing = true
        Task {
            defer { preparing = false }
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    guard let bytes = data() else { throw CocoaError(.fileWriteUnknown) }
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let path = folder.appendingPathComponent(filename)
                    do {
                        try bytes.write(to: path, options: .atomic)
                        return path
                    } catch {
                        try? FileManager.default.removeItem(at: folder)
                        throw error
                    }
                }.value
                cleanupURL = url
                if Launch.isUITesting {
                    requested = true
                    cleanup()
                } else {
                    payload = Payload(url: url, extra: extra, complete: complete)
                }
            } catch {
                failed = true
            }
        }
    }

    func cleanup() {
        guard let folder = cleanupURL?.deletingLastPathComponent() else { return }
        cleanupURL = nil
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: folder) }
    }
}

@MainActor
struct ShareSheet: ViewModifier {
    @ObservedObject var delivery: ShareDelivery

    func body(content: Content) -> some View {
        content.sheet(item: $delivery.payload, onDismiss: { delivery.cleanup() }) { payload in
            ActivityView(payload: payload) { completed, error in
                if completed && error == nil { payload.complete() }
                delivery.payload = nil
                delivery.cleanup()
            }
            .presentationDetents([.medium, .large])
        }
    }
}

@MainActor
private struct ActivityView: UIViewControllerRepresentable {
    let payload: ShareDelivery.Payload
    let finished: (Bool, Error?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = [payload.url]
        if let extra = payload.extra { items.append(extra) }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            Task { @MainActor in finished(completed, error) }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
