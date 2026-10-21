// Renders the Scotta app icon: a battery drawn in spaghetti, charged to ~80% with wavy strands.
// Usage: swift Support/make-icon.swift <out.png>   (1024x1024)
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func gradient(_ colors: [CGColor]) -> CGGradient { CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: nil)! }

// macOS icon grid: 824pt tile centred in 1024, with a soft drop shadow.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(tilePath); ctx.setFillColor(rgb(0xC8321F)); ctx.fillPath()
ctx.restoreGState()

// Tomato-sauce gradient with a gentle top highlight.
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0xF0603A), rgb(0xC62A1C)]), start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)]), startCenter: CGPoint(x: 512, y: 860), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 860), endRadius: 520, options: [])
ctx.restoreGState()

// Spaghetti styling: a darker under-stroke, the pasta body, then a thin highlight on top.
func pasta(_ path: CGPath, width: CGFloat) {
    for (color, w, dy) in [(rgb(0x8A1E12, 0.45), width + 10, -8.0), (rgb(0xC9952E), width + 4, 0), (rgb(0xF7D27A), width, 0), (rgb(0xFFF1C2, 0.9), width * 0.28, 4)] {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: dy)
        ctx.addPath(path); ctx.setStrokeColor(color); ctx.setLineWidth(w)
        ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.strokePath()
        ctx.restoreGState()
    }
}

// Battery body, slightly soft: scotta pasta does not hold a crisp corner.
let body = CGRect(x: 238, y: 362, width: 500, height: 300)

pasta(CGPath(roundedRect: body, cornerWidth: 70, cornerHeight: 70, transform: nil), width: 30)
let terminal = CGMutablePath()
terminal.move(to: CGPoint(x: body.maxX + 46, y: 455)); terminal.addLine(to: CGPoint(x: body.maxX + 46, y: 569))
pasta(terminal, width: 30)

// Charge: wavy strands filling the body to ~80%, each with its own rhythm.
let inner = body.insetBy(dx: 58, dy: 58)
let fillWidth = inner.width * 0.8
let strands: [(freq: CGFloat, phase: CGFloat, amp: CGFloat, len: CGFloat)] = [(2.5, 0.4, 10, 0.97), (3.2, 2.1, 13, 1.0), (2.8, 4.0, 9, 0.92), (3.6, 1.2, 12, 1.0)]
for (i, st) in strands.enumerated() {
    let y = inner.minY + 8 + CGFloat(i) * (inner.height - 16) / 3
    let p = CGMutablePath()
    let steps = 80
    for s in 0...steps {
        let t = CGFloat(s) / CGFloat(steps)
        let x = inner.minX + t * fillWidth * st.len
        let yy = y + sin(t * .pi * st.freq + st.phase) * st.amp
        s == 0 ? p.move(to: CGPoint(x: x, y: yy)) : p.addLine(to: CGPoint(x: x, y: yy))
    }
    if i == 0 {
        // The bottom strand is overcooked: it slumps over the rim and hangs limp. That is "scotta".
        let end = p.currentPoint
        p.addCurve(to: CGPoint(x: 668, y: body.minY), control1: CGPoint(x: end.x + 50, y: end.y), control2: CGPoint(x: 668, y: body.minY + 40))
        p.addCurve(to: CGPoint(x: 650, y: 262), control1: CGPoint(x: 668, y: body.minY - 40), control2: CGPoint(x: 668, y: 300))
        p.addCurve(to: CGPoint(x: 612, y: 236), control1: CGPoint(x: 640, y: 242), control2: CGPoint(x: 626, y: 234))
    }
    pasta(p, width: 20)
}

// Basil leaf tucked at the top-left corner of the battery.
ctx.saveGState()
ctx.translateBy(x: 262, y: 676); ctx.rotate(by: .pi / 5)
let leaf = CGMutablePath()
leaf.move(to: .zero)
leaf.addQuadCurve(to: CGPoint(x: 150, y: 0), control: CGPoint(x: 75, y: 72))
leaf.addQuadCurve(to: .zero, control: CGPoint(x: 75, y: -72))
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 10, color: rgb(0x000000, 0.3))
ctx.addPath(leaf); ctx.setFillColor(rgb(0x3E9B3A)); ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.addPath(leaf); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x7CCB5B), rgb(0x2F7F2C)]), start: CGPoint(x: 0, y: 60), end: CGPoint(x: 0, y: -60), options: [])
let vein = CGMutablePath(); vein.move(to: CGPoint(x: 12, y: 0)); vein.addLine(to: CGPoint(x: 138, y: 0))
ctx.resetClip()
ctx.addPath(vein); ctx.setStrokeColor(rgb(0xD9F2C4, 0.8)); ctx.setLineWidth(5); ctx.setLineCap(.round); ctx.strokePath()
ctx.restoreGState()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
