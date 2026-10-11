// Draws the App Renamer icon: an app tile with a name tag.
// Usage: swift tools/make-icon.swift <out.png>
import AppKit

let S: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let cg = NSGraphicsContext.current!.cgContext

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Background squircle (macOS icon grid: 824pt body, 100pt margin).
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = rgb(0x000000, 0.35)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
shadow.set()
rgb(0x4B3FE0).setFill()
bodyPath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [rgb(0x7B6CFF), rgb(0x3B2CC9)])!.draw(in: bodyPath, angle: -90)

// App tile (white card with a 2x2 grid of dots), tilted slightly.
cg.saveGState()
cg.translateBy(x: 430, y: 560)
cg.rotate(by: 8 * .pi / 180)
let card = NSRect(x: -190, y: -190, width: 380, height: 380)
NSGraphicsContext.saveGraphicsState()
let cardShadow = NSShadow()
cardShadow.shadowColor = rgb(0x1A1060, 0.45)
cardShadow.shadowOffset = NSSize(width: 0, height: -14)
cardShadow.shadowBlurRadius = 30
cardShadow.set()
rgb(0xFFFFFF).setFill()
NSBezierPath(roundedRect: card, xRadius: 92, yRadius: 92).fill()
NSGraphicsContext.restoreGraphicsState()
let dot: CGFloat = 92, gap: CGFloat = 36
for (i, color) in [rgb(0x7B6CFF), rgb(0xB7AEFF), rgb(0xB7AEFF), rgb(0x7B6CFF)].enumerated() {
    let x = (i % 2 == 0 ? -dot - gap / 2 : gap / 2)
    let y = (i < 2 ? gap / 2 : -dot - gap / 2)
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: dot, height: dot), xRadius: 28, yRadius: 28).fill()
}
cg.restoreGState()

// Name tag hanging over the bottom-right corner.
cg.saveGState()
cg.translateBy(x: 640, y: 330)
cg.rotate(by: -18 * .pi / 180)
let tag = NSBezierPath()
let tw: CGFloat = 330, th: CGFloat = 170, notch: CGFloat = 70, r: CGFloat = 26
// Tag outline: pointed left side, rounded right side.
tag.move(to: NSPoint(x: -tw / 2, y: 0))
tag.line(to: NSPoint(x: -tw / 2 + notch, y: th / 2))
tag.appendArc(from: NSPoint(x: tw / 2, y: th / 2), to: NSPoint(x: tw / 2, y: 0), radius: r)
tag.appendArc(from: NSPoint(x: tw / 2, y: -th / 2), to: NSPoint(x: 0, y: -th / 2), radius: r)
tag.line(to: NSPoint(x: -tw / 2 + notch, y: -th / 2))
tag.close()
NSGraphicsContext.saveGraphicsState()
let tagShadow = NSShadow()
tagShadow.shadowColor = rgb(0x1A1060, 0.5)
tagShadow.shadowOffset = NSSize(width: 0, height: -10)
tagShadow.shadowBlurRadius = 24
tagShadow.set()
rgb(0xFF8A3D).setFill()
tag.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [rgb(0xFFA552), rgb(0xFF6B2C)])!.draw(in: tag, angle: -90)
// Hole.
rgb(0x3B2CC9).setFill()
NSBezierPath(ovalIn: NSRect(x: -tw / 2 + 48, y: -17, width: 34, height: 34)).fill()
// "ID" label.
let label = NSAttributedString(string: "ID", attributes: [
    .font: NSFont.systemFont(ofSize: 104, weight: .heavy),
    .foregroundColor: NSColor.white,
    .kern: 4,
])
let ls = label.size()
label.draw(at: NSPoint(x: 40 - ls.width / 2, y: -ls.height / 2 + 2))
cg.restoreGState()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
