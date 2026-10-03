import AppKit
import Foundation

let output = CommandLine.arguments[1]
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.19, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: 220, yRadius: 220).fill()
NSColor.white.setStroke()
func stroke(_ points: [(CGFloat, CGFloat)]) {
    let path = NSBezierPath()
    path.lineWidth = 72
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: NSPoint(x: points[0].0, y: points[0].1))
    for point in points.dropFirst() { path.line(to: NSPoint(x: point.0, y: point.1)) }
    path.stroke()
}
stroke([(345, 708), (212, 512), (345, 316)])
stroke([(679, 708), (812, 512), (679, 316)])
stroke([(606, 786), (418, 238)])
image.unlockFocus()
let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: output))
