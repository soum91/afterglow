import SwiftUI

/// Options shared by Equinox and Afterglow. This view edits only the scene's
/// configuration: the phone or Keystone runtime decides when to execute it.
struct SceneAutomationRows: View {
    @Binding var automation: SceneAutomation?
    var supportsFade = false
    @ObservedObject private var geo = Geo.shared

    private func updated(_ edit: (inout SceneAutomation) -> Void) {
        var item = automation ?? SceneAutomation()
        edit(&item)
        automation = item.event == .none ? nil : item
    }

    private func intBinding(_ keyPath: WritableKeyPath<SceneAutomation, Int>) -> Binding<Int> {
        Binding(get: { (automation ?? SceneAutomation())[keyPath: keyPath] },
                set: { newValue in updated { $0[keyPath: keyPath] = newValue } })
    }

    private func doubleBinding(_ keyPath: WritableKeyPath<SceneAutomation, Double>) -> Binding<Double> {
        Binding(get: { (automation ?? SceneAutomation())[keyPath: keyPath] },
                set: { newValue in updated { $0[keyPath: keyPath] = newValue } })
    }

    private func boolBinding(_ keyPath: WritableKeyPath<SceneAutomation, Bool>) -> Binding<Bool> {
        Binding(get: { (automation ?? SceneAutomation())[keyPath: keyPath] },
                set: { newValue in updated { $0[keyPath: keyPath] = newValue } })
    }

    private func timeBinding(_ keyPath: WritableKeyPath<SceneAutomation, Int>) -> Binding<Date> {
        Binding(get: {
            let minutes = (automation ?? SceneAutomation())[keyPath: keyPath]
            return Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(minutes * 60))
        }, set: { newDate in
            let time = Calendar.current.dateComponents([.hour, .minute], from: newDate)
            updated { $0[keyPath: keyPath] = (time.hour ?? 0) * 60 + (time.minute ?? 0) }
        })
    }

    var body: some View {
        Picker("Additional trigger", selection: Binding(
            get: { automation?.event ?? .none },
            set: { choice in updated { $0.event = choice } })) {
            ForEach(AutomationEvent.allCases) { event in
                Text(event.title).tag(event)
            }
        }

        if let automation {
            switch automation.event {
            case .clock:
                DatePicker("Run at", selection: timeBinding(\.minuteOfDay), displayedComponents: .hourAndMinute)
            case .sunset, .lastLight:
                Picker("Offset", selection: intBinding(\.solarOffsetMinutes)) {
                    Text("30 minutes before").tag(-30)
                    Text("15 minutes before").tag(-15)
                    Text("At event").tag(0)
                    Text("15 minutes after").tag(15)
                    Text("30 minutes after").tag(30)
                }
            case .cloudy:
                Stepper("Cloud cover ≥ \(automation.cloudThreshold)%", value: intBinding(\.cloudThreshold), in: 50...95, step: 5)
            case .roomAbove, .roomBelow, .outsideAbove, .outsideBelow:
                Stepper("Threshold: \(automation.temperatureC.formatted(.number.precision(.fractionLength(1))))°C",
                        value: doubleBinding(\.temperatureC), in: -30...50, step: 0.5)
            case .none:
                EmptyView()
            }

            Toggle("Only during a time window", isOn: boolBinding(\.timeWindow))
            if automation.timeWindow {
                DatePicker("From", selection: timeBinding(\.windowStart), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: timeBinding(\.windowEnd), displayedComponents: .hourAndMinute)
            }

            if automation.event != .cloudy {
                Toggle("Only when cloudy", isOn: boolBinding(\.onlyIfCloudy))
                if automation.onlyIfCloudy {
                    Stepper("Cloud cover ≥ \(automation.cloudThreshold)%", value: intBinding(\.cloudThreshold), in: 50...95, step: 5)
                }
            }

            Picker("Temperature condition", selection: Binding(
                get: { self.automation?.condition ?? .none },
                set: { choice in updated { $0.condition = choice } })) {
                ForEach(AutomationConditionKind.allCases) { condition in
                    Text(condition.title).tag(condition)
                }
            }
            if automation.condition != .none {
                Stepper("Condition: \(automation.conditionTemperatureC.formatted(.number.precision(.fractionLength(1))))°C",
                        value: doubleBinding(\.conditionTemperatureC), in: -30...50, step: 0.5)
            }

            if supportsFade {
                Picker("Gradual brightness", selection: intBinding(\.fadeSeconds)) {
                    Text("Instant").tag(0)
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                    Text("30 minutes").tag(1800)
                }
                Text("Gradual transitions work only on dimmable lights. A paired Keystone can finish a long transition with the phone closed.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if geo.home == nil && (automation.event.isSolar || automation.event.needsWeather ||
                                  automation.onlyIfCloudy || automation.condition == .outsideAbove || automation.condition == .outsideBelow) {
                Label("Set Home in Settings for solar and outdoor weather rules.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
    }
}
