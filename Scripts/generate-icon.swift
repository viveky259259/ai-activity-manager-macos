#!/usr/bin/env swift
// Generates Resources/AppIcon.icns. Renders a 1024px master image (indigo
// gradient + stylized clock-and-bars), produces every iconset size with sips,
// then bundles via iconutil.
//
// Usage:  swift Scripts/generate-icon.swift
import AppKit
import CoreGraphics

let masterSize = 1024
let outputRoot = FileManager.default.currentDirectoryPath
let resourcesDir = (outputRoot as NSString).appendingPathComponent("Resources")
let iconsetDir = (resourcesDir as NSString).appendingPathComponent("AppIcon.iconset")
let masterPNG = (resourcesDir as NSString).appendingPathComponent("AppIcon-1024.png")
let icnsPath = (resourcesDir as NSString).appendingPathComponent("AppIcon.icns")

try? FileManager.default.createDirectory(atPath: resourcesDir, withIntermediateDirectories: true)
try? FileManager.default.removeItem(atPath: iconsetDir)
try FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

// MARK: - Master render

func renderMaster() -> NSImage {
    let size = NSSize(width: masterSize, height: masterSize)
    let image = NSImage(size: size)
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus(); return image
    }

    // Rounded square base (squircle-ish).
    let radius: CGFloat = CGFloat(masterSize) * 0.225
    let rect = CGRect(x: 0, y: 0, width: masterSize, height: masterSize)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path); ctx.clip()

    // Indigo → violet gradient (matches brand seed 0xFF6366F1).
    let colors = [
        CGColor(red: 0.20, green: 0.18, blue: 0.55, alpha: 1.0),
        CGColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 1.0),
        CGColor(red: 0.55, green: 0.36, blue: 0.97, alpha: 1.0),
    ] as CFArray
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: CGFloat(masterSize)),
        end: CGPoint(x: CGFloat(masterSize), y: 0),
        options: []
    )

    // Subtle inner glow at top-left.
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.07))
    ctx.fillEllipse(in: CGRect(x: -CGFloat(masterSize) * 0.4, y: CGFloat(masterSize) * 0.4,
                               width: CGFloat(masterSize), height: CGFloat(masterSize)))

    // Bar chart (3 ascending bars) bottom-left.
    let barColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.95)
    ctx.setFillColor(barColor)
    let barWidth = CGFloat(masterSize) * 0.10
    let barSpacing = CGFloat(masterSize) * 0.04
    let baseX = CGFloat(masterSize) * 0.18
    let baseY = CGFloat(masterSize) * 0.20
    let heights: [CGFloat] = [0.20, 0.32, 0.44].map { CGFloat($0) * CGFloat(masterSize) }
    for (i, h) in heights.enumerated() {
        let x = baseX + CGFloat(i) * (barWidth + barSpacing)
        let r = CGRect(x: x, y: baseY, width: barWidth, height: h)
        let p = CGPath(roundedRect: r, cornerWidth: barWidth * 0.2, cornerHeight: barWidth * 0.2, transform: nil)
        ctx.addPath(p); ctx.fillPath()
    }

    // Clock face top-right.
    let cx = CGFloat(masterSize) * 0.66
    let cy = CGFloat(masterSize) * 0.66
    let radiusOuter = CGFloat(masterSize) * 0.22
    ctx.setLineWidth(CGFloat(masterSize) * 0.030)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.addEllipse(in: CGRect(x: cx - radiusOuter, y: cy - radiusOuter,
                               width: radiusOuter * 2, height: radiusOuter * 2))
    ctx.strokePath()

    // Clock hands (12 + 4 — pointing up and to lower-right).
    ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.setLineWidth(CGFloat(masterSize) * 0.026)

    // Hour hand (up).
    ctx.move(to: CGPoint(x: cx, y: cy))
    ctx.addLine(to: CGPoint(x: cx, y: cy + radiusOuter * 0.55))
    ctx.strokePath()

    // Minute hand (4 o'clock direction).
    ctx.move(to: CGPoint(x: cx, y: cy))
    ctx.addLine(to: CGPoint(
        x: cx + radiusOuter * 0.75 * cos(-CGFloat.pi / 6),
        y: cy + radiusOuter * 0.75 * sin(-CGFloat.pi / 6)
    ))
    ctx.strokePath()

    // Center dot.
    let dotR = CGFloat(masterSize) * 0.018
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2))

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to path: String, size: Int) throws {
    let target = NSImage(size: NSSize(width: size, height: size))
    target.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
               from: .zero, operation: .copy, fraction: 1.0)
    target.unlockFocus()
    guard let tiff = target.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1)
    }
    try png.write(to: URL(fileURLWithPath: path))
}

let master = renderMaster()
try writePNG(master, to: masterPNG, size: masterSize)

// iconset entries.
let entries: [(name: String, size: Int)] = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]
for entry in entries {
    let dst = (iconsetDir as NSString).appendingPathComponent(entry.name)
    try writePNG(master, to: dst, size: entry.size)
    print("wrote \(entry.name)")
}

// Bundle via iconutil.
let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
try task.run()
task.waitUntilExit()
if task.terminationStatus == 0 {
    print("✓ wrote \(icnsPath)")
    try? FileManager.default.removeItem(atPath: iconsetDir)
} else {
    print("iconutil failed (\(task.terminationStatus))")
    exit(Int32(task.terminationStatus))
}
