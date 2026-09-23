// Renders the app icon's light, dark, and tinted PNGs from the geometry in
// tally-icon.svg. Run it from the repository root after changing the mark:
//
//     swift Branding/render-app-icon.swift
//
// The shapes below mirror the SVG's 120-unit grid; keep the two in step.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let pixels = 1024
let outputDirectory = "Tally/Resources/Assets.xcassets/AppIcon.appiconset"

struct Shape {
    let rect: CGRect
    let radius: CGFloat
    let isNewestEntry: Bool
}

/// The crossbar is the total; the blocks under it are monthly entries, newest on top.
let shapes = [
    Shape(rect: CGRect(x: 28, y: 22, width: 64, height: 18), radius: 9, isNewestEntry: false),
    Shape(rect: CGRect(x: 50, y: 46, width: 20, height: 14), radius: 4, isNewestEntry: true),
    Shape(rect: CGRect(x: 50, y: 65, width: 20, height: 14), radius: 4, isNewestEntry: false),
    Shape(rect: CGRect(x: 50, y: 84, width: 20, height: 14), radius: 4, isNewestEntry: false),
]

struct Variant {
    let filename: String
    /// `nil` leaves the background transparent, which iOS fills with its own dark backdrop.
    let background: UInt32?
    let mark: UInt32
    let newestEntry: UInt32
}

let variants = [
    Variant(filename: "AppIcon.png", background: 0x26_215C, mark: 0xFF_FFFF, newestEntry: 0xFA_C775),
    Variant(filename: "AppIcon-Dark.png", background: nil, mark: 0xFF_FFFF, newestEntry: 0xFA_C775),
    // iOS tints by luminance, so the newest entry stays distinct as a mid gray.
    Variant(filename: "AppIcon-Tinted.png", background: 0x00_0000, mark: 0xFF_FFFF, newestEntry: 0x9A_9A9A),
]

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

func render(_ variant: Variant) throws {
    // App Store icons must be opaque, so only the transparent variant gets an alpha channel.
    let alpha: CGImageAlphaInfo = variant.background == nil ? .premultipliedLast : .noneSkipLast
    guard
        let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: alpha.rawValue)
    else { throw CocoaError(.fileWriteUnknown) }

    // Match the SVG: 120 units across, y growing downward.
    let scale = CGFloat(pixels) / 120
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: scale, y: -scale)

    if let background = variant.background {
        context.setFillColor(color(background))
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
    }
    for shape in shapes {
        context.setFillColor(color(shape.isNewestEntry ? variant.newestEntry : variant.mark))
        context.addPath(
            CGPath(roundedRect: shape.rect, cornerWidth: shape.radius, cornerHeight: shape.radius, transform: nil))
        context.fillPath()
    }

    let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(variant.filename)
    guard
        let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    print("Wrote \(url.path)")
}

for variant in variants {
    try render(variant)
}
