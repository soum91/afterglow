import AppIntents
import WidgetKit

struct FavouriteLightConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Favourite light"
    @Parameter(title: "Light") var light: LightEntity?
}
enum LightStep: String, AppEnum {
    case brighter, dimmer
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Brightness"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.brighter: "Brighter", .dimmer: "Dimmer"]
}
@available(iOS 18.0, *) struct BrightnessConfig: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Light brightness"
    @Parameter(title: "Light") var light: LightEntity?
    @Parameter(title: "Direction", default: .brighter) var direction: LightStep
}
struct StepLightIntent: AppIntent {
    #if WIDGET_EXTENSION
    // The widget extension cannot be launched to run intents on this iOS, so
    // Shortcuts must only see (and run) the copy inside the app.
    static let isDiscoverable = false
    #endif
    static var title: LocalizedStringResource = "Adjust Light Brightness"
    @Parameter(title: "Light") var light: LightEntity?
    @Parameter(title: "Direction") var direction: LightStep
    init() { direction = .brighter }
    init(_ light: LightEntity?, _ direction: LightStep) { self.light = light; self.direction = direction }
    func perform() async throws -> some IntentResult {
        await Lights.refresh()
        let targets = LightStore.snaps().filter { ($0.id == light?.id || light == nil || light?.isAll == true) && $0.canDim }
        guard !targets.isEmpty else { throw TuyaError(message: "No dimmable light found for this control.") }
        for target in targets { try await Lights.setBrightness(target.id, percent: max(1, min(100, target.percent + (direction == .brighter ? 10 : -10)))) }
        return .result()
    }
}
