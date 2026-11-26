import ActivityKit
import SwiftUI
import WidgetKit

@main
struct Before3PMWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DepartureActivityAttributes.self) { context in
            DepartureDetails(state: context.state, isStale: context.isStale, onLockScreen: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .activityBackgroundTint(Theme.paper)
                .activitySystemActionForegroundColor(Theme.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    DepartureDetails(state: context.state, isStale: context.isStale, onLockScreen: false)
                        .padding(.horizontal, 8)
                }
            } compactLeading: {
                DepartureSymbol(isOnline: context.state.isOnline, isStale: context.isStale)
            } compactTrailing: {
                if context.isStale {
                    Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                } else {
                    Countdown(interval: context.state.timerInterval)
                        .font(.caption2.weight(.semibold))
                        .frame(width: 50)
                }
            } minimal: {
                DepartureSymbol(isOnline: context.state.isOnline, isStale: context.isStale)
            }
        }
    }
}

private struct DepartureDetails: View {
    let state: DepartureCountdown
    let isStale: Bool
    let onLockScreen: Bool

    private var summary: String {
        if isStale { return state.isOnline ? L.t("live.joinNow") : L.t("live.leaveNow") }
        let time = state.leaveAt.formatted(.dateTime.hour().minute())
        return state.isOnline ? L.f("live.joinCountdown", time) : L.f("live.leaveCountdown", time)
    }

    var body: some View {
        let ink: Color = onLockScreen ? Theme.ink : .primary
        let accent: Color = onLockScreen ? Theme.accent : .primary
        VStack(alignment: .leading, spacing: 4) {
            Text(summary)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(ink)
            if !isStale {
                Countdown(interval: state.timerInterval)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(accent)
                if let task = state.task {
                    HStack(spacing: 6) {
                        Text(task.title).lineLimit(1)
                            .layoutPriority(1)
                        Countdown(interval: task.timerInterval)
                            .frame(width: 50)
                    }
                    .font(.footnote)
                    .foregroundStyle(ink)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Countdown: View {
    let interval: ClosedRange<Date>

    var body: some View {
        Text(timerInterval: interval, pauseTime: interval.upperBound, countsDown: true)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.leading)
    }
}

private struct DepartureSymbol: View {
    let isOnline: Bool
    let isStale: Bool

    var body: some View {
        Image(systemName: isOnline ? "video" : "figure.walk")
            .accessibilityLabel(Text(label))
    }

    private var label: String {
        if isOnline { return isStale ? L.t("live.joinNow") : L.t("live.joinTimer") }
        return isStale ? L.t("live.leaveNow") : L.t("live.leaveTimer")
    }
}
