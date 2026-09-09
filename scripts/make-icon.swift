import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        NSColor(calibratedRed: 0.045, green: 0.075, blue: 0.08, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: Double(pixels) * 0.04, dy: Double(pixels) * 0.04), xRadius: Double(pixels) * 0.22, yRadius: Double(pixels) * 0.22).fill()
        NSColor(calibratedRed: 0.54, green: 0.96, blue: 0.79, alpha: 1).setStroke()
        let path = NSBezierPath()
        path.lineWidth = Double(pixels) * 0.045
        path.lineCapStyle = .round
        for i in 0...160 {
            let t = Double(i) / 160
            let envelope = exp(-pow((t - 0.5) * 4, 2))
            let point = NSPoint(x: Double(pixels) * (0.17 + 0.66 * t), y: Double(pixels) * (0.5 + 0.24 * envelope * sin(t * .pi * 8)))
            if i == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name))
    }
}
