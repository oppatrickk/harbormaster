#!/usr/bin/env swift

// Draws the Harbormaster app icon and writes every size macOS asks for.
//
// The icon is generated rather than checked in as binary art so it stays reviewable in a
// diff: change a number here, re-run, and the whole set is rebuilt. See Scripts/README or
// the "Icon" section of the top-level README for usage.
//
//     swift Scripts/generate-icon.swift [output-appiconset-dir]

import AppKit
import Foundation

// MARK: - Geometry

/// Everything is drawn in a 1024x1024 space and scaled down per output size.
let canvas: CGFloat = 1024

/// Apple's rounded-rect is a superellipse ("squircle"), not a circular-cornered rect — the
/// curvature blends continuously into the straight edges instead of meeting at a tangent.
/// Sampling the superellipse directly gets that shape without hand-fitting bezier corners.
func squirclePath(in rect: CGRect, exponent: Double = 5, samples: Int = 720) -> CGPath {
    let path = CGMutablePath()
    let a = Double(rect.width / 2)
    let b = Double(rect.height / 2)
    let cx = Double(rect.midX)
    let cy = Double(rect.midY)

    for step in 0...samples {
        let t = (Double(step) / Double(samples)) * 2 * .pi
        let cosT = cos(t)
        let sinT = sin(t)
        // |cos t|^(2/n) with the sign carried back, per the superellipse parametric form.
        let x = cx + a * copysign(pow(abs(cosT), 2 / exponent), cosT)
        let y = cy + b * copysign(pow(abs(sinT), 2 / exponent), sinT)
        if step == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }

    path.closeSubpath()
    return path
}

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

// MARK: - Drawing

func drawIcon(into ctx: CGContext, size: CGFloat) {
    let unit = size / canvas
    ctx.scaleBy(x: unit, y: unit)

    // Flip to a top-left origin so the coordinates below read like a design spec.
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)

    // macOS icons don't fill their canvas: the art sits in a ~82% box, leaving room for the
    // shadow and keeping every app's icon optically the same size in the Dock.
    let plate = CGRect(x: 100, y: 92, width: 824, height: 824)
    let shape = squirclePath(in: plate)

    // Body: dusk-harbor gradient, deep navy at the waterline up to a lit teal sky.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    let space = CGColorSpaceCreateDeviceRGB()
    let body = CGGradient(
        colorsSpace: space,
        colors: [rgb(0x2AA0BE), rgb(0x14688F), rgb(0x0A2C48)] as CFArray,
        locations: [0, 0.45, 1]
    )!
    ctx.drawLinearGradient(
        body,
        start: CGPoint(x: plate.midX, y: plate.minY),
        end: CGPoint(x: plate.midX, y: plate.maxY),
        options: []
    )

    // Specular sheen across the top edge, the way a glossy surface catches light.
    let sheen = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        sheen,
        start: CGPoint(x: plate.midX, y: plate.minY),
        end: CGPoint(x: plate.midX, y: plate.minY + plate.height * 0.42),
        options: []
    )
    ctx.restoreGState()

    drawAnchor(into: ctx)

    // Hairline rim: without it the icon's edge dissolves into a dark Dock background.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()
}

/// The anchor: ring, stock (crossbar), shank, and flukes with barbed tips.
func drawAnchor(into ctx: CGContext) {
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    let cx: CGFloat = 512
    let stroke: CGFloat = 52

    // Shank. Starts inside the ring's lower stroke band so the two read as one piece — any
    // higher and it shows as a stub crossing the ring's hole.
    ctx.setLineWidth(stroke)
    ctx.move(to: CGPoint(x: cx, y: 352))
    ctx.addLine(to: CGPoint(x: cx, y: 812))
    ctx.strokePath()

    // Ring.
    ctx.setLineWidth(46)
    ctx.addEllipse(in: CGRect(x: cx - 84, y: 196, width: 168, height: 168))
    ctx.strokePath()

    // Stock.
    ctx.setLineWidth(44)
    ctx.move(to: CGPoint(x: cx - 196, y: 424))
    ctx.addLine(to: CGPoint(x: cx + 196, y: 424))
    ctx.strokePath()

    // Flukes: a single sweep under the shank, rising to a point at each end.
    ctx.setLineWidth(stroke)
    ctx.move(to: CGPoint(x: 250, y: 606))
    ctx.addCurve(
        to: CGPoint(x: cx, y: 846),
        control1: CGPoint(x: 250, y: 764),
        control2: CGPoint(x: 364, y: 846)
    )
    ctx.addCurve(
        to: CGPoint(x: 774, y: 606),
        control1: CGPoint(x: 660, y: 846),
        control2: CGPoint(x: 774, y: 764)
    )
    ctx.strokePath()

    // Barbs at the fluke tips.
    for direction in [CGFloat(-1), CGFloat(1)] {
        let tipX = cx + direction * 262
        ctx.move(to: CGPoint(x: tipX + direction * 74, y: 508))
        ctx.addLine(to: CGPoint(x: tipX - direction * 46, y: 590))
        ctx.addLine(to: CGPoint(x: tipX + direction * 40, y: 664))
        ctx.closePath()
        ctx.fillPath()
    }

    ctx.restoreGState()
}

// MARK: - Output

func renderPNG(size: CGFloat) -> Data {
    let pixels = Int(size)
    let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    drawIcon(into: ctx, size: size)

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: pixels, height: pixels)
    return rep.representation(using: .png, properties: [:])!
}

/// (filename point size, scale) pairs — the full macOS app icon set.
let variants: [(point: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

let defaultDir = "Harbormaster/Assets.xcassets/AppIcon.appiconset"
let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultDir
try FileManager.default.createDirectory(
    atPath: outputDir, withIntermediateDirectories: true
)

var entries: [String] = []
for variant in variants {
    let pixels = variant.point * variant.scale
    let suffix = variant.scale == 1 ? "" : "@\(variant.scale)x"
    let name = "icon_\(variant.point)x\(variant.point)\(suffix).png"

    let data = renderPNG(size: CGFloat(pixels))
    try data.write(to: URL(fileURLWithPath: "\(outputDir)/\(name)"))

    entries.append("""
        {
          "filename" : "\(name)",
          "idiom" : "mac",
          "scale" : "\(variant.scale)x",
          "size" : "\(variant.point)x\(variant.point)"
        }
    """)
    print("wrote \(name) (\(pixels)px)")
}

let contents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try contents.write(toFile: "\(outputDir)/Contents.json", atomically: true, encoding: .utf8)
print("wrote Contents.json")
