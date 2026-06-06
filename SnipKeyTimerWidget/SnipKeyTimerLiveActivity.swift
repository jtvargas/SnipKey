//
//  SnipKeyTimerLiveActivity.swift
//  SnipKeyTimerWidget
//
//  The Live Activity that renders SnipKey's AlarmKit timers on the Lock Screen and in the Dynamic
//  Island. AlarmKit requires a widget extension hosting this for a countdown presentation —
//  without it the system may dismiss the alarm. Keyed on the shared `SnipKeyTimerAttributes`
//  (which is an `ActivityAttributes`); its content state is `AlarmPresentationState`.
//  See INTEGRATIONS.md / the `/timer` plan.
//

import AlarmKit
import SwiftUI
import WidgetKit

struct SnipKeyTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SnipKeyTimerAttributes.self) { context in
            // Lock Screen / banner presentation.
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.title2)
                    .foregroundStyle(context.attributes.tintColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Timer")
                        .font(.headline)
                    countdownText(context.state)
                        .font(.system(.title2, design: .rounded).monospacedDigit())
                        .foregroundStyle(context.attributes.tintColor)
                }
                Spacer()
            }
            .padding()
            .activitySystemActionForegroundColor(context.attributes.tintColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer")
                        .foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.center) {
                    countdownText(context.state)
                        .font(.system(.title, design: .rounded).monospacedDigit())
                        .foregroundStyle(context.attributes.tintColor)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                countdownText(context.state)
                    .monospacedDigit()
                    .foregroundStyle(context.attributes.tintColor)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(context.attributes.tintColor)
            }
            .widgetURL(URL(string: "snipkey://open"))
        }
    }

    /// Live-updating countdown for the timer's current mode.
    @ViewBuilder
    private func countdownText(_ state: AlarmPresentationState) -> some View {
        switch state.mode {
        case .countdown(let countdown):
            // System-driven live countdown to the fire date.
            Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
        case .paused(let paused):
            // Static remaining time while paused.
            let remaining = max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)
            Text(Self.format(remaining))
        case .alert:
            Text("Done")
        @unknown default:
            Text("Timer")
        }
    }

    /// "HH:MM:SS" for a paused remaining duration.
    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
