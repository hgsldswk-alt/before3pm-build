import SwiftUI

extension Theme {
    static let muted = Color(red: 87 / 255, green: 84 / 255, blue: 101 / 255)
    static let line = Color(red: 224 / 255, green: 218 / 255, blue: 234 / 255)
    static let wash = Color(red: 238 / 255, green: 233 / 255, blue: 250 / 255)
    static let prep = Color(red: 133 / 255, green: 113 / 255, blue: 174 / 255)
    static let travel = Color(red: 214 / 255, green: 199 / 255, blue: 236 / 255)
}

extension View {
    func panel(tinted: Bool = false, inset: CGFloat = 16) -> some View {
        padding(inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tinted ? Theme.wash : .white, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.line)
                    .allowsHitTesting(false)
            }
    }
}

struct Page<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .frame(maxWidth: 530)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
    }
}

struct ActionButton: View {
    let title: String
    let id: String
    var primary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .foregroundStyle(primary ? .white : Theme.accent)
                .background(primary ? Theme.accent : .white, in: RoundedRectangle(cornerRadius: 13))
                .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(primary ? Theme.accent : Theme.line) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

struct RowButton: View {
    let title: String
    var detail: String?
    let id: String
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol).foregroundStyle(Theme.accent).accessibilityHidden(true)
                }
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Spacer(minLength: 4)
                if let detail {
                    Text(detail).font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent).multilineTextAlignment(.trailing)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent).accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

struct Heading: View {
    let title: String
    var subtitle: String?
    var buttonTitle: String?
    var buttonID: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Theme.muted) }
            }
            Spacer(minLength: 0)
            if let buttonTitle, let buttonID, let action {
                Button(action: action) {
                    Text(buttonTitle).font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .foregroundStyle(Theme.accent)
                .accessibilityIdentifier(buttonID)
            }
        }
    }
}

enum DisplayTime {
    static func duration(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds))
        if whole >= 3600 { return L.f("duration.hours", whole / 3600, (whole / 60) % 60) }
        if whole >= 60 { return L.f("duration.minutes", whole / 60) }
        return L.f("duration.seconds", whole)
    }

    static func timer(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, ceil(seconds)))
        return String(format: "%02d:%02d", whole / 60, whole % 60)
    }

    static func dateTime(_ date: Date, now: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let day = date.formatted(.dateTime.month(.abbreviated).day())
        let time = clock(date)
        if calendar.isDate(date, inSameDayAs: now) { return L.f("date.today", day, time) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return L.f("date.tomorrow", day, time)
        }
        return date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute())
    }

    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    static func offset(_ date: Date, in zone: TimeZone = .autoupdatingCurrent) -> String {
        let offset = zone.secondsFromGMT(for: date)
        return String(format: "UTC%@%02d:%02d", offset < 0 ? "−" : "+", abs(offset) / 3600, abs(offset / 60) % 60)
    }
}
