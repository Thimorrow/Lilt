import AppKit
import CoreText
import SwiftUI

// Notch design and motion: Vayun Godara, https://vayun.net/studies/lilt/. Values mirror the original CSS.
enum Lilt {
    static let ink = Color(red: 0xf6 / 255, green: 0xef / 255, blue: 0xe7 / 255)
    static let accent1 = Color(red: 1, green: 0x7a / 255, blue: 0x45 / 255)
    static let accent2 = Color(red: 0x45 / 255, green: 0xd8 / 255, blue: 0xcd / 255)
    static let accent3 = Color(red: 1, green: 0xc9 / 255, blue: 0x4f / 255)
    static let warning = Color(red: 1, green: 0xb8 / 255, blue: 0x9b / 255)
    static let destructive = Color(red: 1, green: 0xb0 / 255, blue: 0x94 / 255)
    static let error = Color(red: 1, green: 0x95 / 255, blue: 0x6b / 255)
    static let complete = Color(red: 0xa7 / 255, green: 0xe2 / 255, blue: 0xa1 / 255)
    static let menu = Color(red: 0x1c / 255, green: 0x19 / 255, blue: 0x19 / 255)
    static let field = Color(red: 0x10 / 255, green: 0x0e / 255, blue: 0x0e / 255)
    static let fieldBorder = Color(red: 0x4c / 255, green: 0x45 / 255, blue: 0x40 / 255)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        registerFont()
        return .custom("Familjen Grotesk", fixedSize: size).weight(weight)
    }

    private static let registered: Void = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Fonts/familjen-grotesk.woff2") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()
    static func registerFont() { _ = registered }
}

/// The original 520 ms piecewise-linear spring: `linear(0, 0.062 3.5%, …, 1)`.
enum LiltCurve {
    static let springStops: [(t: Double, v: Double)] = [
        (0, 0), (0.035, 0.062), (0.085, 0.24), (0.145, 0.5), (0.215, 0.76), (0.29, 0.93),
        (0.38, 1.024), (0.46, 1.042), (0.56, 1.03), (0.70, 1.008), (1, 1)
    ]

    static func spring(_ progress: Double) -> Double {
        let t = min(1, max(0, progress))
        for index in 1..<springStops.count where t <= springStops[index].t {
            let a = springStops[index - 1], b = springStops[index]
            return a.v + (b.v - a.v) * (t - a.t) / (b.t - a.t)
        }
        return 1
    }
}

struct LiltSpring: CustomAnimation {
    var duration: TimeInterval = 0.52

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard time < duration else { return nil }
        return value.scaled(by: LiltCurve.spring(time / duration))
    }
}

extension Animation {
    static let liltSpring = Animation(LiltSpring())
    /// CSS `cubic-bezier(0.16, 1, 0.3, 1)`.
    static func liltEaseOut(_ duration: Double) -> Animation { .timingCurve(0.16, 1, 0.3, 1, duration: duration) }
    /// Dropdown opening, `cubic-bezier(.23, 1, .32, 1)` over 200 ms.
    static let menuOpen = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)
    /// Dropdown closing, CSS `ease-in` over 150 ms.
    static let menuClose = Animation.timingCurve(0.42, 0, 1, 1, duration: 0.15)
    /// Tab marker, `cubic-bezier(.65, 0, .35, 1)` over 240 ms.
    static let tabMarker = Animation.timingCurve(0.65, 0, 0.35, 1, duration: 0.24)
}

extension Color {
    func mix(_ percent: Double) -> Color { opacity(percent / 100) }
}

/// Clock text such as `4:05`, matching the web `clock()` helper.
func liltClock(_ seconds: Double) -> String {
    let value = seconds.isFinite ? max(0, seconds) : 0
    return "\(Int(value) / 60):\(String(format: "%02d", Int(value) % 60))"
}
