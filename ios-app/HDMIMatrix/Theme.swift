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
/// to read as glass.
struct MatrixBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            LinearGradient(
                colors: [Theme.backdropTop, Theme.backdropBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height
                Circle()
                    .fill(Theme.blue.opacity(dark ? 0.45 : 0.28))
                    .frame(width: w * 1.1)
                    .blur(radius: 90)
                    .position(x: w * 0.1, y: h * 0.18)
                Circle()
                    .fill(Theme.green.opacity(dark ? 0.32 : 0.2))
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
