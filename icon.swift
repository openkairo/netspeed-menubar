// Zeichnet das App-Symbol (1024 px PNG): dunkle Kachel mit grünem ↓ und blauem ↑.
import Cocoa
let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.22, alpha: 1),
           ending: NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1))!.draw(in: bg, angle: -90)
func arrow(_ x: Double, up: Bool, _ c: NSColor) {
    let p = NSBezierPath(); let top = 760.0, bot = 260.0, w = 70.0, head = 150.0
    if up {
        p.move(to: NSPoint(x: x, y: top)); p.line(to: NSPoint(x: x + head, y: top - head))
        p.line(to: NSPoint(x: x + w/2, y: top - head)); p.line(to: NSPoint(x: x + w/2, y: bot))
        p.line(to: NSPoint(x: x - w/2, y: bot)); p.line(to: NSPoint(x: x - w/2, y: top - head))
        p.line(to: NSPoint(x: x - head, y: top - head))
    } else {
        p.move(to: NSPoint(x: x, y: bot)); p.line(to: NSPoint(x: x + head, y: bot + head))
        p.line(to: NSPoint(x: x + w/2, y: bot + head)); p.line(to: NSPoint(x: x + w/2, y: top))
        p.line(to: NSPoint(x: x - w/2, y: top)); p.line(to: NSPoint(x: x - w/2, y: bot + head))
        p.line(to: NSPoint(x: x - head, y: bot + head))
    }
    p.close(); c.setFill(); p.fill()
}
arrow(370, up: true, NSColor(calibratedRed: 0.30, green: 0.62, blue: 1.0, alpha: 1))
arrow(654, up: false, NSColor(calibratedRed: 0.25, green: 0.85, blue: 0.45, alpha: 1))
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
