import SwiftUI

enum Theme {
    static let accent = Color(red: 1.0, green: 0.68, blue: 0.30)
    static let bgTop = Color(red: 0.07, green: 0.06, blue: 0.06)
    static let bgBottom = Color(red: 0.02, green: 0.02, blue: 0.03)
    static let card = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.08)
    static let off = Color(white: 0.45)
    static let danger = Color(red: 1, green: 0.45, blue: 0.42)

    static func background(_ glow: Color = accent, strength: Double = 0.22) -> some View {
        ZStack {
            LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [glow.opacity(strength), .clear], center: .top, startRadius: 10, endRadius: 540)
        }
        .ignoresSafeArea()
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.5))
    }
}

extension Int {
    /// Minutes after midnight -> Date today, for DatePicker bindings.
    var asTime: Date {
        Calendar.current.date(bySettingHour: self / 60, minute: self % 60, second: 0, of: .now) ?? .now
    }
}

extension Date {
    var minutesOfDay: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: self)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

func timeBinding(_ b: Binding<Int>) -> Binding<Date> {
    Binding(get: { b.wrappedValue.asTime }, set: { b.wrappedValue = $0.minutesOfDay })
}
