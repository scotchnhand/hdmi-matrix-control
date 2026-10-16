#!/usr/bin/env swift
// Renders the iOS app icon (and its dark / tinted variants) into the asset
// catalog. Re-run after changing anything here:
//
//   swift ios-app/scripts/generate_icons.swift
//
// The motif is the app's own job drawn as a diagram: four input ports on the
// left, two screens on the right, and two routes crossing between them --
// blue and green, the same accent / "on" colors as the web app's dark theme.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
// Run from the repo root.
let assets = URL(fileURLWithPath: "ios-app/HDMIMatrix/Assets.xcassets")
let outDir = assets.appendingPathComponent("AppIcon.appiconset")
// The transparent (dark) render doubles as in-app artwork.
let artworkFile = assets.appendingPathComponent("Artwork.imageset/artwork.png")

enum Variant: String, CaseIterable {
    case standard = "icon-1024.png"
    case dark = "icon-dark-1024.png"     // transparent; iOS supplies the dark backdrop
    case tinted = "icon-tinted-1024.png" // grayscale; iOS applies the user's tint
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: white, green: white, blue: white, alpha: alpha)
}

struct Palette {
    var blue: CGColor
    var green: CGColor
    var port: CGColor
    var portEdge: CGColor
    var screenFill: (CGColor) -> CGColor

    static func forVariant(_ v: Variant) -> Palette {
        switch v {
        case .standard, .dark:
            return Palette(
                blue: rgb(0x5BB0FF),
                green: rgb(0x33D17A),
                port: rgb(0x253247),
                portEdge: rgb(0x3B4C66),
                screenFill: { $0.copy(alpha: 0.18)! }
            )
        case .tinted:
            return Palette(
                blue: gray(1.0),
                green: gray(0.82),
                port: gray(0.34),
                portEdge: gray(0.46),
                screenFill: { $0.copy(alpha: 0.16)! }
            )
        }
    }
}

// Geometry (top-left origin; we flip the context below).
let inputX: CGFloat = 168
let inputSize = CGSize(width: 150, height: 84)
let inputYs: [CGFloat] = [258, 414, 570, 726]
let screenRect = { (centerY: CGFloat) in
    CGRect(x: 640, y: centerY - 92, width: 236, height: 184)
}
let outputYs: [CGFloat] = [362, 662]
// input index -> output index (0-based). Crossing routes read as "matrix".
let routes: [(input: Int, output: Int, isBlue: Bool)] = [
    (input: 2, output: 0, isBlue: true),
    (input: 1, output: 1, isBlue: false),
]

func render(_ variant: Variant) throws {
    let palette = Palette.forVariant(variant)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: space,
        bitmapInfo: variant == .standard
            ? CGImageAlphaInfo.noneSkipLast.rawValue // App Store icons must be opaque
            : CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw NSError(domain: "icon", code: 1) }

    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)
    let full = CGRect(x: 0, y: 0, width: size, height: size)

    // Background
    if variant == .standard {
        let bg = CGGradient(
            colorsSpace: space,
            colors: [rgb(0x13203A), rgb(0x070B13)] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(bg, start: .zero, end: CGPoint(x: 0, y: size), options: [])
        // Soft glow behind the crossing point.
        let glow = CGGradient(
            colorsSpace: space,
            colors: [rgb(0x2A5A9A, 0.45), rgb(0x2A5A9A, 0)] as CFArray,
            locations: [0, 1]
        )!
        let c = CGPoint(x: 500, y: 512)
        ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: 460, options: [])
    } else {
        ctx.clear(full)
    }

    func inputRect(_ i: Int) -> CGRect {
        CGRect(x: inputX, y: inputYs[i] - inputSize.height / 2, width: inputSize.width, height: inputSize.height)
    }

    // Routes first, so ports and screens sit on top of the line ends.
    for route in routes {
        let color = route.isBlue ? palette.blue : palette.green
        let start = CGPoint(x: inputRect(route.input).maxX - 10, y: inputYs[route.input])
        let end = CGPoint(x: screenRect(outputYs[route.output]).minX + 10, y: outputYs[route.output])
        let path = CGMutablePath()
        path.move(to: start)
        path.addCurve(
            to: end,
            control1: CGPoint(x: start.x + 190, y: start.y),
            control2: CGPoint(x: end.x - 190, y: end.y)
        )
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 46, color: color.copy(alpha: 0.85))
        ctx.setStrokeColor(color)
        ctx.setLineWidth(40)
        ctx.setLineCap(.round)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // Input ports: an HDMI-ish rounded plug shape, lit if routed.
    let active = Dictionary(uniqueKeysWithValues: routes.map { ($0.input, $0.isBlue) })
    for i in inputYs.indices {
        let rect = inputRect(i)
        let path = CGPath(roundedRect: rect, cornerWidth: 26, cornerHeight: 26, transform: nil)
        ctx.saveGState()
        if let isBlue = active[i] {
            let color = isBlue ? palette.blue : palette.green
            ctx.setShadow(offset: .zero, blur: 30, color: color.copy(alpha: 0.7))
            ctx.setFillColor(color)
        } else {
            ctx.setFillColor(palette.port)
        }
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
        if active[i] == nil {
            ctx.setStrokeColor(palette.portEdge)
            ctx.setLineWidth(6)
            ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerWidth: 23, cornerHeight: 23, transform: nil))
            ctx.strokePath()
        }
    }

    // Output screens, each tinted with the route feeding it, plus a stand.
    for route in routes {
        let color = route.isBlue ? palette.blue : palette.green
        let rect = screenRect(outputYs[route.output])
        let screen = CGPath(roundedRect: rect, cornerWidth: 34, cornerHeight: 34, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 40, color: color.copy(alpha: 0.6))
        ctx.setFillColor(variant == .standard ? rgb(0x0C1422) : gray(0, 0.001))
        ctx.addPath(screen)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.setFillColor(palette.screenFill(color))
        ctx.addPath(screen)
        ctx.fillPath()

        ctx.setStrokeColor(color)
        ctx.setLineWidth(22)
        ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 11, dy: 11), cornerWidth: 26, cornerHeight: 26, transform: nil))
        ctx.strokePath()

        // Stand: a short neck into a foot.
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: rect.midX - 14, y: rect.maxY - 4, width: 28, height: 26))
        let foot = CGRect(x: rect.midX - 52, y: rect.maxY + 18, width: 104, height: 18)
        ctx.addPath(CGPath(roundedRect: foot, cornerWidth: 9, cornerHeight: 9, transform: nil))
        ctx.fillPath()
    }

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(
              outDir.appendingPathComponent(variant.rawValue) as CFURL,
              UTType.png.identifier as CFString, 1, nil
          )
    else { throw NSError(domain: "icon", code: 2) }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "icon", code: 3) }
    print("wrote \(variant.rawValue)")

    if variant == .dark {
        let fm = FileManager.default
        try? fm.removeItem(at: artworkFile)
        try fm.copyItem(at: outDir.appendingPathComponent(variant.rawValue), to: artworkFile)
        print("wrote Artwork.imageset/artwork.png")
    }
}

for variant in Variant.allCases {
    try render(variant)
}
