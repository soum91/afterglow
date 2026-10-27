import SwiftUI
import WidgetKit

// Read-only Lock Screen status, built exactly like DewPoint's 1x1 temperature widget,
// the one Lock Screen widget that renders on iOS 27 beta 4 with sideloaded builds:
// static configuration, cached data only (no network in the timeline), no buttons,
// no accessory background. Tapping it opens the app.
struct AfterglowLockEntry: TimelineEntry {
    var date: Date
    var lights: [LightSnap]
    var onCount: Int { lights.filter(\.isOn).count }
    var icon: String { onCount > 0 ? "lightbulb.fill" : "lightbulb" }
    var short: String { lights.isEmpty ? "--" : (onCount > 0 ? "\(onCount) on" : "Off") }
    var title: String { "Lights" }
    var headline: String { lights.isEmpty ? "Open Afterglow" : (onCount > 0 ? "\(onCount) of \(lights.count) on" : "All off") }
    var detail: String { lights.first(where: \.isOn).map { "\($0.name) \($0.percent)%" } ?? "" }
    static func make() -> AfterglowLockEntry { .init(date: .now, lights: LightStore.snaps()) }
}

struct AfterglowLockProvider: TimelineProvider {
    func placeholder(in context: Context) -> AfterglowLockEntry { AfterglowLockEntry.make() }
    func getSnapshot(in context: Context, completion: @escaping (AfterglowLockEntry) -> Void) { completion(AfterglowLockEntry.make()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AfterglowLockEntry>) -> Void) {
        completion(Timeline(entries: [AfterglowLockEntry.make()], policy: .after(.now.addingTimeInterval(900))))
    }
}

struct AfterglowLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AfterglowLockStatusV1", provider: AfterglowLockProvider()) { entry in
            AfterglowLockView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Lights status")
        .description("How many lights are on. Tap to open Afterglow.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct AfterglowLockView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AfterglowLockEntry

    var body: some View {
        Group {
            if family == .accessoryCircular {
                VStack(spacing: 1) {
                    Image(systemName: entry.icon)
                        .font(.system(size: 16, weight: .semibold))
                    Text(entry.short)
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: entry.icon)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.title).font(.caption2).lineLimit(1)
                        Text(entry.headline).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                        if !entry.detail.isEmpty {
                            Text(entry.detail).font(.caption2).lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}


// Interactive 1x1 Lock Screen control that intentionally uses the exact
// SetLightPowerIntent already proven to work in the Home Screen widget.
// Kept separate from the read-only status widget to compare iOS host paths.
struct AfterglowLockSwitchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AfterglowLockSwitchV1", provider: AfterglowLockProvider()) { entry in
            AfterglowLockSwitchView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Light switch 1x1")
        .description("Toggle your Afterglow lights directly from the Lock Screen.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct AfterglowLockSwitchView: View {
    let entry: AfterglowLockEntry

    var body: some View {
        Group {
            if entry.lights.isEmpty {
                Image(systemName: "lightbulb")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Button(intent: SetLightPowerIntent(light: .all, on: entry.onCount == 0)) {
                    VStack(spacing: 1) {
                        Image(systemName: entry.icon)
                            .font(.system(size: 20, weight: .semibold))
                        Text(entry.short)
                            .font(.system(size: 10, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
