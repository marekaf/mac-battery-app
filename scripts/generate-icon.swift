#!/usr/bin/env swift

import AppKit
import Foundation

let iconSizes: [(size: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
let projectDir = scriptDir.deletingLastPathComponent()
let resourcesDir = projectDir.appendingPathComponent("Resources")
let iconsetDir = resourcesDir.appendingPathComponent("AppIcon.iconset")
let icnsPath = resourcesDir.appendingPathComponent("AppIcon.icns")

try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

func renderIcon(size: Int, scale: Int) -> NSImage {
    let pixelSize = size * scale
    let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))

    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
    let cornerRadius = CGFloat(pixelSize) * 0.22

    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    let gradient = NSGradient(
        starting: NSColor(red: 0.18, green: 0.72, blue: 0.38, alpha: 1.0),
        ending: NSColor(red: 0.10, green: 0.55, blue: 0.30, alpha: 1.0)
    )!
    gradient.draw(in: path, angle: -90)

    let symbolConfig = NSImage.SymbolConfiguration(pointSize: CGFloat(pixelSize) * 0.52, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "minus.plus.batteryblock", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {

        let symbolSize = symbol.size
        let x = (CGFloat(pixelSize) - symbolSize.width) / 2
        let y = (CGFloat(pixelSize) - symbolSize.height) / 2

        NSColor.white.setFill()
        symbol.draw(
            in: NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height),
            from: .zero,
            operation: .sourceAtop,
            fraction: 1.0
        )
    }

    image.unlockFocus()
    return image
}

for entry in iconSizes {
    let image = renderIcon(size: entry.size, scale: entry.scale)
    let pixelSize = entry.size * entry.scale

    let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
        from: .zero,
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    let pngData = bitmapRep.representation(using: .png, properties: [:])!

    let suffix = entry.scale > 1 ? "@\(entry.scale)x" : ""
    let filename = "icon_\(entry.size)x\(entry.size)\(suffix).png"
    let filePath = iconsetDir.appendingPathComponent(filename)
    try pngData.write(to: filePath)
    print("Generated \(filename) (\(pixelSize)x\(pixelSize)px)")
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsPath.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    try FileManager.default.removeItem(at: iconsetDir)
    print("Created \(icnsPath.path)")
} else {
    print("iconutil failed with status \(process.terminationStatus)")
    exit(1)
}
