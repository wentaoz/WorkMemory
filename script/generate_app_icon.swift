#!/usr/bin/env swift

import AppKit
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesURL = rootURL.appendingPathComponent("Resources", isDirectory: true)
try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

let outputURL = resourcesURL.appendingPathComponent("WorkMemoryIcon.png")
let canvasSize: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvasSize, height: canvasSize))

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(
        roundedRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height),
        xRadius: radius,
        yRadius: radius
    )
}

func circle(center: CGPoint, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(
        ovalIn: NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    )
}

func strokeLine(from start: CGPoint, to end: CGPoint, color strokeColor: NSColor, width: CGFloat) {
    let path = NSBezierPath()
    path.move(to: start)
    path.line(to: end)
    path.lineWidth = width
    path.lineCapStyle = .round
    strokeColor.setStroke()
    path.stroke()
}

image.lockFocus()

let iconRect = CGRect(x: 28, y: 28, width: 968, height: 968)
let iconMask = roundedRect(iconRect, radius: 214)

NSGraphicsContext.saveGraphicsState()
iconMask.addClip()

NSGradient(colorsAndLocations:
    (color(0x0b1220), 0.0),
    (color(0x1f4fd8), 0.45),
    (color(0x00c7a7), 1.0)
)?.draw(in: NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize), angle: -38)

color(0xffffff, alpha: 0.06).setStroke()
for offset in stride(from: -420, through: 1220, by: 96) {
    strokeLine(
        from: CGPoint(x: CGFloat(offset), y: 0),
        to: CGPoint(x: CGFloat(offset) + 520, y: canvasSize),
        color: color(0xffffff, alpha: 0.055),
        width: 3
    )
}

NSGraphicsContext.restoreGraphicsState()

let outerStroke = roundedRect(iconRect.insetBy(dx: 5, dy: 5), radius: 208)
outerStroke.lineWidth = 10
color(0xffffff, alpha: 0.24).setStroke()
outerStroke.stroke()

let panelRect = CGRect(x: 188, y: 178, width: 648, height: 668)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowBlurRadius = 42
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.shadowColor = color(0x000000, alpha: 0.26)
shadow.set()
color(0xffffff, alpha: 0.15).setFill()
roundedRect(panelRect, radius: 150).fill()
NSGraphicsContext.restoreGraphicsState()

let panel = roundedRect(panelRect, radius: 150)
panel.lineWidth = 5
color(0xffffff, alpha: 0.32).setStroke()
panel.stroke()

for (index, alpha) in [0.28, 0.22, 0.16].enumerated() {
    let y = CGFloat(284 + index * 118)
    let path = roundedRect(CGRect(x: 284, y: y, width: 456, height: 76), radius: 38)
    color(0xffffff, alpha: CGFloat(alpha)).setFill()
    path.fill()
}

let memoryPath = NSBezierPath()
memoryPath.move(to: CGPoint(x: 286, y: 620))
memoryPath.line(to: CGPoint(x: 390, y: 430))
memoryPath.line(to: CGPoint(x: 512, y: 668))
memoryPath.line(to: CGPoint(x: 634, y: 430))
memoryPath.line(to: CGPoint(x: 738, y: 620))
memoryPath.lineWidth = 58
memoryPath.lineCapStyle = .round
memoryPath.lineJoinStyle = .round
color(0xf8fbff, alpha: 0.96).setStroke()
memoryPath.stroke()

let accentPath = NSBezierPath()
accentPath.move(to: CGPoint(x: 328, y: 624))
accentPath.line(to: CGPoint(x: 418, y: 510))
accentPath.line(to: CGPoint(x: 512, y: 662))
accentPath.line(to: CGPoint(x: 606, y: 510))
accentPath.line(to: CGPoint(x: 696, y: 624))
accentPath.lineWidth = 15
accentPath.lineCapStyle = .round
accentPath.lineJoinStyle = .round
color(0x00e0bd, alpha: 0.92).setStroke()
accentPath.stroke()

let nodes = [
    CGPoint(x: 314, y: 704),
    CGPoint(x: 430, y: 760),
    CGPoint(x: 596, y: 746),
    CGPoint(x: 720, y: 686),
    CGPoint(x: 754, y: 540)
]

for pair in zip(nodes, nodes.dropFirst()) {
    strokeLine(from: pair.0, to: pair.1, color: color(0xffffff, alpha: 0.30), width: 8)
}

for (index, node) in nodes.enumerated() {
    color(index == 2 ? 0x00e0bd : 0xffffff, alpha: index == 2 ? 0.98 : 0.88).setFill()
    circle(center: node, radius: index == 2 ? 24 : 18).fill()
}

let spark = NSBezierPath()
spark.move(to: CGPoint(x: 728, y: 796))
spark.line(to: CGPoint(x: 728, y: 868))
spark.move(to: CGPoint(x: 692, y: 832))
spark.line(to: CGPoint(x: 764, y: 832))
spark.lineWidth = 14
spark.lineCapStyle = .round
color(0xffd166, alpha: 0.95).setStroke()
spark.stroke()

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Failed to render WorkMemory app icon")
}

try pngData.write(to: outputURL)
print(outputURL.path)
