import AppKit

/// Menu-bar battery: the real fill level plus a state badge, drawn like the macOS battery icon.
enum MenuIcon {
    static func image(percent: Int, badge: String?) -> NSImage {
        let fraction = CGFloat(min(max(percent, 0), 100)) / 100
        let image = NSImage(size: NSSize(width: 27, height: 13), flipped: false) { _ in
            let body = NSRect(x: 0.5, y: 0.5, width: 23, height: 12)
            let outline = NSBezierPath(roundedRect: body, xRadius: 3.5, yRadius: 3.5)
            outline.lineWidth = 1
            NSColor.black.withAlphaComponent(0.45).setStroke()
            outline.stroke()

            NSColor.black.withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: NSRect(x: 24.5, y: 4, width: 2, height: 5), xRadius: 1, yRadius: 1).fill()

            if fraction > 0 {
                let inner = body.insetBy(dx: 1.5, dy: 1.5)
                NSColor.black.setFill()
                NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: max(inner.width * fraction, 1.5), height: inner.height),
                             xRadius: 2, yRadius: 2).fill()
            }

            // XOR cuts the badge out of the fill and draws it solid over the empty part, as macOS does.
            if let badge, let symbol = NSImage(systemSymbolName: badge, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 7.5, weight: .black)) {
                let s = symbol.size
                symbol.draw(in: NSRect(x: body.midX - s.width / 2, y: body.midY - s.height / 2, width: s.width, height: s.height),
                            from: .zero, operation: .xor, fraction: 1)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
