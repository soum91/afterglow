import SwiftUI
import WidgetKit
import AppIntents

struct FavouriteLightEntry: TimelineEntry { var date: Date; var light: LightSnap? }
struct FavouriteLightProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FavouriteLightEntry { .init(date: .now, light: nil) }
    func snapshot(for configuration: FavouriteLightConfig, in context: Context) async -> FavouriteLightEntry { make(configuration) }
    func timeline(for configuration: FavouriteLightConfig, in context: Context) async -> Timeline<FavouriteLightEntry> {
        await Lights.refresh()
        return Timeline(entries: [make(configuration)], policy: .after(.now.addingTimeInterval(900)))
    }
    func make(_ config: FavouriteLightConfig) -> FavouriteLightEntry { .init(date: .now, light: LightStore.snaps().first { $0.id == config.light?.id }) }
}
struct FavouriteLightWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AfterglowFavouriteLight", intent: FavouriteLightConfig.self, provider: FavouriteLightProvider()) { entry in
            FavouriteLightView(entry: entry).containerBackground(for: .widget) { Color.clear }
        }.configurationDisplayName("Favourite light").description("Choose a light for a dedicated Lock Screen switch.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
struct FavouriteLightView: View {
    @Environment(\.widgetFamily) var family
    var entry: FavouriteLightEntry
    var body: some View {
        if let s = entry.light {
            Button(intent: ToggleLightIntent(light: LightEntity(id: s.id, name: s.name))) {
                if family == .accessoryCircular {
                    ZStack { AccessoryWidgetBackground(); Image(systemName: s.isOn ? "lightbulb.fill" : "lightbulb") }
                } else {
                    VStack(alignment: .leading) {
                        Label(s.name, systemImage: s.isOn ? "lightbulb.fill" : "lightbulb").font(.headline)
                        Text(!s.online ? "Offline" : s.isOn ? "On · \(s.percent)%" : "Off").font(.caption)
                    }
                }
            }.buttonStyle(.plain)
        } else if family == .accessoryCircular {
            Image(systemName: "lightbulb")
                .font(.system(size: 20, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Label("Choose a light", systemImage: "lightbulb").font(.caption)
        }
    }
}
@available(iOS 18.0, *) struct LightBrightnessControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "com.soum91.afterglow.brightness", intent: BrightnessConfig.self) { config in
            ControlWidgetButton(action: StepLightIntent(config.light, config.direction)) {
                Label(config.direction == .brighter ? "Brighter" : "Dimmer", systemImage: config.direction == .brighter ? "sun.max.fill" : "sun.min.fill")
            }
        }.displayName("Light brightness").description("Adjust a selected light by ten percentage points.")
    }
}
