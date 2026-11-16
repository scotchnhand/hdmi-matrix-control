import MatrixKit
import SwiftUI
import UIKit

/// Colors shared with the app icon and the web app's theme tokens: output 1
/// is blue, output 2 is green, on a deep navy backdrop.
enum Theme {
    static let blue = Color(light: 0x0A5FB4, dark: 0x5BB0FF)
    static let green = Color(light: 0x0F7A3D, dark: 0x33D17A)
    static let backdropTop = Color(light: 0xE8EEF7, dark: 0x13203A)
    static let backdropBottom = Color(light: 0xF6F8FB, dark: 0x070B13)

    static func color(forOutput index: Int) -> Color {
        index == 2 ? green : blue
    }
}

/// The colors a holiday theme swaps in: the app tint and the backdrop.
/// Output colors and status colors are not part of a theme and stay fixed.
struct HolidayColors {
    let accent: Color
    let backdropTop: Color
    let backdropBottom: Color
    let glowA: Color
    let glowB: Color

    /// Nil unless the holiday's palette has every token for both appearances.
    init?(_ holiday: Holiday) {
        func pair(_ token: String) -> (light: UInt32, dark: UInt32)? {
            guard let light = holiday.palette.color(token, dark: false),
                  let dark = holiday.palette.color(token, dark: true)
            else { return nil }
            return (light, dark)
        }
        guard let accent = pair("accent"), let bg = pair("bg"),
              let glowA = pair("glow-a"), let glowB = pair("glow-b")
        else { return nil }
        self.accent = Color(light: accent.light, dark: accent.dark)
        self.backdropBottom = Color(light: bg.light, dark: bg.dark)
        // The palette has one background color; the top of the gradient
        // leans it toward the first glow, like the default navy backdrop.
        self.backdropTop = Color(
            light: Self.mix(bg.light, glowA.light, 0.12),
            dark: Self.mix(bg.dark, glowA.dark, 0.2)
        )
        self.glowA = Color(light: glowA.light, dark: glowA.dark)
        self.glowB = Color(light: glowB.light, dark: glowB.dark)
    }

    private static func mix(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
        [16, 8, 0].reduce(UInt32(0)) { result, shift in
            let from = Double((a >> shift) & 0xFF)
            let to = Double((b >> shift) & 0xFF)
            return result | (UInt32((from + (to - from) * amount).rounded()) << shift)
        }
    }
}

extension EnvironmentValues {
    /// The active holiday theme's colors; nil for the default look.
    @Entry var holidayColors: HolidayColors?
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The app icon's artwork as a full-screen backdrop: navy gradient with the
/// blue and green route glows. Liquid Glass needs something vivid behind it
/// to read as glass. A holiday theme swaps in its own gradient and glows.
struct MatrixBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.holidayColors) private var holiday

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            LinearGradient(
                colors: [holiday?.backdropTop ?? Theme.backdropTop, holiday?.backdropBottom ?? Theme.backdropBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height
                Circle()
                    .fill((holiday?.glowA ?? Theme.blue).opacity(dark ? 0.45 : 0.28))
                    .frame(width: w * 1.1)
                    .blur(radius: 90)
                    .position(x: w * 0.1, y: h * 0.18)
                Circle()
                    .fill((holiday?.glowB ?? Theme.green).opacity(dark ? 0.32 : 0.2))
                    .frame(width: w * 1.0)
                    .blur(radius: 100)
                    .position(x: w * 0.95, y: h * 0.72)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A rounded Liquid Glass panel for grouping content on the backdrop.
struct GlassCard<Content: View>: View {
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                tint.map { Glass.regular.tint($0.opacity(0.12)) } ?? .regular,
                in: .rect(cornerRadius: 28)
            )
    }
}
